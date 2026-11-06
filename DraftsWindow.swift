// DraftsWindow.swift
// All Drafts window: search, open, pin, rename, delete and export drafts.

import Cocoa

/// Table that acts on Return and Command Delete.
final class KeyTableView: NSTableView {
    var onReturn: (() -> Void)?
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if (event.keyCode == 36 || event.keyCode == 76) && flags.isEmpty { onReturn?(); return }
        if (event.keyCode == 51 || event.keyCode == 117) && flags == .command { onDelete?(); return }
        super.keyDown(with: event)
    }
}

/// Builds a one-line table cell.
@MainActor
func makeTextCell(_ tableView: NSTableView, owner: Any?, text: String) -> NSView {
    let id = NSUserInterfaceItemIdentifier("cell")
    let cell: NSTableCellView
    if let reused = tableView.makeView(withIdentifier: id, owner: owner) as? NSTableCellView {
        cell = reused
    } else {
        cell = NSTableCellView()
        cell.identifier = id
        let tf = NSTextField(labelWithString: "")
        tf.lineBreakMode = .byTruncatingTail
        tf.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(tf)
        cell.textField = tf
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
    }
    cell.textField?.stringValue = text
    return cell
}

@MainActor
final class DraftsWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let window: NSWindow
    private let store: DraftStore
    private let search = NSSearchField()
    private let table = KeyTableView()
    private let countLabel = NSTextField(labelWithString: "")
    private var shown: [Draft] = []
    private var didCenter = false

    var onOpen: ((UUID) -> Void)?
    var onDeleted: ((UUID) -> Void)?
    var onExport: ((Draft) -> Void)?

    private let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    init(store: DraftStore) {
        self.store = store
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "All Drafts"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                               name: .draftsChanged, object: nil)
    }

    private func button(_ title: String, _ action: Selector, key: String = "") -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        if !key.isEmpty { b.keyEquivalent = key; b.keyEquivalentModifierMask = [.command] }
        return b
    }

    private func build() {
        search.placeholderString = "Search drafts"
        search.setAccessibilityLabel("Search drafts")
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(reload)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("draft"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 22
        table.allowsMultipleSelection = false
        table.doubleAction = #selector(openSelected)
        table.target = self
        table.setAccessibilityLabel("Drafts")
        table.onReturn = { [weak self] in self?.openSelected() }
        table.onDelete = { [weak self] in self?.deleteSelected() }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let buttons = NSStackView(views: [
            button("Open", #selector(openSelected)),
            button("Pin or Unpin", #selector(togglePin), key: "p"),
            button("Rename\u{2026}", #selector(renameSelected), key: "r"),
            button("Export\u{2026}", #selector(exportSelected), key: "e"),
            button("Delete", #selector(deleteSelected)),
        ])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        countLabel.textColor = .secondaryLabelColor

        let content = NSView()
        for v in [search, scroll, buttons, countLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            search.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            search.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttons.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            countLabel.centerYAnchor.constraint(equalTo: buttons.centerYAnchor),
            countLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        window.contentView = content
        window.initialFirstResponder = table
        search.nextKeyView = table
    }

    func show() {
        reload()
        NSApp.activate(ignoringOtherApps: true)
        if !didCenter { window.center(); didCenter = true }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(table)
    }

    // MARK: Data

    @objc private func reload() {
        let selectedID = selectedDraft()?.id
        let q = search.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        shown = store.ordered.filter { d in
            q.isEmpty || d.text.lowercased().contains(q) || (d.title?.lowercased().contains(q) ?? false)
        }
        table.reloadData()
        if let selectedID, let row = shown.firstIndex(where: { $0.id == selectedID }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if !shown.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        let pinned = store.drafts.filter { $0.pinned }.count
        countLabel.stringValue = "\(store.drafts.count) drafts, \(pinned) pinned"
    }

    func controlTextDidChange(_ obj: Notification) { reload() }

    private func selectedDraft() -> Draft? {
        let row = table.selectedRow
        guard row >= 0, row < shown.count else { return nil }
        return shown[row]
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let d = shown[row]
        let title = (d.pinned ? "Pinned, " : "") + d.displayName + ", " + fmt.string(from: d.created)
        return makeTextCell(tableView, owner: self, text: title)
    }

    // MARK: Actions

    @objc private func openSelected() {
        guard let d = selectedDraft() else { NSSound.beep(); return }
        window.orderOut(nil)
        onOpen?(d.id)
    }

    @objc private func togglePin() {
        guard let d = selectedDraft() else { NSSound.beep(); return }
        store.setPinned(d.id, !d.pinned)
        AppDelegate.shared?.announce(d.pinned ? "Unpinned." : "Pinned.")
    }

    @objc private func renameSelected() {
        guard let d = selectedDraft() else { NSSound.beep(); return }
        if let newName = AppDelegate.askForText(title: "Rename Draft",
                                                message: "Leave empty to use the first line as the name.",
                                                value: d.title ?? "") {
            store.rename(d.id, to: newName)
        }
    }

    @objc private func exportSelected() {
        guard let d = selectedDraft() else { NSSound.beep(); return }
        onExport?(d)
    }

    @objc private func deleteSelected() {
        guard let d = selectedDraft() else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = "Delete \u{201C}\(d.displayName)\u{201D}?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let row = table.selectedRow
        store.remove(d.id)
        onDeleted?(d.id)
        if !shown.isEmpty {
            table.selectRowIndexes(IndexSet(integer: min(row, shown.count - 1)), byExtendingSelection: false)
        }
        AppDelegate.shared?.announce("Deleted.")
    }
}
