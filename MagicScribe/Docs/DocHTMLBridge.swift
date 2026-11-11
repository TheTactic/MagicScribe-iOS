import SwiftUI

/// Custom attribute — Foundation's PresentationIntent/IntentType is really
/// designed for a markdown-conversion pipeline (block-level, nested-intent
/// chains) and its exact Swift construction/read-back surface is murky.
/// A small, fully-controlled custom key is simpler and sufficient for the
/// closed h1/h2/h3 vocabulary this editor needs — same "small, controlled"
/// philosophy as MagicCommandParser rather than fighting a general API.
nonisolated struct DocsHeadingLevelAttribute: AttributedStringKey {
    typealias Value = Int
    static let name = "DocsHeadingLevel"
}

extension AttributeScopes {
    struct DocsHeadingScope: AttributeScope {
        let headingLevel: DocsHeadingLevelAttribute
    }
    var docsHeading: DocsHeadingScope.Type { DocsHeadingScope.self }
}

extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.DocsHeadingScope, T>) -> T {
        self[T.self]
    }
}

/// `inlinePresentationIntent` lives under `AttributeScopes.FoundationAttributes`,
/// `underlineStyle` under `AttributeScopes.SwiftUIAttributes` — a formatting
/// definition is scoped to one single AttributeScope, so a custom combined
/// scope is required to constrain both together. (Confirmed working via a
/// feasibility spike before this file was written.) Heading level is
/// deliberately NOT part of this constraint — it's only ever set by this
/// app's own toolbar/magic-command code, never by the system's built-in
/// formatting controls, so there's nothing to constrain there.
nonisolated struct DocsAttributeScope: AttributeScope {
    let inlinePresentationIntent: AttributeScopes.FoundationAttributes.InlinePresentationIntentAttribute
    let underlineStyle: AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute
}

extension AttributeScopes {
    var docsAttributeScope: DocsAttributeScope.Type { DocsAttributeScope.self }
}

nonisolated struct DocsFormattingDefinition: AttributedTextFormattingDefinition {
    var body: some AttributedTextFormattingDefinition<DocsAttributeScope> {
        AttributedTextFormatting.ValueConstraint(
            for: \.inlinePresentationIntent,
            values: [nil, .stronglyEmphasized, .emphasized, [.stronglyEmphasized, .emphasized]],
            default: nil
        )
        AttributedTextFormatting.ValueConstraint(
            for: \.underlineStyle,
            values: [nil, .single],
            default: nil
        )
    }
}

/// Hand-rolled HTML<->AttributedString codec scoped to exactly the tag
/// vocabulary MagicScribe Docs uses: b/i/u/h1/h2/h3/p. Not a general HTML
/// parser — same spirit as MagicCommandParser, a small parser for a closed,
/// controlled vocabulary (either this codec's own output, or web's
/// equivalently-plain docs.js-authored markup). Deliberately NOT using
/// NSAttributedString's HTML bridge: its writer bakes everything into
/// CSS-class/inline-style spans with no semantic <h1>/<b> at all, and its
/// reader produces generic TextKit attributes that don't match this
/// editor's closed attribute vocabulary.
enum DocHTMLBridge {
    private static let tagRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: "<(/?)(\\w+)[^>]*>")
    }()

    // MARK: - Parse: HTML -> AttributedString

    static func parse(html: String) -> AttributedString {
        let ns = html as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = tagRegex.matches(in: html, range: fullRange)

        var result = AttributedString()
        var cursor = 0
        var boldDepth = 0
        var italicDepth = 0
        var underlineDepth = 0
        var headingLevel: Int?

        func appendText(_ raw: String) {
            let unescaped = unescapeEntities(raw)
            guard !unescaped.isEmpty else { return }
            var run = AttributedString(unescaped)
            var intent: InlinePresentationIntent = []
            if boldDepth > 0 { intent.insert(.stronglyEmphasized) }
            if italicDepth > 0 { intent.insert(.emphasized) }
            if !intent.isEmpty { run.inlinePresentationIntent = intent }
            if underlineDepth > 0 { run.underlineStyle = .single }
            if let headingLevel {
                run.headingLevel = headingLevel
                run.font = headingFont(for: headingLevel)
            }
            result += run
        }

        for match in matches {
            let matchRange = match.range(at: 0)
            if matchRange.location > cursor {
                appendText(ns.substring(with: NSRange(location: cursor, length: matchRange.location - cursor)))
            }
            let isClosing = ns.substring(with: match.range(at: 1)) == "/"
            let tag = ns.substring(with: match.range(at: 2)).lowercased()

            if isClosing {
                switch tag {
                case "b", "strong": boldDepth = max(0, boldDepth - 1)
                case "i", "em": italicDepth = max(0, italicDepth - 1)
                case "u": underlineDepth = max(0, underlineDepth - 1)
                case "h1", "h2", "h3":
                    headingLevel = nil
                    result += AttributedString("\n")
                case "p":
                    result += AttributedString("\n")
                default: break
                }
            } else {
                switch tag {
                case "b", "strong": boldDepth += 1
                case "i", "em": italicDepth += 1
                case "u": underlineDepth += 1
                case "h1": headingLevel = 1
                case "h2": headingLevel = 2
                case "h3": headingLevel = 3
                case "br": result += AttributedString("\n")
                default: break
                }
            }
            cursor = matchRange.location + matchRange.length
        }
        if cursor < ns.length {
            appendText(ns.substring(from: cursor))
        }

        // Trim a single trailing newline — every block closes with one,
        // including the last, which would otherwise leave a dangling blank line.
        if result.characters.last == "\n" {
            result.removeSubrange(result.index(beforeCharacter: result.endIndex)..<result.endIndex)
        }
        return result
    }

    // MARK: - Render: AttributedString -> HTML

    static func render(_ text: AttributedString) -> String {
        var html = ""
        var paragraphRun = AttributedString()

        func flushParagraph() {
            guard !paragraphRun.characters.isEmpty else { return }
            let level = paragraphRun.runs.first?.headingLevel
            let tag = level.map { "h\($0)" } ?? "p"
            html += "<\(tag)>" + renderInline(paragraphRun) + "</\(tag)>"
            paragraphRun = AttributedString()
        }

        for character in text.characters.indices {
            let charString = String(text.characters[character])
            if charString == "\n" {
                flushParagraph()
            } else {
                paragraphRun += text[character..<text.index(afterCharacter: character)]
            }
        }
        flushParagraph()
        return html
    }

    /// Renders the inline b/i/u runs within a single paragraph/heading's
    /// worth of content — no block-level concerns here, just nested tags.
    private static func renderInline(_ text: AttributedString) -> String {
        var html = ""
        for run in text.runs {
            let runText = escapeEntities(String(text[run.range].characters))
            var openTags: [String] = []
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.stronglyEmphasized) { openTags.append("b") }
            if intent.contains(.emphasized) { openTags.append("i") }
            if run.underlineStyle == .single { openTags.append("u") }

            let opening = openTags.map { "<\($0)>" }.joined()
            let closing = openTags.reversed().map { "</\($0)>" }.joined()
            html += opening + runText + closing
        }
        return html
    }

    // MARK: - Heading visual style

    /// Shared with DocFormattingState so dictation-applied headings get the
    /// identical visual treatment as parsed-from-HTML ones.
    static func headingFont(for level: Int) -> Font {
        switch level {
        case 1: .title.bold()
        case 2: .title2.bold()
        default: .title3.bold()
        }
    }

    // MARK: - Entity escaping

    private static func unescapeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&") // must be last
    }

    private static func escapeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;") // must be first
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
