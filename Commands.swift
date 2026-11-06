// Commands.swift
// Every action in Typing Box, with its default in-window shortcut.
// Shortcuts can be changed in Settings, Shortcuts.

import Cocoa
import Carbon.HIToolbox

struct CommandInfo {
    let id: String
    let title: String
    let group: String
    let defaultKey: HotKey?
}

@MainActor
enum Commands {
    private static let cmd = Int(cmdKey), shift = Int(shiftKey), opt = Int(optionKey), ctrl = Int(controlKey)

    private static let letterCodes: [String: Int] = [
        "a": kVK_ANSI_A, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "i": kVK_ANSI_I, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N,
        "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "w": kVK_ANSI_W,
        "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5,
        "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    ]

    private static func k(_ ch: String, _ mods: Int) -> HotKey {
        HotKey(keyCode: UInt32(letterCodes[ch] ?? 0), carbonMods: UInt32(mods), keyName: ch.uppercased(), chars: ch)
    }

    private static func c(_ id: String, _ title: String, _ group: String, _ key: HotKey? = nil) -> CommandInfo {
        CommandInfo(id: id, title: title, group: group, defaultKey: key)
    }

    static let groups = ["Typing Box", "Drafts", "Snippets", "Speech", "Find", "Text"]

    static let all: [CommandInfo] = {
        var list: [CommandInfo] = [
            c("commit", "Paste into Previous App", "Typing Box",
              HotKey(keyCode: UInt32(kVK_Return), carbonMods: UInt32(cmd), keyName: "Return", chars: "\r")),
            c("close", "Close Typing Box", "Typing Box",
              HotKey(keyCode: UInt32(kVK_Escape), carbonMods: 0, keyName: "Escape", chars: "\u{1b}")),
            c("actionsMenu", "Show Actions Menu", "Typing Box", k("m", cmd | shift)),
            c("settings", "Settings", "Typing Box",
              HotKey(keyCode: UInt32(kVK_ANSI_Comma), carbonMods: UInt32(cmd), keyName: "comma", chars: ",")),
            c("shortcutSettings", "Keyboard Shortcuts", "Typing Box"),
            c("copyLast", "Copy Last Pasted Text", "Typing Box"),
            c("quit", "Quit Typing Box", "Typing Box", k("q", cmd)),

            c("newDraft", "New Draft", "Drafts", k("n", cmd)),
            c("chooseDraft", "Choose Draft", "Drafts", k("d", cmd)),
            c("allDrafts", "All Drafts Window", "Drafts", k("d", cmd | shift)),
            c("togglePin", "Pin or Unpin This Draft", "Drafts", k("p", cmd | shift)),
            c("renameDraft", "Rename This Draft", "Drafts"),
            c("deleteDraft", "Delete This Draft", "Drafts"),
            c("exportDraft", "Export as Text File", "Drafts", k("s", cmd)),
            c("exportAll", "Export All Drafts", "Drafts", k("s", cmd | shift)),

            c("snippetMenu", "Insert Snippet Menu", "Snippets", k("i", cmd | shift)),
            c("saveSnippet", "Save Selection as Snippet", "Snippets"),
            c("manageSnippets", "Manage Snippets", "Snippets"),

            c("speakTyping", "Speak Typing On or Off", "Speech", k("t", cmd | shift)),
            c("readAll", "Read All", "Speech", k("r", cmd | shift)),
            c("readLine", "Read Current Line", "Speech", k("l", cmd | shift)),
            c("readSentence", "Read Current Sentence", "Speech", k("e", cmd | shift)),
            c("readWord", "Read Current Word", "Speech", k("w", cmd | shift)),
            c("readSelection", "Read Selection", "Speech", k("a", cmd | shift)),
            c("announceCount", "Announce Word and Character Count", "Speech", k("c", cmd | shift)),
            c("stopSpeaking", "Stop Speaking", "Speech"),

            c("find", "Find", "Find", k("f", cmd)),
            c("findNext", "Find Next", "Find", k("g", cmd)),
            c("findPrevious", "Find Previous", "Find", k("g", cmd | shift)),
            c("findReplace", "Find and Replace", "Find", k("f", cmd | opt)),

            c("codeMode", "Code Mode On or Off", "Text"),
            c("markdown", "Paste Markdown as Formatting On or Off", "Text"),
            c("spellCheck", "Check Spelling While Typing On or Off", "Text"),
            c("grammar", "Check Grammar On or Off", "Text"),
            c("autocorrect", "Correct Spelling Automatically On or Off", "Text"),
            c("smartQuotes", "Smart Quotes On or Off", "Text"),
            c("smartDashes", "Smart Dashes On or Off", "Text"),
            c("textReplacement", "Text Replacement On or Off", "Text"),
            c("writingTools", "Writing Tools On or Off", "Text"),
        ]
        // Snippet slots 1 to 9 go right after Manage Snippets.
        let slots = (1...9).map { n in
            c("snippet\(n)", "Insert Snippet \(n)", "Snippets", k("\(n)", cmd | ctrl))
        }
        if let i = list.firstIndex(where: { $0.id == "manageSnippets" }) {
            list.insert(contentsOf: slots, at: i + 1)
        }
        return list
    }()

    static func info(_ id: String) -> CommandInfo? { all.first { $0.id == id } }
}
