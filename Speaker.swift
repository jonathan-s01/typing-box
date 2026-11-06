// Speaker.swift
// Typing Box's own voice. Modelled on how VoiceOver speaks while you type.

import Cocoa
import AVFoundation

/// Character names and punctuation sets. Kept outside the Speaker class so
/// the text view can use them too.
enum TextNames {
    static let names: [Character: String] = [
        " ": "space", "\n": "new line", "\r": "new line", "\t": "tab",
        ".": "period", ",": "comma", ";": "semicolon", ":": "colon",
        "!": "exclamation", "?": "question mark",
        "'": "apostrophe", "\u{2019}": "apostrophe", "\u{2018}": "left single quote",
        "\"": "quote", "\u{201C}": "left quote", "\u{201D}": "right quote",
        "(": "left paren", ")": "right paren", "[": "left bracket", "]": "right bracket",
        "{": "left brace", "}": "right brace", "<": "less than", ">": "greater than",
        "-": "dash", "\u{2013}": "en dash", "\u{2014}": "em dash", "_": "underscore",
        "/": "slash", "\\": "backslash", "|": "vertical bar",
        "@": "at", "#": "number", "$": "dollar", "%": "percent", "^": "caret",
        "&": "ampersand", "*": "star", "+": "plus", "=": "equals", "~": "tilde",
        "`": "grave accent", "\u{2026}": "ellipsis", "\u{2022}": "bullet",
    ]
    static let somePunct: Set<Character> = Set("@#$%^&*_+=<>|~`\\/\u{2022}")
    static let mostPunct: Set<Character> = somePunct.union("()[]{}\"\u{201C}\u{201D}\u{2018}-\u{2013}\u{2014};:!?\u{2026}")
    static let allPunct: Set<Character> = mostPunct.union(".,'\u{2019}")

    /// Letters, numbers and apostrophes count as part of a word.
    static func isWordChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "'" || c == "\u{2019}"
    }
}

@MainActor
final class Speaker {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()
    private var s: Settings { Settings.shared }

    struct Part {
        var text: String
        var pitch: Float = 1
        var ipa: String? = nil
    }

    // MARK: When speaking is allowed

    var voiceOverRunning: Bool { NSWorkspace.shared.isVoiceOverEnabled }
    /// False when VoiceOver is on and "Stay silent while VoiceOver is on" is checked.
    var allowedNow: Bool { !(s.silentWithVoiceOver && voiceOverRunning) }
    var typingEnabled: Bool { s.speakTyping && allowedNow }

    // MARK: Core

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    func speak(_ parts: [Part], interrupt: Bool = true) {
        if interrupt { stop() }
        // Join neighbouring parts with the same pitch into one utterance to avoid gaps.
        var merged: [Part] = []
        for p in parts where !p.text.isEmpty {
            if var last = merged.last, last.pitch == p.pitch, last.ipa == nil, p.ipa == nil {
                last.text += ", " + p.text
                merged[merged.count - 1] = last
            } else {
                merged.append(p)
            }
        }
        for p in merged { synth.speak(utterance(p)) }
    }

    private func utterance(_ p: Part) -> AVSpeechUtterance {
        let u: AVSpeechUtterance
        if let ipa = p.ipa {
            let key = NSAttributedString.Key(rawValue: AVSpeechSynthesisIPANotationAttribute)
            u = AVSpeechUtterance(attributedString: NSAttributedString(string: p.text, attributes: [key: ipa]))
        } else {
            u = AVSpeechUtterance(string: p.text)
        }
        let minRate = AVSpeechUtteranceMinimumSpeechRate
        let maxRate = AVSpeechUtteranceMaximumSpeechRate
        u.rate = minRate + (maxRate - minRate) * Float(s.rate / 100)
        u.pitchMultiplier = max(0.5, min(2.0, Float(s.pitch / 100) * p.pitch))
        u.volume = Float(s.volume / 100)
        if !s.voiceID.isEmpty, let v = AVSpeechSynthesisVoice(identifier: s.voiceID) {
            u.voice = v
        }
        u.preUtteranceDelay = 0
        u.postUtteranceDelay = 0
        return u
    }

    // MARK: Turning text into speech parts

    private func letter(_ t: String, pitch: Float) -> Part {
        // A lone "a" is often read as the word "uh", so force the letter name.
        if t.lowercased() == "a" { return Part(text: t, pitch: pitch, ipa: "\u{02C8}e\u{026A}") }
        return Part(text: t, pitch: pitch)
    }

    func charParts(_ c: Character, pitch: Float = 1) -> [Part] {
        if let name = TextNames.names[c] { return [Part(text: name, pitch: pitch)] }
        if c.isLetter && c.isUppercase {
            let lower = String(c).lowercased()
            switch s.caps {
            case .changePitch: return [letter(lower, pitch: pitch * 1.35)]
            case .sayCap:
                if lower == "a" { return [Part(text: "cap", pitch: pitch), letter(lower, pitch: pitch)] }
                return [Part(text: "cap \(lower)", pitch: pitch)]
            case .nothing: return [letter(lower, pitch: pitch)]
            }
        }
        return [letter(String(c), pitch: pitch)]
    }

    func verbalize(_ text: String) -> String {
        let set: Set<Character>
        switch s.punctuation {
        case .none: return text
        case .some: set = TextNames.somePunct
        case .most: set = TextNames.mostPunct
        case .all: set = TextNames.allPunct
        }
        var out = ""
        for c in text {
            if set.contains(c), let name = TextNames.names[c] { out += " \(name) " } else { out.append(c) }
        }
        return out
    }

    func chunkParts(_ text: String, pitch: Float = 1) -> [Part] {
        if text.count == 1, let c = text.first { return charParts(c, pitch: pitch) }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if text.contains("\n") { return [Part(text: "new line", pitch: pitch)] }
            let n = text.count
            return [Part(text: n > 1 ? "\(n) spaces" : "space", pitch: pitch)]
        }
        return [Part(text: verbalize(text), pitch: pitch)]
    }

    // MARK: Events from the text box

    func typed(_ inserted: String, wordBefore: String) {
        guard typingEnabled else { return }
        let mode = s.echo
        if mode == .nothing { return }
        guard inserted.count == 1, let c = inserted.first else {
            speak(chunkParts(inserted))   // pasted, autocompleted or multi-character input
            return
        }
        if TextNames.isWordChar(c) {
            if mode == .characters || mode == .charactersAndWords { speak(charParts(c)) }
            return
        }
        // Space, return or punctuation ends a word.
        switch mode {
        case .characters:
            speak(charParts(c))
        case .words:
            if !wordBefore.isEmpty { speak([Part(text: verbalize(wordBefore))]) }
        case .charactersAndWords:
            if wordBefore.isEmpty {
                speak(charParts(c))
            } else {
                var parts = [Part(text: verbalize(wordBefore))]
                if !c.isWhitespace { parts += charParts(c) }
                speak(parts)
            }
        case .nothing:
            break
        }
    }

    func deleted(_ text: String) {
        guard typingEnabled else { return }
        switch s.delete {
        case .nothing: return
        case .lowerPitch: speak(chunkParts(text, pitch: 0.7))
        case .sayDeleted: speak([Part(text: "deleted")] + chunkParts(text))
        }
    }

    func character(_ text: String) {
        guard typingEnabled, s.speakNavigation, !text.isEmpty else { return }
        speak(chunkParts(text))
    }

    func word(_ text: String) {
        guard typingEnabled, s.speakNavigation, !text.isEmpty else { return }
        speak(chunkParts(text))
    }

    func line(_ text: String) {
        guard typingEnabled, s.speakNavigation else { return }
        let t = text.trimmingCharacters(in: .newlines)
        if t.trimmingCharacters(in: .whitespaces).isEmpty { speak([Part(text: "blank")]); return }
        speak([Part(text: indentPrefix(t) + verbalize(t))])
    }

    /// In code mode, says how far a line is indented, for example "4 spaces, ".
    func indentPrefix(_ line: String) -> String {
        guard s.codeMode && s.speakIndentation else { return "" }
        let lead = line.prefix(while: { $0 == " " || $0 == "\t" })
        let tabs = lead.filter { $0 == "\t" }.count
        let spaces = lead.count - tabs
        var bits: [String] = []
        if tabs > 0 { bits.append(tabs == 1 ? "1 tab" : "\(tabs) tabs") }
        if spaces > 0 { bits.append(spaces == 1 ? "1 space" : "\(spaces) spaces") }
        return bits.isEmpty ? "" : bits.joined(separator: " ") + ", "
    }

    func selection(added: String, removed: String) {
        guard typingEnabled, s.speakSelection else { return }
        var parts: [Part] = []
        if !added.isEmpty { parts += chunkParts(added); parts.append(Part(text: "selected")) }
        if !removed.isEmpty { parts += chunkParts(removed); parts.append(Part(text: "unselected")) }
        speak(parts)
    }

    func selectedAll() {
        guard typingEnabled, s.speakSelection else { return }
        speak([Part(text: "all selected")])
    }

    func edge() {
        guard typingEnabled, s.edgeSound else { return }
        NSSound(named: "Tink")?.play()
    }

    // MARK: Commands

    /// Used by the reading commands. The app decides whether VoiceOver or this voice speaks.
    func readText(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        speak([Part(text: t.isEmpty ? "empty" : verbalize(text))])
    }

    func preview() {
        speak([Part(text: "This is how Typing Box sounds.")])
    }

    /// Spoken status messages when VoiceOver isn't the one talking.
    func say(_ message: String) {
        guard typingEnabled else { return }
        speak([Part(text: message)])
    }
}
