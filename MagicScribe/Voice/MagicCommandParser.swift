import Foundation

nonisolated enum MagicCommand: String, Sendable {
    case boldOn, boldOff, bold
    case italicOn, italicOff, italic
    case underlineOn, underlineOff, underline
    case h1, h2, h3, headingOff
    case newParagraph, newLine
    case capsOn, capsOff, capsToggle
    case undo, redo
    case stop
}

nonisolated enum MagicToken: Equatable {
    case text(String)
    case command(MagicCommand)
}

/// Faithful port of assets/js/docs.js's CMD_PHRASES + tokenizer (lines
/// 119-135, 1357-1411) — same fixed English phrase list, same longest-
/// phrase-first matching, same "commands can appear mid-utterance, stripped
/// before insertion" behavior. Standalone and reusable, not demo-specific,
/// so the real post-paywall Docs feature can reuse it directly later.
nonisolated enum MagicCommandParser {
    private static let phraseTable: [(phrase: String, command: MagicCommand)] = [
        ("magic bold on", .boldOn),
        ("magic bold off", .boldOff),
        ("magic bold", .bold),
        ("magic italic on", .italicOn),
        ("magic italic off", .italicOff),
        ("magic italic", .italic),
        ("magic underline on", .underlineOn),
        ("magic underline off", .underlineOff),
        ("magic underline", .underline),
        ("magic heading one", .h1),
        ("magic heading 1", .h1),
        ("magic heading two", .h2),
        ("magic heading 2", .h2),
        ("magic heading three", .h3),
        ("magic heading 3", .h3),
        ("magic heading off", .headingOff),
        ("magic new paragraph", .newParagraph),
        ("magic new line", .newLine),
        ("magic caps on", .capsOn),
        ("magic caps lock on", .capsOn),
        ("magic all caps", .capsOn),
        ("magic caps off", .capsOff),
        ("magic caps lock off", .capsOff),
        ("magic no caps", .capsOff),
        ("magic caps", .capsToggle),
        ("magic undo", .undo),
        ("magic redo", .redo),
        ("magic stop", .stop),
        ("magic done", .stop),
        ("magic stop dictation", .stop),
    ]

    // Longest phrase first, so "magic bold on" matches before the shorter
    // "magic bold" — same ordering rule as cmdTokenizerRegex() in docs.js.
    private static let sortedPhrases: [(phrase: String, command: MagicCommand)] =
        phraseTable.sorted { $0.phrase.count > $1.phrase.count }

    private static let phraseToCommand: [String: MagicCommand] = Dictionary(
        uniqueKeysWithValues: phraseTable.map { ($0.phrase, $0.command) }
    )

    // NSRegularExpression rather than Swift's native Regex type — long-
    // established, predictable behavior for this kind of dynamic
    // alternation pattern.
    private static let regex: NSRegularExpression = {
        let escapedPhrases = sortedPhrases.map { NSRegularExpression.escapedPattern(for: $0.phrase) }
        let alternation = escapedPhrases.joined(separator: "|")
        // Word-boundary guards so "magic bold" inside a longer word never
        // matches; trailing s? tolerates Whisper pluralizing ("magics bold
        // on"), same as docs.js's regex.
        let pattern = "(?<![a-z0-9])(\(alternation))s?(?![a-z])"
        // swiftlint:disable:next force_try — pattern is built from a fixed,
        // known-valid phrase list; a failure here is a programmer error.
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    /// Splits a raw transcript into text/command tokens in order. Command
    /// phrases are never included in the text tokens — same "never written
    /// to the document" rule as docs.js.
    static func tokenize(_ transcript: String) -> [MagicToken] {
        let nsTranscript = transcript as NSString
        let fullRange = NSRange(location: 0, length: nsTranscript.length)
        let matches = regex.matches(in: transcript, options: [], range: fullRange)

        var tokens: [MagicToken] = []
        var lastEnd = 0

        for match in matches where match.numberOfRanges > 1 {
            let matchRange = match.range(at: 0)
            let phraseRange = match.range(at: 1)
            guard matchRange.location != NSNotFound, phraseRange.location != NSNotFound else { continue }

            if matchRange.location > lastEnd {
                let text = nsTranscript.substring(with: NSRange(location: lastEnd, length: matchRange.location - lastEnd))
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    tokens.append(.text(text))
                }
            }

            // Group 1 is the phrase itself, without the optional trailing
            // "s" tolerance — look it up directly rather than re-deriving it.
            let matchedPhrase = nsTranscript.substring(with: phraseRange).lowercased()
            if let command = phraseToCommand[matchedPhrase] {
                tokens.append(.command(command))
            }

            lastEnd = matchRange.location + matchRange.length
        }

        if lastEnd < nsTranscript.length {
            let text = nsTranscript.substring(with: NSRange(location: lastEnd, length: nsTranscript.length - lastEnd))
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                tokens.append(.text(text))
            }
        }

        return tokens
    }
}
