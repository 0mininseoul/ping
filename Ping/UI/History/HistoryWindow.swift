import AppKit
import SwiftUI

@MainActor
final class HistoryWindow: NSWindow {
    init(
        appState: AppState,
        messageService: MessageService,
        cacheService: HistoryCacheService
    ) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.title = "Ping 히스토리"
        self.minSize = NSSize(width: 640, height: 480)
        self.isReleasedWhenClosed = false
        self.center()

        let viewModel = HistoryViewModel(messageService: messageService)
        let host = NSHostingView(rootView:
            HistoryView(appState: appState, viewModel: viewModel, cacheService: cacheService)
        )
        host.frame = contentView!.bounds
        host.autoresizingMask = [.width, .height]
        contentView?.addSubview(host)
    }
}
