import SwiftUI
import AppKit

// MARK: - SelectableTextView
// NSTextView wrap: drag selection 유지 + 우클릭 시 우리 contextMenu 반환.
// macOS NSText 시스템 메뉴 (찾아보기/번역/Google) 차단.

struct SelectableTextView: NSViewRepresentable {
    let text: String
    let font: NSFont
    let textColor: NSColor
    let maxWidth: CGFloat
    let menuProvider: () -> NSMenu

    func makeNSView(context: Context) -> ContextMenuTextView {
        let tv = ContextMenuTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainerInset = .zero
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.autoresizingMask = [.width]
        tv.menuProvider = menuProvider
        applyText(to: tv)
        return tv
    }

    func updateNSView(_ tv: ContextMenuTextView, context: Context) {
        tv.menuProvider = menuProvider
        if tv.string != text {
            applyText(to: tv)
        } else {
            // font/color만 update
            let range = NSRange(location: 0, length: tv.textStorage?.length ?? 0)
            tv.textStorage?.addAttributes([.font: font, .foregroundColor: textColor], range: range)
        }
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ContextMenuTextView, context: Context) -> CGSize? {
        let width = min(proposal.width ?? maxWidth, maxWidth)
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        let lm = NSLayoutManager()
        lm.addTextContainer(container)
        storage.addLayoutManager(lm)
        lm.ensureLayout(for: container)
        let usedRect = lm.usedRect(for: container)
        return CGSize(width: width, height: ceil(usedRect.height))
    }

    private func applyText(to tv: ContextMenuTextView) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        tv.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attrs))
    }
}

// MARK: - ContextMenuTextView

final class ContextMenuTextView: NSTextView {
    var menuProvider: (() -> NSMenu)?

    override func menu(for event: NSEvent) -> NSMenu? {
        // 시스템 메뉴 대신 항상 우리 메뉴 반환
        return menuProvider?() ?? super.menu(for: event)
    }
}

// MARK: - ContextMenuTarget / ContextMenuAction
// NSMenu action을 SwiftUI closure로 연결하는 브릿지.
// NSMenu는 main thread에서만 호출되므로 @unchecked Sendable 안전.

final class ContextMenuTarget: NSObject, @unchecked Sendable {
    static let shared = ContextMenuTarget()

    @objc func handle(_ sender: NSMenuItem) {
        guard let action = (sender.representedObject as? ContextMenuAction)?.action else { return }
        action()
    }
}

final class ContextMenuAction {
    let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
}
