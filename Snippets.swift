// Snippets.swift
// Saved bits of text you reuse. Saved to:
// ~/Library/Application Support/Typing Box/snippets.json

import Foundation

struct Snippet: Codable {
    var id: UUID
    var name: String
    var text: String
}

@MainActor
final class SnippetStore {
    private(set) var snippets: [Snippet] = []
    private let url: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Typing Box", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("snippets.json")
        if let data = try? Data(contentsOf: url) {
            snippets = (try? JSONDecoder().decode([Snippet].self, from: data)) ?? []
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(snippets) {
            try? data.write(to: url, options: .atomic)
        }
        NotificationCenter.default.post(name: .snippetsChanged, object: nil)
    }

    func snippet(_ id: UUID) -> Snippet? { snippets.first { $0.id == id } }

    @discardableResult
    func add(name: String, text: String) -> UUID {
        let s = Snippet(id: UUID(), name: name, text: text)
        snippets.append(s)
        save()
        return s.id
    }

    func update(_ id: UUID, name: String? = nil, text: String? = nil) {
        guard let i = snippets.firstIndex(where: { $0.id == id }) else { return }
        if let name { snippets[i].name = name }
        if let text { snippets[i].text = text }
        save()
    }

    func remove(_ id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
    }

    func move(_ id: UUID, by offset: Int) {
        guard let i = snippets.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard j >= 0, j < snippets.count else { return }
        snippets.swapAt(i, j)
        save()
    }
}
