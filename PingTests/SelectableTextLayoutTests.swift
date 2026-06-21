import AppKit
import SwiftUI
import XCTest
@testable import Ping

@MainActor
final class SelectableTextLayoutTests: XCTestCase {
    func testShortChatTextKeepsIntrinsicBubbleWidth() {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let size = SelectableTextLayout.size(text: "ㅋㅋ", font: font, maxWidth: 280, proposedWidth: nil)

        XCTAssertLessThan(size.width, 80)
        XCTAssertGreaterThan(size.width, 8)
    }

    func testLongChatTextWrapsAtMaximumWidth() {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let short = SelectableTextLayout.size(text: "짧은 말", font: font, maxWidth: 280, proposedWidth: nil)
        let long = SelectableTextLayout.size(
            text: String(repeating: "긴 메시지입니다 ", count: 24),
            font: font,
            maxWidth: 280,
            proposedWidth: nil
        )

        XCTAssertLessThanOrEqual(long.width, 280)
        XCTAssertGreaterThan(long.width, short.width)
        XCTAssertGreaterThan(long.height, short.height * 2)
    }

    func testLongURLWrapsWithinTextContentWidth() {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let text = "그리고 애들아 이거 한번 가입해서 써봐\nhttps://gatitagachon.vercel.app/invite/abcdefghijklmnopqrstuvwxyz"

        let size = SelectableTextLayout.size(text: text, font: font, maxWidth: 258, proposedWidth: nil)

        XCTAssertLessThanOrEqual(size.width, 258)
        XCTAssertGreaterThan(size.height, 40)
    }

    func testLongURLChatBubbleOuterWidthFitsMessageColumn() {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let text = "그리고 애들아 이거 한번 가입해서 써봐\nhttps://gatitagachon.vercel.app/invite/abcdefghijklmnopqrstuvwxyz"

        let size = ChatMessageBubbleLayout.textContentSize(for: text, font: font)
        let bubbleSize = ChatMessageBubbleLayout.textBubbleSize(for: text, font: font)

        XCTAssertLessThanOrEqual(size.width, ChatMessageBubbleLayout.textContentMaxWidth)
        XCTAssertLessThanOrEqual(bubbleSize.width, ChatMessageBubbleLayout.messageMaxWidth)
        XCTAssertEqual(bubbleSize.height, size.height + ChatMessageBubbleLayout.textBubbleVerticalPadding * 2)
        XCTAssertGreaterThan(size.height, 40)
    }

    func testRenderedOutgoingLongURLRowStaysInsideTimelineWidth() {
        let timelineWidth: CGFloat = 620
        let message = ChatMessage(
            id: "chat-1",
            roomId: "room-1",
            senderUid: "me",
            senderNickname: "나",
            body: "그리고 애들아 이거 한번 가입해서 써봐\nhttps://gatitagachon.vercel.app/invite/abcdefghijklmnopqrstuvwxyz",
            createdAt: Date()
        )
        let row = ChatMessageRowView(
            message: message,
            isMine: true,
            showsSender: false,
            replyPreview: nil,
            cacheService: HistoryCacheService(),
            reactions: [],
            onReply: {},
            onReact: {},
            onDelete: {},
            onToggleReaction: { _ in }
        )
        .frame(width: timelineWidth)

        let host = NSHostingView(rootView: row)
        host.frame = NSRect(x: 0, y: 0, width: timelineWidth, height: 360)
        host.layoutSubtreeIfNeeded()

        XCTAssertLessThanOrEqual(host.fittingSize.width, timelineWidth)
        XCTAssertLessThanOrEqual(maxDescendantMaxX(in: host, relativeTo: host), timelineWidth + 0.5)
    }

    func testRenderedOutgoingTextWithoutLinkKeepsNativeTrailingAlignment() {
        let timelineWidth: CGFloat = 620
        let message = ChatMessage(
            id: "chat-1",
            roomId: "room-1",
            senderUid: "me",
            senderNickname: "나",
            body: "세연이랑 모수 다녀오기로 했어",
            createdAt: Date()
        )
        let row = ChatMessageRowView(
            message: message,
            isMine: true,
            showsSender: false,
            replyPreview: nil,
            cacheService: HistoryCacheService(),
            reactions: [],
            onReply: {},
            onReact: {},
            onDelete: {},
            onToggleReaction: { _ in }
        )
        .frame(width: timelineWidth)

        let host = NSHostingView(rootView: row)
        host.frame = NSRect(x: 0, y: 0, width: timelineWidth, height: 160)
        host.layoutSubtreeIfNeeded()

        XCTAssertGreaterThanOrEqual(
            maxSelectableTextContainerMaxX(in: host, relativeTo: host),
            timelineWidth - ChatMessageBubbleLayout.textBubbleHorizontalPadding - 0.5
        )
    }

    func testRenderedOutgoingLongTextFitsNarrowMacTimelineWidth() {
        let timelineWidth: CGFloat = 287
        let message = ChatMessage(
            id: "chat-1",
            roomId: "room-1",
            senderUid: "me",
            senderNickname: "나",
            body: "무슨 네이버, 카카오 VC 투자 유치하고 팁스 선정 됐었던 사람이 PT 플랫폼 앱 만들고",
            createdAt: Date()
        )
        let row = ChatMessageRowView(
            message: message,
            isMine: true,
            showsSender: false,
            replyPreview: nil,
            cacheService: HistoryCacheService(),
            reactions: [],
            onReply: {},
            onReact: {},
            onDelete: {},
            onToggleReaction: { _ in }
        )
        .frame(width: timelineWidth)

        let host = NSHostingView(rootView: row)
        host.frame = NSRect(x: 0, y: 0, width: timelineWidth, height: 220)
        host.layoutSubtreeIfNeeded()

        XCTAssertLessThanOrEqual(maxDescendantMaxX(in: host, relativeTo: host), timelineWidth + 0.5)
    }

    func testOutgoingTextWithPreviewUsesSameTrailingEdgeAsRegularOutgoingText() {
        let timelineWidth: CGFloat = 287
        let regularHost = makeOutgoingChatRowHost(
            width: timelineWidth,
            body: "무슨 네이버, 카카오 VC 투자 유치하고 팁스 선정 됐었던 사람이 PT 플랫폼 앱 만들고"
        )
        let linkHost = makeOutgoingChatRowHost(
            width: timelineWidth,
            body: "심심할 때 한번 봐봐\nhttps://www.youtube.com/watch?v=oFAvC8gw-fQ"
        )

        XCTAssertEqual(
            maxSelectableTextContainerMaxX(in: regularHost, relativeTo: regularHost),
            maxSelectableTextContainerMaxX(in: linkHost, relativeTo: linkHost),
            accuracy: 0.5
        )
    }

    func testOutgoingLinkTextUsesReadableColorOnBlueBubble() throws {
        let urlString = "https://gatitagachon.vercel.app/"
        let message = ChatMessage(
            id: "chat-1",
            roomId: "room-1",
            senderUid: "me",
            senderNickname: "나",
            body: "그리고 애들아 이거 한번 가입해서 써봐\n\(urlString)",
            createdAt: Date()
        )
        let row = ChatMessageRowView(
            message: message,
            isMine: true,
            showsSender: false,
            replyPreview: nil,
            cacheService: HistoryCacheService(),
            reactions: [],
            onReply: {},
            onReact: {},
            onDelete: {},
            onToggleReaction: { _ in }
        )
        .frame(width: 620)

        let host = NSHostingView(rootView: row)
        host.frame = NSRect(x: 0, y: 0, width: 620, height: 240)
        host.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(firstTextView(containing: urlString, in: host))
        let range = (textView.string as NSString).range(of: urlString)
        let color = try XCTUnwrap(
            textView.attributedString().attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
        )
        XCTAssertTrue(isReadableOutgoingLinkColor(color), "\(color) should be readable on the outgoing blue bubble")
    }

    @MainActor
    func testRenderedRoomTimelineKeepsOutgoingLongURLInsideVisibleViewport() {
        let timelineWidth = sampleTimelineWidth
        let host = makeSampleTimelineHost(width: timelineWidth)

        XCTAssertLessThanOrEqual(host.fittingSize.width, timelineWidth)
        XCTAssertLessThanOrEqual(maxDescendantMaxX(in: host, relativeTo: host), timelineWidth + 0.5)
    }

    @MainActor
    func testRenderedRoomTimelineKeepsOutgoingTextBubbleAlignedWithViewportEdge() {
        let timelineWidth = sampleTimelineWidth
        let timelineHorizontalPadding: CGFloat = 16
        let host = makeSampleTimelineHost(width: timelineWidth)
        let textContainerMaxX = maxSelectableTextContainerMaxX(in: host, relativeTo: host)

        XCTAssertGreaterThan(textContainerMaxX, 0)
        XCTAssertLessThanOrEqual(
            textContainerMaxX,
            timelineWidth - timelineHorizontalPadding - ChatMessageBubbleLayout.textBubbleHorizontalPadding + 0.5
        )
    }

    private func maxDescendantMaxX(in view: NSView, relativeTo root: NSView) -> CGFloat {
        let frame = view == root ? root.bounds : view.convert(view.bounds, to: root)
        return view.subviews.reduce(frame.maxX) { max($0, maxDescendantMaxX(in: $1, relativeTo: root)) }
    }

    private var sampleTimelineWidth: CGFloat { 636 }

    @MainActor
    private func makeSampleTimelineHost(width timelineWidth: CGFloat) -> NSHostingView<some View> {
        let appState = AppState()
        appState.currentUser = PingUser(
            id: "me",
            nickname: "나",
            searchableNickname: "나",
            rooms: ["room-1"]
        )
        appState.rooms = [
            Room(
                id: "room-1",
                name: "코코네친구들",
                searchableName: "코코네친구들",
                ownerUid: "me",
                memberUids: ["me", "suseong", "member-3", "member-4"],
                memberNicknames: [
                    "me": "나",
                    "suseong": "수성",
                    "member-3": "영민",
                    "member-4": "범준"
                ],
                status: .open
            )
        ]

        let viewModel = HistoryViewModel(
            messageService: MessageService(),
            appState: appState
        )
        viewModel.selectedRoomId = "room-1"
        let now = Date()
        viewModel.groups = [
            HistoryViewModel.DayGroup(
                date: Calendar.current.startOfDay(for: now),
                items: [
                    .chat(ChatMessage(
                        id: "incoming-1",
                        roomId: "room-1",
                        senderUid: "suseong",
                        senderNickname: "수성",
                        body: "VIKINGDEFENSE",
                        createdAt: now.addingTimeInterval(-120)
                    )),
                    .chat(ChatMessage(
                        id: "incoming-2",
                        roomId: "room-1",
                        senderUid: "suseong",
                        senderNickname: "수성",
                        body: "이거 쿠폰 코드인데",
                        createdAt: now.addingTimeInterval(-90)
                    )),
                    .chat(ChatMessage(
                        id: "mine-1",
                        roomId: "room-1",
                        senderUid: "me",
                        senderNickname: "나",
                        body: "그리고 애들아 이거 한번 가입해서 써봐\nhttps://gatitagachon.vercel.app/invite/abcdefghijklmnopqrstuvwxyz",
                        createdAt: now
                    ))
                ]
            )
        ]

        let view = RoomTimelineView(
            viewModel: viewModel,
            cacheService: HistoryCacheService(),
            appState: appState
        )
        .frame(width: timelineWidth, height: 820)

        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: timelineWidth, height: 820)
        host.layoutSubtreeIfNeeded()
        return host
    }

    @MainActor
    private func makeOutgoingChatRowHost(width timelineWidth: CGFloat, body: String) -> NSHostingView<some View> {
        let message = ChatMessage(
            id: UUID().uuidString,
            roomId: "room-1",
            senderUid: "me",
            senderNickname: "나",
            body: body,
            createdAt: Date()
        )
        let row = ChatMessageRowView(
            message: message,
            isMine: true,
            showsSender: false,
            replyPreview: nil,
            cacheService: HistoryCacheService(),
            reactions: [],
            onReply: {},
            onReact: {},
            onDelete: {},
            onToggleReaction: { _ in }
        )
        .frame(width: timelineWidth)

        let host = NSHostingView(rootView: row)
        host.frame = NSRect(x: 0, y: 0, width: timelineWidth, height: 260)
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func maxSelectableTextContainerMaxX(in view: NSView, relativeTo root: NSView) -> CGFloat {
        let currentMax: CGFloat
        if view is SelectableTextContainerView {
            currentMax = view.convert(view.bounds, to: root).maxX
        } else {
            currentMax = -.greatestFiniteMagnitude
        }
        return view.subviews.reduce(currentMax) {
            max($0, maxSelectableTextContainerMaxX(in: $1, relativeTo: root))
        }
    }

    private func firstTextView(containing text: String, in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView, textView.string.contains(text) {
            return textView
        }
        for subview in view.subviews {
            if let match = firstTextView(containing: text, in: subview) {
                return match
            }
        }
        return nil
    }

    private func isReadableOutgoingLinkColor(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return false }
        return rgb.redComponent > 0.8 && rgb.greenComponent > 0.8 && rgb.blueComponent > 0.8
    }
}
