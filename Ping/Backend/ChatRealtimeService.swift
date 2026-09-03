import Foundation
import Combine
import Realtime

// MARK: - ChatRealtimeService

/// Delivers real-time chat events to observers.
///
/// Attempts a Realtime WebSocket subscription first. If the connection cannot
/// be established within a short window it falls back to 10-second polling
/// via `ChatMessageService`. Observers depend only on the published surface;
/// the internal strategy is transparent.
@MainActor
final class ChatRealtimeService: ObservableObject {

    // MARK: Public surface (consumed by E1 / F5 / G1)

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case fallbackPolling
    }

    enum Event {
        case chatInserted(ChatMessage)
        case chatDeleted(messageId: String, roomId: String)
        /// 나에게 온 영상이 방금 만들어졌다. 페이로드는 싣지 않는다 —
        /// 수신자는 기존 RPC로 다시 읽어 중복 제거와 RLS를 그대로 태운다.
        case incomingVideo
        case reactionChanged(
            targetKind: MessageReaction.TargetKind,
            targetId: String,
            emoji: String
        )
    }

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var lastEvent: Event?

    // MARK: Dependencies

    private let chatService: ChatMessageService
    private let reactionService: ReactionService

    // MARK: Internal state

    private var subscribedRoomIds: Set<String> = []
    private var lastSubscribeAttemptAt: Date?
    /// 교체된 클라이언트의 상태 모니터를 식별하기 위한 세대 번호.
    fileprivate var connectionGeneration: UInt64 = 0

    // Realtime path
    private var realtimeClient: RealtimeClientV2?
    private var realtimeChannels: [RealtimeChannelV2] = []
    private var realtimeSubscriptions: [RealtimeSubscription] = []
    private var realtimeMonitorTask: Task<Void, Never>?

    // Polling path (fallback)
    private var pollingTask: Task<Void, Never>?
    private var seenChatIds: Set<String> = []
    /// 폴백 폴링이 시작된 시각. 이보다 오래된 채팅은 조용히 기록만 하고 알리지 않는다.
    /// 그러지 않으면 실행할 때마다 최근 20건이 "새 메시지"로 재생돼 알림이 폭주하고,
    /// macOS가 그 폭주를 배너 없이 알림 센터로 흘려보낸다(2026-09-03 확인).
    /// 밀린 채팅은 AppDelegate의 캐치업이 룸당 1건으로 묶어 알린다.
    private var pollingBaseline: Date?

    // MARK: Init

    init(
        chatService: ChatMessageService = ChatMessageService(),
        reactionService: ReactionService = ReactionService()
    ) {
        self.chatService = chatService
        self.reactionService = reactionService
    }

    // MARK: Public API

    /// 호출자가 세션 토큰 조회 같은 준비 작업을 건너뛸 수 있도록 미리 알려준다.
    func needsSubscription(roomIds: [String]) -> Bool {
        currentPlan(for: Set(roomIds)) != .reuse
    }

    private func currentPlan(for requested: Set<String>) -> RealtimeSubscriptionPlan {
        RealtimeSubscriptionPlan.plan(
            requestedRoomIds: requested,
            subscribedRoomIds: subscribedRoomIds,
            state: connectionState,
            isSocketConnected: realtimeClient?.status == .connected,
            lastAttemptAt: lastSubscribeAttemptAt
        )
    }

    func subscribe(
        roomIds: [String],
        uid: String?,
        supabaseURL: URL,
        anonKey: String,
        accessToken: String?
    ) async {
        let requested = Set(roomIds)
        switch currentPlan(for: requested) {
        case .unsubscribe:
            await unsubscribeAll()
            return
        case .reuse:
            return
        case .resubscribe:
            break
        }

        lastSubscribeAttemptAt = Date()

        // 새로 붙기 전에 이전 클라이언트·채널·모니터 task를 반드시 걷어낸다.
        await tearDownRealtime()

        subscribedRoomIds = requested
        connectionState = .connecting

        // Try Realtime first; fall back to polling on any failure.
        let didConnect = await tryRealtime(
            roomIds: roomIds,
            uid: uid,
            supabaseURL: supabaseURL,
            anonKey: anonKey,
            accessToken: accessToken
        )

        if !didConnect {
            connectionState = .fallbackPolling
            ClientEventService.shared.log("realtime_disconnected")
            startPolling()
        }
    }

    func unsubscribeAll() async {
        subscribedRoomIds.removeAll()
        await tearDownRealtime()

        // Tear down polling
        pollingTask?.cancel()
        pollingTask = nil

        connectionState = .disconnected
    }

    /// 클라이언트를 버리기 전에 모니터 task부터 끊는다. 살아남은 모니터는 죽은 연결의
    /// 상태 변화를 계속 보고하며 `realtime_disconnected`를 무한히 남긴다.
    private func tearDownRealtime() async {
        connectionGeneration &+= 1
        realtimeMonitorTask?.cancel()
        realtimeMonitorTask = nil
        realtimeSubscriptions.forEach { $0.cancel() }
        realtimeSubscriptions.removeAll()
        if let client = realtimeClient {
            await client.removeAllChannels()
            await client.disconnect()
        }
        realtimeChannels.removeAll()
        realtimeClient = nil
    }

    // MARK: - Realtime path

    private func tryRealtime(
        roomIds: [String],
        uid: String?,
        supabaseURL: URL,
        anonKey: String,
        accessToken: String?
    ) async -> Bool {
        // Supabase Realtime lives at <project-url>/realtime/v1.
        let realtimeURL = RealtimeEndpoint.socketURL(for: supabaseURL)

        let capturedToken = accessToken
        var headers: [String: String] = ["apikey": anonKey]
        if let token = capturedToken {
            headers["Authorization"] = "Bearer \(token)"
        }

        // 토큰을 캡처해 두면 안 된다. access token은 1시간(jwt_exp=3600)이면 만료되고
        // Realtime은 이 클로저로 주기적으로 재인증한다. 스냅샷을 돌려주면 만료된 토큰으로
        // 재인증해 서버가 소켓을 닫고, 재연결도 같은 토큰이라 영구히 실패한다.
        let tokenClosure: (@Sendable () async throws -> String?)? = {
            await SupabaseClient.shared.currentAccessToken()
        }

        let options = RealtimeClientOptions(
            headers: headers,
            heartbeatInterval: 25,
            reconnectDelay: 7,
            timeoutInterval: 10,
            connectOnSubscribe: true,
            accessToken: tokenClosure,
            handleAppLifecycle: true
        )

        let client = RealtimeClientV2(url: realtimeURL, options: options)
        realtimeClient = client

        // Attempt connection with a short timeout.
        let connected = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await client.connect()
                return client.status == .connected
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 s
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }

        guard connected else {
            realtimeClient = nil
            return false
        }

        // Subscribe one channel per room for postgres_changes on chat_messages.
        for roomId in roomIds {
            let topic = "chat-room-\(roomId)"
            let channel = client.channel(topic)

            // INSERT on chat_messages for this room
            let weakSelf1 = WeakBox(self)
            let capturedRoomId = roomId
            let insertSub = channel.onPostgresChange(
                InsertAction.self,
                schema: "public",
                table: "chat_messages",
                filter: "room_id=eq.\(roomId)"
            ) { (action: InsertAction) in
                Task { @MainActor in
                    weakSelf1.value?.handleInsert(action: action, roomId: capturedRoomId)
                }
            }

            // DELETE on chat_messages for this room
            let weakSelf2 = WeakBox(self)
            let capturedRoomId2 = roomId
            let deleteSub = channel.onPostgresChange(
                DeleteAction.self,
                schema: "public",
                table: "chat_messages",
                filter: "room_id=eq.\(roomId)"
            ) { (action: DeleteAction) in
                Task { @MainActor in
                    weakSelf2.value?.handleDelete(action: action, roomId: capturedRoomId2)
                }
            }

            // UPDATE on message_reactions for this room (emoji changes)
            let weakSelf3 = WeakBox(self)
            let reactionSub = channel.onPostgresChange(
                AnyAction.self,
                schema: "public",
                table: "message_reactions",
                filter: "room_id=eq.\(roomId)"
            ) { (action: AnyAction) in
                Task { @MainActor in
                    weakSelf3.value?.handleReactionChange(action: action)
                }
            }

            realtimeSubscriptions.append(contentsOf: [insertSub, deleteSub, reactionSub])
            realtimeChannels.append(channel)

            try? await channel.subscribeWithError()
        }

        // 나에게 오는 영상은 룸이 아니라 수신자로 거른다. 페이로드는 쓰지 않고
        // "지금 확인하라"는 신호로만 쓴다 — 중복 제거와 RLS는 기존 RPC 경로가 맡는다.
        if let uid {
            let videoChannel = client.channel("incoming-video-\(uid)")
            let weakVideoSelf = WeakBox(self)
            let videoSub = videoChannel.onPostgresChange(
                InsertAction.self,
                schema: "public",
                table: "messages",
                filter: "receiver_uid=eq.\(uid)"
            ) { (_: InsertAction) in
                Task { @MainActor in
                    weakVideoSelf.value?.lastEvent = .incomingVideo
                }
            }
            realtimeSubscriptions.append(videoSub)
            realtimeChannels.append(videoChannel)
            try? await videoChannel.subscribeWithError()
        }

        connectionState = .connected
        // 연결 성공을 남겨야 원격에서 실제로 붙었는지 확인할 수 있다.
        // 실패 이벤트의 부재만으로는 판단이 안 된다.
        ClientEventService.shared.log("realtime_connected")

        // Monitor client status to detect disconnects and fall back to polling.
        connectionGeneration &+= 1
        let generation = connectionGeneration
        let weakSelf = WeakBox(self)
        realtimeMonitorTask = Task.detached(priority: .utility) {
            for await status in client.statusChange {
                if Task.isCancelled { break }
                guard let svc = weakSelf.value else { break }
                let isCurrent = await MainActor.run { svc.connectionGeneration == generation }
                // 교체된 클라이언트의 모니터가 살아남아 상태를 되돌리거나 이벤트를
                // 남기지 않도록, 자기 세대가 아니면 즉시 빠져나온다.
                guard isCurrent else { break }

                await MainActor.run {
                    switch status {
                    case .connected:
                        if svc.connectionState == .fallbackPolling {
                            svc.pollingTask?.cancel()
                            svc.pollingTask = nil
                            svc.connectionState = .connected
                            ClientEventService.shared.log("realtime_reconnected")
                        }
                    case .disconnected:
                        if svc.connectionState == .connected {
                            svc.connectionState = .fallbackPolling
                            ClientEventService.shared.log("realtime_disconnected")
                            svc.startPolling()
                        }
                    case .connecting:
                        break
                    }
                }
            }
        }

        return true
    }

    // MARK: Realtime event handlers

    private func handleInsert(action: InsertAction, roomId: String) {
        guard let msg = decodeMessage(from: action.record, roomId: roomId) else { return }
        guard let id = msg.id, !seenChatIds.contains(id) else { return }
        seenChatIds.insert(id)
        lastEvent = .chatInserted(msg)
    }

    private func handleDelete(action: DeleteAction, roomId: String) {
        guard let id = action.oldRecord["id"]?.stringValue else { return }
        lastEvent = .chatDeleted(messageId: id, roomId: roomId)
    }

    private func handleReactionChange(action: AnyAction) {
        let record: [String: AnyJSON]
        switch action {
        case .insert(let a): record = a.record
        case .update(let a): record = a.record
        case .delete(let a): record = a.oldRecord
        }
        guard
            let kindRaw = record["target_kind"]?.stringValue,
            let kind = MessageReaction.TargetKind(rawValue: kindRaw),
            let targetId = record["target_id"]?.stringValue,
            let emoji = record["emoji"]?.stringValue
        else { return }
        lastEvent = .reactionChanged(targetKind: kind, targetId: targetId, emoji: emoji)
    }

    private func decodeMessage(from record: [String: AnyJSON], roomId: String) -> ChatMessage? {
        guard
            let id = record["id"]?.stringValue,
            let senderUid = record["sender_uid"]?.stringValue,
            let senderNickname = record["sender_nickname"]?.stringValue
        else { return nil }

        return ChatMessage(
            id: id,
            roomId: roomId,
            senderUid: senderUid,
            senderNickname: senderNickname,
            body: record["body"]?.stringValue ?? "",
            replyToChatId: record["reply_to_chat_id"]?.stringValue,
            replyToVideoId: record["reply_to_video_id"]?.stringValue,
            mediaPath: record["media_path"]?.stringValue,
            mediaMimeType: record["media_mime_type"]?.stringValue,
            mediaWidth: record["media_width"]?.intValue,
            mediaHeight: record["media_height"]?.intValue,
            mediaFileName: record["media_file_name"]?.stringValue,
            createdAt: parseRealtimeDate(record["created_at"]?.stringValue)
        )
    }

    private func parseRealtimeDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let date = ISO8601DateFormatter.shared.date(from: value) {
            return date
        }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value)
    }

    // MARK: - Polling fallback

    private func startPolling() {
        pollingTask?.cancel()
        pollingBaseline = Date()
        let chatSvc = chatService
        pollingTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let roomIds = await MainActor.run {
                    Array(self.subscribedRoomIds)
                }
                for roomId in roomIds {
                    if Task.isCancelled { break }
                    if let messages = try? await chatSvc.roomChatMessages(
                        roomId: roomId,
                        beforeTimestamp: nil,
                        limit: 20
                    ) {
                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            for msg in messages.reversed() {
                                guard let id = msg.id, !self.seenChatIds.contains(id) else { continue }
                                self.seenChatIds.insert(id)
                                guard self.isFreshForPolling(msg) else { continue }
                                self.lastEvent = .chatInserted(msg)
                            }
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 s
            }
        }
    }
}

extension ChatRealtimeService {
    /// 폴링 시작 이후에 만들어진 채팅만 알림 대상이다.
    func isFreshForPolling(_ message: ChatMessage) -> Bool {
        Self.isFresh(messageCreatedAt: message.createdAt, pollingStartedAt: pollingBaseline)
    }

    static func isFresh(messageCreatedAt: Date?, pollingStartedAt: Date?) -> Bool {
        guard let pollingStartedAt else { return true }
        guard let messageCreatedAt else { return false }
        return messageCreatedAt >= pollingStartedAt
    }
}

// MARK: - Helpers

/// A non-Sendable weak reference wrapper for capturing `@MainActor` classes
/// safely from `Task.detached` closures.
private final class WeakBox<T: AnyObject>: @unchecked Sendable {
    private let lock = NSLock()
    private weak var _value: T?

    var value: T? {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    init(_ value: T) {
        _value = value
    }
}
