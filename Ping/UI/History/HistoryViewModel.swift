import Foundation
import Combine

@MainActor
final class HistoryViewModel: ObservableObject {
    struct DayGroup: Identifiable {
        let date: Date
        let messages: [VideoMessage]
        var id: TimeInterval { date.timeIntervalSince1970 }
    }

    @Published var selectedRoomId: String?
    @Published var groups: [DayGroup] = []
    @Published var isLoading: Bool = false
    @Published var expandedMessageId: String?

    private let messageService: MessageService
    private var loadedMessages: [VideoMessage] = []

    init(messageService: MessageService) {
        self.messageService = messageService
    }

    func selectRoom(_ roomId: String) async {
        selectedRoomId = roomId
        loadedMessages = []
        groups = []
        await loadMore()
    }

    func loadMore() async {
        guard let roomId = selectedRoomId, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let before = loadedMessages.last?.createdAt
        do {
            let next = try await messageService.roomMessages(roomId: roomId, beforeTimestamp: before, limit: 50)
            loadedMessages.append(contentsOf: next)
            groups = Self.groupByDay(messages: loadedMessages, calendar: .current)
        } catch {
            NSLog("History load failed: \(error)")
        }
    }

    let inlineController = InlinePlayerController()

    func save(message: VideoMessage, cacheService: HistoryCacheService, currentUid: String?) async {
        guard let id = message.id else { return }
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
        let isMine = message.senderUid == currentUid
        do {
            if isMine {
                try await messageService.deleteMessage(messageId: id)
            } else {
                try await messageService.hideMessageForReceiver(messageId: id)
            }
            loadedMessages.removeAll { $0.id == id }
            groups = Self.groupByDay(messages: loadedMessages, calendar: .current)
        } catch {
            NSLog("Delete failed: \(error)")
        }
    }

    static func groupByDay(messages: [VideoMessage], calendar: Calendar) -> [DayGroup] {
        let sorted = messages.compactMap { msg -> (Date, VideoMessage)? in
            guard let created = msg.createdAt else { return nil }
            return (created, msg)
        }.sorted { $0.0 > $1.0 }

        var groups: [DayGroup] = []
        var currentDate: Date?
        var currentMsgs: [VideoMessage] = []

        for (date, msg) in sorted {
            let day = calendar.startOfDay(for: date)
            if day != currentDate {
                if let currentDate {
                    groups.append(DayGroup(date: currentDate, messages: currentMsgs))
                }
                currentDate = day
                currentMsgs = [msg]
            } else {
                currentMsgs.append(msg)
            }
        }
        if let currentDate {
            groups.append(DayGroup(date: currentDate, messages: currentMsgs))
        }
        return groups
    }
}
