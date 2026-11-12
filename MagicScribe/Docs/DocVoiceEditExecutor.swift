import Foundation

nonisolated enum DocVoiceEditMatch {
    case undo
    case redo
}

/// Faithful port of assets/js/docs.js's EDIT_UNDO_PHRASES/EDIT_REDO_PHRASES
/// + matchEditUndoRedo() (lines 147-155), plus the executeEditOperations()
/// side (lines 1905-1921) adapted to AttributedString instead of DOM
/// elements/execCommand.
///
/// Web addresses edits by `.dictated-chunk` element — a real per-session
/// DOM node. That doesn't exist in this single-page iOS model, so chunks
/// here are just the "\n"-delimited paragraphs already present in the
/// document, numbered 1-based to match the same "Line N" prompt framing
/// api/edit.php expects — no separate chunk-tracking state needed.
nonisolated enum DocVoiceEditExecutor {
    private static let undoPhrases: Set<String> = [
        "undo", "undo that", "undo this", "undo it",
        "undo the last change", "undo the last edit", "undo that last edit", "undo that change",
    ]
    private static let redoPhrases: Set<String> = [
        "redo", "redo that", "redo this", "redo it",
        "redo the last change", "redo that change", "redo the last undo",
    ]

    static func matchUndoRedo(_ instruction: String) -> DocVoiceEditMatch? {
        var normalized = instruction.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("please ") {
            normalized.removeFirst("please ".count)
        }
        while let last = normalized.last, ".!?".contains(last) {
            normalized.removeLast()
        }
        if undoPhrases.contains(normalized) { return .undo }
        if redoPhrases.contains(normalized) { return .redo }
        return nil
    }

    /// Splits on "\n" — the same paragraph-break character DocHTMLBridge
    /// already uses, so chunk boundaries here line up with real block/
    /// paragraph boundaries in the rendered document.
    static func paragraphRanges(in text: AttributedString) -> [Range<AttributedString.Index>] {
        var ranges: [Range<AttributedString.Index>] = []
        var start = text.startIndex
        var idx = text.startIndex
        while idx < text.endIndex {
            if text.characters[idx] == "\n" {
                ranges.append(start..<idx)
                idx = text.index(afterCharacter: idx)
                start = idx
            } else {
                idx = text.index(afterCharacter: idx)
            }
        }
        ranges.append(start..<text.endIndex)
        return ranges
    }

    static func chunks(from text: AttributedString) -> [EditChunk] {
        paragraphRanges(in: text).enumerated().map { index, range in
            EditChunk(id: index + 1, text: String(text[range].characters))
        }
    }

    /// Applies Claude's returned operations in order, returning how many
    /// actually matched something in the document (a target string Claude
    /// invented that isn't really there is silently skipped, same as web
    /// doing nothing when `selectInElement` can't find the target).
    ///
    /// Paragraph ranges are recomputed before each operation rather than
    /// cached up front — a prior op in this same batch (a delete or
    /// replace) shifts every index after it, so a stale range would either
    /// miss or corrupt the wrong text. Same reasoning as web re-querying
    /// `.dictated-chunk` elements live instead of reusing a stale NodeList.
    @discardableResult
    static func apply(_ operations: [EditOperation], to text: inout AttributedString) -> Int {
        var appliedCount = 0

        for op in operations {
            guard let chunkNumber = op.chunk else { continue }
            let ranges = paragraphRanges(in: text)
            guard chunkNumber >= 1, chunkNumber <= ranges.count else { continue }
            let chunkRange = ranges[chunkNumber - 1]

            switch op.type {
            case "delete_chunk":
                var removeRange = chunkRange
                if removeRange.upperBound < text.endIndex {
                    // Swallow the trailing "\n" too, so removing a whole
                    // paragraph doesn't leave a blank line behind.
                    removeRange = removeRange.lowerBound..<text.index(afterCharacter: removeRange.upperBound)
                } else if removeRange.lowerBound > text.startIndex {
                    removeRange = text.index(beforeCharacter: removeRange.lowerBound)..<removeRange.upperBound
                }
                text.removeSubrange(removeRange)
                appliedCount += 1

            case "format":
                guard let target = op.target, !target.isEmpty, let format = op.format,
                      let targetRange = text[chunkRange].range(of: target, options: .caseInsensitive)
                else { continue }
                switch format {
                case "bold":
                    var intent = text[targetRange].inlinePresentationIntent ?? []
                    intent.insert(.stronglyEmphasized)
                    text[targetRange].inlinePresentationIntent = intent
                case "italic":
                    var intent = text[targetRange].inlinePresentationIntent ?? []
                    intent.insert(.emphasized)
                    text[targetRange].inlinePresentationIntent = intent
                case "underline":
                    text[targetRange].underlineStyle = .single
                default:
                    continue
                }
                appliedCount += 1

            case "delete_text":
                guard let target = op.target, !target.isEmpty,
                      let targetRange = text[chunkRange].range(of: target, options: .caseInsensitive)
                else { continue }
                text.removeSubrange(targetRange)
                appliedCount += 1

            case "replace_text":
                guard let target = op.target, !target.isEmpty,
                      let targetRange = text[chunkRange].range(of: target, options: .caseInsensitive)
                else { continue }
                text.replaceSubrange(targetRange, with: AttributedString(op.replacement ?? ""))
                appliedCount += 1

            default:
                continue
            }
        }

        return appliedCount
    }
}
