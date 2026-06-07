import Foundation
import Combine

@MainActor
final class HistoryViewModel: ObservableObject {
    struct DayGroup: Identifiable {
        let date: Date
        let items: [TimelineItem]
        var id: TimeInterval { date.timeIntervalSince1970 }

        // Compatibility shim — callers updated in Task F4
        var messages: [VideoMessage] {
            items.compactMap {
                if case .video(let m) = $0 { return m }
                return nil
            }
        }
    }

    struct ReactionAggregate: Hashable {
        let emoji: String
        let count: Int
        let myReacted: Bool
    }

    enum ReplyTarget: Hashable {
        case chat(id: String, sender: String, preview: String)
        case video(id: String, sender: String, captureMode: CaptureMode)
    }

    @Published var selectedRoomId: String?
    @Published var groups: [DayGroup] = []
    @Published var isLoading: Bool = false
    @Published var expandedMessageId: String?
    @Published var replyTarget: ReplyTarget?
    @Published var reactionsByTargetId: [String: [String: ReactionAggregate]] = [:]
    @Published var lastErrorMessage: String?

    let inlineController = InlinePlayerController()

    private let messageService: MessageService
    private let appState: AppState
    private let chatService: ChatMessageService
    private let reactionService: ReactionService
    private let storageService: StorageService
    private var loadedVideos: [VideoMessage] = []
    private var loadedChats: [ChatMessage] = []
    private var videoPaginationCursor: Date?

    init(
        messageService: MessageService,
        appState: AppState,
        chatService: ChatMessageService = ChatMessageService(),
        reactionService: ReactionService = ReactionService(),
        storageService: StorageService = StorageService()
    ) {
        self.messageService = messageService
        self.appState = appState
        self.chatService = chatService
        self.reactionService = reactionService
        self.storageService = storageService
    }

    func selectRoom(_ roomId: String) async {
        selectedRoomId = roomId
        loadedVideos = []
        loadedChats = []
        videoPaginationCursor = nil
        groups = []
        reactionsByTargetId = [:]
        await loadMore()
        do {
            try await chatService.markRoomRead(roomId: roomId)
            appState.markRoomReadLocally(roomId: roomId)
        } catch {
            NSLog("Mark room read failed: \(error) — roomId=\(roomId)")
        }
        ClientEventService.shared.log("chat_received_view", properties: ["room_id": roomId])
    }

    func loadMore() async {
        guard let roomId = selectedRoomId, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        async let videosTask = messageService.roomMessages(roomId: roomId, beforeTimestamp: videoPaginationCursor, limit: 50)
        async let chatsTask = chatService.roomChatMessages(roomId: roomId, beforeTimestamp: loadedChats.last?.createdAt, limit: 50)

        do {
            let videos = try await videosTask
            let chats = try await chatsTask
            NSLog("History load OK: roomId=\(roomId) videos=\(videos.count) chats=\(chats.count)")
            if let nextVideoCursor = videos.last?.createdAt {
                videoPaginationCursor = nextVideoCursor
            }
            loadedVideos = Self.dedupedSenderVideos(loadedVideos + videos, currentUid: appState.currentUser?.id)
            loadedChats.append(contentsOf: chats)
            groups = Self.groupTimelineByDay(videos: loadedVideos, chats: loadedChats, calendar: .current)
            await refreshReactions()
        } catch {
            let errorMsg: String
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    errorMsg = "히스토리 디코딩 실패 (키 누락: \(key.stringValue), 경로: \(context.codingPath.map(\.stringValue).joined(separator: ".")))"
                case .typeMismatch(let type, let context):
                    errorMsg = "히스토리 디코딩 실패 (타입 불일치: \(type), 경로: \(context.codingPath.map(\.stringValue).joined(separator: ".")))"
                case .valueNotFound(let type, let context):
                    errorMsg = "히스토리 디코딩 실패 (값 없음: \(type), 경로: \(context.codingPath.map(\.stringValue).joined(separator: ".")))"
                case .dataCorrupted(let context):
                    errorMsg = "히스토리 디코딩 실패 (데이터 손상: \(context.debugDescription))"
                @unknown default:
                    errorMsg = "히스토리 로드 실패: \(error.localizedDescription)"
                }
            } else {
                errorMsg = "히스토리 로드 실패: \(error.localizedDescription)"
            }
            lastErrorMessage = errorMsg
            NSLog("History load failed: \(error) — roomId=\(roomId)")
        }
    }

    func refreshReactions() async {
        let chatIds = loadedChats.compactMap(\.id)
        let videoIds = loadedVideos.compactMap(\.id)
        guard !chatIds.isEmpty || !videoIds.isEmpty else { return }
        do {
            let reactions = try await reactionService.reactions(chatIds: chatIds, videoIds: videoIds)
            var map: [String: [String: ReactionAggregate]] = [:]
            for r in reactions {
                let key = "\(r.targetKind.rawValue):\(r.targetId)"
                map[key, default: [:]][r.emoji] = ReactionAggregate(emoji: r.emoji, count: r.totalCount, myReacted: r.myReacted)
            }
            reactionsByTargetId = map
        } catch {
            NSLog("Reactions fetch failed: \(error)")
        }
    }

    func handleRealtimeEvent(_ event: ChatRealtimeService.Event) {
        switch event {
        case .chatInserted(let msg):
            guard msg.roomId == selectedRoomId else { return }
            if !loadedChats.contains(where: { $0.id == msg.id }) {
                loadedChats.append(msg)
                groups = Self.groupTimelineByDay(videos: loadedVideos, chats: loadedChats, calendar: .current)
            }
        case .chatDeleted(let id, _):
            loadedChats.removeAll { $0.id == id }
            groups = Self.groupTimelineByDay(videos: loadedVideos, chats: loadedChats, calendar: .current)
        case .reactionChanged:
            Task { await refreshReactions() }
        }
    }

    func sendChat(body: String) async {
        guard let roomId = selectedRoomId else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var replyChatId: String?
        var replyVideoId: String?
        switch replyTarget {
        case .chat(let id, _, _): replyChatId = id
        case .video(let id, _, _): replyVideoId = id
        case .none: break
        }

        let snapshotReplyTarget = replyTarget
        replyTarget = nil

        do {
            let id = try await chatService.sendChat(
                roomId: roomId,
                body: trimmed,
                replyToChatId: replyChatId,
                replyToVideoId: replyVideoId
            )
            // Optimistic insert: place the new message in the loaded list immediately
            let nickname = appState.currentUser?.nickname ?? ""
            let uid = appState.currentUser?.id ?? ""
            let optimistic = ChatMessage(
                id: id,
                roomId: roomId,
                senderUid: uid,
                senderNickname: nickname,
                body: trimmed,
                replyToChatId: replyChatId,
                replyToVideoId: replyVideoId,
                createdAt: Date()
            )
            if !loadedChats.contains(where: { $0.id == id }) {
                loadedChats.append(optimistic)
                groups = Self.groupTimelineByDay(videos: loadedVideos, chats: loadedChats, calendar: .current)
            }
            ClientEventService.shared.log("chat_sent", properties: [
                "room_id": roomId,
                "body_length": trimmed.count,
                "is_reply": (replyChatId != nil || replyVideoId != nil),
                "reply_kind": replyChatId != nil ? "chat" : (replyVideoId != nil ? "video" : "none")
            ])
            await refreshReactions()
        } catch {
            replyTarget = snapshotReplyTarget
            lastErrorMessage = "메시지 전송 실패: \(error.localizedDescription)"
            NSLog("Send chat failed: \(error)")
        }
    }

    func sendChatImage(localURL: URL, caption: String) async {
        guard let roomId = selectedRoomId else { return }
        guard let currentUser = appState.currentUser,
              let uid = currentUser.id else {
            lastErrorMessage = PingError.currentUserMissing.localizedDescription
            return
        }

        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 2000 else {
            lastErrorMessage = "메시지는 2000자까지 입력할 수 있습니다."
            return
        }

        var replyChatId: String?
        var replyVideoId: String?
        switch replyTarget {
        case .chat(let id, _, _): replyChatId = id
        case .video(let id, _, _): replyVideoId = id
        case .none: break
        }

        let snapshotReplyTarget = replyTarget
        replyTarget = nil
        let messageId = UUID().uuidString

        do {
            let uploaded = try await storageService.uploadChatImage(
                localURL: localURL,
                senderUid: uid,
                messageId: messageId
            )
            let media = ChatMessageService.ChatMediaPayload(
                path: uploaded.path,
                mimeType: uploaded.mimeType,
                width: uploaded.width,
                height: uploaded.height,
                fileName: uploaded.fileName
            )
            let id = try await chatService.sendChat(
                roomId: roomId,
                body: trimmed,
                replyToChatId: replyChatId,
                replyToVideoId: replyVideoId,
                messageId: messageId,
                media: media
            )

            let optimistic = ChatMessage(
                id: id,
                roomId: roomId,
                senderUid: uid,
                senderNickname: currentUser.nickname,
                body: trimmed,
                replyToChatId: replyChatId,
                replyToVideoId: replyVideoId,
                mediaPath: uploaded.path,
                mediaMimeType: uploaded.mimeType,
                mediaWidth: uploaded.width,
                mediaHeight: uploaded.height,
                mediaFileName: uploaded.fileName,
                createdAt: Date()
            )
            if !loadedChats.contains(where: { $0.id == id }) {
                loadedChats.append(optimistic)
                groups = Self.groupTimelineByDay(videos: loadedVideos, chats: loadedChats, calendar: .current)
            }
            ClientEventService.shared.log("chat_sent", properties: [
                "room_id": roomId,
                "body_length": trimmed.count,
                "has_image": true,
                "is_reply": (replyChatId != nil || replyVideoId != nil),
                "reply_kind": replyChatId != nil ? "chat" : (replyVideoId != nil ? "video" : "none")
            ])
            await refreshReactions()
        } catch {
            replyTarget = snapshotReplyTarget
            lastErrorMessage = "사진 전송 실패: \(error.localizedDescription)"
            NSLog("Send chat image failed: \(error)")
        }
    }

    func toggleReaction(target: MessageReaction.TargetKind, targetId: String, emoji: String) async {
        // Optimistic flip in cached aggregates
        let key = "\(target.rawValue):\(targetId)"
        var roomMap = reactionsByTargetId[key] ?? [:]
        if let existing = roomMap[emoji] {
            if existing.myReacted {
                let newCount = max(0, existing.count - 1)
                if newCount == 0 {
                    roomMap.removeValue(forKey: emoji)
                } else {
                    roomMap[emoji] = ReactionAggregate(emoji: emoji, count: newCount, myReacted: false)
                }
            } else {
                roomMap[emoji] = ReactionAggregate(emoji: emoji, count: existing.count + 1, myReacted: true)
            }
        } else {
            roomMap[emoji] = ReactionAggregate(emoji: emoji, count: 1, myReacted: true)
        }
        reactionsByTargetId[key] = roomMap

        do {
            let added = try await reactionService.toggle(target: target, targetId: targetId, emoji: emoji)
            ClientEventService.shared.log(
                added ? "reaction_added" : "reaction_removed",
                properties: ["target_kind": target.rawValue, "emoji": emoji]
            )
            await refreshReactions()
        } catch {
            lastErrorMessage = "반응 처리 실패: \(error.localizedDescription)"
            NSLog("Toggle reaction failed: \(error)")
            await refreshReactions()
        }
    }

    func deleteChat(messageId: String) async {
        do {
            try await chatService.deleteChat(messageId: messageId)
            loadedChats.removeAll { $0.id == messageId }
            groups = Self.groupTimelineByDay(videos: loadedVideos, chats: loadedChats, calendar: .current)
        } catch {
            NSLog("Delete chat failed: \(error)")
        }
    }

    static func groupTimelineByDay(videos: [VideoMessage], chats: [ChatMessage], calendar: Calendar) -> [DayGroup] {
        var items: [TimelineItem] = []
        items.append(contentsOf: videos.map(TimelineItem.video))
        items.append(contentsOf: chats.map(TimelineItem.chat))
        let sorted = items.compactMap { item -> (Date, TimelineItem)? in
            guard let d = item.createdAt else { return nil }
            return (d, item)
        }.sorted { $0.0 < $1.0 }  // ascending: oldest first

        var groups: [DayGroup] = []
        var currentDate: Date?
        var currentItems: [TimelineItem] = []
        for (date, item) in sorted {
            let day = calendar.startOfDay(for: date)
            if day != currentDate {
                if let currentDate {
                    groups.append(DayGroup(date: currentDate, items: currentItems))
                }
                currentDate = day
                currentItems = [item]
            } else {
                currentItems.append(item)
            }
        }
        if let currentDate {
            groups.append(DayGroup(date: currentDate, items: currentItems))
        }
        return groups
    }

    static func dedupedSenderVideos(_ videos: [VideoMessage], currentUid: String?) -> [VideoMessage] {
        guard let currentUid else { return videos }

        var seenSentVideoKeys = Set<String>()
        var deduped: [VideoMessage] = []

        for video in videos {
            guard video.senderUid == currentUid else {
                deduped.append(video)
                continue
            }

            let key = "\(video.roomId)|\(video.videoUrl)"
            guard seenSentVideoKeys.insert(key).inserted else { continue }
            deduped.append(video)
        }

        return deduped
    }

    // Compatibility shim — callers updated in Task F4
    static func groupByDay(messages: [VideoMessage], calendar: Calendar) -> [DayGroup] {
        groupTimelineByDay(videos: messages, chats: [], calendar: calendar)
    }

    // MARK: - Video save/delete (API preserved; callers updated in Task F4)

    func save(message: VideoMessage, cacheService: HistoryCacheService, currentUid: String?) async {
        guard let id = message.id else { return }
        guard message.canBeSavedLocally(by: currentUid) else {
            lastErrorMessage = "보낸 사람이 로컬 저장을 허용하지 않았습니다."
            return
        }
        guard let cached = cacheService.cachedFile(roomId: message.roomId, messageId: id) else { return }
        let isMine = message.senderUid == currentUid
        LocalArchive.ensureFolders()
        let dest: URL
        if isMine {
            dest = LocalArchive.sentURL(to: message.senderNickname)
        } else {
            dest = LocalArchive.receivedURL(from: message.senderNickname)
        }
        try? FileManager.default.copyItem(at: cached, to: dest)
    }

    func delete(message: VideoMessage, currentUid: String?) async {
        guard let id = message.id else { return }
        do {
            let result = try await messageService.removeMessageForCurrentUser(messageId: id)
            switch result {
            case .deletedForEveryone:
                Task { @MainActor in
                    do {
                        try await storageService.deleteVideo(remotePath: message.videoUrl)
                    } catch {
                        NSLog("Video storage cleanup failed: \(error)")
                    }
                }
                loadedVideos.removeAll { $0.videoUrl == message.videoUrl }
            case .hiddenForCurrentUser:
                loadedVideos.removeAll { $0.id == id }
            case .missing:
                loadedVideos.removeAll { $0.id == id }
            }
            if expandedMessageId == id {
                expandedMessageId = nil
            }
            groups = Self.groupTimelineByDay(videos: loadedVideos, chats: loadedChats, calendar: .current)
        } catch {
            lastErrorMessage = "삭제 실패: \(error.localizedDescription)"
            NSLog("Delete failed: \(error)")
        }
    }
}
