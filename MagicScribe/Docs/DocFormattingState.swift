import SwiftUI

/// The open-span formatting state machine — bold/italic/underline/heading/
/// caps flags carried across a `[MagicToken]` sequence, faithful port of
/// web's `buildChunkElements()` concept: text runs are built already-styled
/// at construction time, not applied via a selection+toggle model. State
/// persists for the lifetime of this instance (owned by DocsEditorView),
/// matching web's module-level `openSpanFormats`/`voiceCapsOpen` persisting
/// across chunk boundaries and across separate recording sessions.
///
/// Shared by both input paths per the approved plan: dictation consumes a
/// whole chunk's tokens via `buildRuns(from:)`; the manual toolbar toggles
/// one flag at a time and applies `currentContainer` directly to the
/// current selection — same underlying state, so "is bold currently on"
/// stays consistent between what you say and what you tap.
@MainActor
final class DocFormattingState {
    private(set) var boldOn = false
    private(set) var italicOn = false
    private(set) var underlineOn = false
    private(set) var headingLevel: Int?
    private(set) var capsOn = false

    /// nil = inherit the editor's baseline default (Georgia/14, matching
    /// web's own default toolbar selection) rather than forcing every
    /// character to carry an explicit font override when nothing was
    /// changed — mirrors web's CSS-default-unless-overridden behavior.
    private(set) var fontFamily: String?
    private(set) var fontSize: CGFloat?
    private(set) var foregroundColor: Color?

    /// Block-level (apply to a whole paragraph, not a character run) —
    /// unlike everything else here, these aren't touched by styledRun()/
    /// dictation at all. Applied via DocsEditorView's
    /// applyBlockAttributeToSelection(), not currentContainer.
    private(set) var alignment: AttributedString.TextAlignment?
    private(set) var listKind: DocsListKind?

    static let availableFontFamilies = ["Georgia", "Arial", "Times New Roman", "Courier New", "Verdana", "Trebuchet MS"]
    static let availableFontSizes: [CGFloat] = [10, 12, 14, 16, 18, 24, 32, 48]

    /// `text` is the styled content built from this chunk's tokens.
    /// `sessionCommands` is `.undo`/`.redo`/`.stop` encountered, in order —
    /// these are session-level signals, not formatting, so the caller
    /// (ContinuousDictationController) reacts to them directly instead of
    /// re-scanning the token list itself.
    struct ChunkResult {
        let text: AttributedString
        let sessionCommands: [MagicCommand]
    }

    func toggleBold() { boldOn.toggle() }
    func toggleItalic() { italicOn.toggle() }
    func toggleUnderline() { underlineOn.toggle() }

    /// Tapping the same heading level again turns it off — standard
    /// toggle-button behavior for a one-of-four (H1/H2/H3/normal) control.
    func setHeading(_ level: Int) {
        headingLevel = (headingLevel == level) ? nil : level
    }

    func setFontFamily(_ family: String) {
        fontFamily = (family == "Georgia") ? nil : family
    }

    func setFontSize(_ size: CGFloat) {
        fontSize = (size == 14) ? nil : size
    }

    func setColor(_ color: Color?) {
        foregroundColor = color
    }

    /// Same toggle-off-on-reselect behavior as setHeading — tapping the
    /// active alignment again resets to the default (left/natural).
    func setAlignment(_ value: AttributedString.TextAlignment) {
        alignment = (alignment == value || value == .left) ? nil : value
    }

    /// Same toggle-off-on-reselect behavior as setHeading.
    func setListKind(_ kind: DocsListKind) {
        listKind = (listKind == kind) ? nil : kind
    }

    var currentContainer: AttributeContainer {
        var container = AttributeContainer()
        var intent: InlinePresentationIntent = []
        if boldOn { intent.insert(.stronglyEmphasized) }
        if italicOn { intent.insert(.emphasized) }
        if !intent.isEmpty { container.inlinePresentationIntent = intent }
        if underlineOn { container.underlineStyle = .single }
        if let foregroundColor { container.foregroundColor = foregroundColor }
        // Heading's own font override wins when active — font-family/size
        // pickers only apply to body (non-heading) text, same precedence
        // as web, where picking a heading style isn't expected to also
        // respect whatever the font dropdowns say. fontFamily/fontSizePx
        // are DocHTMLBridge's own custom attributes (Font has no
        // introspection surface to recover a family/size from `.font`
        // alone, so those are the source of truth on render) — `.font`
        // itself is also set here purely so TextEditor visually reflects
        // the choice, never read back for serialization.
        if headingLevel == nil, fontFamily != nil || fontSize != nil {
            container.fontFamily = fontFamily ?? "Georgia"
            container.fontSizePx = fontSize ?? 14
            container.font = .custom(fontFamily ?? "Georgia", size: fontSize ?? 14)
        }
        return container
    }

    func buildRuns(from tokens: [MagicToken]) -> ChunkResult {
        var result = AttributedString()
        var sessionCommands: [MagicCommand] = []

        for token in tokens {
            switch token {
            case .text(let text):
                result += styledRun(for: text)
            case .command(let command):
                switch command {
                case .boldOn: boldOn = true
                case .boldOff: boldOn = false
                case .bold: boldOn.toggle()
                case .italicOn: italicOn = true
                case .italicOff: italicOn = false
                case .italic: italicOn.toggle()
                case .underlineOn: underlineOn = true
                case .underlineOff: underlineOn = false
                case .underline: underlineOn.toggle()
                case .h1: headingLevel = 1
                case .h2: headingLevel = 2
                case .h3: headingLevel = 3
                case .headingOff: headingLevel = nil
                case .newParagraph, .newLine:
                    // v1 simplification: both produce the same paragraph
                    // break — DocHTMLBridge treats every "\n" as a block
                    // boundary; there's no separate soft-<br>-within-<p>
                    // model yet, unlike web's distinct newParagraph/newLine.
                    result += AttributedString("\n")
                case .capsOn: capsOn = true
                case .capsOff: capsOn = false
                case .capsToggle: capsOn.toggle()
                case .undo, .redo, .stop:
                    sessionCommands.append(command)
                }
            }
        }
        return ChunkResult(text: result, sessionCommands: sessionCommands)
    }

    private func styledRun(for text: String) -> AttributedString {
        // capsOn is a text transform (uppercase subsequent characters), not
        // an attribute — modeling it as a flag like bold/italic would drift
        // from web's actual behavior and wouldn't serialize to anything
        // meaningful in DocHTMLBridge.
        let transformed = capsOn ? text.uppercased() : text
        var run = AttributedString(transformed, attributes: currentContainer)
        if let headingLevel {
            run.headingLevel = headingLevel
            run.font = DocHTMLBridge.headingFont(for: headingLevel)
        }
        return run
    }
}
