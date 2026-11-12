import SwiftUI

/// Native AttributedString-backed rich text editor — no pixel canvas, no
/// UIViewRepresentable/UITextView bridging (brand-new iOS 27 SwiftUI
/// capability, confirmed via a feasibility spike before this file was
/// written). Single page per document for v1 (see DocsService's doc
/// comment) — a long document in one scrollable AttributedString is
/// already natural mobile UX, not a visible limitation.
struct DocsEditorView: View {
    let docId: Int?
    let onSaved: () -> Void

    @State private var title: String = "Untitled Document"
    @State private var text = AttributedString()
    @State private var selection = AttributedTextSelection()
    @State private var keptPageId: String?
    @State private var isLoading: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var resyncMessage: String?
    @AppStorage("ms_docs_dictation_lang") private var dictationLanguage: DocsDictationLanguage = .en

    // @State, not `let` — these are reference types needing persistent
    // identity across re-renders (same convention as AudioRecorder
    // elsewhere in this codebase).
    @State private var formattingState = DocFormattingState()
    @State private var undoStack = DocsUndoStack()
    @State private var dictationController: ContinuousDictationController?
    @State private var isDictating = false
    @State private var voiceEditController: VoiceEditController?
    @State private var isVoiceEditing = false
    @State private var dictationStatus: String?

    private let docsService = DocsService()

    init(docId: Int?, onSaved: @escaping () -> Void) {
        self.docId = docId
        self.onSaved = onSaved
        _isLoading = State(initialValue: docId != nil)
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    TextField("Document title", text: $title)
                        .font(.headline)
                        .padding()

                    Divider()
                    formattingToolbar
                    Divider()

                    TextEditor(text: $text, selection: $selection)
                        .attributedTextFormattingDefinition(DocsFormattingDefinition())
                        .disabled(isDictating || isVoiceEditing)
                        .padding(.horizontal, 4)

                    if let dictationStatus {
                        Text(dictationStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.bottom, 6)
                    }
                }
            }
        }
        .navigationTitle(docId == nil ? "New Document" : "Edit Document")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    ForEach(DocsDictationLanguage.allCases) { lang in
                        Button("\(lang.flag) \(lang.displayName)") {
                            dictationLanguage = lang
                        }
                    }
                } label: {
                    Label("\(dictationLanguage.flag) \(dictationLanguage.displayName)", systemImage: "globe")
                }
            }
        }
        .alert(
            "Couldn't save",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(
            "This document changed elsewhere",
            isPresented: Binding(get: { resyncMessage != nil }, set: { if !$0 { resyncMessage = nil } })
        ) {
            Button("Reload", role: .destructive) { Task { await loadIfNeeded(force: true) } }
            Button("Keep my version", role: .cancel) {}
        } message: {
            Text(resyncMessage ?? "A newer version of this document exists — reload to see it, or keep editing your current version.")
        }
        .task { await loadIfNeeded(force: false) }
    }

    // MARK: - Formatting toolbar

    private var formattingToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                toolbarButton(systemImage: "bold", isOn: formattingState.boldOn) {
                    undoStack.push(text)
                    formattingState.toggleBold()
                    applyCurrentFormattingToSelection()
                }
                toolbarButton(systemImage: "italic", isOn: formattingState.italicOn) {
                    undoStack.push(text)
                    formattingState.toggleItalic()
                    applyCurrentFormattingToSelection()
                }
                toolbarButton(systemImage: "underline", isOn: formattingState.underlineOn) {
                    undoStack.push(text)
                    formattingState.toggleUnderline()
                    applyCurrentFormattingToSelection()
                }

                Divider().frame(height: 32)

                ForEach([1, 2, 3], id: \.self) { level in
                    toolbarButton(text: "H\(level)", isOn: formattingState.headingLevel == level) {
                        undoStack.push(text)
                        formattingState.setHeading(level)
                    }
                }

                Divider().frame(height: 32)

                toolbarButton(systemImage: "arrow.uturn.backward", isOn: false, disabled: !undoStack.canUndo) {
                    performUndo()
                }
                toolbarButton(systemImage: "arrow.uturn.forward", isOn: false, disabled: !undoStack.canRedo) {
                    performRedo()
                }

                Spacer(minLength: 8)

                voiceControlsRow
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    /// Two explicitly-labeled buttons, not icon-only — an icon alone
    /// (even something like a plain "edit" glyph) doesn't communicate
    /// "this starts a voice recording," and web itself doesn't trust an
    /// icon to carry that meaning either: it renders literal "Dictate" /
    /// "Voice Edit" text labels next to its own mic buttons. Gold = actively
    /// listening, for both buttons — one consistent "something is recording
    /// right now" signal, with the label distinguishing which mode.
    private var voiceControlsRow: some View {
        HStack(spacing: 10) {
            labeledVoiceButton(
                systemImage: isDictating ? "mic.fill" : "mic",
                label: isDictating ? "Stop" : "Dictate",
                isActive: isDictating,
                disabled: isVoiceEditing
            ) {
                Task { await toggleDictation() }
            }

            labeledVoiceButton(
                systemImage: isVoiceEditing ? "waveform" : "wand.and.stars",
                label: isVoiceEditing ? "Stop" : "Voice Edit",
                isActive: isVoiceEditing,
                disabled: isDictating
            ) {
                Task { await toggleVoiceEdit() }
            }
        }
    }

    private func labeledVoiceButton(
        systemImage: String,
        label: String,
        isActive: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(label).font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .foregroundStyle(.white)
            .background(isActive ? Color.magicGold : Color.magicBlue, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func toolbarButton(
        systemImage: String? = nil,
        text: String? = nil,
        isOn: Bool,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                } else if let text {
                    Text(text).font(.subheadline.weight(.semibold))
                }
            }
            .frame(width: 44, height: 44)
            .foregroundStyle(isOn ? .white : Color.magicNavy)
            .background(isOn ? Color.magicBlue : Color.magicBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    /// Applies the toolbar's just-toggled formatting state to whatever is
    /// currently selected — AttributedTextSelection isn't guaranteed to be
    /// one simple contiguous range, so this goes through the selection-
    /// synchronized transform API rather than assuming a single range.
    private func applyCurrentFormattingToSelection() {
        let container = formattingState.currentContainer
        text.transformAttributes(in: &selection) { attributes in
            if let intent = container.inlinePresentationIntent {
                attributes.inlinePresentationIntent = intent
            } else {
                attributes.inlinePresentationIntent = nil
            }
            attributes.underlineStyle = container.underlineStyle
        }
    }

    private func performUndo() {
        guard let previous = undoStack.undo(current: text) else { return }
        text = previous
    }

    private func performRedo() {
        guard let next = undoStack.redo(current: text) else { return }
        text = next
    }

    // MARK: - Dictation

    private func toggleDictation() async {
        if isDictating {
            dictationController?.stop()
        } else {
            errorMessage = nil
            let controller = ContinuousDictationController(
                formattingState: formattingState,
                language: { dictationLanguage.rawValue }
            )
            controller.onChunkApplied = { chunk in
                text += chunk
            }
            controller.onUndoRequested = { performUndo() }
            controller.onRedoRequested = { performRedo() }
            controller.onHalted = { reason in
                isDictating = false
                dictationStatus = nil
                switch reason {
                case .userStopped:
                    break
                case .planLimitReached(let message):
                    errorMessage = message
                case .error(let message):
                    errorMessage = message
                }
            }
            dictationController = controller
            undoStack.push(text)
            let started = await controller.start()
            if started {
                isDictating = true
                dictationStatus = "Listening — tap the mic again to stop."
            } else {
                errorMessage = "Microphone access is off — enable it in Settings to dictate."
            }
        }
    }

    // MARK: - Voice Edit

    /// Speak an instruction about the document ("bold the word important",
    /// "delete the second paragraph") rather than dictating content — a
    /// one-shot recording, not a chunked/open-span session like dictation.
    private func toggleVoiceEdit() async {
        if isVoiceEditing {
            guard let controller = voiceEditController else { return }
            dictationStatus = "Working…"
            let outcome = await controller.finish(documentText: text)
            isVoiceEditing = false
            dictationStatus = nil
            switch outcome {
            case .undo:
                performUndo()
            case .redo:
                performRedo()
            case .applied(let operations):
                undoStack.push(text)
                let appliedCount = DocVoiceEditExecutor.apply(operations, to: &text)
                if appliedCount == 0 {
                    errorMessage = "Couldn't find that text to edit."
                }
            case .noMatch:
                errorMessage = "Didn't catch an edit instruction — try again."
            case .upgradeRequired(let message):
                errorMessage = message
            case .error(let message):
                errorMessage = message
            }
        } else {
            errorMessage = nil
            let controller = VoiceEditController(language: { dictationLanguage.rawValue })
            voiceEditController = controller
            let started = await controller.start()
            if started {
                isVoiceEditing = true
                dictationStatus = "Listening for your edit instruction — tap again to stop."
            } else {
                errorMessage = "Microphone access is off — enable it in Settings to use Voice Edit."
            }
        }
    }

    // MARK: - Load / Save

    private func loadIfNeeded(force: Bool) async {
        guard let docId else {
            title = "Untitled Document"
            text = AttributedString()
            keptPageId = nil
            isLoading = false
            return
        }
        guard force || isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await docsService.load(docId: docId)
            title = result.title
            text = result.text
            keptPageId = result.keptPageId
        } catch let DocsServiceError.loadFailed(message) {
            errorMessage = message
        } catch let APIError.server(_, message) {
            errorMessage = message ?? "Something went wrong — please try again."
        } catch APIError.unauthorized {
            errorMessage = "Not signed in — please log in again."
        } catch {
            errorMessage = "Couldn't reach the server — check your connection and try again."
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let result = try await docsService.save(docId: docId, title: title, text: text, keptPageId: keptPageId)
            keptPageId = keptPageId ?? String(result.docId)
            if result.resyncNeeded {
                resyncMessage = "This document changed elsewhere since you opened it."
            }
            onSaved()
        } catch let DocsServiceError.saveFailed(message) {
            errorMessage = message
        } catch let APIError.server(_, message) {
            errorMessage = message ?? "Something went wrong — please try again."
        } catch APIError.unauthorized {
            errorMessage = "Not signed in — please log in again."
        } catch {
            errorMessage = "Couldn't reach the server — check your connection and try again."
        }
    }
}

#Preview {
    NavigationStack {
        DocsEditorView(docId: nil, onSaved: {})
    }
}
