import SwiftUI

struct ProfileView: View {
    let user: AuthUser
    let environmentName: String?
    let onLogout: () async -> Void

    @State private var isConfirmingLogout = false
    @State private var isLoggingOut = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    VStack(spacing: Theme.Spacing.m) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [Theme.Colors.lightBlue, Theme.Colors.primary],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 96, height: 96)
                            Text(initial)
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .accessibilityHidden(true)
                        Text(user.email)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Spacing.l)

                    VStack(spacing: 0) {
                        row(title: "Version", value: appVersion)
                        if let environmentName {
                            Divider().overlay(Theme.Colors.border)
                            row(title: "Server", value: environmentName)
                        }
                    }
                    .cardSurface(cornerRadius: 18)

                    Button(role: .destructive) { isConfirmingLogout = true } label: {
                        LoadingLabel(title: "Log out", isLoading: isLoggingOut)
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: Theme.Colors.danger))
                    .disabled(isLoggingOut)
                }
                .padding(Theme.Spacing.l)
            }
            .background(AppBackground())
            .navigationTitle("Profile")
            .confirmationDialog("Log out of Flashcards AI?", isPresented: $isConfirmingLogout, titleVisibility: .visible) {
                Button("Log out", role: .destructive) {
                    isLoggingOut = true
                    Task { await onLogout() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var initial: String {
        String(user.email.first.map { Character($0.uppercased()) } ?? "?")
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func row(title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(value).foregroundStyle(Theme.Colors.textPrimary).lineLimit(1)
        }
        .font(Theme.Typography.body)
        .padding(Theme.Spacing.l)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Profile") {
    ProfileView(user: PreviewData.user, environmentName: "localhost", onLogout: {})
}
#endif
