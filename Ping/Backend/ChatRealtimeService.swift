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

    // Realtime path
    private var realtimeClient: RealtimeClientV2?
    private var realtimeChannels: [RealtimeChannelV2] = []
    private var realtimeSubscriptions: [RealtimeSubscription] = []
    private var realtimeMonitorTask: Task<Void, Never>?

    // Polling path (fallback)
    private var pollingTask: Task<Void, Never>?
    private var seenChatIds: Set<String> = []

    // MARK: Init

    init(
        chatService: ChatMessageService = ChatMessageService(),
        reactionService: ReactionService = ReactionService()
    ) {
        self.chatService = chatService
        self.reactionService = reactionService
    }

    // MARK: Public API

    func subscribe(
        roomIds: [String],
        supabaseURL: URL,
        anonKey: String,
        accessToken: String?
    ) async {
        guard !roomIds.isEmpty else {
            await unsubscribeAll()
            return
        }

        subscribedRoomIds = Set(roomIds)
        connectionState = .connecting

        // Try Realtime first; fall back to polling on any failure.
        let didConnect = await tryRealtime(
            roomIds: roomIds,
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

        // Tear down Realtime
        realtimeMonitorTask?.cancel()
        realtimeMonitorTask = nil
        realtimeSubscriptions.forEach { $0.cancel() }
        realtimeSubscriptions.removeAll()
        if let client = realtimeClient {
            await client.removeAllChannels()
        }
        realtimeChannels.removeAll()
        realtimeClient = nil

        // Tear down polling
        pollingTask?.cancel()
        pollingTask = nil

        connectionState = .disconnected
    }

    // MARK: - Realtime path

    private func tryRealtime(
        roomIds: [String],
        supabaseURL: URL,
        anonKey: String,
        accessToken: String?
    ) async -> Bool {
        // Build the Realtime endpoint from the Supabase project URL.
        // Supabase Realtime lives at <project-url>/realtime/v1.
        guard var components = URLComponents(url: supabaseURL, resolvingAgainstBaseURL: false) else {
            return false
        }
        components.path = (components.path as NSString)
            .appendingPathComponent("realtime/v1")
            .replacingOccurrences(of: "//", with: "/")
        guard let realtimeURL = components.url else { return false }

        let capturedToken = accessToken
        var headers: [String: String] = ["apikey": anonKey]
        if let token = capturedToken {
            headers["Authorization"] = "Bearer \(token)"
        }

        // Build a @Sendable closure for the access token.
        let tokenClosure: (@Sendable () async throws -> String?)? = capturedToken.map { tok in
            let sendableTok = tok
            return { sendableTok }
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

        connectionState = .connected

        // Monitor client status to detect disconnects and fall back to polling.
        let weakSelf = WeakBox(self)
        realtimeMonitorTask = Task.detached(priority: .utility) {
            for await status in client.statusChange {
                guard let svc = weakSelf.value else { break }
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
