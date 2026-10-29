import SwiftUI

/// Shows which backend the app talks to and, when tapped, lets a developer change it.
/// Only created in DEBUG builds (`serverName` is nil in Release, so the auth screens skip it).
struct DebugServerLabel: View {
    let serverName: String

    @State private var isEditing = false
    @State private var draft = ""
    @State private var notice: String?

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Button {
                draft = serverName
                isEditing = true
            } label: {
                Label(serverName, systemImage: "server.rack")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Server \(serverName)")
            .accessibilityHint("Debug build. Double tap to change the server address.")

            if let notice {
                Text(notice)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.primary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Tap to change")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.7))
            }
        }
        .alert("Server address (debug)", isPresented: $isEditing) {
            TextField("http://<your-mac-ip>:8080", text: $draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button("Save") { save() }
            Button("Use default", role: .destructive) {
                DebugServerOverride.clear()
                notice = "Reset. Quit and reopen the app to apply."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("For a real iPhone use your Mac's address, e.g. http://<your-mac-ip>:8080. Applies after you quit and reopen the app.")
        }
    }

    private func save() {
        guard AppConfig.parse(draft) != nil else {
            notice = "Not saved: use http://host:port"
            return
        }
        DebugServerOverride.save(draft)
        notice = "Saved. Quit and reopen the app to apply."
    }
}
