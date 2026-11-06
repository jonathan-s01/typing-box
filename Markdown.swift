// Markdown.swift
// Turns simple Markdown into HTML so rich editors (Teams, Outlook and similar)
// paste it as real formatting. Supports: headings (#), bold (**text** or __text__),
// italic (*text*), strikethrough (~~text~~), inline code (`code`), code blocks (```),
// links [text](url), bulleted lists (- * +), numbered lists (1.), and quotes (>).

import Foundation

enum Markdown {
    static func html(from markdown: String) -> String {
        var out: [String] = []
        var paragraph: [String] = []
        var listType: String? = nil      // "ul" or "ol"
        var inCode = false
        var code: [String] = []
        var quote: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                out.append("<p>" + paragraph.map(inline).joined(separator: "<br>") + "</p>")
                paragraph = []
            }
        }
        func closeList() {
            if let t = listType { out.append("</\(t)>"); listType = nil }
        }
        func flushQuote() {
            if !quote.isEmpty {
                out.append("<blockquote>" + quote.map(inline).joined(separator: "<br>") + "</blockquote>")
                quote = []
            }
        }
        func flushAll() { flushParagraph(); closeList(); flushQuote() }

        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCode {
                    out.append("<pre><code>" + code.map(escape).joined(separator: "\n") + "</code></pre>")
                    code = []
                    inCode = false
                } else {
                    flushAll()
                    inCode = true
                }
                continue
            }
            if inCode { code.append(line); continue }
            if trimmed.isEmpty { flushAll(); continue }

            if let m = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                flushAll()
                let level = trimmed[m].filter { $0 == "#" }.count
                out.append("<h\(level)>\(inline(String(trimmed[m.upperBound...])))</h\(level)>")
                continue
            }
            if trimmed.hasPrefix(">") {
                flushParagraph(); closeList()
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }
            if let m = trimmed.range(of: #"^[-*+]\s+"#, options: .regularExpression) {
                flushParagraph(); flushQuote()
                if listType != "ul" { closeList(); out.append("<ul>"); listType = "ul" }
                out.append("<li>\(inline(String(trimmed[m.upperBound...])))</li>")
                continue
            }
            if let m = trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                flushParagraph(); flushQuote()
                if listType != "ol" { closeList(); out.append("<ol>"); listType = "ol" }
                out.append("<li>\(inline(String(trimmed[m.upperBound...])))</li>")
                continue
            }
            closeList(); flushQuote()
            paragraph.append(trimmed)
        }
        if inCode {
            out.append("<pre><code>" + code.map(escape).joined(separator: "\n") + "</code></pre>")
        }
        flushAll()
        return "<html><head><meta charset=\"utf-8\"></head><body>" + out.joined(separator: "\n") + "</body></html>"
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Inline formatting. Text inside backticks is left alone.
    static func inline(_ s: String) -> String {
        let pieces = s.components(separatedBy: "`")
        // With an odd number of backticks, the last one has no partner and is kept as is.
        let paired = pieces.count % 2 == 1 ? pieces.count : pieces.count - 1
        var result = ""
        for (i, piece) in pieces.enumerated() {
            if i >= paired {
                result += "`" + formatText(escape(piece))
            } else if i % 2 == 1 {
                result += "<code>" + escape(piece) + "</code>"
            } else {
                result += formatText(escape(piece))
            }
        }
        return result
    }

    private static func formatText(_ s: String) -> String {
        var t = s
        t = replace(t, #"\[([^\]]+)\]\(([^)\s]+)\)"#, "<a href=\"$2\">$1</a>")
        t = replace(t, #"\*\*(.+?)\*\*"#, "<strong>$1</strong>")
        t = replace(t, #"(?<![\w])__(.+?)__(?![\w])"#, "<strong>$1</strong>")
        t = replace(t, #"(?<![\*\w])\*(?!\s)(.+?)(?<!\s)\*(?![\*\w])"#, "<em>$1</em>")
        t = replace(t, #"~~(.+?)~~"#, "<del>$1</del>")
        return t
    }

    private static func replace(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return re.stringByReplacingMatches(in: s, range: range, withTemplate: template)
    }
}
