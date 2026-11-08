import SwiftUI

/// No pixel canvas — fields reflow into a native vertical list (deliberate
/// decision: voice-fill and AI-build are both position-agnostic, and a
/// freeform drag canvas doesn't work well on a 6" touch screen). Real
/// position/dimensions get synthesized by FormLayoutEngine at save time —
/// see FormsService.save.
struct FormEditorView: View {
    let formId: Int?
    let onSaved: () -> Void

    @State private var form: MSFForm = .blank(title: "")
    @State private var title: String = "Untitled Form"
    @State private var fields: [MSFField] = []
    @State private var isLoading: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var upgradeMessage: String?
    @State private var showAddFieldSheet = false
    @State private var editingField: MSFField?

    private let formsService = FormsService()

    // Fields per displayed "page" before the editor switches from one plain
    // list to labeled sections — purely a presentation-time chunking of the
    // same flat array (FormLayoutEngine's save-time pagination is unrelated
    // and unaffected). Tunable with no data migration.
    private let pageSize = 8

    init(formId: Int?, onSaved: @escaping () -> Void) {
        self.formId = formId
        self.onSaved = onSaved
        _isLoading = State(initialValue: formId != nil)
    }

    // v1 subset — signature (needs a sig pad) and image (needs a picker)
    // are deliberately deferred; any other/unknown type renders disabled.
    private let editableTypes: [(type: String, label: String, icon: String)] = [
        ("text", "Text", "text.cursor"),
        ("textarea", "Text Area", "text.alignleft"),
        ("checkbox", "Checkbox", "checkmark.square"),
        ("dropdown", "Dropdown", "chevron.down.square"),
        ("date", "Date", "calendar"),
        ("textblock", "Text Block", "textformat"),
    ]

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        TextField("Form title", text: $title)
                            .font(.headline)
                    }
                    // Overarching, form-level context — distinct from each
                    // field's own "Notes" below. Mirrors the web builder's
                    // "AI Context" input (form_ai_context), which Claude
                    // reads alongside every field's own context when
                    // mapping a voice transcript — same mechanism, just two
                    // scopes (whole-form vs. per-field).
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AI Context")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("What this form is for, e.g. \"Spouse's passport renewal\"", text: $form.formAiContext, axis: .vertical)
                        }
                    }
                    if fields.count > pageSize {
                        // Surfaced pagination: labeled sections over the same
                        // flat array, once there are enough fields that one
                        // undifferentiated list stops being scannable. Each
                        // section's onMove/onDelete offsets into the full
                        // array — within-page reorder works correctly;
                        // dragging a row across a page boundary isn't
                        // supported (same limitation genuine swipeable pages
                        // would have — you can't drag between pages either).
                        ForEach(Array(pagedFields.enumerated()), id: \.offset) { pageIndex, pageFields in
                            Section("Page \(pageIndex + 1)") {
                                fieldRows(pageFields, pageBase: pageIndex * pageSize)
                            }
                        }
                        Section {
                            addFieldButton
                        }
                    } else {
                        Section("Fields") {
                            if fields.isEmpty {
                                Text("No fields yet — tap \"Add Field\" below.")
                                    .foregroundStyle(.secondary)
                            }
                            fieldRows(fields, pageBase: 0)
                            addFieldButton
                        }
                    }
                }
            }
        }
        .navigationTitle(formId == nil ? "New Form" : "Edit Form")
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
                EditButton()
            }
        }
        .sheet(isPresented: $showAddFieldSheet) {
            BatchAddFieldSheet(types: editableTypes) { items in
                var counter = FormLayoutEngine.nextFieldCounter(in: fields)
                for item in items {
                    fields.append(FormLayoutEngine.makeField(type: item.type, label: item.label, counter: counter))
                    counter += 1
                }
            }
        }
        .sheet(item: $editingField) { field in
            FieldDetailSheet(field: field) { updated in
                if let index = fields.firstIndex(where: { $0.id == updated.id }) {
                    fields[index] = updated
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
            "Form limit reached",
            isPresented: Binding(get: { upgradeMessage != nil }, set: { if !$0 { upgradeMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(upgradeMessage ?? "")
        }
        .task { await loadIfNeeded() }
    }

    private var pagedFields: [[MSFField]] {
        stride(from: 0, to: fields.count, by: pageSize).map { start in
            Array(fields[start..<min(start + pageSize, fields.count)])
        }
    }

    private var addFieldButton: some View {
        // A normal list row, not a toolbar item — a .bottomBar toolbar item
        // can get crowded out when this view is pushed inside a tab's
        // NavigationStack (the tab bar and a custom bottom toolbar compete
        // for the same screen edge), so this stays reliably visible and
        // scrolls with the content instead. Generous padding keeps it
        // comfortably above the 44pt touch-target minimum.
        Button {
            showAddFieldSheet = true
        } label: {
            Label("Add Field", systemImage: "plus.circle.fill")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func fieldRows(_ pageFields: [MSFField], pageBase: Int) -> some View {
        ForEach(pageFields) { field in
            fieldRow(field)
        }
        .onMove { indices, newOffset in
            fields.move(
                fromOffsets: IndexSet(indices.map { $0 + pageBase }),
                toOffset: newOffset + pageBase
            )
        }
        .onDelete { indexSet in
            fields.remove(atOffsets: IndexSet(indexSet.map { $0 + pageBase }))
        }
    }

    private func icon(for type: String) -> String {
        editableTypes.first(where: { $0.type == type })?.icon ?? "questionmark.square"
    }

    private func displayName(for type: String) -> String {
        switch type {
        case "signature": "Signature"
        case "image": "Image"
        default: type.capitalized
        }
    }

    private func fieldRow(_ field: MSFField) -> some View {
        let supported = editableTypes.contains { $0.type == field.type }
        return Button {
            if supported { editingField = field }
        } label: {
            HStack {
                Image(systemName: supported ? icon(for: field.type) : "lock.fill")
                    .foregroundStyle(supported ? Color.magicBlue : .secondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.label.isEmpty ? "Untitled field" : field.label)
                        .foregroundStyle(supported ? Color.magicNavy : .secondary)
                    if !supported {
                        Text("\(displayName(for: field.type)) — edit on web")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if supported {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // Generous vertical padding keeps every row comfortably above
            // the 44pt Fitts's-Law touch-target minimum.
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .disabled(!supported)
    }

    private func loadIfNeeded() async {
        guard let formId else {
            form = .blank(title: "")
            title = "Untitled Form"
            fields = []
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await formsService.load(formId: formId)
            form = result.form
            title = result.title
            fields = result.form.pages.flatMap(\.fields)
        } catch let FormsServiceError.loadFailed(message) {
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
            _ = try await formsService.save(title: title, fields: fields, baseForm: form, formId: formId)
            onSaved()
        } catch let FormsServiceError.limitReached(message, _) {
            upgradeMessage = message
        } catch let FormsServiceError.saveFailed(message) {
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

/// Two ways to add fields, both reachable from one sheet: a quick-add list
/// (fastest path for several similar fields at once) and a multi-select
/// type grid (for mixed-type batches the quick-add list can't express).
/// Batches, not one-at-a-time — the old single-type-single-label flow made
/// building a real form a slow, repetitive modal-reopening loop.
private struct BatchAddFieldSheet: View {
    let types: [(type: String, label: String, icon: String)]
    let onAdd: ([(type: String, label: String)]) -> Void

    fileprivate enum Mode: String, CaseIterable {
        case quick = "Quick Add"
        case grid = "Choose Types"
    }

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    @State private var quickText = ""
    @State private var selectedTypes: [String] = []
    @State private var labelsByType: [String: String] = [:]
    @State private var showLabelEntry = false

    fileprivate init(
        types: [(type: String, label: String, icon: String)],
        initialMode: Mode = .quick,
        onAdd: @escaping ([(type: String, label: String)]) -> Void
    ) {
        self.types = types
        self.onAdd = onAdd
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: mode) { showLabelEntry = false }

                switch mode {
                case .quick:
                    quickAddView
                case .grid:
                    if showLabelEntry {
                        labelEntryView
                    } else {
                        typeGridView
                    }
                }
            }
            .padding(.top)
            .navigationTitle("Add Fields")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(showLabelEntry ? "Back" : "Cancel") {
                        if showLabelEntry {
                            showLabelEntry = false
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    confirmButton
                }
            }
        }
    }

    private var quickAddView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("One field per line")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            TextEditor(text: $quickText)
                .frame(minHeight: 200)
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            Spacer()
        }
    }

    private var typeGridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 140), spacing: 16)], spacing: 16) {
                ForEach(types, id: \.type) { entry in
                    let isSelected = selectedTypes.contains(entry.type)
                    Button {
                        if isSelected {
                            selectedTypes.removeAll { $0 == entry.type }
                        } else {
                            selectedTypes.append(entry.type)
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: entry.icon)
                                .font(.system(size: 28))
                            Text(entry.label)
                                .font(.caption.weight(.medium))
                                .multilineTextAlignment(.center)
                        }
                        // >=90x90pt — large, well-spaced tap targets so
                        // selecting several types in a row is comfortable,
                        // not fiddly.
                        .frame(minWidth: 90, minHeight: 90)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(isSelected ? .white : Color.magicNavy)
                        .background(
                            isSelected ? Color.magicBlue : Color.magicBlue.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private var labelEntryView: some View {
        Form {
            ForEach(types.filter { selectedTypes.contains($0.type) }, id: \.type) { entry in
                TextField(entry.label, text: Binding(
                    get: { labelsByType[entry.type] ?? entry.label },
                    set: { labelsByType[entry.type] = $0 }
                ))
            }
        }
    }

    @ViewBuilder
    private var confirmButton: some View {
        switch mode {
        case .quick:
            Button("Add") {
                let items = quickText
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .map { (type: "text", label: $0) }
                guard !items.isEmpty else { return }
                onAdd(items)
                dismiss()
            }
            .disabled(quickText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        case .grid:
            if showLabelEntry {
                Button("Add") {
                    let items = types
                        .filter { selectedTypes.contains($0.type) }
                        .map { entry in (type: entry.type, label: labelsByType[entry.type] ?? entry.label) }
                    onAdd(items)
                    dismiss()
                }
            } else {
                Button("Next") { showLabelEntry = true }
                    .disabled(selectedTypes.isEmpty)
            }
        }
    }
}

private struct FieldDetailSheet: View {
    let field: MSFField
    let onSave: (MSFField) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var edited: MSFField
    @State private var newOption = ""

    init(field: MSFField, onSave: @escaping (MSFField) -> Void) {
        self.field = field
        self.onSave = onSave
        _edited = State(initialValue: field)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Field") {
                    TextField("Label", text: $edited.label)
                    TextField("Placeholder", text: Binding(
                        get: { edited.placeholder },
                        set: { edited.placeholder = $0 }
                    ))
                    Toggle("Required", isOn: $edited.required)
                }
                // Per-field AI context ("Notes" on web) — distinct from the
                // whole-form AI Context above. Gets interpolated directly
                // into this field's line in the map_fields prompt, which is
                // how Claude tells apart two similarly-labeled fields (e.g.
                // two "Name" fields, one per applicant) when voice-filling.
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI Context")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Extra context for AI, e.g. \"Spouse's legal name\"", text: $edited.aiContext, axis: .vertical)
                    }
                }
                if edited.type == "dropdown" {
                    Section("Options") {
                        ForEach(edited.options ?? [], id: \.self) { option in
                            Text(option)
                        }
                        .onDelete { indexSet in
                            edited.options?.remove(atOffsets: indexSet)
                        }
                        HStack {
                            TextField("New option", text: $newOption)
                            Button("Add") {
                                let trimmed = newOption.trimmingCharacters(in: .whitespaces)
                                guard !trimmed.isEmpty else { return }
                                edited.options = (edited.options ?? []) + [trimmed]
                                newOption = ""
                            }
                            .disabled(newOption.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }
            .navigationTitle("Edit Field")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(edited)
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        FormEditorView(formId: nil, onSaved: {})
    }
}

#Preview("Field Detail") {
    NavigationStack {
        FieldDetailSheet(
            field: FormLayoutEngine.makeField(type: "text", label: "Name", counter: 1),
            onSave: { _ in }
        )
    }
}

private let previewFieldTypes: [(type: String, label: String, icon: String)] = [
    ("text", "Text", "text.cursor"),
    ("textarea", "Text Area", "text.alignleft"),
    ("checkbox", "Checkbox", "checkmark.square"),
    ("dropdown", "Dropdown", "chevron.down.square"),
    ("date", "Date", "calendar"),
    ("textblock", "Text Block", "textformat"),
]

#Preview("Batch Add — Quick") {
    BatchAddFieldSheet(types: previewFieldTypes, onAdd: { _ in })
}

#Preview("Batch Add — Grid") {
    BatchAddFieldSheet(types: previewFieldTypes, initialMode: .grid, onAdd: { _ in })
}
