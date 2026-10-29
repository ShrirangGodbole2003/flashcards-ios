import SwiftUI

struct RegisterView: View {
    @Bindable var viewModel: RegisterViewModel
    /// DEBUG builds: the backend URL in use, so a wrong server is obvious.
    var serverName: String?

    private enum Field { case email, password, confirmation }
    @FocusState private var focused: Field?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                AuthHeader(title: "Create account",
                           subtitle: "Your decks stay with your account on every device.")
                    .padding(.top, Theme.Spacing.l)

                VStack(spacing: Theme.Spacing.l) {
                    AppTextField(title: "Email", text: $viewModel.email, systemImage: "envelope",
                                 error: viewModel.emailError, contentType: .username,
                                 keyboard: .emailAddress, submitLabel: .next)
                        .focused($focused, equals: .email)
                        .onSubmit { focused = .password }

                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        AppTextField(title: "Password", text: $viewModel.password, systemImage: "lock",
                                     isSecure: true, error: viewModel.passwordError,
                                     contentType: .newPassword, submitLabel: .next)
                            .focused($focused, equals: .password)
                            .onSubmit { focused = .confirmation }

                        Label("At least \(CredentialsValidator.minPasswordLength) characters",
                              systemImage: viewModel.meetsLengthRule ? "checkmark.circle.fill" : "circle")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(viewModel.meetsLengthRule ? Theme.Colors.success : Theme.Colors.textSecondary)
                            .animation(.easeOut(duration: 0.2), value: viewModel.meetsLengthRule)
                    }

                    AppTextField(title: "Confirm password", text: $viewModel.confirmation,
                                 systemImage: "lock.rotation", isSecure: true,
                                 error: viewModel.confirmationError,
                                 contentType: .newPassword, submitLabel: .go)
                        .focused($focused, equals: .confirmation)
                        .onSubmit(submit)

                    if let message = viewModel.errorMessage {
                        ErrorBanner(message: message)
                    }

                    Button(action: submit) {
                        LoadingLabel(title: "Create account", isLoading: viewModel.isLoading)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(viewModel.isLoading)
                }

                if let serverName {
                    DebugServerLabel(serverName: serverName)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackground())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() {
        focused = nil
        Task { await viewModel.submit() }
    }
}
