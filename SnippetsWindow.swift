// SnippetsWindow.swift
// Snippets window: a list on the left, name and text on the right.
// Changes save as you type.

import Cocoa

@MainActor
final class SnippetsWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate,
                                      NSTextFieldDelegate, NSTextViewDelegate {
    private let window: NSWindow
    private let store: SnippetStore
    private let table = KeyTableView()
    private let nameField = NSTextField(string: "")
    private let textView = NSTextView()
    private var didCenter = false
    private var reloading = false

    init(store: SnippetStore) {
        self.store = store
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 440),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Snippets"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        build()
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        return b
    }

    private func build() {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("snippet"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 22
        table.setAccessibilityLabel("Snippets")
        table.onReturn = { [weak self] in
            guard let self else { return }
            self.window.makeFirstResponder(self.textView)
        }
        table.onDelete = { [weak self] in self?.deleteSnippet() }

        let listScroll = NSScrollView()
        listScroll.documentView = table
        listScroll.hasVerticalScroller = true
        listScroll.borderType = .bezelBorder

        let nameLabel = NSTextField(labelWithString: "Name:")
        nameLabel.setAccessibilityElement(false)
        nameField.setAccessibilityLabel("Snippet name")
        nameField.delegate = self

        let textLabel = NSTextField(labelWithString: "Text:")
        textLabel.setAccessibilityElement(false)
        let textScroll = NSScrollView()
        textScroll.hasVerticalScroller = true
        textScroll.borderType = .bezelBorder
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.font = NSFont.systemFont(ofSize: CGFloat(Settings.shared.fontSize))
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.setAccessibilityLabel("Snippet text")
        textView.delegate = self
        textScroll.documentView = textView

        let buttons = NSStackView(views: [
            button("Add", #selector(addSnippet)),
            button("Delete", #selector(deleteSnippet)),
            button("Move Up", #selector(moveUp)),
            button("Move Down", #selector(moveDown)),
        ])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let content = NSView()
        for v in [listScroll, nameLabel, nameField, textLabel, textScroll, buttons] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            listScroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            listScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            listScroll.widthAnchor.constraint(equalToConstant: 210),
            listScroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -10),

            nameLabel.leadingAnchor.constraint(equalTo: listScroll.trailingAnchor, constant: 12),
            nameLabel.centerYAnchor.constraint(equalTo: nameField.centerYAnchor),
            nameField.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            nameField.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
            nameField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            textLabel.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 10),
            textLabel.leadingAnchor.constraint(equalTo: listScroll.trailingAnchor, constant: 12),
            textScroll.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 4),
            textScroll.leadingAnchor.constraint(equalTo: listScroll.trailingAnchor, constant: 12),
            textScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            textScroll.bottomAnchor.constraint(equalTo: listScroll.bottomAnchor),

            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        window.contentView = content
        window.initialFirstResponder = table
        table.nextKeyView = nameField
        nameField.nextKeyView = textView
        textView.nextKeyView = table
    }

    func show(select id: UUID? = nil) {
        reloadTable(select: id)
        NSApp.activate(ignoringOtherApps: true)
        if !didCenter { window.center(); didCenter = true }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(id == nil ? table : nameField)
    }

    private func reloadTable(select id: UUID? = nil) {
        reloading = true
        let keep = id ?? selected()?.id
        table.reloadData()
        if let keep, let row = store.snippets.firstIndex(where: { $0.id == keep }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if !store.snippets.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        reloading = false
        loadEditor()
    }

    private func selected() -> Snippet? {
        let row = table.selectedRow
        guard row >= 0, row < store.snippets.count else { return nil }
        return store.snippets[row]
    }

    private func loadEditor() {
        let s = selected()
        nameField.stringValue = s?.name ?? ""
        textView.string = s?.text ?? ""
        nameField.isEnabled = s != nil
        textView.isEditable = s != nil
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { store.snippets.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let s = store.snippets[row]
        let number = row < 9 ? "\(row + 1). " : ""
        return makeTextCell(tableView, owner: self, text: number + (s.name.isEmpty ? "Untitled" : s.name))
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if !reloading { loadEditor() }
    }

    // MARK: Editing

    func controlTextDidChange(_ obj: Notification) {
        guard let s = selected() else { return }
        store.update(s.id, name: nameField.stringValue)
        let row = table.selectedRow
        reloading = true
        table.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
        reloading = false
    }

    func textDidChange(_ notification: Notification) {
        guard let s = selected() else { return }
        store.update(s.id, text: textView.string)
    }

    @objc private func addSnippet() {
        let id = store.add(name: "New Snippet", text: "")
        reloadTable(select: id)
        window.makeFirstResponder(nameField)
        nameField.currentEditor()?.selectAll(nil)
    }

    /// Adds a snippet from text (used by Save Selection as Snippet).
    func addFromText(_ text: String) {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "New Snippet"
        let name = firstLine.count > 40 ? String(firstLine.prefix(40)) : firstLine
        let id = store.add(name: name, text: text)
        show(select: id)
        nameField.currentEditor()?.selectAll(nil)
    }

    @objc private func deleteSnippet() {
        guard let s = selected() else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = "Delete the snippet \u{201C}\(s.name)\u{201D}?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let row = table.selectedRow
        store.remove(s.id)
        reloading = true
        table.reloadData()
        if !store.snippets.isEmpty {
            table.selectRowIndexes(IndexSet(integer: min(row, store.snippets.count - 1)), byExtendingSelection: false)
        }
        reloading = false
        loadEditor()
        window.makeFirstResponder(table)
    }

    @objc private func moveUp() { move(-1) }
    @objc private func moveDown() { move(1) }

    private func move(_ by: Int) {
        guard let s = selected() else { NSSound.beep(); return }
        store.move(s.id, by: by)
        reloadTable(select: s.id)
        window.makeFirstResponder(table)
    }
}
