import AppKit
import KeyboardShortcuts

@MainActor
enum StatusMenuBuilder {
    static func makeMenu(target: AnyObject) -> NSMenu {
        let menu = NSMenu()

        let status = NSMenuItem(title: "Ping", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(NSMenuItem.separator())

        menu.addItem(command(title: "영상 보내기", action: Selector(("toggleMirrorAction")), shortcutName: .pingTrigger, target: target))
        menu.addItem(command(title: "히스토리 열기", action: Selector(("toggleHistoryAction")), shortcutName: .historyToggle, target: target))
        menu.addItem(command(title: "내 룸…", action: Selector(("showRoomManager")), target: target))
        menu.addItem(command(title: "설정…", action: Selector(("showSettings")), keyEquivalent: ",", target: target))
        menu.addItem(command(title: "라이트/다크 전환", action: Selector(("toggleAppearanceModeAction")), shortcutName: .appearanceToggle, target: target))

        menu.addItem(NSMenuItem.separator())
        let updateItem = NSMenuItem(
            title: "업데이트 확인…",
            action: #selector(UpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = UpdaterController.shared
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    private static func command(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        shortcutName: KeyboardShortcuts.Name? = nil,
        target: AnyObject
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        if let shortcutName {
            applyShortcut(shortcutName, to: item)
        }
        item.target = target
        return item
    }

    private static func applyShortcut(_ name: KeyboardShortcuts.Name, to item: NSMenuItem) {
        item.setShortcut(for: name)
    }
}
