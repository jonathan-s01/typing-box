// HotKey.swift
// A global shortcut (key plus modifiers) and a button that records a new one.

import Cocoa
import Carbon.HIToolbox

struct HotKey: Equatable {
    var keyCode: UInt32
    var carbonMods: UInt32
    var keyName: String
    var chars: String = ""          // the character the key types, used to show the shortcut in menus

    /// Spoken-friendly name, for example "Command Option Return".
    var displayName: String {
        var parts: [String] = []
        if carbonMods & UInt32(cmdKey) != 0 { parts.append("Command") }
        if carbonMods & UInt32(controlKey) != 0 { parts.append("Control") }
        if carbonMods & UInt32(optionKey) != 0 { parts.append("Option") }
        if carbonMods & UInt32(shiftKey) != 0 { parts.append("Shift") }
        parts.append(keyName)
        return parts.joined(separator: " ")
    }

    /// Return and keypad Enter count as the same key.
    private static func normal(_ code: UInt32) -> UInt32 {
        code == UInt32(kVK_ANSI_KeypadEnter) ? UInt32(kVK_Return) : code
    }

    func sameKeys(as other: HotKey) -> Bool {
        HotKey.normal(keyCode) == HotKey.normal(other.keyCode) && carbonMods == other.carbonMods
    }

    func matches(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return HotKey.normal(UInt32(event.keyCode)) == HotKey.normal(keyCode)
            && HotKey.carbonMods(from: flags) == carbonMods
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if carbonMods & UInt32(cmdKey) != 0 { f.insert(.command) }
        if carbonMods & UInt32(optionKey) != 0 { f.insert(.option) }
        if carbonMods & UInt32(shiftKey) != 0 { f.insert(.shift) }
        if carbonMods & UInt32(controlKey) != 0 { f.insert(.control) }
        return f
    }

    private static func fn(_ v: Int) -> String {
        String(Character(UnicodeScalar(UInt32(v)) ?? " "))
    }

    /// The key equivalent string used to show this shortcut in a menu.
    var menuKeyEquivalent: String {
        let fkeys: [Int: Int] = [
            kVK_F1: NSF1FunctionKey, kVK_F2: NSF2FunctionKey, kVK_F3: NSF3FunctionKey, kVK_F4: NSF4FunctionKey,
            kVK_F5: NSF5FunctionKey, kVK_F6: NSF6FunctionKey, kVK_F7: NSF7FunctionKey, kVK_F8: NSF8FunctionKey,
            kVK_F9: NSF9FunctionKey, kVK_F10: NSF10FunctionKey, kVK_F11: NSF11FunctionKey, kVK_F12: NSF12FunctionKey,
            kVK_F13: NSF13FunctionKey, kVK_F14: NSF14FunctionKey, kVK_F15: NSF15FunctionKey, kVK_F16: NSF16FunctionKey,
            kVK_F17: NSF17FunctionKey, kVK_F18: NSF18FunctionKey, kVK_F19: NSF19FunctionKey,
            kVK_LeftArrow: NSLeftArrowFunctionKey, kVK_RightArrow: NSRightArrowFunctionKey,
            kVK_UpArrow: NSUpArrowFunctionKey, kVK_DownArrow: NSDownArrowFunctionKey,
            kVK_Home: NSHomeFunctionKey, kVK_End: NSEndFunctionKey,
            kVK_PageUp: NSPageUpFunctionKey, kVK_PageDown: NSPageDownFunctionKey,
            kVK_ForwardDelete: NSDeleteFunctionKey,
        ]
        let code = Int(keyCode)
        if let f = fkeys[code] { return HotKey.fn(f) }
        switch code {
        case kVK_Return: return "\r"
        case kVK_ANSI_KeypadEnter: return "\u{3}"
        case kVK_Tab: return "\t"
        case kVK_Space: return " "
        case kVK_Delete: return "\u{8}"
        case kVK_Escape: return "\u{1b}"
        default: return chars.lowercased()
        }
    }

    static func isFunctionKey(_ code: UInt16) -> Bool {
        let f: Set<Int> = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                           kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19]
        return f.contains(Int(code))
    }

    static func carbonMods(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    static func keyName(for event: NSEvent) -> String {
        let names: [Int: String] = [
            kVK_Return: "Return", kVK_ANSI_KeypadEnter: "Enter", kVK_Space: "Space", kVK_Tab: "Tab",
            kVK_Delete: "Delete", kVK_ForwardDelete: "Forward Delete", kVK_Escape: "Escape",
            kVK_LeftArrow: "Left Arrow", kVK_RightArrow: "Right Arrow",
            kVK_UpArrow: "Up Arrow", kVK_DownArrow: "Down Arrow",
            kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up", kVK_PageDown: "Page Down",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
            kVK_F18: "F18", kVK_F19: "F19",
        ]
        if let n = names[Int(event.keyCode)] { return n }
        let chars = event.charactersIgnoringModifiers ?? ""
        if let c = chars.first, c != " ", let spoken = TextNames.names[c] { return spoken }
        return chars.uppercased()
    }
}

enum RecordResult {
    case cancelled
    case cleared
    case set(HotKey)
}

/// A button that records a shortcut. Press it, then press the new shortcut.
/// Escape cancels. Delete removes the shortcut (when allowed).
/// The shortcut has to include Command, Option or Control, unless it's a function key.
@MainActor
final class ShortcutRecorderButton: NSButton {
    static var isRecording = false
    var hotKey: HotKey? { didSet { updateTitle() } }
    var onRecordingStarted: (() -> Void)?
    var onRecorded: ((RecordResult) -> Void)?
    private var monitor: Any?
    private let name: String
    private let allowsClear: Bool

    init(name: String, hotKey: HotKey?, allowsClear: Bool) {
        self.name = name
        self.hotKey = hotKey
        self.allowsClear = allowsClear
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(startRecording)
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func updateTitle() {
        let current = hotKey?.displayName ?? "None"
        title = current
        setAccessibilityLabel("\(name): \(current). Press to change.")
    }

    private func say(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    @objc private func startRecording() {
        guard monitor == nil else { return }
        ShortcutRecorderButton.isRecording = true
        onRecordingStarted?()
        title = "Press new shortcut\u{2026}"
        let hint = allowsClear ? "Press the new shortcut. Delete removes it. Escape cancels."
                               : "Press the new shortcut, or Escape to cancel."
        setAccessibilityLabel("\(name): \(hint)")
        say(hint)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            self.handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == UInt16(kVK_Escape) && flags.isEmpty {
            finish(.cancelled)
            return
        }
        if allowsClear && flags.isEmpty
            && (event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete)) {
            hotKey = nil
            finish(.cleared)
            return
        }
        let hasModifier = flags.contains(.command) || flags.contains(.option) || flags.contains(.control)
        guard hasModifier || HotKey.isFunctionKey(event.keyCode) else {
            NSSound.beep()
            say("Include Command, Option or Control, or use a function key.")
            return
        }
        let k = HotKey(keyCode: UInt32(event.keyCode),
                       carbonMods: HotKey.carbonMods(from: flags),
                       keyName: HotKey.keyName(for: event),
                       chars: event.charactersIgnoringModifiers ?? "")
        hotKey = k
        finish(.set(k))
    }

    private func finish(_ result: RecordResult) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        ShortcutRecorderButton.isRecording = false
        updateTitle()
        onRecorded?(result)
    }
}
