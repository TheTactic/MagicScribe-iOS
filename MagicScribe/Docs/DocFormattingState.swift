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

    var currentContainer: AttributeContainer {
        var container = AttributeContainer()
        var intent: InlinePresentationIntent = []
        if boldOn { intent.insert(.stronglyEmphasized) }
        if italicOn { intent.insert(.emphasized) }
        if !intent.isEmpty { container.inlinePresentationIntent = intent }
        if underlineOn { container.underlineStyle = .single }
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
