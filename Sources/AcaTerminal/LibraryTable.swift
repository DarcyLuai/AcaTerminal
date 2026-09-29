import SwiftUI
import AppKit
import AcaCore

/// NSTableView owns single selection and double-click separately, including row whitespace.
struct LibraryTable: NSViewRepresentable {
    var papers: [ResearchObject]
    var database: ResearchDatabase
    @Binding var selection: UUID?
    var open: (ResearchObject) -> Void
    var markRead: (ResearchObject) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView(); table.headerView = nil; table.backgroundColor = .clear
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("paper")))
        table.rowHeight = 94; table.intercellSpacing = NSSize(width: 0, height: 4)
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.target = context.coordinator; table.doubleAction = #selector(Coordinator.openDoubleClick)
        table.allowsEmptySelection = true; table.style = .plain
        let menu = NSMenu(); menu.delegate = context.coordinator; table.menu = menu
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        context.coordinator.table = table
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let changed = coordinator.parent.papers != papers || coordinator.parent.database.readingStates != database.readingStates || coordinator.language != L10n.identifier
        coordinator.parent = self; coordinator.language = L10n.identifier
        guard let table = coordinator.table else { return }
        coordinator.updating = true
        if changed || table.numberOfRows != papers.count { table.reloadData() }
        if let index = papers.firstIndex(where: { $0.id == selection }) { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) } else { table.deselectAll(nil) }
        coordinator.updating = false
    }
    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
        var parent: LibraryTable; weak var table: NSTableView?; var updating = false; var language = L10n.identifier
        init(_ parent: LibraryTable) { self.parent = parent }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.papers.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let paper = parent.papers[row]
            let title = NSTextField(wrappingLabelWithString: paper.title); title.font = .systemFont(ofSize: 14, weight: .medium); title.maximumNumberOfLines = 2
            let metadata = [paper.authors.map(\.name).joined(separator: ", "), paper.year.map(String.init) ?? "", paper.venue].filter { !$0.isEmpty }.joined(separator: " · ")
            let detail = NSTextField(labelWithString: metadata); detail.font = .systemFont(ofSize: 11); detail.textColor = .secondaryLabelColor; detail.lineBreakMode = .byTruncatingTail
            let position = parent.database.readingPosition(for: paper.id)
            let progress = NSTextField(labelWithString: position.map { $0.markedRead ? tr("Read") : tr("Reading") + " · \($0.progress)%" } ?? tr("Unread")); progress.font = .systemFont(ofSize: 10); progress.textColor = .secondaryLabelColor
            let stack = NSStackView(views: metadata.isEmpty ? [title, progress] : [title, detail, progress]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 7
            let cell = NSTableCellView(); cell.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -16), stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor), title.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor)])
            return cell
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let row = table?.selectedRow else { return }
            parent.selection = parent.papers.indices.contains(row) ? parent.papers[row].id : nil
        }
        @objc func openDoubleClick() {
            guard let row = table?.clickedRow, parent.papers.indices.contains(row) else { return }
            parent.open(parent.papers[row])
        }
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let row = table?.clickedRow, parent.papers.indices.contains(row) else { return }
            for (name, action) in [("Open Reader", #selector(openContext(_:))), ("Mark as Read", #selector(markContext(_:)))] {
                let item = NSMenuItem(title: tr(name), action: action, keyEquivalent: ""); item.target = self; item.representedObject = parent.papers[row]; menu.addItem(item)
            }
        }
        @objc func openContext(_ item: NSMenuItem) { if let paper = item.representedObject as? ResearchObject { parent.open(paper) } }
        @objc func markContext(_ item: NSMenuItem) { if let paper = item.representedObject as? ResearchObject { parent.markRead(paper) } }
    }
}
