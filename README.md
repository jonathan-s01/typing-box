# Typing Box

A small Mac app for writing comfortably, made screen reader first. Press a shortcut in any app to open a plain text box, write or edit there with speech feedback, drafts and snippets, then paste the result back into the app you came from.

It is useful when a website or app's own text field is hard to edit with VoiceOver, too small, or easy to lose your work in.

By Jonathan Sieswerda ([jonathan-s01](https://github.com/jonathan-s01)). Free software under the GNU General Public License, version 3 or later (see LICENSE).

Version 3.1.2. Needs macOS 14 Sonoma or later.

## Shortcuts anywhere on your Mac
Command Option Return: open the box. If text is selected in the field you're in, that selection is cut into the box.
Command Option Shift Return: cut all the text out of the field you're in and open it in the box.

## In the box
Everything is in the window. Tab moves between: Drafts, Snippets, Actions, and the text.
- Drafts: pick a draft. Pinned drafts are listed first, then recent ones.
- Snippets: insert a snippet, save the selection as a snippet, or manage snippets.
- Actions (Command Shift M): every command, grouped into Drafts, Snippets, Speech, Find and Text Options, plus Settings, Keyboard Shortcuts and Quit. Menu items show their current shortcut.

Every shortcut can be changed in Settings, Shortcuts (Actions, Keyboard Shortcuts).
Press a shortcut button, then the new keys. Delete removes a shortcut. Escape cancels.
Reset All Shortcuts to Defaults puts everything back.

## Default shortcuts in the box
Command Return: paste into the previous app. Escape: close.
Command Shift M: Actions menu. Command Comma: Settings. Command Q: quit.
Command N: new draft. Command D: Drafts menu. Command Shift D: All Drafts window.
Command Shift P: pin or unpin. Command S: export draft. Command Shift S: export all.
Command Shift I: snippet menu at the cursor. Command Control 1 to 9: insert snippet 1 to 9.
Command Shift T: speak typing on or off. Command Shift R: read all. Command Shift L: read line.
Command Shift E: read sentence. Command Shift W: read word. Command Shift A: read selection.
Command Shift C: announce word and character count. Control: stop speaking.
Command F: find. Command G and Command Shift G: next and previous. Command Option F: find and replace.
Cut, copy, paste, undo, redo and select all use the standard keys.

## Privacy and permissions

- Everything stays on your Mac. Typing Box never connects to the internet.
- Drafts and snippets are saved in ~/Library/Application Support/Typing Box/. Settings, such as your shortcuts and voice, are saved in macOS's normal settings for the app.
- Typing Box needs the Accessibility permission (System Settings, Privacy and Security, Accessibility). It uses it to copy or cut the text from the field you were in, and to paste back into the app you came from. Without it, the box still opens, but it cannot pull text in or paste it back.
- Speech uses the voices built into macOS.

## Build it yourself

Typing Box is shared as source code, so you build it on your own Mac. It takes about a minute.

1. Install Apple's command line tools, if you do not have Xcode. In Terminal:

   xcode-select --install

2. Download this project. On GitHub, choose Code, then Download ZIP, and unzip it. Or, with Git:

   git clone https://github.com/jonathan-s01/typing-box.git

3. In Terminal, go to the folder, for example:

   cd ~/Downloads/typing-box

4. Recommended, once: make a signing certificate, so macOS keeps the Accessibility permission when you rebuild or update:

   bash setup-signing.sh

   This makes a free certificate that only exists on your Mac, in your login keychain. It may ask for your Mac password. Follow the steps it prints at the end.

5. Build and install:

   bash build.sh

   If a dialog asks whether codesign can use the key, choose Always Allow.

build.sh compiles the app, quits Typing Box if it is running, replaces /Applications/TypingBox.app with the new copy, and opens it.

6. The first time, turn on Typing Box in System Settings, Privacy and Security, Accessibility.

To update later, download the new version and run bash build.sh again.

To remove Typing Box: quit it, delete /Applications/TypingBox.app, and if you like, the folder ~/Library/Application Support/Typing Box. The signing certificate is called "Typing Box Local Signing" in Keychain Access, if you want to delete that too.

### Updating from 3.1.1 or earlier

The app's ID changed in 3.1.2, so macOS treats it as a new app. Your drafts, snippets and settings are kept. Turn the Accessibility permission on again once: run tccutil reset Accessibility local.jonathan.typingbox to remove the old entry, then turn on Typing Box in System Settings, Privacy and Security, Accessibility.

## Files
main.swift, AppDelegate.swift, Commands.swift (all commands and default shortcuts),
HotKey.swift (shortcuts and the recorder), TypingTextView.swift, Speaker.swift,
Settings.swift, SettingsWindow.swift, Drafts.swift, DraftsWindow.swift,
Snippets.swift, SnippetsWindow.swift, Markdown.swift.
Saved data: ~/Library/Application Support/Typing Box/
