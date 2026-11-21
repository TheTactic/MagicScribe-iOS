import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Mirrors web's `#save-status` indicator (`.saving`/`.saved`/`.error`) —
/// `.idle` is the one additional case needed before any save has happened.
enum SaveStatus {
    case idle, saving, saved, failed
}

/// Native AttributedString-backed rich text editor — no pixel canvas, no
/// UIViewRepresentable/UITextView bridging (brand-new iOS 27 SwiftUI
/// capability, confirmed via a feasibility spike before this file was
/// written). Single page per document for v1 (see DocsService's doc
/// comment) — a long document in one scrollable AttributedString is
/// already natural mobile UX, not a visible limitation.
struct DocsEditorView: View {
    let docId: Int?
    let onSaved: () -> Void
    /// Default false (set in init) preserves the real Docs tab exactly as
    /// before — true only for onboarding's "try it" step, where this
    /// editor doubles as the user's actual first saved document rather
    /// than a disposable demo. Gates: the sample-dictation hint card,
    /// "Save & Continue" copy, star confetti on save, and the Voice Edit
    /// plan-gate bypass.
    let isOnboardingDemo: Bool
    /// Only meaningful (and shown) when isOnboardingDemo is true — the
    /// real Docs tab has no concept of "skip," only onboarding does.
    let onSkipped: (() -> Void)?

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
    @State private var isShowingFormatSheet = false
    @State private var showSaveConfetti = false

    // MARK: Autosave — debounce 1.2s after the last edit, matching web's
    // hardcoded setTimeout(persistDoc, 1200) exactly.
    @State private var autosaveTask: Task<Void, Never>?
    /// False until the initial load (or new-document setup) completes —
    /// otherwise `loadIfNeeded`'s own `text =`/`title =` assignment would
    /// be misread as a user edit and schedule a pointless immediate save.
    @State private var isAutosaveArmed = false
    @State private var saveStatus: SaveStatus = .idle

    // MARK: Image gallery — a separate, non-inline collection (see
    // DocHTMLBridge.extractImages/appendImages) rather than true inline
    // placement, which this editor's AttributedString model has no
    // attribute to support.
    @State private var images: [DocImage] = []
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingImage = false
    @State private var viewingImage: DocImage?

    private let docsService = DocsService()

    init(
        docId: Int?,
        onSaved: @escaping () -> Void,
        isOnboardingDemo: Bool = false,
        onSkipped: (() -> Void)? = nil
    ) {
        self.docId = docId
        self.onSaved = onSaved
        self.isOnboardingDemo = isOnboardingDemo
        self.onSkipped = onSkipped
        _isLoading = State(initialValue: docId != nil)
    }

    // Split from `editorBody` below — chaining every modifier onto one
    // expression (toolbar + 2 alerts + sheet + 4 onChange + task) made the
    // Swift type-checker time out in Preview's slower compile mode. Two
    // independently-inferred chains, not one giant one.
    var body: some View {
        editorBody
            .alert(
                "Couldn't save",
                isPresented: isErrorAlertPresented
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert(
                "This document changed elsewhere",
                isPresented: isResyncAlertPresented
            ) {
                Button("Reload", role: .destructive) { Task { await loadIfNeeded(force: true) } }
                Button("Keep my version", role: .cancel) {}
            } message: {
                Text(resyncMessage ?? "A newer version of this document exists — reload to see it, or keep editing your current version.")
            }
    }

    private var editorBody: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    TextField("Document title", text: $title)
                        .font(.headline)
                        .padding()

                    if let saveStatusCaption {
                        Text(saveStatusCaption)
                            .font(.caption)
                            .foregroundStyle(saveStatus == .failed ? .red : .secondary)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                    }

                    imageGalleryStrip

                    // Disappears the moment there's real content — a hint,
                    // not a tutorial overlay that has to be dismissed.
                    if isOnboardingDemo && text.characters.isEmpty {
                        onboardingHintCard
                    }

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
        .overlay {
            if showSaveConfetti {
                ConfettiView(colors: [.magicGold, .magicBlue], symbol: "star.fill")
            }
        }
        .navigationTitle(docId == nil ? "New Document" : "Edit Document")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if isOnboardingDemo, let onSkipped {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip for now", action: onSkipped)
                        .font(.footnote)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if isSaving {
                    ProgressView()
                        .accessibilityLabel("Saving")
                } else {
                    Button(isOnboardingDemo ? "Save & Continue" : "Save") { Task { await save() } }
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
        .sheet(item: $viewingImage) { image in
            imageViewerSheet(image)
        }
        .onChange(of: text) { scheduleAutosave() }
        .onChange(of: title) { scheduleAutosave() }
        .onChange(of: images) { scheduleAutosave() }
        .onChange(of: selectedPhotoItem) {
            guard let item = selectedPhotoItem else { return }
            Task { await uploadPickedPhoto(item) }
        }
        .task { await loadIfNeeded(force: false) }
    }

    private var isErrorAlertPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var isResyncAlertPresented: Binding<Bool> {
        Binding(get: { resyncMessage != nil }, set: { if !$0 { resyncMessage = nil } })
    }

    private var saveStatusCaption: String? {
        switch saveStatus {
        case .idle: nil
        case .saving: "Saving…"
        case .saved: "Saved"
        case .failed: "Not saved"
        }
    }

    // MARK: - Onboarding

    private var onboardingHintCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Need something to say?")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.magicNavy)
            Text("Try: \"Magic heading one. My First Document. Magic heading off. This is my first time using MagicScribe — pretty cool, right?\"")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.magicBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Autosave

    /// `loadIfNeeded`'s own `text =`/`title =`/`images =` assignments
    /// trigger `.onChange(of:)`'s callback on SwiftUI's own next update
    /// pass — confirmed via live testing to run *sooner* than a
    /// `DispatchQueue.main.async`-deferred block, so that deferral alone
    /// doesn't help: setting `isAutosaveArmed = true` there still lands
    /// before the load-triggered onChange fires, scheduling a spurious
    /// autosave of the just-loaded, unmodified content. A short real delay
    /// — far longer than a single SwiftUI update pass (tied to the
    /// ~16ms display refresh), imperceptible to a human — is what
    /// actually guarantees landing after it.
    private func armAutosave() {
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            isAutosaveArmed = true
        }
    }

    /// Cancel-and-restart idiom, same as `ContinuousDictationController
    /// .refineWithTimeout`'s timeout racing — not a new pattern. Fires
    /// 1.2s after the *last* call, matching web's `scheduleSave()` exactly.
    private func scheduleAutosave() {
        guard isAutosaveArmed else { return }
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            await save(isAutosave: true)
        }
    }

    // MARK: - Image gallery

    private var imageGalleryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Group {
                        if isUploadingImage {
                            ProgressView()
                        } else {
                            Image(systemName: "plus")
                        }
                    }
                    .frame(width: 60, height: 60)
                    .foregroundStyle(Color.magicNavy)
                    .background(Color.magicBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
                .disabled(isUploadingImage)
                .accessibilityLabel(isUploadingImage ? "Uploading photo" : "Add photo")

                ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                    Button { viewingImage = image } label: {
                        AsyncImage(url: URL(string: image.url)) { phase in
                            if let loaded = phase.image {
                                loaded.resizable().scaledToFill()
                            } else {
                                Color.secondary.opacity(0.15)
                            }
                        }
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Attached image \(index + 1) of \(images.count)")
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private func imageViewerSheet(_ image: DocImage) -> some View {
        NavigationStack {
            AsyncImage(url: URL(string: image.url)) { phase in
                if let loaded = phase.image {
                    loaded.resizable().scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .accessibilityLabel("Document image")
            .navigationTitle("Image")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { viewingImage = nil }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Remove", role: .destructive) {
                        images.removeAll { $0.id == image.id }
                        viewingImage = nil
                    }
                }
            }
        }
    }

    /// Uploads to the same api/upload.php web's Docs editor uses, then
    /// attaches the result to the gallery — never positioned inline (see
    /// DocHTMLBridge's doc comments for why). `item.supportedContentTypes`
    /// gives the real UTType rather than assuming JPEG; upload.php itself
    /// re-sniffs the actual bytes server-side regardless, but a correctly
    /// declared Content-Type/filename extension is still the honest thing
    /// to send.
    private func uploadPickedPhoto(_ item: PhotosPickerItem) async {
        selectedPhotoItem = nil
        isUploadingImage = true
        defer { isUploadingImage = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let utType = item.supportedContentTypes.first
            let mimeType = utType?.preferredMIMEType ?? "image/jpeg"
            let ext = utType?.preferredFilenameExtension ?? "jpg"
            let uploaded = try await docsService.uploadImage(data: data, fileName: "photo.\(ext)", mimeType: mimeType)
            images.append(uploaded)
        } catch {
            errorMessage = "Couldn't upload that image — try again."
        }
    }

    // MARK: - Formatting toolbar

    /// Two rows, not one — Dictate/Voice Edit are this app's whole reason
    /// for existing, so they get their own always-visible, never-clipped
    /// row rather than competing for width with the formatting icons
    /// inside a horizontal scroll strip (where they were getting pushed
    /// off-screen). Bold/Italic/Underline/Undo/Redo stay as quick,
    /// single-tap icons rather than moving into the Format sheet — they're
    /// the highest-frequency actions in the editor (Undo especially, as
    /// the main way to recover from a bad dictation/Voice Edit result),
    /// and burying the most-used actions behind a sheet tap would be a
    /// net UX loss even though it would "consolidate" the icon count.
    private var formattingToolbar: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    toolbarButton(systemImage: "bold", label: "Bold", isOn: formattingState.boldOn) {
                        undoStack.push(text)
                        formattingState.toggleBold()
                        applyCurrentFormattingToSelection()
                    }
                    toolbarButton(systemImage: "italic", label: "Italic", isOn: formattingState.italicOn) {
                        undoStack.push(text)
                        formattingState.toggleItalic()
                        applyCurrentFormattingToSelection()
                    }
                    toolbarButton(systemImage: "underline", label: "Underline", isOn: formattingState.underlineOn) {
                        undoStack.push(text)
                        formattingState.toggleUnderline()
                        applyCurrentFormattingToSelection()
                    }

                    Divider().frame(height: 32)

                    toolbarButton(systemImage: "arrow.uturn.backward", label: "Undo", isOn: false, disabled: !undoStack.canUndo) {
                        performUndo()
                    }
                    toolbarButton(systemImage: "arrow.uturn.forward", label: "Redo", isOn: false, disabled: !undoStack.canRedo) {
                        performRedo()
                    }

                    Divider().frame(height: 32)

                    // Heading/font family+size/color/alignment/lists all
                    // live in one sheet behind this button instead of
                    // flattening ~16 controls into this row.
                    toolbarButton(systemImage: "textformat", label: "Format", isOn: false) {
                        isShowingFormatSheet = true
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, 6)

            voiceControlsRow
                .padding(.horizontal)
                .padding(.bottom, 6)
        }
        .sheet(isPresented: $isShowingFormatSheet) {
            DocsFormatSheet(
                formattingState: formattingState,
                pushUndo: { undoStack.push(text) },
                applyInline: applyCurrentFormattingToSelection,
                applyBlock: applyBlockAttributeToSelection
            )
            .presentationDetents([.medium, .large])
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
            .frame(maxWidth: .infinity)
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
        label: String,
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
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    /// Applies the toolbar's just-toggled formatting state to whatever is
    /// currently selected — AttributedTextSelection isn't guaranteed to be
    /// one simple contiguous range, so this goes through the selection-
    /// synchronized transform API rather than assuming a single range.
    /// Inline-level only (bold/italic/underline/color/font-family/size) —
    /// block-level attributes (heading/alignment/lists) go through
    /// applyBlockAttributeToSelection instead.
    private func applyCurrentFormattingToSelection() {
        let container = formattingState.currentContainer
        text.transformAttributes(in: &selection) { attributes in
            if let intent = container.inlinePresentationIntent {
                attributes.inlinePresentationIntent = intent
            } else {
                attributes.inlinePresentationIntent = nil
            }
            attributes.underlineStyle = container.underlineStyle
            // Unlike bold/underline, there's no "clear color/font" toggle
            // in this UI — only apply when the toolbar actually has one
            // set, otherwise toggling Bold on a colored/custom-font
            // selection would silently wipe that override out.
            if let color = container.foregroundColor { attributes.foregroundColor = color }
            if let family = container.fontFamily { attributes.fontFamily = family }
            if let sizePx = container.fontSizePx { attributes.fontSizePx = sizePx }
            if let font = container.font { attributes.font = font }
        }
    }

    /// Alignment/heading/list-kind are block-level — unlike bold/italic/
    /// underline, web's own execCommand('justifyLeft')/formatBlock apply
    /// to the WHOLE containing block, not a substring, and a list item is
    /// always a whole paragraph. Expands to every paragraph the selection
    /// touches (reusing DocVoiceEditExecutor.paragraphRanges(in:) rather
    /// than re-deriving paragraph boundaries a third time) and applies
    /// `mutate` to each.
    private func applyBlockAttributeToSelection(_ mutate: (inout AttributedString, Range<AttributedString.Index>) -> Void) {
        var selectedRanges: [Range<AttributedString.Index>] = []
        switch selection.indices(in: text) {
        case .insertionPoint(let index):
            selectedRanges = [index..<index]
        case .ranges(let rangeSet):
            selectedRanges = Array(rangeSet.ranges)
        @unknown default:
            break
        }
        guard !selectedRanges.isEmpty else { return }

        for paragraph in DocVoiceEditExecutor.paragraphRanges(in: text) {
            let overlaps = selectedRanges.contains {
                $0.lowerBound <= paragraph.upperBound && $0.upperBound >= paragraph.lowerBound
            }
            if overlaps {
                mutate(&text, paragraph)
            }
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
                demoContext: isOnboardingDemo ? "ios_onboarding_demo_docs" : nil,
                language: { dictationLanguage.rawValue }
            )
            controller.onChunkApplied = { chunk in
                text += chunk
            }
            controller.onPreviousChunkCorrected = { old, new in
                // Last occurrence, not first — matches web's lastIndexOf,
                // since the same phrase could coincidentally appear
                // earlier in the document and correcting that instead
                // would be a real (if rare) correctness bug.
                if let range = text.range(of: old, options: [.backwards]) {
                    text.replaceSubrange(range, with: AttributedString(new))
                }
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
            let controller = VoiceEditController(
                context: isOnboardingDemo ? "ios_onboarding_demo_docs" : nil,
                language: { dictationLanguage.rawValue }
            )
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
            images = []
            isLoading = false
            armAutosave()
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
            images = result.images
            armAutosave()
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

    /// `isAutosave` gates everything that would otherwise be disruptive
    /// mid-typing: the blocking "Couldn't save"/"changed elsewhere" alerts
    /// (web's autosave equivalent is silent — only the status caption
    /// changes) and `onSaved()` itself, which for the onboarding flow
    /// advances to the next step entirely — firing that from a background
    /// autosave would sweep the user out of the editor just for pausing
    /// while typing.
    private func save(isAutosave: Bool = false) async {
        saveStatus = .saving
        if !isAutosave { isSaving = true }
        defer { if !isAutosave { isSaving = false } }
        do {
            let result = try await docsService.save(
                docId: docId, title: title, text: text, keptPageId: keptPageId, images: images,
                context: isOnboardingDemo ? "ios_onboarding_demo_docs" : nil
            )
            keptPageId = keptPageId ?? String(result.docId)
            saveStatus = .saved
            if result.resyncNeeded && !isAutosave {
                resyncMessage = "This document changed elsewhere since you opened it."
            }
            guard !isAutosave else { return }
            if isOnboardingDemo {
                showSaveConfetti = true
                try? await Task.sleep(for: .seconds(1.2))
            }
            onSaved()
        } catch let DocsServiceError.saveFailed(message) {
            saveStatus = .failed
            if !isAutosave { errorMessage = message }
        } catch let APIError.server(_, message) {
            saveStatus = .failed
            if !isAutosave { errorMessage = message ?? "Something went wrong — please try again." }
        } catch APIError.unauthorized {
            saveStatus = .failed
            if !isAutosave { errorMessage = "Not signed in — please log in again." }
        } catch {
            saveStatus = .failed
            if !isAutosave { errorMessage = "Couldn't reach the server — check your connection and try again." }
        }
    }
}

#Preview {
    NavigationStack {
        DocsEditorView(docId: nil, onSaved: {})
    }
}
