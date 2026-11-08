import SwiftUI

/// Real post-onboarding app shell. Build → Fill → Docs is the agreed build
/// order (Fill needs a real form to point at, Docs is independent) — Fill
/// and Docs are placeholders until their turn.
struct MainAppShellView: View {
    let onSignOut: () -> Void

    var body: some View {
        TabView {
            NavigationStack {
                FormsListView(onSignOut: onSignOut)
            }
            .tabItem { Label("Build", systemImage: "square.and.pencil") }

            ComingSoonView(
                title: "Fill",
                systemImage: "mic.fill",
                message: "Fill out your forms by voice — coming soon."
            )
            .tabItem { Label("Fill", systemImage: "mic.fill") }

            ComingSoonView(
                title: "Docs",
                systemImage: "doc.text.fill",
                message: "Dictate and format documents by voice — coming soon."
            )
            .tabItem { Label("Docs", systemImage: "doc.text.fill") }
        }
        .tint(Color.magicBlue)
    }
}

private struct ComingSoonView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        NavigationStack {
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
            .navigationTitle(title)
        }
    }
}

#Preview {
    MainAppShellView(onSignOut: {})
}
