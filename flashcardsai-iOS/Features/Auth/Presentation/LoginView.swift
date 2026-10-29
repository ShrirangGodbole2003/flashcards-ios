import SwiftUI

struct LoginView<RegisterDestination: View>: View {
    @Bindable var viewModel: LoginViewModel
    /// DEBUG builds: the backend URL in use, so a wrong server is obvious.
    var serverName: String?
    @ViewBuilder var registerDestination: () -> RegisterDestination

    private enum Field { case email, password }
    @FocusState private var focused: Field?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                AuthHeader(title: "Flashcards AI",
                           subtitle: "Learn anything with cards made just for you.")
                    .padding(.top, Theme.Spacing.xxl)

                VStack(spacing: Theme.Spacing.l) {
                    AppTextField(title: "Email", text: $viewModel.email, systemImage: "envelope",
                                 error: viewModel.emailError, contentType: .username,
                                 keyboard: .emailAddress, submitLabel: .next)
                        .focused($focused, equals: .email)
                        .onSubmit { focused = .password }

                    AppTextField(title: "Password", text: $viewModel.password, systemImage: "lock",
                                 isSecure: true, error: viewModel.passwordError,
                                 contentType: .password, submitLabel: .go)
                        .focused($focused, equals: .password)
                        .onSubmit(submit)

                    if let message = viewModel.errorMessage {
                        ErrorBanner(message: message)
                    }

                    Button(action: submit) {
                        LoadingLabel(title: "Log in", isLoading: viewModel.isLoading)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(viewModel.isLoading)
                }

                HStack(spacing: Theme.Spacing.xs) {
                    Text("New here?")
                        .foregroundStyle(Theme.Colors.textSecondary)
                    NavigationLink("Create an account", destination: registerDestination)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.primary)
                }
                .font(Theme.Typography.body)

                if let serverName {
                    DebugServerLabel(serverName: serverName)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackground())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func submit() {
        focused = nil
        Task { await viewModel.submit() }
    }
}
