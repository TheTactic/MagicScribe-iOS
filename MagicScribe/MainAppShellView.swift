import SwiftUI

/// Real post-onboarding app shell. iOS v1 ships Docs (voice dictation) only
/// — Form Building/Filling are on the web at magicscribe.tech. No TabView
/// for a single screen; FormsListView/FormEditorView/FormsService etc. stay
/// in the repo untouched, just no longer referenced here.
struct MainAppShellView: View {
    let onSignOut: () -> Void

    var body: some View {
        NavigationStack {
            ComingSoonView(
                title: "Docs",
                systemImage: "doc.text.fill",
                message: "Dictate and format documents by voice — coming soon."
            )
            .navigationTitle("Docs")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Sign Out", role: .destructive, action: onSignOut)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}

private struct ComingSoonView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(Color.magicBlue.opacity(0.6))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    MainAppShellView(onSignOut: {})
}
