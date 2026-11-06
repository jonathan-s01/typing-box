// TypingTextView.swift
// The text area. Tells the Speaker
// what happened after each key press (typed, deleted, moved, selected).

import Cocoa
import Carbon.HIToolbox

final class TypingTextView: NSTextView {
    private var handlingKey = false
    private var change: (range: NSRange, removed: String, inserted: String)?

    private static let navKeys: Set<Int> = [
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
        kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
    ]

    private func mods(_ e: NSEvent) -> NSEvent.ModifierFlags {
        e.modifierFlags.intersection([.command, .option, .control, .shift])
    }

    // MARK: Record what each key press changed

    private func record(_ range: NSRange, _ replacement: String?) {
        guard handlingKey else { return }
        let ns = string as NSString
        var removed = ""
        if range.location != NSNotFound, NSMaxRange(range) <= ns.length, range.length > 0 {
            removed = ns.substring(with: range)
        }
        change = (range, removed, replacement ?? "")
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        let ok = super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        if ok { record(affectedCharRange, replacementString) }
        return ok
    }

    override func shouldChangeText(inRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
        let ok = super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings)
        if ok, let first = affectedRanges.first {
            record(first.rangeValue, replacementStrings?.first)
        }
        return ok
    }

    override func keyDown(with event: NSEvent) {
        let oldSel = selectedRange()
        change = nil
        handlingKey = true
        super.keyDown(with: event)
        handlingKey = false
        afterKey(event, oldSel: oldSel)
    }

    // Pressing Control on its own stops speech, like VoiceOver.
    override func flagsChanged(with event: NSEvent) {
        let isControlKey = event.keyCode == UInt16(kVK_Control) || event.keyCode == UInt16(kVK_RightControl)
        if isControlKey && mods(event) == .control { Speaker.shared.stop() }
        super.flagsChanged(with: event)
    }

    // MARK: Code mode

    private var codeMode: Bool { Settings.shared.codeMode }

    override func insertTab(_ sender: Any?) {
        guard codeMode else { super.insertTab(sender); return }
        insertText(String(repeating: " ", count: Settings.shared.indentWidth), replacementRange: selectedRange())
    }

    override func insertNewline(_ sender: Any?) {
        guard codeMode else { super.insertNewline(sender); return }
        let ns = string as NSString
        let loc = selectedRange().location
        let lineStart = ns.lineRange(for: NSRange(location: min(loc, ns.length), length: 0)).location
        let before = ns.substring(with: NSRange(location: lineStart, length: loc - lineStart))
        let indent = String(before.prefix(while: { $0 == " " || $0 == "\t" }))
        insertText("\n" + indent, replacementRange: selectedRange())
    }

    /// Shift Tab in code mode removes one indent from the start of the current line.
    override func insertBacktab(_ sender: Any?) {
        guard codeMode else { super.insertBacktab(sender); return }
        let ns = string as NSString
        let sel = selectedRange()
        let lineStart = ns.lineRange(for: NSRange(location: min(sel.location, ns.length), length: 0)).location
        var count = 0
        while count < Settings.shared.indentWidth, lineStart + count < ns.length,
              ns.character(at: lineStart + count) == 32 {
            count += 1
        }
        if count == 0, lineStart < ns.length, ns.character(at: lineStart) == 9 { count = 1 }
        guard count > 0 else { Speaker.shared.edge(); return }
        let r = NSRange(location: lineStart, length: count)
        if shouldChangeText(in: r, replacementString: "") {
            textStorage?.replaceCharacters(in: r, with: "")
            didChangeText()
            setSelectedRange(NSRange(location: max(lineStart, sel.location - count), length: 0))
            Speaker.shared.line(currentLineText())
        }
    }

    override func selectAll(_ sender: Any?) {
        super.selectAll(sender)
        Speaker.shared.selectedAll()
    }

    // MARK: Decide what to speak

    private func afterKey(_ event: NSEvent, oldSel: NSRange) {
        let sp = Speaker.shared
        let newSel = selectedRange()

        if let c = change {
            if !c.inserted.isEmpty {
                sp.typed(c.inserted, wordBefore: wordBefore(c.range.location))
            } else if !c.removed.isEmpty {
                sp.deleted(c.removed)
            }
            return
        }

        let key = Int(event.keyCode)
        guard Self.navKeys.contains(key) else { return }
        if NSEqualRanges(oldSel, newSel) { sp.edge(); return }

        let m = mods(event)
        if m.contains(.shift) {
            speakSelectionChange(old: oldSel, new: newSel)
            return
        }

        let ns = string as NSString
        let horizontal = key == kVK_LeftArrow || key == kVK_RightArrow
        let a = min(oldSel.location, newSel.location)
        let b = max(oldSel.location, newSel.location)
        let crossed = (oldSel.length == 0 && b > a) ? ns.substring(with: NSRange(location: a, length: b - a)) : ""

        if horizontal && m.isEmpty {
            sp.character(crossed.isEmpty ? charAt(newSel.location) : crossed)
        } else if horizontal && m == .option {
            let w = crossed.trimmingCharacters(in: .whitespacesAndNewlines)
            sp.word(w.isEmpty ? wordAt(newSel.location) : w)
        } else {
            sp.line(lineText(at: newSel.location))
        }
    }

    private func speakSelectionChange(old: NSRange, new: NSRange) {
        let ns = string as NSString
        let added = parts(of: new, notIn: old).map { ns.substring(with: $0) }.joined()
        let removed = parts(of: old, notIn: new).map { ns.substring(with: $0) }.joined()
        Speaker.shared.selection(added: added, removed: removed)
    }

    private func parts(of a: NSRange, notIn b: NSRange) -> [NSRange] {
        if a.length == 0 { return [] }
        if b.length == 0 { return [a] }
        var out: [NSRange] = []
        if a.location < b.location {
            out.append(NSRange(location: a.location, length: min(NSMaxRange(a), b.location) - a.location))
        }
        if NSMaxRange(a) > NSMaxRange(b) {
            let start = max(a.location, NSMaxRange(b))
            out.append(NSRange(location: start, length: NSMaxRange(a) - start))
        }
        return out.filter { $0.length > 0 }
    }

    // MARK: Text helpers

    private func wordBefore(_ loc: Int) -> String {
        let ns = string as NSString
        let start = max(0, loc - 200)
        guard loc <= ns.length, loc > start else { return "" }
        let text = ns.substring(with: NSRange(location: start, length: loc - start))
        return String(String(text.reversed().prefix(while: { TextNames.isWordChar($0) })).reversed())
    }

    private func charAt(_ loc: Int) -> String {
        let ns = string as NSString
        guard loc < ns.length else { return "" }
        return ns.substring(with: ns.rangeOfComposedCharacterSequence(at: loc))
    }

    func wordAt(_ loc: Int) -> String {
        let ns = string as NSString
        guard ns.length > 0 else { return "" }
        let at = min(loc, ns.length - 1)
        let r = selectionRange(forProposedRange: NSRange(location: at, length: 0), granularity: .selectByWord)
        guard r.location != NSNotFound, NSMaxRange(r) <= ns.length else { return "" }
        return ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The visual line (as wrapped on screen) that contains this position.
    func lineText(at loc: Int) -> String {
        let ns = string as NSString
        if ns.length == 0 { return "" }
        if loc >= ns.length && ns.character(at: ns.length - 1) == 10 { return "" }
        let idx = min(loc, ns.length - 1)
        guard let lm = layoutManager, let tc = textContainer else {
            return ns.substring(with: ns.lineRange(for: NSRange(location: idx, length: 0)))
        }
        lm.ensureLayout(for: tc)
        let glyph = lm.glyphIndexForCharacter(at: idx)
        var glyphRange = NSRange()
        _ = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &glyphRange)
        let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard NSMaxRange(charRange) <= ns.length else { return "" }
        return ns.substring(with: charRange)
    }

    func currentLineText() -> String { lineText(at: selectedRange().location) }

    func selectedText() -> String {
        let ns = string as NSString
        let r = selectedRange()
        guard r.length > 0, NSMaxRange(r) <= ns.length else { return "" }
        return ns.substring(with: r)
    }

    func currentWordText() -> String {
        let loc = selectedRange().location
        let w = wordAt(loc)
        if !w.isEmpty { return w }
        return loc > 0 ? wordAt(loc - 1) : ""
    }

    func currentSentenceText() -> String {
        let ns = string as NSString
        guard ns.length > 0 else { return "" }
        let loc = min(selectedRange().location, ns.length - 1)
        var result = ""
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .bySentences) { sub, _, enclosing, stop in
            if NSLocationInRange(loc, enclosing) {
                result = sub ?? ""
                stop.pointee = true
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
