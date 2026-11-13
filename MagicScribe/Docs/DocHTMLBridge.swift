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

/// Paragraph-level, same convention as heading level — stored on a
/// paragraph's first run, read by DocHTMLBridge.render() to decide whether
/// consecutive paragraphs should be grouped into one shared <ul>/<ol>.
nonisolated enum DocsListKind: Int, Sendable, Hashable, Codable {
    case bullet, numbered
}

nonisolated struct DocsListKindAttribute: AttributedStringKey {
    typealias Value = DocsListKind
    static let name = "DocsListKind"
}

/// SwiftUI's `Font` has no introspection surface to read a family name or
/// point size back out of an arbitrary value (unlike `Color.resolve(in:)`),
/// so family/size are tracked as their own small custom attributes — the
/// closed-vocabulary-custom-key pattern, not fighting an opaque system
/// type. The visual `.font` attribute is still set separately (derived
/// from these two) purely for TextEditor's own rendering; DocHTMLBridge's
/// render() always reads these, never decomposes `.font`.
nonisolated struct DocsFontFamilyAttribute: AttributedStringKey {
    typealias Value = String
    static let name = "DocsFontFamily"
}

nonisolated struct DocsFontSizeAttribute: AttributedStringKey {
    typealias Value = CGFloat
    static let name = "DocsFontSize"
}

/// Holds this app's own custom attributes (not part of DocsAttributeScope
/// below, which exists only for attributes that need a ValueConstraint —
/// these never do, since they're only ever set by this app's own toolbar/
/// magic-command code, never by the system's built-in formatting controls).
extension AttributeScopes {
    struct DocsHeadingScope: AttributeScope {
        let headingLevel: DocsHeadingLevelAttribute
        let listKind: DocsListKindAttribute
        let fontFamily: DocsFontFamilyAttribute
        let fontSizePx: DocsFontSizeAttribute
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
    let textAlignment: AttributeScopes.CoreTextAttributes.TextAlignmentAttribute
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
        AttributedTextFormatting.ValueConstraint(
            for: \.textAlignment,
            values: [nil, .left, .center, .right],
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
    // 3rd capture group = raw attribute string (face="..."/color="..."/
    // style="...") — discarded by every tag that doesn't use it, parsed
    // further below for font/p/h1-3 tags.
    private static let tagRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: "<(/?)(\\w+)([^>]*)>")
    }()
    private static let faceAttrRegex = try! NSRegularExpression(pattern: #"face="([^"]*)""#)
    private static let colorAttrRegex = try! NSRegularExpression(pattern: #"\bcolor="([^"]*)""#)
    private static let fontSizeStyleRegex = try! NSRegularExpression(pattern: #"font-size:\s*(\d+)px"#)
    private static let textAlignStyleRegex = try! NSRegularExpression(pattern: #"text-align:\s*(\w+)"#)

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
        var paragraphAlignment: AttributedString.TextAlignment?
        var listContext: DocsListKind?
        // Stacks for web's real nested-<font>-tag behavior: innermost
        // wins for whichever of face/color/size it specifies, inheriting
        // whatever was active before for anything it doesn't. First
        // element is always the "no override" baseline so `.last!` is
        // never empty.
        var fontFamilyStack: [String?] = [nil]
        var fontColorStack: [Color?] = [nil]
        var fontSizeStack: [CGFloat?] = [nil]

        func appendText(_ raw: String) {
            let unescaped = unescapeEntities(raw)
            guard !unescaped.isEmpty else { return }
            var run = AttributedString(unescaped)
            var intent: InlinePresentationIntent = []
            if boldDepth > 0 { intent.insert(.stronglyEmphasized) }
            if italicDepth > 0 { intent.insert(.emphasized) }
            if !intent.isEmpty { run.inlinePresentationIntent = intent }
            if underlineDepth > 0 { run.underlineStyle = .single }

            let family = fontFamilyStack.last!
            let sizePx = fontSizeStack.last!
            if family != nil || sizePx != nil {
                run.fontFamily = family ?? "Georgia"
                run.fontSizePx = sizePx ?? 14
                run.font = .custom(family ?? "Georgia", size: sizePx ?? 14)
            }
            if let color = fontColorStack.last! { run.foregroundColor = color }

            if let headingLevel {
                run.headingLevel = headingLevel
                run.font = headingFont(for: headingLevel)
            }
            if let paragraphAlignment {
                run[AttributeScopes.CoreTextAttributes.TextAlignmentAttribute.self] = paragraphAlignment
            }
            if let listContext {
                run.listKind = listContext
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
            let attrRange = match.range(at: 3)
            let attrString = attrRange.location != NSNotFound ? ns.substring(with: attrRange) : ""

            if isClosing {
                switch tag {
                case "b", "strong": boldDepth = max(0, boldDepth - 1)
                case "i", "em": italicDepth = max(0, italicDepth - 1)
                case "u": underlineDepth = max(0, underlineDepth - 1)
                case "font":
                    if fontFamilyStack.count > 1 { fontFamilyStack.removeLast() }
                    if fontColorStack.count > 1 { fontColorStack.removeLast() }
                    if fontSizeStack.count > 1 { fontSizeStack.removeLast() }
                case "h1", "h2", "h3":
                    headingLevel = nil
                    paragraphAlignment = nil
                    result += AttributedString("\n")
                case "p", "li":
                    paragraphAlignment = nil
                    result += AttributedString("\n")
                case "ul", "ol":
                    listContext = nil
                default: break
                }
            } else {
                switch tag {
                case "b", "strong": boldDepth += 1
                case "i", "em": italicDepth += 1
                case "u": underlineDepth += 1
                case "font":
                    let face = firstMatch(faceAttrRegex, in: attrString)
                    let colorHex = firstMatch(colorAttrRegex, in: attrString)
                    let sizePx = firstMatch(fontSizeStyleRegex, in: attrString).flatMap { Double($0) }.map { CGFloat($0) }
                    fontFamilyStack.append(face ?? fontFamilyStack.last!)
                    fontColorStack.append(colorHex.flatMap { colorFromHex($0) } ?? fontColorStack.last!)
                    fontSizeStack.append(sizePx ?? fontSizeStack.last!)
                case "h1": headingLevel = 1
                case "h2": headingLevel = 2
                case "h3": headingLevel = 3
                case "ul": listContext = .bullet
                case "ol": listContext = .numbered
                case "br": result += AttributedString("\n")
                default: break
                }
                if tag == "p" || tag == "h1" || tag == "h2" || tag == "h3" {
                    paragraphAlignment = firstMatch(textAlignStyleRegex, in: attrString).flatMap { alignmentFromKeyword($0) }
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

    private struct ParagraphInfo {
        let tag: String
        let listKind: DocsListKind?
        let alignment: AttributedString.TextAlignment?
        let innerHTML: String
    }

    static func render(_ text: AttributedString) -> String {
        var paragraphs: [ParagraphInfo] = []
        var paragraphRun = AttributedString()

        func flushParagraph() {
            guard !paragraphRun.characters.isEmpty else { return }
            let firstRun = paragraphRun.runs.first
            let level = firstRun?.headingLevel
            let tag = level.map { "h\($0)" } ?? "p"
            paragraphs.append(ParagraphInfo(
                tag: tag,
                listKind: firstRun?.listKind,
                alignment: firstRun?[AttributeScopes.CoreTextAttributes.TextAlignmentAttribute.self],
                innerHTML: renderInline(paragraphRun)
            ))
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

        // Group consecutive same-kind list paragraphs into one shared
        // <ul>/<ol> wrapping multiple <li> — a list item is never its own
        // standalone element, matching web's real DOM shape.
        var html = ""
        var index = 0
        while index < paragraphs.count {
            let paragraph = paragraphs[index]
            if let listKind = paragraph.listKind {
                let wrapper = listKind == .bullet ? "ul" : "ol"
                html += "<\(wrapper)>"
                while index < paragraphs.count, paragraphs[index].listKind == listKind {
                    html += "<li>" + paragraphs[index].innerHTML + "</li>"
                    index += 1
                }
                html += "</\(wrapper)>"
            } else {
                let styleAttr = paragraph.alignment.map { " style=\"text-align:\(keywordFromAlignment($0))\"" } ?? ""
                html += "<\(paragraph.tag)\(styleAttr)>" + paragraph.innerHTML + "</\(paragraph.tag)>"
                index += 1
            }
        }
        return html
    }

    /// Renders the inline b/i/u/font runs within a single paragraph/
    /// heading/list-item's worth of content — no block-level concerns
    /// here, just nested tags.
    private static func renderInline(_ text: AttributedString) -> String {
        var html = ""
        for run in text.runs {
            let runText = escapeEntities(String(text[run.range].characters))
            var openTags: [String] = []
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.stronglyEmphasized) { openTags.append("b") }
            if intent.contains(.emphasized) { openTags.append("i") }
            if run.underlineStyle == .single { openTags.append("u") }

            // Skipped entirely when family/size are at baseline default
            // and there's no color override, matching web's own "only
            // wrap on explicit override" behavior — default-styled text
            // stays clean, same reasoning as the baseline-skip in
            // DocFormattingState.setFontFamily/setFontSize.
            var fontAttrs = ""
            if let family = run.fontFamily, family != "Georgia" {
                fontAttrs += " face=\"\(family)\""
            }
            if let color = run.foregroundColor {
                fontAttrs += " color=\"\(hexFromColor(color))\""
            }
            if let sizePx = run.fontSizePx, sizePx != 14 {
                fontAttrs += " style=\"font-size:\(Int(sizePx))px\""
            }
            let hasFontWrapper = !fontAttrs.isEmpty

            let opening = openTags.map { "<\($0)>" }.joined() + (hasFontWrapper ? "<font\(fontAttrs)>" : "")
            let closing = (hasFontWrapper ? "</font>" : "") + openTags.reversed().map { "</\($0)>" }.joined()
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

    // MARK: - Attribute string parsing helpers

    /// Extracts the first capture group of `regex`'s first match in `s`,
    /// or nil if there's no match — used for pulling face="..."/color="..."
    /// /font-size:...px/text-align:... out of a tag's raw attribute string.
    private static func firstMatch(_ regex: NSRegularExpression, in s: String) -> String? {
        guard !s.isEmpty else { return nil }
        let ns = s as NSString
        guard let match = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        let range = match.range(at: 1)
        guard range.location != NSNotFound else { return nil }
        return ns.substring(with: range)
    }

    private static func colorFromHex(_ hex: String) -> Color? {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let value = UInt32(h, radix: 16) else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    private static func hexFromColor(_ color: Color) -> String {
        let resolved = color.resolve(in: EnvironmentValues())
        func clamp(_ v: Float) -> Int { min(255, max(0, Int((v * 255).rounded()))) }
        return String(format: "#%02x%02x%02x", clamp(resolved.red), clamp(resolved.green), clamp(resolved.blue))
    }

    private static func alignmentFromKeyword(_ keyword: String) -> AttributedString.TextAlignment? {
        switch keyword.lowercased() {
        case "center": .center
        case "right": .right
        case "left": .left
        default: nil
        }
    }

    private static func keywordFromAlignment(_ alignment: AttributedString.TextAlignment) -> String {
        switch alignment {
        case .center: "center"
        case .right: "right"
        default: "left"
        }
    }
}
