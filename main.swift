// Typing Box
// Command Option Return: open the box (or pull in selected text).
// Command Option Shift Return: cut the whole field into the box.
// Command Return: paste into the app you came from.
// Escape: close the box and keep the draft.

import Cocoa

// The app starts on the main thread, so tell Swift that's where this code runs.
// Versions before 3.1.2 used the app ID local.jonathan.typingbox. Settings (shortcuts, voice and so on)
// are saved under the app ID, so copy them across once. Drafts and snippets are files and need nothing.
func moveOldSettings() {
    let old = "local.jonathan.typingbox"
    guard let id = Bundle.main.bundleIdentifier, id != old else { return }
    let d = UserDefaults.standard
    guard d.persistentDomain(forName: id)?.isEmpty ?? true,
          let previous = d.persistentDomain(forName: old), !previous.isEmpty else { return }
    d.setPersistentDomain(previous, forName: id)
}
moveOldSettings()

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
