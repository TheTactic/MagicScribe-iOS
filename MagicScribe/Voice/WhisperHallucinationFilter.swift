import Foundation

/// Faithful port of assets/js/docs.js's HALLUCINATION_DENY list +
/// isWhisperHallucination() (lines 109-116, 1970-1978). Whisper reliably
/// hallucinates filler text — a bare "." most of all — on near-silent
/// audio, e.g. the beat between tapping the mic and actually starting to
/// speak. Web discards a whole chunk's transcript when it matches; this
/// does the same before a chunk ever reaches MagicCommandParser.
nonisolated enum WhisperHallucinationFilter {
    private static let denyPatterns: [NSRegularExpression] = [
        #"^\.?\s*$"#,
        #"^(thank you|thanks|bye|goodbye|you|okay|ok|um+|uh+|hmm+)\.?$"#,
        #"^thank you (so much|very much|for watching|for listening)\.?$"#,
        #"^(please )?(like and subscribe|subscribe)\.?$"#,
        #"^\.\s*(thank you|thanks|bye).*$"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    static func isHallucination(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }

        let fullRange = NSRange(trimmed.startIndex..., in: trimmed)
        for pattern in denyPatterns where pattern.firstMatch(in: trimmed, range: fullRange) != nil {
            return true
        }

        // Fewer than 3 actual letters → almost certainly noise. ASCII a-z/
        // A-Z only, matching web's `replace(/[^a-z]/gi, '')` exactly — not
        // CharacterSet.letters, which would also count accented es/fr
        // letters web's check doesn't.
        let letterCount = trimmed.unicodeScalars.filter { scalar in
            (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
        }.count
        return letterCount < 3
    }
}
