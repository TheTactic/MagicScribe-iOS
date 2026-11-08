import SwiftUI

/// Filler Pro's Build demo: real drag-and-drop with two objects (a Label
/// chip and a Text Field chip) onto two specific target zones, instead of
/// the old single-tap scripted version. No network call — manual building
/// genuinely doesn't need one.
struct DemoFormBuildManualView: View {
    let coordinator: OnboardingCoordinator

    private enum ChipKind: String {
        case label = "Label"
        case textField = "Text Field"

        var systemImage: String {
            switch self {
            case .label: "textformat"
            case .textField: "text.cursor"
            }
        }
    }

    @State private var labelPlaced = false
    @State private var textFieldPlaced = false
    @State private var labelDragOffset: CGSize = .zero
    @State private var textFieldDragOffset: CGSize = .zero

    // Canvas-relative target centers — label sits above the text field,
    // forming a simple "Name" field layout.
    private let labelTarget = CGPoint(x: 70, y: 36)
    private let textFieldTarget = CGPoint(x: 70, y: 84)
    private let snapTolerance: CGFloat = 40

    private var bothPlaced: Bool { labelPlaced && textFieldPlaced }

    var body: some View {
        VStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Try building a form")
                    .font(.title.bold())
                    .foregroundStyle(Color.magicNavy)
                Text(bothPlaced ? "Nice work!" : "Drag the Label and Text Field onto the canvas.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Named coordinate space wraps canvas + chips together, with the
            // canvas as the first child, so drag locations line up with the
            // same origin as the target points and the placed-field overlay.
            VStack(spacing: 16) {
                canvas

                HStack(spacing: 16) {
                    if !labelPlaced {
                        chip(.label, placed: $labelPlaced, offset: $labelDragOffset, target: labelTarget)
                    }
                    if !textFieldPlaced {
                        chip(.textField, placed: $textFieldPlaced, offset: $textFieldDragOffset, target: textFieldTarget)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.spring(response: 0.35), value: labelPlaced)
                .animation(.spring(response: 0.35), value: textFieldPlaced)
            }
            .coordinateSpace(name: "canvas")

            Spacer()

            if bothPlaced {
                Button {
                    coordinator.completeDemo(.completed)
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.magicBlue)
            } else {
                Button("Skip this demo") {
                    coordinator.completeDemo(.skipped)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var canvas: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.magicNavy.opacity(0.2), lineWidth: 2)
            .frame(height: 160)
            .overlay(alignment: .topLeading) {
                if !labelPlaced && !textFieldPlaced {
                    Text("Your form canvas")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if labelPlaced {
                    placedField(.label).position(labelTarget)
                }
                if textFieldPlaced {
                    placedField(.textField).position(CGPoint(x: textFieldTarget.x, y: textFieldTarget.y + 6))
                }
            }
    }

    private func placedField(_ kind: ChipKind) -> some View {
        HStack(spacing: 6) {
            Image(systemName: kind.systemImage)
                .foregroundStyle(Color.magicBlue)
            Text(kind.rawValue)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.magicNavy)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .transition(.scale.combined(with: .opacity))
    }

    private func chip(_ kind: ChipKind, placed: Binding<Bool>, offset: Binding<CGSize>, target: CGPoint) -> some View {
        Label(kind.rawValue, systemImage: kind.systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.magicNavy)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.magicGold.opacity(0.25), in: Capsule())
            .overlay(Capsule().stroke(Color.magicGold, lineWidth: 1.5))
            .offset(offset.wrappedValue)
            .gesture(
                DragGesture(coordinateSpace: .named("canvas"))
                    .onChanged { value in
                        offset.wrappedValue = value.translation
                    }
                    .onEnded { value in
                        let dropPoint = value.location
                        let distance = hypot(dropPoint.x - target.x, dropPoint.y - target.y)
                        if distance <= snapTolerance {
                            placed.wrappedValue = true
                        }
                        offset.wrappedValue = .zero
                    }
            )
    }
}

#Preview {
    DemoFormBuildManualView(coordinator: OnboardingCoordinator())
}
