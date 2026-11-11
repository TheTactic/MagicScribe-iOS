import SwiftUI

/// Real post-onboarding app shell. iOS v1 ships Docs (voice dictation) only
/// — Form Building/Filling are on the web at magicscribe.tech. No TabView
/// for a single screen; FormsListView/FormEditorView/FormsService etc. stay
/// in the repo untouched, just no longer referenced here.
struct MainAppShellView: View {
    let onSignOut: () -> Void

    var body: some View {
        DocsListView(onSignOut: onSignOut)
    }
}

#Preview {
    MainAppShellView(onSignOut: {})
}
