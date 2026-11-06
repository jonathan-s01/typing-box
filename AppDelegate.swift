// AppDelegate.swift
// Window, menus, hotkeys, pasting, pulling text in, drafts, snippets, counts and export.

import Cocoa
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

let restoreClipboardAfter = 1.0   // seconds before your old clipboard is put back

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextViewDelegate, NSMenuItemValidation, NSMenuDelegate {
    static var shared: AppDelegate?

    private var window: NSWindow!
    private var textView: TypingTextView!
    private var draftsPopup: NSPopUpButton!
    private var snippetsButton: NSPopUpButton!
    private var actionsButton: NSPopUpButton!
    private var keyMonitor: Any?
    private var shortcutCache: [(id: String, key: HotKey)] = []
    private var countLabel: NSTextField!
    private var countHeight: NSLayoutConstraint!
    private var statusItem: NSStatusItem!
    private var settingsController: SettingsWindowController?
    private var draftsController: DraftsWindowController?
    private var snippetsController: SnippetsWindowController?
    private var previousApp: NSRunningApplication?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var hotKeyHandlerInstalled = false
    private var isBusy = false
    private var lastText = ""
    private var currentDraftID: UUID?
    private let store = DraftStore()
    private let snippets = SnippetStore()
    private let settings = Settings.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        buildMainMenu()
        buildWindow()
        buildStatusItem()
        registerHotKeys()
        refreshShortcuts()
        installKeyMonitor()
        applyTextSettings()

        // Bring back whatever was in the box last time.
        if let id = settings.currentDraftID, let d = store.draft(id) {
            currentDraftID = id
            textView.string = d.text
        }
        refreshDraftsPopup()
        updateCounts()

        NotificationCenter.default.addObserver(self, selector: #selector(draftsChangedElsewhere),
                                               name: .draftsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildSnippetsMenu),
                                               name: .snippetsChanged, object: nil)

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveNow()
    }

    // MARK: - Menus

    private func item(_ title: String, _ action: Selector?, _ key: String = "",
                      _ mods: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil, tag: Int = 0) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.target = target
        i.tag = tag
        return i
    }

    /// Typing Box doesn't show a menu bar, but this keeps standard editing keys
    /// (cut, copy, paste, undo, select all) working in every Typing Box window.
    /// Everything else is in the Actions menu inside the window.
    private func buildMainMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(item("Settings\u{2026}", #selector(showSettings), ",", target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit Typing Box", #selector(NSApplication.terminate(_:)), "q"))
        addSubmenu(appMenu, "Typing Box", to: main)

        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", NSSelectorFromString("undo:"), "z"))
        edit.addItem(item("Redo", NSSelectorFromString("redo:"), "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        addSubmenu(edit, "Edit", to: main)

        NSApp.mainMenu = main
    }

    private func addSubmenu(_ menu: NSMenu, _ title: String, to parent: NSMenu) {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        parent.addItem(holder)
    }

    @objc private func rebuildSnippetsMenu() {
        if let menu = snippetsButton?.menu { fillSnippetsMenu(menu) }
    }

    // MARK: - Commands and shortcuts

    /// Reloads shortcuts after they change in Settings.
    func refreshShortcuts() {
        shortcutCache = Commands.all.compactMap { c in settings.shortcut(c.id).map { (id: c.id, key: $0) } }
        let commit = settings.shortcut("commit")?.displayName ?? "the Paste shortcut"
        let close = settings.shortcut("close")?.displayName ?? "the Close shortcut"
        let actions = settings.shortcut("actionsMenu").map { " \($0.displayName) shows all actions." } ?? ""
        textView?.setAccessibilityHelp("\(commit) pastes into the previous app. \(close) closes and keeps your draft.\(actions)")
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleShortcut(event) ? nil : event
        }
    }

    /// Runs a command if the key press matches one of its shortcuts. Only works in the Typing Box window.
    private func handleShortcut(_ event: NSEvent) -> Bool {
        guard !ShortcutRecorderButton.isRecording, let window, event.window === window, window.isKeyWindow else {
            return false
        }
        for (id, key) in shortcutCache where key.matches(event) {
            // Let Escape and similar keys reach the Find bar or other small text fields.
            if id == "close", let fr = window.firstResponder as? NSTextView, fr !== textView, fr.isFieldEditor {
                return false
            }
            if event.isARepeat && (id == "commit" || id == "close") { return true }
            runCommand(id)
            return true
        }
        return false
    }

    @objc private func runCommandItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        // Let the menu close before running, so dialogs and focus changes behave.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.runCommand(id) }
        }
    }

    func runCommand(_ id: String) {
        switch id {
        case "commit": commit()
        case "close": cancel()
        case "actionsMenu": showBoxIfHidden(); actionsButton.performClick(nil)
        case "settings": showSettings()
        case "shortcutSettings": showShortcutSettings()
        case "copyLast": copyLastText()
        case "quit": NSApp.terminate(nil)
        case "newDraft": newDraft()
        case "chooseDraft": openDraftsMenu()
        case "allDrafts": showAllDrafts()
        case "togglePin": togglePinCurrent()
        case "renameDraft": renameCurrent()
        case "deleteDraft": deleteDraft()
        case "exportDraft": exportCurrent()
        case "exportAll": exportAll()
        case "snippetMenu": showSnippetPicker()
        case "saveSnippet": saveSelectionAsSnippet()
        case "manageSnippets": showSnippets()
        case "speakTyping": toggleSpeakTyping()
        case "readAll": readAll()
        case "readLine": readLine()
        case "readSentence": readSentence()
        case "readWord": readWord()
        case "readSelection": readSelection()
        case "announceCount": announceCounts()
        case "stopSpeaking": stopSpeaking()
        case "find": findAction(.showFindInterface)
        case "findNext": findAction(.nextMatch)
        case "findPrevious": findAction(.previousMatch)
        case "findReplace": findAction(.showReplaceInterface)
        case "codeMode": toggleCodeMode()
        case "markdown": toggleMarkdown()
        case "spellCheck":
            textView.toggleContinuousSpellChecking(nil)
            toggled("Spell checking", textView.isContinuousSpellCheckingEnabled)
        case "grammar":
            textView.toggleGrammarChecking(nil)
            toggled("Grammar checking", textView.isGrammarCheckingEnabled)
        case "autocorrect":
            textView.toggleAutomaticSpellingCorrection(nil)
            toggled("Automatic spelling correction", textView.isAutomaticSpellingCorrectionEnabled)
        case "smartQuotes":
            textView.toggleAutomaticQuoteSubstitution(nil)
            toggled("Smart quotes", textView.isAutomaticQuoteSubstitutionEnabled)
        case "smartDashes":
            textView.toggleAutomaticDashSubstitution(nil)
            toggled("Smart dashes", textView.isAutomaticDashSubstitutionEnabled)
        case "writingTools":
            settings.writingTools.toggle()
            applyTextSettings()
            announce("Writing Tools \(settings.writingTools ? "on" : "off").")
        case "textReplacement":
            textView.toggleAutomaticTextReplacement(nil)
            toggled("Text replacement", textView.isAutomaticTextReplacementEnabled)
        default:
            if id.hasPrefix("snippet"), let n = Int(id.dropFirst("snippet".count)) { insertSnippet(number: n) }
        }
    }

    private func toggled(_ name: String, _ on: Bool) {
        syncTextSettingsFromView()
        announce("\(name) \(on ? "on" : "off").")
    }

    private func findAction(_ action: NSTextFinder.Action) {
        showBoxIfHidden()
        window.makeFirstResponder(textView)
        let sender = NSMenuItem()
        sender.tag = action.rawValue
        textView.performTextFinderAction(sender)
    }

    /// A menu item that runs a command and shows its current shortcut.
    private func commandItem(_ id: String, _ title: String? = nil, checked: Bool? = nil, enabled: Bool = true) -> NSMenuItem {
        let i = NSMenuItem(title: title ?? Commands.info(id)?.title ?? id,
                           action: #selector(runCommandItem(_:)), keyEquivalent: "")
        i.target = self
        i.representedObject = id
        i.isEnabled = enabled
        // Shortcuts without Command, Option or Control (like Escape) aren't shown,
        // so pressing them while the menu is open just closes the menu.
        if let k = settings.shortcut(id), !k.modifierFlags.intersection([.command, .option, .control]).isEmpty
            || HotKey.isFunctionKey(UInt16(k.keyCode)) {
            i.keyEquivalent = k.menuKeyEquivalent
            i.keyEquivalentModifierMask = k.modifierFlags
        }
        if let checked { i.state = checked ? .on : .off }
        return i
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let m = NSMenu(title: title)
        m.autoenablesItems = false
        for i in items { m.addItem(i) }
        holder.submenu = m
        return holder
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === actionsButton?.menu { fillActionsMenu(menu) }
        if menu === snippetsButton?.menu { fillSnippetsMenu(menu) }
    }

    private func fillActionsMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem(title: "Actions", action: nil, keyEquivalent: ""))   // button title
        let hasDraft = currentDraftID != nil
        let pinned = currentDraftID.flatMap { store.draft($0) }?.pinned ?? false
        let hasSelection = textView.selectedRange().length > 0

        menu.addItem(commandItem("commit"))
        menu.addItem(commandItem("close"))
        menu.addItem(.separator())
        menu.addItem(submenu("Drafts", [
            commandItem("newDraft"),
            commandItem("chooseDraft", "Choose Draft\u{2026}"),
            commandItem("allDrafts", "All Drafts\u{2026}"),
            .separator(),
            commandItem("togglePin", pinned ? "Unpin This Draft" : "Pin This Draft", enabled: hasDraft),
            commandItem("renameDraft", "Rename This Draft\u{2026}", enabled: hasDraft),
            commandItem("deleteDraft", enabled: hasDraft),
            .separator(),
            commandItem("exportDraft", "Export as Text File\u{2026}"),
            commandItem("exportAll", "Export All Drafts\u{2026}"),
        ]))
        menu.addItem(submenu("Snippets", snippetItems(hasSelection: hasSelection)))
        menu.addItem(submenu("Speech", [
            commandItem("speakTyping", "Speak Typing", checked: settings.speakTyping),
            .separator(),
            commandItem("readAll"),
            commandItem("readLine"),
            commandItem("readSentence"),
            commandItem("readWord"),
            commandItem("readSelection"),
            commandItem("announceCount"),
            .separator(),
            commandItem("stopSpeaking", "Stop Speaking (or press Control)"),
        ]))
        menu.addItem(submenu("Find", [
            commandItem("find", "Find\u{2026}"),
            commandItem("findNext"),
            commandItem("findPrevious"),
            commandItem("findReplace", "Find and Replace\u{2026}"),
        ]))
        menu.addItem(submenu("Text Options", [
            commandItem("codeMode", "Code Mode", checked: settings.codeMode),
            commandItem("markdown", "Paste Markdown as Formatting", checked: settings.pasteMarkdown),
            .separator(),
            commandItem("spellCheck", "Check Spelling While Typing", checked: textView.isContinuousSpellCheckingEnabled),
            commandItem("grammar", "Check Grammar With Spelling", checked: textView.isGrammarCheckingEnabled),
            commandItem("autocorrect", "Correct Spelling Automatically", checked: textView.isAutomaticSpellingCorrectionEnabled),
            commandItem("smartQuotes", "Smart Quotes", checked: textView.isAutomaticQuoteSubstitutionEnabled),
            commandItem("smartDashes", "Smart Dashes", checked: textView.isAutomaticDashSubstitutionEnabled),
            commandItem("textReplacement", "Text Replacement", checked: textView.isAutomaticTextReplacementEnabled),
            commandItem("writingTools", "Writing Tools", checked: settings.writingTools),
        ]))
        menu.addItem(.separator())
        menu.addItem(commandItem("settings", "Settings\u{2026}"))
        menu.addItem(commandItem("shortcutSettings", "Keyboard Shortcuts\u{2026}"))
        menu.addItem(commandItem("copyLast"))
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(commandItem("quit"))
    }

    private func snippetItems(hasSelection: Bool) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        for (i, sn) in snippets.snippets.enumerated() {
            let name = sn.name.isEmpty ? "Untitled" : sn.name
            if i < 9 {
                items.append(commandItem("snippet\(i + 1)", name))
            } else {
                let mi = NSMenuItem(title: name, action: #selector(insertSnippet(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = sn.id.uuidString
                items.append(mi)
            }
        }
        if items.isEmpty {
            let none = NSMenuItem(title: "No snippets yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            items.append(none)
        }
        items.append(.separator())
        items.append(commandItem("snippetMenu", "Insert Snippet at Cursor\u{2026}"))
        items.append(commandItem("saveSnippet", enabled: hasSelection))
        items.append(commandItem("manageSnippets", "Manage Snippets\u{2026}"))
        return items
    }

    private func fillSnippetsMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem(title: "Snippets", action: nil, keyEquivalent: ""))   // button title
        for i in snippetItems(hasSelection: textView.selectedRange().length > 0) { menu.addItem(i) }
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Typing Box")
            image?.isTemplate = true
            button.image = image
            button.setAccessibilityLabel("Typing Box")
        }
        let menu = NSMenu()
        menu.addItem(item("Open Typing Box", #selector(showBox), "", [], target: self))
        menu.addItem(item("All Drafts\u{2026}", #selector(showAllDrafts), "", [], target: self))
        menu.addItem(item("Snippets\u{2026}", #selector(showSnippets), "", [], target: self))
        menu.addItem(item("Speak Typing", #selector(toggleSpeakTyping), "", [], target: self))
        menu.addItem(item("Settings\u{2026}", #selector(showSettings), "", [], target: self))
        menu.addItem(item("Keyboard Shortcuts\u{2026}", #selector(showShortcutSettings), "", [], target: self))
        menu.addItem(item("Copy Last Pasted Text", #selector(copyLastText), "", [], target: self))
        menu.addItem(.separator())
        menu.addItem(item("Open at Login", #selector(toggleLogin), "", [], target: self))
        menu.addItem(.separator())
        menu.addItem(item("Quit Typing Box", #selector(NSApplication.terminate(_:)), "", []))
        statusItem.menu = menu
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleSpeakTyping)?:
            menuItem.state = settings.speakTyping ? .on : .off
        case #selector(toggleLogin)?:
            menuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        case #selector(toggleCodeMode)?:
            menuItem.state = settings.codeMode ? .on : .off
        case #selector(toggleMarkdown)?:
            menuItem.state = settings.pasteMarkdown ? .on : .off
        case #selector(togglePinCurrent)?:
            let pinned = currentDraftID.flatMap { store.draft($0) }?.pinned ?? false
            menuItem.title = pinned ? "Unpin This Draft" : "Pin This Draft"
            return currentDraftID != nil
        case #selector(deleteDraft)?, #selector(renameCurrent)?:
            return currentDraftID != nil
        case #selector(saveSelectionAsSnippet)?:
            return window.isVisible && textView.selectedRange().length > 0
        default:
            break
        }
        return true
    }

    // MARK: - Window

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 380),
                          styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Typing Box"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 380))

        let label = NSTextField(labelWithString: "Drafts:")
        label.setAccessibilityElement(false)
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.target = self
        popup.action = #selector(draftChosen(_:))
        popup.setAccessibilityLabel("Drafts")
        popup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        popup.autoenablesItems = false
        draftsPopup = popup

        let snippetsBtn = NSPopUpButton(frame: .zero, pullsDown: true)
        snippetsBtn.menu?.delegate = self
        snippetsBtn.addItem(withTitle: "Snippets")
        snippetsBtn.setAccessibilityLabel("Snippets")
        snippetsBtn.setContentCompressionResistancePriority(.required, for: .horizontal)
        snippetsButton = snippetsBtn

        let actionsBtn = NSPopUpButton(frame: .zero, pullsDown: true)
        actionsBtn.menu?.delegate = self
        actionsBtn.addItem(withTitle: "Actions")
        actionsBtn.setAccessibilityLabel("Actions")
        actionsBtn.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionsButton = actionsBtn

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
        scroll.hasVerticalScroller = true

        let tv = TypingTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        _ = tv.layoutManager   // use the classic text system so line reading is reliable
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.delegate = self
        tv.setAccessibilityLabel("Typing Box text")
        scroll.documentView = tv
        textView = tv

        let counts = NSTextField(labelWithString: "")
        counts.textColor = .secondaryLabelColor
        counts.setAccessibilityLabel("Count")
        countLabel = counts

        for v in [label, popup, snippetsBtn, actionsBtn, scroll, counts] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        countHeight = counts.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: popup.centerYAnchor),
            popup.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            popup.trailingAnchor.constraint(equalTo: snippetsBtn.leadingAnchor, constant: -8),
            popup.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            snippetsBtn.centerYAnchor.constraint(equalTo: popup.centerYAnchor),
            snippetsBtn.trailingAnchor.constraint(equalTo: actionsBtn.leadingAnchor, constant: -8),
            actionsBtn.centerYAnchor.constraint(equalTo: popup.centerYAnchor),
            actionsBtn.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: popup.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            counts.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 4),
            counts.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            counts.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
            counts.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -6),
        ])
        window.contentView = content
        window.initialFirstResponder = tv
        popup.nextKeyView = snippetsBtn
        snippetsBtn.nextKeyView = actionsBtn
        actionsBtn.nextKeyView = tv
        tv.nextKeyView = popup
        window.center()
        window.setFrameAutosaveName("TypingBoxWindow")
    }

    func applyTextSettings() {
        guard let tv = textView else { return }
        let size = CGFloat(settings.fontSize)
        let font: NSFont
        switch settings.fontName {
        case "": font = NSFont.systemFont(ofSize: size)
        case "monospaced": font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        default: font = NSFontManager.shared.font(withFamily: settings.fontName, traits: [], weight: 5, size: size)
            ?? NSFont.systemFont(ofSize: size)
        }
        tv.font = font

        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = CGFloat(settings.lineSpacing)
        tv.defaultParagraphStyle = para
        var typing = tv.typingAttributes
        typing[.paragraphStyle] = para
        typing[.font] = font

        if settings.customColors {
            tv.textColor = settings.textColor
            tv.backgroundColor = settings.backgroundColor
            tv.insertionPointColor = settings.textColor
            tv.enclosingScrollView?.backgroundColor = settings.backgroundColor
            typing[.foregroundColor] = settings.textColor
        } else {
            tv.textColor = .textColor
            tv.backgroundColor = .textBackgroundColor
            tv.insertionPointColor = .textColor
            tv.enclosingScrollView?.backgroundColor = .textBackgroundColor
            typing[.foregroundColor] = NSColor.textColor
        }
        tv.typingAttributes = typing
        if let storage = tv.textStorage, storage.length > 0 {
            let all = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttribute(.paragraphStyle, value: para, range: all)
            storage.addAttribute(.font, value: font, range: all)
            storage.addAttribute(.foregroundColor, value: typing[.foregroundColor] ?? NSColor.textColor, range: all)
            storage.endEditing()
        }

        tv.isContinuousSpellCheckingEnabled = settings.spellCheck
        tv.isGrammarCheckingEnabled = settings.grammarCheck
        tv.isAutomaticSpellingCorrectionEnabled = settings.autoCorrect
        tv.isAutomaticQuoteSubstitutionEnabled = settings.smartQuotes
        tv.isAutomaticDashSubstitutionEnabled = settings.smartDashes
        tv.isAutomaticTextReplacementEnabled = settings.textReplacement
        // The Writing Tools button that pops up over selected text shows up to VoiceOver as a
        // dialog and can leave VoiceOver silent, so it's off unless turned on in Settings.
        if #available(macOS 15.0, *) {
            tv.writingToolsBehavior = settings.writingTools ? .default : .none
        }
        // Inline predictive text can also show a floating suggestion; keep it off.
        if #available(macOS 14.0, *) {
            tv.inlinePredictionType = .no
        }

        countLabel.isHidden = !settings.showCounts
        countHeight.isActive = !settings.showCounts
        updateCounts()
    }

    /// Picks up changes made from the Edit menu so they're remembered.
    private func syncTextSettingsFromView() {
        guard let tv = textView else { return }
        settings.spellCheck = tv.isContinuousSpellCheckingEnabled
        settings.grammarCheck = tv.isGrammarCheckingEnabled
        settings.autoCorrect = tv.isAutomaticSpellingCorrectionEnabled
        settings.smartQuotes = tv.isAutomaticQuoteSubstitutionEnabled
        settings.smartDashes = tv.isAutomaticDashSubstitutionEnabled
        settings.textReplacement = tv.isAutomaticTextReplacementEnabled
    }

    private func makeSettingsController() -> SettingsWindowController {
        if let c = settingsController { return c }
        let c = SettingsWindowController(
            onTextSettingsChanged: { [weak self] in self?.applyTextSettings() },
            onClearDrafts: { [weak self] in self?.clearAllDrafts() },
            onHotKeysChanged: { [weak self] in
                self?.registerHotKeys()
                self?.refreshShortcuts()
            },
            onSuspendHotKeys: { [weak self] in self?.unregisterHotKeys() })
        settingsController = c
        return c
    }

    @objc func showSettings() {
        syncTextSettingsFromView()
        makeSettingsController().show()
    }

    @objc func showShortcutSettings() {
        syncTextSettingsFromView()
        makeSettingsController().show(shortcuts: true)
    }

    @objc func toggleCodeMode() {
        settings.codeMode.toggle()
        announce(settings.codeMode ? "Code mode on." : "Code mode off.")
    }

    @objc func toggleMarkdown() {
        settings.pasteMarkdown.toggle()
        announce(settings.pasteMarkdown ? "Markdown formatting on." : "Markdown formatting off.")
    }

    // MARK: - Word and character count

    private func counts(of text: String) -> (words: Int, chars: Int) {
        var words = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            words += 1
        }
        return (words, text.count)
    }

    private func plural(_ n: Int, _ word: String) -> String {
        "\(n) \(word)\(n == 1 ? "" : "s")"
    }

    private func countSummary() -> String {
        let all = counts(of: textView.string)
        var text = "\(plural(all.words, "word")), \(plural(all.chars, "character"))"
        let sel = textView.selectedText()
        if !sel.isEmpty {
            let c = counts(of: sel)
            text += ". Selected: \(plural(c.words, "word")), \(plural(c.chars, "character"))"
        }
        return text
    }

    private func updateCounts() {
        guard let countLabel, settings.showCounts else { return }
        countLabel.stringValue = countSummary()
    }

    /// Updates the count shortly after the selection stops changing,
    /// so holding Shift and an arrow key doesn't update it on every step.
    func textViewDidChangeSelection(_ notification: Notification) {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(updateCountsLater), object: nil)
        perform(#selector(updateCountsLater), with: nil, afterDelay: 0.3)
    }

    @objc private func updateCountsLater() { updateCounts() }

    @objc func announceCounts() {
        readOut(countSummary())
    }

    // MARK: - Reading

    /// Speaks with VoiceOver if it's running and Typing Box is set to stay quiet, otherwise with Typing Box's voice.
    private func readOut(_ text: String) {
        if Speaker.shared.voiceOverRunning && settings.silentWithVoiceOver {
            announce(text.isEmpty ? "Empty" : text)
        } else {
            Speaker.shared.readText(text)
        }
    }

    @objc func readAll() { readOut(textView.string) }
    @objc func readLine() {
        let line = textView.currentLineText()
        readOut(Speaker.shared.indentPrefix(line) + line)
    }
    @objc func readSentence() { readOut(textView.currentSentenceText()) }
    @objc func readWord() { readOut(textView.currentWordText()) }
    @objc func readSelection() {
        let sel = textView.selectedText()
        readOut(sel.isEmpty ? "Nothing selected" : sel)
    }
    @objc func stopSpeaking() { Speaker.shared.stop() }

    // MARK: - Drafts

    private func refreshDraftsPopup() {
        guard let popup = draftsPopup, let menu = popup.menu else { return }
        popup.removeAllItems()
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem(title: "New Draft", action: nil, keyEquivalent: ""))
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short

        func header(_ title: String) {
            menu.addItem(.separator())
            let h = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            h.isEnabled = false
            menu.addItem(h)
        }
        func add(_ d: Draft) {
            let title = (d.pinned ? "Pinned, " : "") + d.displayName + ", " + fmt.string(from: d.created)
            let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            i.representedObject = d.id.uuidString
            menu.addItem(i)
        }
        let pinned = store.drafts.filter { $0.pinned }
        let recent = store.drafts.filter { !$0.pinned }
        if !pinned.isEmpty { header("Pinned"); pinned.forEach(add) }
        if !recent.isEmpty { header("Recent"); recent.forEach(add) }

        let target = currentDraftID?.uuidString
        if let target, let idx = popup.itemArray.firstIndex(where: { ($0.representedObject as? String) == target }) {
            popup.selectItem(at: idx)
        } else {
            popup.selectItem(at: 0)
        }
    }

    @objc private func draftsChangedElsewhere() {
        // A draft may have been deleted from the All Drafts window.
        if let id = currentDraftID, store.draft(id) == nil { setCurrentDraft(nil) }
        refreshDraftsPopup()
    }

    private func setCurrentDraft(_ id: UUID?) {
        currentDraftID = id
        settings.currentDraftID = id
    }

    /// Saves the box text into its draft (or a new draft at the top).
    private func saveNow() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(autosave), object: nil)
        guard textView != nil else { return }
        let newID = store.upsert(id: currentDraftID, text: textView.string)
        if newID != currentDraftID { setCurrentDraft(newID) }
        refreshDraftsPopup()
        syncTextSettingsFromView()
    }

    @objc private func autosave() { saveNow() }

    func textDidChange(_ notification: Notification) {
        updateCounts()
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(autosave), object: nil)
        perform(#selector(autosave), with: nil, afterDelay: 1.0)
    }

    private func loadIntoBox(_ text: String, id: UUID?) {
        setCurrentDraft(id)
        textView.string = text
        applyTextSettings()
        textView.undoManager?.removeAllActions()
        let end = (text as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
        refreshDraftsPopup()
        updateCounts()
    }

    @objc private func draftChosen(_ sender: NSPopUpButton) {
        let chosen = (sender.selectedItem?.representedObject as? String).flatMap { UUID(uuidString: $0) }
        saveNow()
        if let id = chosen, let d = store.draft(id) {
            loadIntoBox(d.text, id: id)
        } else {
            loadIntoBox("", id: nil)
        }
        window.makeFirstResponder(textView)
    }

    private func openDraft(_ id: UUID) {
        saveNow()
        guard let d = store.draft(id) else { return }
        loadIntoBox(d.text, id: id)
        showBox()
    }

    @objc func newDraft() {
        showBoxIfHidden()
        saveNow()
        loadIntoBox("", id: nil)
        window.makeFirstResponder(textView)
        Speaker.shared.say("New draft")
    }

    @objc func openDraftsMenu() {
        showBoxIfHidden()
        saveNow()
        draftsPopup.performClick(nil)
    }

    @objc func showAllDrafts() {
        saveNow()
        if draftsController == nil {
            let c = DraftsWindowController(store: store)
            c.onOpen = { [weak self] id in self?.openDraft(id) }
            c.onDeleted = { [weak self] id in
                guard let self, self.currentDraftID == id else { return }
                self.loadIntoBox("", id: nil)
            }
            c.onExport = { [weak self] d in
                self?.saveTextFile(d.text, name: "\(d.displayName.prefix(40)) \(self?.stamp() ?? "").txt")
            }
            draftsController = c
        }
        draftsController?.show()
    }

    @objc func togglePinCurrent() {
        saveNow()
        guard let id = currentDraftID, let d = store.draft(id) else { return }
        store.setPinned(id, !d.pinned)
        announce(d.pinned ? "Unpinned." : "Pinned.")
    }

    @objc func renameCurrent() {
        saveNow()
        guard let id = currentDraftID, let d = store.draft(id) else { return }
        if let name = AppDelegate.askForText(title: "Rename Draft",
                                             message: "Leave empty to use the first line as the name.",
                                             value: d.title ?? "") {
            store.rename(id, to: name)
        }
    }

    @objc func deleteDraft() {
        guard let id = currentDraftID else { return }
        store.remove(id)
        loadIntoBox("", id: nil)
        announce("Draft deleted.")
    }

    private func clearAllDrafts() {
        let alert = NSAlert()
        alert.messageText = "Clear all unpinned drafts?"
        alert.informativeText = "Pinned drafts and the text currently in the box are kept."
        alert.addButton(withTitle: "Clear Drafts")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.removeAllUnpinned()
        if let id = currentDraftID, store.draft(id) == nil { setCurrentDraft(nil) }
        saveNow()
        announce("Drafts cleared.")
    }

    /// Asks for one line of text. Returns nil if cancelled.
    static func askForText(title: String, message: String, value: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(string: value)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        field.setAccessibilityLabel(title)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    // MARK: - Snippets

    @objc func showSnippets() {
        if snippetsController == nil { snippetsController = SnippetsWindowController(store: snippets) }
        snippetsController?.show()
    }

    @objc func saveSelectionAsSnippet() {
        let sel = textView.selectedText()
        guard !sel.isEmpty else { announce("Nothing selected.", error: true); return }
        if snippetsController == nil { snippetsController = SnippetsWindowController(store: snippets) }
        snippetsController?.addFromText(sel)
    }

    @objc func insertSnippet(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String, let id = UUID(uuidString: idString),
              let sn = snippets.snippet(id) else { return }
        insert(sn)
    }

    private func insertSnippet(number n: Int) {
        guard n >= 1, n <= snippets.snippets.count else {
            announce("There's no snippet \(n).", error: true)
            return
        }
        insert(snippets.snippets[n - 1])
    }

    private func insert(_ sn: Snippet) {
        showBoxIfHidden()
        window.makeFirstResponder(textView)
        textView.insertText(sn.text, replacementRange: textView.selectedRange())
        readOut("Inserted \(sn.name)")
    }

    /// Shows a menu of snippets at the cursor.
    @objc func showSnippetPicker() {
        showBoxIfHidden()
        guard !snippets.snippets.isEmpty else {
            announce("No snippets yet. Add some in Manage Snippets.", error: true)
            return
        }
        let menu = NSMenu(title: "Insert Snippet")
        for (i, s) in snippets.snippets.enumerated() {
            let key = i < 9 ? "\(i + 1)" : ""
            let mi = item(s.name.isEmpty ? "Untitled" : s.name, #selector(insertSnippet(_:)), key, [], target: self)
            mi.representedObject = s.id.uuidString
            menu.addItem(mi)
        }
        // Put the menu just below the cursor.
        var point = NSPoint(x: 20, y: 20)
        let caret = textView.firstRect(forCharacterRange: textView.selectedRange(), actualRange: nil)
        if caret != .zero {
            let inWindow = window.convertFromScreen(caret)
            let inView = textView.convert(inWindow, from: nil)
            point = NSPoint(x: inView.minX, y: textView.isFlipped ? inView.maxY : inView.minY)
        }
        menu.popUp(positioning: nil, at: point, in: textView)
    }

    // MARK: - Export

    func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HHmm"
        return f.string(from: Date())
    }

    @objc func exportCurrent() {
        showBoxIfHidden()
        let text = textView.string
        guard !text.isEmpty else { announce("Nothing to export.", error: true); return }
        saveTextFile(text, name: "Typing Box \(stamp()).txt")
    }

    @objc func exportAll() {
        showBoxIfHidden()
        saveNow()
        guard !store.drafts.isEmpty else { announce("No drafts to export.", error: true); return }
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .short
        let body = store.ordered
            .map { d -> String in
                var header = f.string(from: d.created)
                if let t = d.title { header = t + ", " + header }
                if d.pinned { header = "Pinned, " + header }
                return header + "\n\n" + d.text
            }
            .joined(separator: "\n\n----------\n\n")
        saveTextFile(body + "\n", name: "Typing Box drafts \(stamp()).txt")
    }

    private func saveTextFile(_ text: String, name: String) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.level = .modalPanel
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            announce("Exported.")
        } catch {
            showAlert("Could not save the file: \(error.localizedDescription)")
        }
    }

    // MARK: - Speech menu

    @objc func toggleSpeakTyping() {
        settings.speakTyping.toggle()
        if settings.speakTyping {
            Speaker.shared.say("Speak typing on")
            if Speaker.shared.voiceOverRunning && settings.silentWithVoiceOver {
                announce("Speak typing is on, but stays silent while VoiceOver is on. You can change this in Settings.")
            }
        } else {
            if NSWorkspace.shared.isVoiceOverEnabled {
                announce("Speak typing off.")
            } else {
                Speaker.shared.speak([Speaker.Part(text: "Speak typing off")])
            }
        }
    }

    // MARK: - Hotkeys

    private func installHotKeyHandler() {
        guard !hotKeyHandlerInstalled else { return }
        hotKeyHandlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            _ = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let which = hk.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if which == 2 { AppDelegate.shared?.pullIn(selectionOnly: false) } else { AppDelegate.shared?.openFromHotKey() }
                }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    func unregisterHotKeys() {
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
    }

    func registerHotKeys() {
        installHotKeyHandler()
        unregisterHotKeys()
        var failed: [String] = []
        for n in 1...2 {
            let k = settings.hotKey(n)
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: OSType(0x5459_4258), id: UInt32(n))
            let status = RegisterEventHotKey(k.keyCode, k.carbonMods, hkID, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { hotKeyRefs.append(ref) } else { failed.append(k.displayName) }
        }
        if !failed.isEmpty {
            showAlert("\(failed.joined(separator: " and ")) could not be registered. Another app may already be using it. You can choose a different shortcut in Settings, Shortcuts.")
        }
    }

    // MARK: - Open, cancel, commit

    @objc func showBox() {
        let me = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != me {
            previousApp = front
        }
        refreshDraftsPopup()
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        let end = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
        Speaker.shared.say(textView.string.isEmpty ? "Typing Box, empty" : "Typing Box")
    }

    private func showBoxIfHidden() {
        if !window.isVisible { showBox() }
    }

    private func cancel() {
        saveNow()
        Speaker.shared.stop()
        window.orderOut(nil)
        NSApp.hide(nil)
        _ = previousApp?.activate(options: [])
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancel()
        return false
    }

    private func commit() {
        guard !isBusy else { return }
        let text = textView.string
        if text.isEmpty { cancel(); return }
        isBusy = true
        lastText = text
        saveNow()                    // keeps it in the Drafts menu
        Speaker.shared.stop()

        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        pb.clearContents()
        pb.setString(text, forType: .string)
        if settings.pasteMarkdown {
            pb.setString(Markdown.html(from: text), forType: .html)
        }
        pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let ourChange = pb.changeCount

        loadIntoBox("", id: nil)     // the box starts fresh next time
        window.orderOut(nil)
        let target = previousApp

        waitForKeysUp(onlyReturn: true, triesLeft: 60) { [weak self] in
            guard let self else { return }
            NSApp.hide(nil)
            _ = target?.activate(options: [])

            guard AXIsProcessTrusted() else {
                self.isBusy = false
                self.announce("Text copied. Typing Box needs Accessibility permission to paste, so press Command V.", error: true)
                return
            }
            guard let target else {
                self.isBusy = false
                self.announce("No previous app found. Text copied, press Command V.", error: true)
                return
            }
            self.waitUntilFrontmost(target, triesLeft: 40) { ok in
                self.isBusy = false
                if ok {
                    self.postKey(kVK_ANSI_V)
                    DispatchQueue.main.asyncAfter(deadline: .now() + restoreClipboardAfter) {
                        if pb.changeCount == ourChange { self.restore(saved, to: pb) }
                    }
                } else {
                    self.announce("Could not return to the previous app. Text copied, press Command V.", error: true)
                }
            }
        }
    }

    // MARK: - Pull text in

    /// First shortcut: if text is selected in the current field, cut just that into the box.
    /// If nothing is selected, open the box without touching the field.
    @objc func openFromHotKey() {
        let me = ProcessInfo.processInfo.processIdentifier
        guard !isBusy,
              let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != me,
              AXIsProcessTrusted(),
              fieldHasSelection(in: front) else {
            showBox()
            return
        }
        pullIn(selectionOnly: true)
    }

    /// Cuts text out of the current field and opens it in the box.
    /// selectionOnly true: Command X only. False: Command A then Command X (the whole field).
    func pullIn(selectionOnly: Bool) {
        guard !isBusy else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != me else {
            showBox()
            return
        }
        guard AXIsProcessTrusted() else {
            announce("Typing Box needs Accessibility permission to pull in text.", error: true)
            return
        }
        isBusy = true
        previousApp = front
        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        let before = pb.changeCount

        waitForKeysUp(onlyReturn: false, triesLeft: 50) { [weak self] in
            guard let self else { return }
            if !selectionOnly { self.postKey(kVK_ANSI_A) }
            DispatchQueue.main.asyncAfter(deadline: .now() + (selectionOnly ? 0.05 : 0.15)) {
                self.postKey(kVK_ANSI_X)
                self.waitForClipboardChange(pb, from: before, triesLeft: 20) { changed in
                    self.isBusy = false
                    guard changed else {
                        self.showBox()
                        self.announce("Nothing was cut from the field.", error: true)
                        return
                    }
                    let text = pb.string(forType: .string) ?? ""
                    if text.isEmpty {
                        // Something was cut but it isn't text. Leave it on the clipboard so it isn't lost.
                        self.showBox()
                        self.announce("What was cut isn\u{2019}t plain text. It\u{2019}s on the clipboard, or press Command Z in the app to undo.", error: true)
                        return
                    }
                    self.restore(saved, to: pb)
                    self.saveNow()                         // keep the old draft in the Drafts menu
                    self.loadIntoBox(text, id: nil)
                    self.saveNow()                         // pulled text becomes its own draft
                    self.showBox()
                    Speaker.shared.say(selectionOnly ? "Selection pulled in" : "Field pulled in")
                }
            }
        }
    }

    // MARK: - Helpers

    /// Asks the app, through the accessibility API, whether the focused field has selected text.
    /// Returns false if the app doesn't answer.
    private func fieldHasSelection(in app: NSRunningApplication) -> Bool {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.5)
        // Electron apps only expose their text fields when asked to. Other apps ignore this.
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focusedRef = focused, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return false }
        let field = focusedRef as! AXUIElement
        AXUIElementSetMessagingTimeout(field, 0.5)

        var rangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
           let rv = rangeValue, CFGetTypeID(rv) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(rv as! AXValue, .cfRange, &range) { return range.length > 0 }
        }
        var selected: CFTypeRef?
        if AXUIElementCopyAttributeValue(field, kAXSelectedTextAttribute as CFString, &selected) == .success,
           let text = selected as? String {
            return !text.isEmpty
        }
        return false
    }

    /// Waits for Return (and, if needed, Command, Option, Shift and Control) to be released.
    private func waitForKeysUp(onlyReturn: Bool, triesLeft: Int, then done: @escaping () -> Void) {
        var held = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Return))
            || CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_ANSI_KeypadEnter))
        if !onlyReturn {
            let f = CGEventSource.flagsState(.combinedSessionState)
            held = held || f.contains(.maskCommand) || f.contains(.maskAlternate)
                || f.contains(.maskShift) || f.contains(.maskControl)
            let k = settings.hotKey(1), k2 = settings.hotKey(2)
            held = held || CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(k.keyCode))
                || CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(k2.keyCode))
        }
        if !held || triesLeft <= 0 { done(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.waitForKeysUp(onlyReturn: onlyReturn, triesLeft: triesLeft - 1, then: done)
        }
    }

    private func waitUntilFrontmost(_ app: NSRunningApplication, triesLeft: Int, then done: @escaping (Bool) -> Void) {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { done(true) }
            return
        }
        if triesLeft <= 0 { done(false); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.waitUntilFrontmost(app, triesLeft: triesLeft - 1, then: done)
        }
    }

    private func waitForClipboardChange(_ pb: NSPasteboard, from count: Int, triesLeft: Int, then done: @escaping (Bool) -> Void) {
        if pb.changeCount != count { done(true); return }
        if triesLeft <= 0 { done(false); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.waitForClipboardChange(pb, from: count, triesLeft: triesLeft - 1, then: done)
        }
    }

    /// Sends Command plus a key to the frontmost app.
    private func postKey(_ keyCode: Int) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let code = CGKeyCode(keyCode)
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func snapshot(_ pb: NSPasteboard) -> [NSPasteboardItem] {
        (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private func restore(_ items: [NSPasteboardItem], to pb: NSPasteboard) {
        pb.clearContents()
        if !items.isEmpty { pb.writeObjects(items) }
    }

    @objc private func copyLastText() {
        guard !lastText.isEmpty else { announce("Nothing has been pasted yet.", error: true); return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(lastText, forType: .string)
        announce("Last text copied.")
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert("Could not change the login setting: \(error.localizedDescription)")
        }
    }

    /// Tells you something through VoiceOver if it's on, otherwise through Typing Box's voice.
    func announce(_ message: String, error: Bool = false) {
        if error { NSSound.beep() }
        if NSWorkspace.shared.isVoiceOverEnabled {
            NSAccessibility.post(element: NSApp as Any,
                                 notification: .announcementRequested,
                                 userInfo: [.announcement: message,
                                            .priority: NSAccessibilityPriorityLevel.high.rawValue])
        } else {
            Speaker.shared.say(message)   // only when Speak Typing is on
        }
    }

    private func showAlert(_ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Typing Box"
        alert.informativeText = text
        alert.runModal()
    }
}
