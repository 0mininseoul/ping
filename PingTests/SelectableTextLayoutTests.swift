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

    @MainActor
    func testRenderedRoomTimelineKeepsOutgoingLongURLInsideVisibleViewport() {
        let timelineWidth = sampleTimelineWidth
        let host = makeSampleTimelineHost(width: timelineWidth)

        XCTAssertLessThanOrEqual(host.fittingSize.width, timelineWidth)
        XCTAssertLessThanOrEqual(maxDescendantMaxX(in: host, relativeTo: host), timelineWidth + 0.5)
    }

    @MainActor
    func testRenderedRoomTimelineKeepsOutgoingTextBubbleAlignedWithPreviewInset() {
        let timelineWidth = sampleTimelineWidth
        let timelineHorizontalPadding: CGFloat = 16
        let outgoingTrailingInset: CGFloat = 28
        let host = makeSampleTimelineHost(width: timelineWidth)
        let textContainerMaxX = maxSelectableTextContainerMaxX(in: host, relativeTo: host)

        XCTAssertGreaterThan(textContainerMaxX, 0)
        XCTAssertLessThanOrEqual(
            textContainerMaxX,
            timelineWidth - timelineHorizontalPadding - outgoingTrailingInset + 0.5
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
}
