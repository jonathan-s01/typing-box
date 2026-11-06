// Drafts.swift
// Keeps the last 50 things that were in the box, newest first, plus any pinned drafts.
// Pinned drafts don't count toward the 50 and are never removed automatically.
// Saved to: ~/Library/Application Support/Typing Box/drafts.json

import Foundation

extension Notification.Name {
    static let draftsChanged = Notification.Name("TypingBoxDraftsChanged")
    static let snippetsChanged = Notification.Name("TypingBoxSnippetsChanged")
}

struct Draft: Codable {
    var id: UUID
    var text: String
    var created: Date
    var modified: Date
    var pinned: Bool = false
    var title: String? = nil

    init(id: UUID, text: String, created: Date, modified: Date) {
        self.id = id
        self.text = text
        self.created = created
        self.modified = modified
    }

    // Reads drafts saved by older versions, which had no pinned or title.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        created = try c.decode(Date.self, forKey: .created)
        modified = try c.decode(Date.self, forKey: .modified)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        title = try c.decodeIfPresent(String.self, forKey: .title)
    }

    /// The name shown in menus: the title if renamed, otherwise the first line.
    var displayName: String {
        if let t = title, !t.trimmingCharacters(in: .whitespaces).isEmpty { return t }
        let firstLine = text.split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let line = firstLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { return "Untitled" }
        return line.count > 60 ? String(line.prefix(60)) + "\u{2026}" : line
    }
}

@MainActor
final class DraftStore {
    static let maxCount = 50
    private(set) var drafts: [Draft] = []   // newest first
    private let url: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Typing Box", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("drafts.json")
        load()
    }

    /// Pinned drafts first, then the rest, each newest first.
    var ordered: [Draft] {
        drafts.filter { $0.pinned } + drafts.filter { !$0.pinned }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        drafts = (try? decoder.decode([Draft].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(drafts) {
            try? data.write(to: url, options: .atomic)
        }
        NotificationCenter.default.post(name: .draftsChanged, object: nil)
    }

    private func trim() {
        var unpinnedSeen = 0
        drafts = drafts.filter { d in
            if d.pinned { return true }
            unpinnedSeen += 1
            return unpinnedSeen <= Self.maxCount
        }
    }

    func draft(_ id: UUID) -> Draft? {
        drafts.first { $0.id == id }
    }

    /// Updates the draft with this id, or adds a new one at the top.
    /// Empty text is never stored. Returns the id the text now lives under.
    @discardableResult
    func upsert(id: UUID?, text: String) -> UUID? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return id }
        let now = Date()
        if let id, let i = drafts.firstIndex(where: { $0.id == id }) {
            if drafts[i].text != text {
                drafts[i].text = text
                drafts[i].modified = now
                save()
            }
            return id
        }
        let new = Draft(id: UUID(), text: text, created: now, modified: now)
        drafts.insert(new, at: 0)
        trim()
        save()
        return new.id
    }

    func setPinned(_ id: UUID, _ pinned: Bool) {
        guard let i = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[i].pinned = pinned
        trim()
        save()
    }

    func rename(_ id: UUID, to title: String?) {
        guard let i = drafts.firstIndex(where: { $0.id == id }) else { return }
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        drafts[i].title = (t?.isEmpty ?? true) ? nil : t
        save()
    }

    func remove(_ id: UUID) {
        drafts.removeAll { $0.id == id }
        save()
    }

    /// Removes every unpinned draft. Pinned drafts stay.
    func removeAllUnpinned() {
        drafts.removeAll { !$0.pinned }
        save()
    }
}
