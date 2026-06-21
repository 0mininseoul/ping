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
        tv.textContainer?.lineBreakMode = .byCharWrapping
        tv.textContainerInset = .zero
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.maxSize = NSSize(width: maxWidth, height: .greatestFiniteMagnitude)
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
            tv.textStorage?.addAttributes(baseAttributes, range: range)
        }
        tv.maxSize = NSSize(width: maxWidth, height: .greatestFiniteMagnitude)
        tv.textContainer?.lineBreakMode = .byCharWrapping
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ContextMenuTextView, context: Context) -> CGSize? {
        SelectableTextLayout.size(text: text, font: font, maxWidth: maxWidth, proposedWidth: proposal.width)
    }

    private func applyText(to tv: ContextMenuTextView) {
        let attributed = NSMutableAttributedString(string: text, attributes: baseAttributes)
        for match in LinkPreviewDetector.matches(in: text) {
            attributed.addAttributes([
                .link: match.url,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: NSColor.linkColor
            ], range: match.range)
        }
        tv.textStorage?.setAttributedString(attributed)
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byCharWrapping
        return [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
    }
}

enum SelectableTextLayout {
    static func size(text: String, font: NSFont, maxWidth: CGFloat, proposedWidth: CGFloat?) -> CGSize {
        let wrappingWidth = max(1, min(proposedWidth ?? maxWidth, maxWidth))
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byCharWrapping
        let storage = NSTextStorage(string: text, attributes: [
            .font: font,
            .paragraphStyle: paragraphStyle
        ])
        let container = NSTextContainer(size: NSSize(width: wrappingWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byCharWrapping
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)

        let usedRect = layoutManager.usedRect(for: container)
        let minimumLineHeight = ceil(font.ascender - font.descender + font.leading)
        return CGSize(
            width: ceil(max(1, min(wrappingWidth, usedRect.width))),
            height: ceil(max(minimumLineHeight, usedRect.height))
        )
    }
}

// MARK: - ContextMenuTextView

final class ContextMenuTextView: NSTextView {
    var menuProvider: (() -> NSMenu)?

    override func menu(for event: NSEvent) -> NSMenu? {
        // 시스템 메뉴 대신 항상 우리 메뉴 반환
        return menuProvider?() ?? super.menu(for: event)
    }

    override func mouseUp(with event: NSEvent) {
        let link = selectedRange().length == 0 ? linkURL(at: event) : nil
        if let url = link {
            NSWorkspace.shared.open(url)
            return
        }
        super.mouseUp(with: event)
    }

    private func linkURL(at event: NSEvent) -> URL? {
        guard let layoutManager, let textContainer else { return nil }
        var point = convert(event.locationInWindow, from: nil)
        point.x -= textContainerOrigin.x
        point.y -= textContainerOrigin.y

        let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < attributedString().length else { return nil }

        let value = attributedString().attribute(.link, at: characterIndex, effectiveRange: nil)
        if let url = value as? URL {
            return url
        }
        if let string = value as? String {
            return URL(string: string)
        }
        return nil
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
