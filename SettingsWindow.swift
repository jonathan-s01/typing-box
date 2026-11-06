// SettingsWindow.swift
// The Settings window (Command Comma while Typing Box is open).
// Four tabs: Speech, Text and Display, Code and Paste, Shortcuts.

import Cocoa
import AVFoundation

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let s = Settings.shared
    private let onTextSettingsChanged: () -> Void
    private let onClearDrafts: () -> Void
    private let onHotKeysChanged: () -> Void
    private let onSuspendHotKeys: () -> Void
    private var didCenter = false

    // Speech
    private let speakTyping = NSButton(checkboxWithTitle: "Speak typing with Typing Box\u{2019}s own voice", target: nil, action: nil)
    private let silentVO = NSButton(checkboxWithTitle: "Stay silent while VoiceOver is on", target: nil, action: nil)
    private let voicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let rateSlider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let pitchSlider = NSSlider(value: 100, minValue: 50, maxValue: 200, target: nil, action: nil)
    private let volumeSlider = NSSlider(value: 100, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let rateValue = NSTextField(labelWithString: "")
    private let pitchValue = NSTextField(labelWithString: "")
    private let volumeValue = NSTextField(labelWithString: "")
    private let previewButton = NSButton(title: "Preview Voice", target: nil, action: nil)
    private let echoPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let capsPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let deletePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let punctPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let speakNav = NSButton(checkboxWithTitle: "Speak when moving the cursor", target: nil, action: nil)
    private let speakSel = NSButton(checkboxWithTitle: "Speak selection changes", target: nil, action: nil)
    private let edgeSound = NSButton(checkboxWithTitle: "Play a sound at the start or end of the text", target: nil, action: nil)

    // Text and display
    private let fontSizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fontNamePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let spacingPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let customColors = NSButton(checkboxWithTitle: "Use my own colours", target: nil, action: nil)
    private let textColorWell = NSColorWell()
    private let bgColorWell = NSColorWell()
    private let showCounts = NSButton(checkboxWithTitle: "Show word and character count", target: nil, action: nil)
    private let spell = NSButton(checkboxWithTitle: "Check spelling while typing", target: nil, action: nil)
    private let grammar = NSButton(checkboxWithTitle: "Check grammar with spelling", target: nil, action: nil)
    private let autocorrect = NSButton(checkboxWithTitle: "Correct spelling automatically", target: nil, action: nil)
    private let quotes = NSButton(checkboxWithTitle: "Smart quotes", target: nil, action: nil)
    private let dashes = NSButton(checkboxWithTitle: "Smart dashes", target: nil, action: nil)
    private let replacement = NSButton(checkboxWithTitle: "Text replacement", target: nil, action: nil)
    private let writingTools = NSButton(checkboxWithTitle: "Writing Tools (can make VoiceOver go silent when selecting text)", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear Unpinned Drafts\u{2026}", target: nil, action: nil)

    // Code and paste
    private let codeMode = NSButton(checkboxWithTitle: "Code mode", target: nil, action: nil)
    private let indentPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let speakIndent = NSButton(checkboxWithTitle: "Speak indentation when reading lines", target: nil, action: nil)
    private let pasteMarkdown = NSButton(checkboxWithTitle: "Paste Markdown as formatting", target: nil, action: nil)

    // Shortcuts
    private let hotKey1: ShortcutRecorderButton
    private let hotKey2: ShortcutRecorderButton
    private var localRecorders: [String: ShortcutRecorderButton] = [:]
    private let resetKeys = NSButton(title: "Reset All Shortcuts to Defaults", target: nil, action: nil)
    private let tabs = NSTabView()

    private let fontSizes: [Double] = [12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 64]
    private let spacings: [Double] = [1.0, 1.15, 1.5, 2.0]
    private let indents: [Int] = [2, 4, 8]

    init(onTextSettingsChanged: @escaping () -> Void,
         onClearDrafts: @escaping () -> Void,
         onHotKeysChanged: @escaping () -> Void,
         onSuspendHotKeys: @escaping () -> Void) {
        self.onTextSettingsChanged = onTextSettingsChanged
        self.onClearDrafts = onClearDrafts
        self.onHotKeysChanged = onHotKeysChanged
        self.onSuspendHotKeys = onSuspendHotKeys
        hotKey1 = ShortcutRecorderButton(name: "Open Typing Box, or pull in selected text", hotKey: Settings.shared.hotKey(1), allowsClear: false)
        hotKey2 = ShortcutRecorderButton(name: "Pull in the whole field", hotKey: Settings.shared.hotKey(2), allowsClear: false)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 560),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Typing Box Settings"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        build()
    }

    // MARK: Layout helpers

    private func label(_ title: String, for control: NSView) -> NSTextField {
        let l = NSTextField(labelWithString: title + ":")
        l.alignment = .right
        l.setAccessibilityElement(false)        // the control carries the name instead
        control.setAccessibilityLabel(title)
        return l
    }

    private func note(_ text: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.textColor = .secondaryLabelColor
        l.preferredMaxLayoutWidth = 380
        return l
    }

    private func sliderRow(_ slider: NSSlider, _ value: NSTextField) -> NSStackView {
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 240).isActive = true
        value.setAccessibilityElement(false)    // VoiceOver reads the slider's own value
        value.widthAnchor.constraint(equalToConstant: 44).isActive = true
        return NSStackView(views: [slider, value])
    }

    private func fill(_ popup: NSPopUpButton, _ titles: [String]) {
        popup.removeAllItems()
        for t in titles { popup.menu?.addItem(NSMenuItem(title: t, action: nil, keyEquivalent: "")) }
    }

    private func grid(_ rows: [[NSView]]) -> NSView {
        let g = NSGridView(views: rows)
        g.rowSpacing = 8
        g.columnSpacing = 10
        g.column(at: 0).xPlacement = .trailing
        for i in 0..<g.numberOfRows { g.row(at: i).yPlacement = .center }
        let holder = NSView()
        g.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(g)
        NSLayoutConstraint.activate([
            g.topAnchor.constraint(equalTo: holder.topAnchor, constant: 16),
            g.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 16),
            g.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor, constant: -16),
            g.bottomAnchor.constraint(lessThanOrEqualTo: holder.bottomAnchor, constant: -16),
        ])
        return holder
    }

    private func tab(_ title: String, _ view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        item.view = view
        return item
    }

    // MARK: Build

    private func build() {
        let checkboxes = [speakTyping, silentVO, speakNav, speakSel, edgeSound, customColors, showCounts,
                          spell, grammar, autocorrect, quotes, dashes, replacement, writingTools,
                          codeMode, speakIndent, pasteMarkdown]
        for cb in checkboxes { cb.target = self; cb.action = #selector(changed(_:)) }
        for c in [rateSlider, pitchSlider, volumeSlider] { c.target = self; c.action = #selector(changed(_:)) }
        for p in [voicePopup, echoPopup, capsPopup, deletePopup, punctPopup,
                  fontSizePopup, fontNamePopup, spacingPopup, indentPopup] {
            p.target = self; p.action = #selector(changed(_:))
        }
        for w in [textColorWell, bgColorWell] {
            w.target = self; w.action = #selector(changed(_:))
            w.widthAnchor.constraint(equalToConstant: 60).isActive = true
        }
        previewButton.target = self; previewButton.action = #selector(preview)
        clearButton.target = self; clearButton.action = #selector(clearDrafts)
        resetKeys.target = self; resetKeys.action = #selector(resetHotKeys)

        for b in [hotKey1, hotKey2] {
            b.onRecordingStarted = { [weak self] in self?.onSuspendHotKeys() }
        }
        hotKey1.onRecorded = { [weak self] r in self?.recordedGlobal(1, r) }
        hotKey2.onRecorded = { [weak self] r in self?.recordedGlobal(2, r) }

        fill(echoPopup, EchoMode.allCases.map { $0.title })
        fill(capsPopup, CapsMode.allCases.map { $0.title })
        fill(deletePopup, DeleteMode.allCases.map { $0.title })
        fill(punctPopup, PunctuationLevel.allCases.map { $0.title })
        fill(fontSizePopup, fontSizes.map { "\(Int($0)) point" })
        fill(spacingPopup, ["Single", "1.15", "1.5", "Double"])
        fill(indentPopup, indents.map { "\($0) spaces" })
        fillVoices()
        fillFonts()

        let empty = NSGridCell.emptyContentView

        let speech = grid([
            [empty, speakTyping],
            [empty, silentVO],
            [label("Voice", for: voicePopup), voicePopup],
            [label("Rate", for: rateSlider), sliderRow(rateSlider, rateValue)],
            [label("Pitch", for: pitchSlider), sliderRow(pitchSlider, pitchValue)],
            [label("Volume", for: volumeSlider), sliderRow(volumeSlider, volumeValue)],
            [empty, previewButton],
            [label("Typing echo", for: echoPopup), echoPopup],
            [label("Capital letters", for: capsPopup), capsPopup],
            [label("Deleted text", for: deletePopup), deletePopup],
            [label("Punctuation", for: punctPopup), punctPopup],
            [empty, speakNav],
            [empty, speakSel],
            [empty, edgeSound],
        ])

        let text = grid([
            [label("Font", for: fontNamePopup), fontNamePopup],
            [label("Text size", for: fontSizePopup), fontSizePopup],
            [label("Line spacing", for: spacingPopup), spacingPopup],
            [empty, customColors],
            [label("Text colour", for: textColorWell), textColorWell],
            [label("Background colour", for: bgColorWell), bgColorWell],
            [empty, showCounts],
            [empty, spell],
            [empty, grammar],
            [empty, autocorrect],
            [empty, quotes],
            [empty, dashes],
            [empty, replacement],
            [empty, writingTools],
            [empty, clearButton],
        ])

        let code = grid([
            [empty, codeMode],
            [empty, note("Tab inserts spaces, Return keeps the current indent, and Shift Tab removes one indent.")],
            [label("Indent width", for: indentPopup), indentPopup],
            [empty, speakIndent],
            [empty, pasteMarkdown],
            [empty, note("Pastes **bold**, *italic*, lists, headings, links and code as real formatting in apps that support it, like Teams and Outlook. Plain text apps still get the text as typed.")],
        ])

        let keys = buildShortcutsTab()

        tabs.addTabViewItem(tab("Speech", speech))
        tabs.addTabViewItem(tab("Text and Display", text))
        tabs.addTabViewItem(tab("Code and Paste", code))
        tabs.addTabViewItem(tab("Shortcuts", keys))

        let content = NSView()
        tabs.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            tabs.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            tabs.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            content.widthAnchor.constraint(greaterThanOrEqualToConstant: 600),
            content.heightAnchor.constraint(greaterThanOrEqualToConstant: 560),
        ])
        window.contentView = content
        window.initialFirstResponder = tabs
    }

    private func fillVoices() {
        voicePopup.removeAllItems()
        guard let menu = voicePopup.menu else { return }
        let def = NSMenuItem(title: "System Default", action: nil, keyEquivalent: "")
        def.representedObject = ""
        menu.addItem(def)
        let voices = AVSpeechSynthesisVoice.speechVoices().sorted {
            ($0.language, $0.name) < ($1.language, $1.name)
        }
        for v in voices {
            var title = "\(v.name), \(v.language)"
            switch v.quality {
            case .enhanced: title += ", Enhanced"
            case .premium: title += ", Premium"
            default: break
            }
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = v.identifier
            menu.addItem(item)
        }
    }

    private func fillFonts() {
        fontNamePopup.removeAllItems()
        guard let menu = fontNamePopup.menu else { return }
        for (title, value) in [("System", ""), ("System Monospaced", "monospaced")] {
            let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            i.representedObject = value
            menu.addItem(i)
        }
        menu.addItem(.separator())
        for family in NSFontManager.shared.availableFontFamilies {
            let i = NSMenuItem(title: family, action: nil, keyEquivalent: "")
            i.representedObject = family
            menu.addItem(i)
        }
    }

    // MARK: Show and sync

    func show(shortcuts: Bool = false) {
        refresh()
        if shortcuts { tabs.selectTabViewItem(at: 3) }
        NSApp.activate(ignoringOtherApps: true)
        if !didCenter { window.center(); didCenter = true }
        window.makeKeyAndOrderFront(nil)
    }

    private func on(_ b: Bool) -> NSControl.StateValue { b ? .on : .off }

    private func refresh() {
        speakTyping.state = on(s.speakTyping)
        silentVO.state = on(s.silentWithVoiceOver)
        voicePopup.selectItem(at: voicePopup.itemArray.firstIndex { ($0.representedObject as? String) == s.voiceID } ?? 0)
        rateSlider.doubleValue = s.rate
        pitchSlider.doubleValue = s.pitch
        volumeSlider.doubleValue = s.volume
        updateValueLabels()
        echoPopup.selectItem(at: s.echo.rawValue)
        capsPopup.selectItem(at: s.caps.rawValue)
        deletePopup.selectItem(at: s.delete.rawValue)
        punctPopup.selectItem(at: s.punctuation.rawValue)
        speakNav.state = on(s.speakNavigation)
        speakSel.state = on(s.speakSelection)
        edgeSound.state = on(s.edgeSound)

        fontNamePopup.selectItem(at: fontNamePopup.itemArray.firstIndex { ($0.representedObject as? String) == s.fontName } ?? 0)
        fontSizePopup.selectItem(at: fontSizes.firstIndex(of: s.fontSize) ?? (fontSizes.firstIndex(of: 16) ?? 0))
        spacingPopup.selectItem(at: spacings.firstIndex(of: s.lineSpacing) ?? 0)
        customColors.state = on(s.customColors)
        textColorWell.color = s.textColor
        bgColorWell.color = s.backgroundColor
        textColorWell.isEnabled = s.customColors
        bgColorWell.isEnabled = s.customColors
        showCounts.state = on(s.showCounts)
        spell.state = on(s.spellCheck)
        grammar.state = on(s.grammarCheck)
        autocorrect.state = on(s.autoCorrect)
        quotes.state = on(s.smartQuotes)
        dashes.state = on(s.smartDashes)
        replacement.state = on(s.textReplacement)
        writingTools.state = on(s.writingTools)

        codeMode.state = on(s.codeMode)
        indentPopup.selectItem(at: indents.firstIndex(of: s.indentWidth) ?? 1)
        speakIndent.state = on(s.speakIndentation)
        pasteMarkdown.state = on(s.pasteMarkdown)

        hotKey1.hotKey = s.hotKey(1)
        hotKey2.hotKey = s.hotKey(2)
        for (id, b) in localRecorders { b.hotKey = s.shortcut(id) }
    }

    private func updateValueLabels() {
        rateValue.stringValue = "\(Int(rateSlider.doubleValue))"
        pitchValue.stringValue = "\(Int(pitchSlider.doubleValue))%"
        volumeValue.stringValue = "\(Int(volumeSlider.doubleValue))%"
    }

    // MARK: Actions

    @objc private func changed(_ sender: Any?) {
        s.speakTyping = speakTyping.state == .on
        s.silentWithVoiceOver = silentVO.state == .on
        s.voiceID = (voicePopup.selectedItem?.representedObject as? String) ?? ""
        rateSlider.doubleValue = rateSlider.doubleValue.rounded()
        pitchSlider.doubleValue = pitchSlider.doubleValue.rounded()
        volumeSlider.doubleValue = volumeSlider.doubleValue.rounded()
        s.rate = rateSlider.doubleValue
        s.pitch = pitchSlider.doubleValue
        s.volume = volumeSlider.doubleValue
        updateValueLabels()
        s.echo = EchoMode(rawValue: echoPopup.indexOfSelectedItem) ?? .charactersAndWords
        s.caps = CapsMode(rawValue: capsPopup.indexOfSelectedItem) ?? .changePitch
        s.delete = DeleteMode(rawValue: deletePopup.indexOfSelectedItem) ?? .lowerPitch
        s.punctuation = PunctuationLevel(rawValue: punctPopup.indexOfSelectedItem) ?? .some
        s.speakNavigation = speakNav.state == .on
        s.speakSelection = speakSel.state == .on
        s.edgeSound = edgeSound.state == .on

        s.fontName = (fontNamePopup.selectedItem?.representedObject as? String) ?? ""
        let fi = fontSizePopup.indexOfSelectedItem
        if fi >= 0 && fi < fontSizes.count { s.fontSize = fontSizes[fi] }
        let si = spacingPopup.indexOfSelectedItem
        if si >= 0 && si < spacings.count { s.lineSpacing = spacings[si] }
        s.customColors = customColors.state == .on
        textColorWell.isEnabled = s.customColors
        bgColorWell.isEnabled = s.customColors
        if sender as AnyObject? === textColorWell { s.textColor = textColorWell.color }
        if sender as AnyObject? === bgColorWell { s.backgroundColor = bgColorWell.color }
        s.showCounts = showCounts.state == .on
        s.spellCheck = spell.state == .on
        s.grammarCheck = grammar.state == .on
        s.autoCorrect = autocorrect.state == .on
        s.smartQuotes = quotes.state == .on
        s.smartDashes = dashes.state == .on
        s.textReplacement = replacement.state == .on
        s.writingTools = writingTools.state == .on

        s.codeMode = codeMode.state == .on
        let ii = indentPopup.indexOfSelectedItem
        if ii >= 0 && ii < indents.count { s.indentWidth = indents[ii] }
        s.speakIndentation = speakIndent.state == .on
        s.pasteMarkdown = pasteMarkdown.state == .on

        onTextSettingsChanged()
    }

    // MARK: Shortcuts tab

    private func buildShortcutsTab() -> NSView {
        var rows: [[NSView]] = []
        var headerRows: [Int] = []
        let empty = NSGridCell.emptyContentView

        func header(_ title: String) {
            let l = NSTextField(labelWithString: title)
            l.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize + 1)
            l.setAccessibilityRole(.staticText)
            headerRows.append(rows.count)
            rows.append([l, empty])
        }

        header("Anywhere on your Mac")
        rows.append([plainLabel("Open Typing Box, or pull in selected text"), hotKey1])
        rows.append([plainLabel("Pull in the whole field"), hotKey2])

        for group in Commands.groups {
            header("In Typing Box: \(group)")
            for c in Commands.all where c.group == group {
                let b = ShortcutRecorderButton(name: c.title, hotKey: s.shortcut(c.id), allowsClear: true)
                b.onRecorded = { [weak self] r in self?.recordedLocal(c.id, r) }
                localRecorders[c.id] = b
                rows.append([plainLabel(c.title), b])
            }
        }

        let g = NSGridView(views: rows)
        g.rowSpacing = 6
        g.columnSpacing = 10
        g.column(at: 0).xPlacement = .trailing
        for i in 0..<g.numberOfRows { g.row(at: i).yPlacement = .center }
        for i in headerRows {
            g.row(at: i).mergeCells(in: NSRange(location: 0, length: 2))
            g.cell(atColumnIndex: 0, rowIndex: i).xPlacement = .leading
            g.row(at: i).topPadding = i == 0 ? 0 : 12
        }

        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        g.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(g)
        NSLayoutConstraint.activate([
            g.topAnchor.constraint(equalTo: doc.topAnchor, constant: 8),
            g.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 8),
            g.trailingAnchor.constraint(lessThanOrEqualTo: doc.trailingAnchor, constant: -8),
            g.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -8),
        ])

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = doc
        doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor).isActive = true
        doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor).isActive = true
        doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor).isActive = true

        let help = note("Press a shortcut button, then press the new shortcut. It needs Command, Option or Control, or it can be a function key. Delete removes a shortcut. Escape cancels.")
        let holder = NSView()
        for v in [help, scroll, resetKeys] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(v)
        }
        NSLayoutConstraint.activate([
            help.topAnchor.constraint(equalTo: holder.topAnchor, constant: 12),
            help.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 16),
            help.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: help.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -8),
            resetKeys.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            resetKeys.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 16),
            resetKeys.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -12),
        ])
        return holder
    }

    /// A label VoiceOver skips, because each shortcut button already says its own name and value.
    private func plainLabel(_ title: String) -> NSTextField {
        let l = NSTextField(labelWithString: title + ":")
        l.alignment = .right
        l.setAccessibilityElement(false)
        return l
    }

    /// Returns the name of whatever already uses this shortcut, if anything.
    private func conflict(_ k: HotKey, except id: String) -> String? {
        if id != "global1", s.hotKey(1).sameKeys(as: k) { return "Open Typing Box" }
        if id != "global2", s.hotKey(2).sameKeys(as: k) { return "Pull in the whole field" }
        for c in Commands.all where c.id != id {
            if let other = s.shortcut(c.id), other.sameKeys(as: k) { return c.title }
        }
        return nil
    }

    private func recordedGlobal(_ n: Int, _ r: RecordResult) {
        let button = n == 1 ? hotKey1 : hotKey2
        if case .set(let k) = r {
            if let other = conflict(k, except: "global\(n)") {
                NSSound.beep()
                AppDelegate.shared?.announce("Already used by \(other).")
            } else {
                s.setHotKey(n, k)
                AppDelegate.shared?.announce("Shortcut set to \(k.displayName).")
            }
        }
        button.hotKey = s.hotKey(n)
        onHotKeysChanged()
    }

    private func recordedLocal(_ id: String, _ r: RecordResult) {
        switch r {
        case .cancelled:
            break
        case .cleared:
            s.setShortcut(id, nil)
            AppDelegate.shared?.announce("Shortcut removed.")
        case .set(let k):
            if let other = conflict(k, except: id) {
                NSSound.beep()
                AppDelegate.shared?.announce("Already used by \(other).")
            } else {
                s.setShortcut(id, k)
                AppDelegate.shared?.announce("Shortcut set to \(k.displayName).")
            }
        }
        localRecorders[id]?.hotKey = s.shortcut(id)
        onHotKeysChanged()
    }

    @objc private func resetHotKeys() {
        s.resetShortcuts()
        hotKey1.hotKey = s.hotKey(1)
        hotKey2.hotKey = s.hotKey(2)
        for (id, b) in localRecorders { b.hotKey = s.shortcut(id) }
        onHotKeysChanged()
        AppDelegate.shared?.announce("All shortcuts reset.")
    }

    @objc private func preview() {
        Speaker.shared.preview()
    }

    @objc private func clearDrafts() {
        onClearDrafts()
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
