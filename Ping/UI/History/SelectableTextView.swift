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

    func makeNSView(context: Context) -> SelectableTextContainerView {
        let view = SelectableTextContainerView()
        view.maxTextWidth = maxWidth
        view.menuProvider = menuProvider
        view.setAttributedText(attributedText)
        return view
    }

    func updateNSView(_ view: SelectableTextContainerView, context: Context) {
        view.maxTextWidth = maxWidth
        view.menuProvider = menuProvider
        view.setAttributedText(attributedText)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SelectableTextContainerView, context: Context) -> CGSize? {
        SelectableTextLayout.size(text: text, font: font, maxWidth: maxWidth, proposedWidth: proposal.width)
    }

    private var attributedText: NSAttributedString {
        let attributed = NSMutableAttributedString(string: text, attributes: baseAttributes)
        for match in LinkPreviewDetector.matches(in: text) {
            attributed.addAttributes([
                .link: match.url,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: NSColor.linkColor
            ], range: match.range)
        }
        return attributed
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

final class SelectableTextContainerView: NSView {
    private let textView = ContextMenuTextView()

    var maxTextWidth: CGFloat = 1 {
        didSet {
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    var menuProvider: (() -> NSMenu)? {
        didSet {
            textView.menuProvider = menuProvider
        }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byCharWrapping
        textView.textContainer?.widthTracksTextView = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = []
        addSubview(textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setAttributedText(_ attributedText: NSAttributedString) {
        if textView.attributedString() != attributedText {
            textView.textStorage?.setAttributedString(attributedText)
        }
        updateTextGeometry()
    }

    override func layout() {
        super.layout()
        textView.frame = bounds
        updateTextGeometry()
    }

    private func updateTextGeometry() {
        guard let textContainer = textView.textContainer else { return }
        let width = max(1, bounds.width > 0 ? bounds.width : maxTextWidth)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        textContainer.widthTracksTextView = false
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byCharWrapping
        textView.layoutManager?.ensureLayout(for: textContainer)
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
