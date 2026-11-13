import SwiftUI

/// Everything that isn't Bold/Italic/Underline/Undo/Redo/Dictate/Voice
/// Edit — Heading, Font family/size, Color, Alignment, Lists — lives here
/// behind a single "Format" toolbar button instead of flattening ~16
/// controls into one always-visible scrolling row.
///
/// `formattingState` is a plain (non-Observable) class, same as the rest
/// of this feature — reactivity works the same way the main toolbar
/// already relies on: every button here also calls `applyInline`/
/// `applyBlock`, which mutate DocsEditorView's own `@State var text`,
/// forcing a fresh re-render (and re-read of `formattingState`'s current
/// values) on every tap.
struct DocsFormatSheet: View {
    let formattingState: DocFormattingState
    let pushUndo: () -> Void
    let applyInline: () -> Void
    let applyBlock: (@escaping (inout AttributedString, Range<AttributedString.Index>) -> Void) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Heading") {
                    Picker("Heading", selection: Binding(
                        get: { formattingState.headingLevel ?? 0 },
                        set: { level in
                            pushUndo()
                            formattingState.setHeading(level)
                            applyHeadingToSelection()
                        }
                    )) {
                        Text("Normal").tag(0)
                        Text("H1").tag(1)
                        Text("H2").tag(2)
                        Text("H3").tag(3)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Font") {
                    Picker("Family", selection: Binding(
                        get: { formattingState.fontFamily ?? "Georgia" },
                        set: { family in
                            pushUndo()
                            formattingState.setFontFamily(family)
                            applyInline()
                        }
                    )) {
                        ForEach(DocFormattingState.availableFontFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    Picker("Size", selection: Binding(
                        get: { formattingState.fontSize ?? 14 },
                        set: { size in
                            pushUndo()
                            formattingState.setFontSize(size)
                            applyInline()
                        }
                    )) {
                        ForEach(DocFormattingState.availableFontSizes, id: \.self) { size in
                            Text("\(Int(size))").tag(size)
                        }
                    }
                }

                Section("Color") {
                    ColorPicker(
                        "Text Color",
                        selection: Binding(
                            get: { formattingState.foregroundColor ?? .primary },
                            set: { color in
                                pushUndo()
                                formattingState.setColor(color)
                                applyInline()
                            }
                        )
                    )
                }

                Section("Alignment") {
                    HStack(spacing: 10) {
                        alignmentButton(.left, systemImage: "text.alignleft")
                        alignmentButton(.center, systemImage: "text.aligncenter")
                        alignmentButton(.right, systemImage: "text.alignright")
                    }
                }

                Section("List") {
                    HStack(spacing: 10) {
                        listButton(.bullet, systemImage: "list.bullet", label: "Bullet")
                        listButton(.numbered, systemImage: "list.number", label: "Numbered")
                    }
                }
            }
            .navigationTitle("Format")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    /// Heading is block-level like alignment/lists (web's formatBlock
    /// applies to the whole containing element), not inline like bold/
    /// italic — but the previous toolbar never actually applied it to a
    /// selection at all (only to future dictated/typed text via
    /// DocFormattingState.styledRun), a latent gap fixed here while
    /// moving this control into the sheet.
    private func applyHeadingToSelection() {
        applyBlock { text, range in
            if let level = self.formattingState.headingLevel {
                text[range].headingLevel = level
                text[range].font = DocHTMLBridge.headingFont(for: level)
            } else {
                text[range].headingLevel = nil
                text[range].font = nil
            }
        }
    }

    private func alignmentButton(_ value: AttributedString.TextAlignment, systemImage: String) -> some View {
        let isOn = formattingState.alignment == value
        return Button {
            pushUndo()
            formattingState.setAlignment(value)
            applyBlock { text, range in
                text[range][AttributeScopes.CoreTextAttributes.TextAlignmentAttribute.self] = self.formattingState.alignment
            }
        } label: {
            Image(systemName: systemImage)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .foregroundStyle(isOn ? .white : Color.magicNavy)
                .background(isOn ? Color.magicBlue : Color.magicBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func listButton(_ kind: DocsListKind, systemImage: String, label: String) -> some View {
        let isOn = formattingState.listKind == kind
        return Button {
            pushUndo()
            formattingState.setListKind(kind)
            applyBlock { text, range in
                text[range].listKind = self.formattingState.listKind
            }
        } label: {
            Label(label, systemImage: systemImage)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .foregroundStyle(isOn ? .white : Color.magicNavy)
                .background(isOn ? Color.magicBlue : Color.magicBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DocsFormatSheet(
        formattingState: DocFormattingState(),
        pushUndo: {},
        applyInline: {},
        applyBlock: { _ in }
    )
}
