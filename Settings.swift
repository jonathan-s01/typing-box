// Settings.swift
// Every option is saved in the app's preferences so it survives quitting.

import Cocoa

enum EchoMode: Int, CaseIterable {
    case nothing, characters, words, charactersAndWords
    var title: String {
        switch self {
        case .nothing: return "Nothing"
        case .characters: return "Characters"
        case .words: return "Words"
        case .charactersAndWords: return "Characters and Words"
        }
    }
}

enum CapsMode: Int, CaseIterable {
    case changePitch, sayCap, nothing
    var title: String {
        switch self {
        case .changePitch: return "Change Pitch"
        case .sayCap: return "Speak \u{201C}cap\u{201D}"
        case .nothing: return "Do Nothing"
        }
    }
}

enum DeleteMode: Int, CaseIterable {
    case lowerPitch, sayDeleted, nothing
    var title: String {
        switch self {
        case .lowerPitch: return "Speak in Lower Pitch"
        case .sayDeleted: return "Speak \u{201C}deleted\u{201D} First"
        case .nothing: return "Do Nothing"
        }
    }
}

enum PunctuationLevel: Int, CaseIterable {
    case none, some, most, all
    var title: String {
        switch self {
        case .none: return "None"
        case .some: return "Some"
        case .most: return "Most"
        case .all: return "All"
        }
    }
}

@MainActor
final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    private init() {
        d.register(defaults: [
            "speakTyping": false,
            "silentWithVoiceOver": true,
            "voiceID": "",
            "rate": 50.0,
            "pitch": 100.0,
            "volume": 100.0,
            "echo": EchoMode.charactersAndWords.rawValue,
            "caps": CapsMode.changePitch.rawValue,
            "delete": DeleteMode.lowerPitch.rawValue,
            "punctuation": PunctuationLevel.some.rawValue,
            "speakNavigation": true,
            "speakSelection": true,
            "edgeSound": true,
            "fontSize": 16.0,
            "spellCheck": true,
            "grammarCheck": false,
            "autoCorrect": NSSpellChecker.isAutomaticSpellingCorrectionEnabled,
            "smartQuotes": false,
            "smartDashes": false,
            "textReplacement": false,
            "writingTools": false,
            "currentDraftID": "",
            // Display
            "fontName": "",                 // "" = system font, "monospaced" = system monospaced
            "lineSpacing": 1.0,
            "customColors": false,
            "showCounts": true,
            // Code mode
            "codeMode": false,
            "indentWidth": 4,
            "speakIndentation": true,
            // Paste
            "pasteMarkdown": false,
            // Hotkeys. Carbon modifier values: Command 256, Shift 512, Option 2048, Control 4096.
            "hotKey1Code": 36, "hotKey1Mods": 2304, "hotKey1Name": "Return",
            "hotKey2Code": 36, "hotKey2Mods": 2816, "hotKey2Name": "Return",
        ])
    }

    private func bool(_ key: String) -> Bool { d.bool(forKey: key) }
    private func store(_ value: Any, _ key: String) { d.set(value, forKey: key) }

    // Speech
    var speakTyping: Bool { get { bool("speakTyping") } set { store(newValue, "speakTyping") } }
    var silentWithVoiceOver: Bool { get { bool("silentWithVoiceOver") } set { store(newValue, "silentWithVoiceOver") } }
    var voiceID: String { get { d.string(forKey: "voiceID") ?? "" } set { store(newValue, "voiceID") } }
    var rate: Double { get { d.double(forKey: "rate") } set { store(newValue, "rate") } }       // 0 to 100
    var pitch: Double { get { d.double(forKey: "pitch") } set { store(newValue, "pitch") } }    // 50 to 200 percent
    var volume: Double { get { d.double(forKey: "volume") } set { store(newValue, "volume") } } // 0 to 100
    var echo: EchoMode {
        get { EchoMode(rawValue: d.integer(forKey: "echo")) ?? .charactersAndWords }
        set { store(newValue.rawValue, "echo") }
    }
    var caps: CapsMode {
        get { CapsMode(rawValue: d.integer(forKey: "caps")) ?? .changePitch }
        set { store(newValue.rawValue, "caps") }
    }
    var delete: DeleteMode {
        get { DeleteMode(rawValue: d.integer(forKey: "delete")) ?? .lowerPitch }
        set { store(newValue.rawValue, "delete") }
    }
    var punctuation: PunctuationLevel {
        get { PunctuationLevel(rawValue: d.integer(forKey: "punctuation")) ?? .some }
        set { store(newValue.rawValue, "punctuation") }
    }
    var speakNavigation: Bool { get { bool("speakNavigation") } set { store(newValue, "speakNavigation") } }
    var speakSelection: Bool { get { bool("speakSelection") } set { store(newValue, "speakSelection") } }
    var edgeSound: Bool { get { bool("edgeSound") } set { store(newValue, "edgeSound") } }

    // Text
    var fontSize: Double { get { d.double(forKey: "fontSize") } set { store(newValue, "fontSize") } }
    var spellCheck: Bool { get { bool("spellCheck") } set { store(newValue, "spellCheck") } }
    var grammarCheck: Bool { get { bool("grammarCheck") } set { store(newValue, "grammarCheck") } }
    var autoCorrect: Bool { get { bool("autoCorrect") } set { store(newValue, "autoCorrect") } }
    var smartQuotes: Bool { get { bool("smartQuotes") } set { store(newValue, "smartQuotes") } }
    var smartDashes: Bool { get { bool("smartDashes") } set { store(newValue, "smartDashes") } }
    var textReplacement: Bool { get { bool("textReplacement") } set { store(newValue, "textReplacement") } }
    /// Off by default: the Writing Tools pop-up that appears on selection can stall VoiceOver.
    var writingTools: Bool { get { bool("writingTools") } set { store(newValue, "writingTools") } }

    // Display
    var fontName: String { get { d.string(forKey: "fontName") ?? "" } set { store(newValue, "fontName") } }
    var lineSpacing: Double { get { d.double(forKey: "lineSpacing") } set { store(newValue, "lineSpacing") } }
    var customColors: Bool { get { bool("customColors") } set { store(newValue, "customColors") } }
    var showCounts: Bool { get { bool("showCounts") } set { store(newValue, "showCounts") } }
    var textColor: NSColor {
        get { color("textColor") ?? .white }
        set { setColor(newValue, "textColor") }
    }
    var backgroundColor: NSColor {
        get { color("backgroundColor") ?? .black }
        set { setColor(newValue, "backgroundColor") }
    }
    private func color(_ key: String) -> NSColor? {
        guard let data = d.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    }
    private func setColor(_ c: NSColor, _ key: String) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: c, requiringSecureCoding: true) {
            store(data, key)
        }
    }

    // Code mode
    var codeMode: Bool { get { bool("codeMode") } set { store(newValue, "codeMode") } }
    var indentWidth: Int { get { max(1, d.integer(forKey: "indentWidth")) } set { store(newValue, "indentWidth") } }
    var speakIndentation: Bool { get { bool("speakIndentation") } set { store(newValue, "speakIndentation") } }

    // Paste
    var pasteMarkdown: Bool { get { bool("pasteMarkdown") } set { store(newValue, "pasteMarkdown") } }

    // Hotkeys
    func hotKey(_ n: Int) -> HotKey {
        HotKey(keyCode: UInt32(d.integer(forKey: "hotKey\(n)Code")),
               carbonMods: UInt32(d.integer(forKey: "hotKey\(n)Mods")),
               keyName: d.string(forKey: "hotKey\(n)Name") ?? "Return")
    }
    func setHotKey(_ n: Int, _ k: HotKey) {
        store(Int(k.keyCode), "hotKey\(n)Code")
        store(Int(k.carbonMods), "hotKey\(n)Mods")
        store(k.keyName, "hotKey\(n)Name")
    }
    func resetHotKeys() {
        for n in 1...2 {
            for suffix in ["Code", "Mods", "Name"] { d.removeObject(forKey: "hotKey\(n)\(suffix)") }
        }
    }

    // In-window shortcuts. Missing means "use the default"; ["none": true] means no shortcut.
    func shortcut(_ id: String) -> HotKey? {
        guard let dict = d.dictionary(forKey: "sc.\(id)") else { return Commands.info(id)?.defaultKey }
        if dict["none"] as? Bool == true { return nil }
        return HotKey(keyCode: UInt32(dict["code"] as? Int ?? 0),
                      carbonMods: UInt32(dict["mods"] as? Int ?? 0),
                      keyName: dict["name"] as? String ?? "",
                      chars: dict["chars"] as? String ?? "")
    }
    func setShortcut(_ id: String, _ k: HotKey?) {
        if let k {
            store(["code": Int(k.keyCode), "mods": Int(k.carbonMods), "name": k.keyName, "chars": k.chars], "sc.\(id)")
        } else {
            store(["none": true], "sc.\(id)")
        }
    }
    func resetShortcuts() {
        for c in Commands.all { d.removeObject(forKey: "sc.\(c.id)") }
        resetHotKeys()
    }

    // Drafts
    var currentDraftID: UUID? {
        get { UUID(uuidString: d.string(forKey: "currentDraftID") ?? "") }
        set { store(newValue?.uuidString ?? "", "currentDraftID") }
    }
}
