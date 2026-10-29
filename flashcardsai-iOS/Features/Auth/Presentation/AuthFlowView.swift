import SwiftUI

/// Signed-out experience: login, with a push to registration.
struct AuthFlowView: View {
    private let authRepository: AuthRepository
    private let serverName: String?
    private let onAuthenticated: (AuthUser) -> Void
    @State private var loginViewModel: LoginViewModel

    /// `serverName` is passed in DEBUG builds only, to show which backend the app talks to.
    init(authRepository: AuthRepository, serverName: String? = nil, onAuthenticated: @escaping (AuthUser) -> Void) {
        self.authRepository = authRepository
        self.serverName = serverName
        self.onAuthenticated = onAuthenticated
        _loginViewModel = State(initialValue: LoginViewModel(authRepository: authRepository,
                                                              onAuthenticated: onAuthenticated))
    }

    var body: some View {
        NavigationStack {
            LoginView(viewModel: loginViewModel, serverName: serverName) {
                RegisterView(viewModel: RegisterViewModel(authRepository: authRepository,
                                                          onAuthenticated: onAuthenticated),
                             serverName: serverName)
            }
        }
    }
}

struct AuthHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Theme.Colors.lightBlue, Theme.Colors.primary],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 84, height: 84)
                    .shadow(color: Theme.Colors.lightBlue.opacity(0.45), radius: 16, y: 8)
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            Text(title)
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(subtitle)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

#if DEBUG
#Preview("Login / register") {
    AuthFlowView(authRepository: PreviewAuthRepository(), onAuthenticated: { _ in })
}
#endif
