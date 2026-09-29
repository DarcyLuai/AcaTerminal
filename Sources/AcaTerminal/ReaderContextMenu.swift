import AppKit

final class ReaderContextMenu: NSMenu {
    private var actions: [() -> Void] = []
    static func make(_ items: [(String, () -> Void)]) -> NSMenu {
        let menu = ReaderContextMenu(title: "")
        menu.autoenablesItems = false
        for (index, item) in items.enumerated() {
            menu.actions.append(item.1)
            let entry = NSMenuItem(title: item.0, action: #selector(invoke(_:)), keyEquivalent: "")
            entry.target = menu; entry.tag = index; menu.addItem(entry)
        }
        return menu
    }
    @objc private func invoke(_ item: NSMenuItem) { actions[item.tag]() }
}
