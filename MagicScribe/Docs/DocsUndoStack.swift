import Foundation

/// Bounded whole-AttributedString snapshot stack for programmatic
/// mutations — toolbar taps and applied dictation chunks — which the
/// system TextEditor's native undo does NOT cover (that only follows real
/// typed/IME edits). Wired to the `.undo`/`.redo` MagicToken cases: those
/// already exist in the parser vocabulary, so shipping without this would
/// make "magic undo" silently do nothing after a bad dictation chunk, a
/// real functional regression, not a scope cut.
///
/// Deliberately NOT per-keystroke (native undo already covers ordinary
/// typing) and NOT a diff/patch system — each entry is the full document
/// state immediately before one toolbar tap or one applied chunk, which is
/// already a natural transaction boundary at that granularity.
@MainActor
final class DocsUndoStack {
    private var undoEntries: [AttributedString] = []
    private var redoEntries: [AttributedString] = []
    private let maxEntries = 30

    /// Call BEFORE mutating the document.
    func push(_ current: AttributedString) {
        undoEntries.append(current)
        if undoEntries.count > maxEntries {
            undoEntries.removeFirst()
        }
        redoEntries.removeAll()
    }

    func undo(current: AttributedString) -> AttributedString? {
        guard let previous = undoEntries.popLast() else { return nil }
        redoEntries.append(current)
        return previous
    }

    func redo(current: AttributedString) -> AttributedString? {
        guard let next = redoEntries.popLast() else { return nil }
        undoEntries.append(current)
        return next
    }

    var canUndo: Bool { !undoEntries.isEmpty }
    var canRedo: Bool { !redoEntries.isEmpty }
}
