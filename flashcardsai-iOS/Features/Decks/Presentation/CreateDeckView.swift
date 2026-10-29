import SwiftUI

struct CreateDeckView: View {
    @Bindable var viewModel: CreateDeckViewModel
    let onCreated: (Deck) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var topicFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("What do you want to learn?")
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("We'll generate a deck with questions, multiple choice and true/false cards.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        AppTextField(title: "Topic", text: $viewModel.topic, systemImage: "sparkles",
                                     error: viewModel.topicError, submitLabel: .done)
                            .focused($topicFocused)
                            .onSubmit { topicFocused = false }
                            .disabled(viewModel.isGenerating)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.Spacing.s) {
                                ForEach(CreateDeckViewModel.suggestions, id: \.self) { suggestion in
                                    Button(suggestion) { viewModel.topic = suggestion }
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.Colors.primary)
                                        .padding(.horizontal, Theme.Spacing.m)
                                        .padding(.vertical, 8)
                                        .background(Theme.Colors.surfaceTint, in: Capsule())
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Difficulty")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Picker("Difficulty", selection: $viewModel.difficulty) {
                            ForEach(Difficulty.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .disabled(viewModel.isGenerating)
                    }

                    if let message = viewModel.errorMessage {
                        ErrorBanner(message: message)
                    }

                    Button {
                        topicFocused = false
                        Task {
                            if let deck = await viewModel.generate() { onCreated(deck) }
                        }
                    } label: {
                        LoadingLabel(title: "Generate deck", isLoading: viewModel.isGenerating)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(viewModel.isGenerating)
                }
                .padding(Theme.Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel.isGenerating)
                }
            }
            .overlay { if viewModel.isGenerating { GeneratingOverlay() } }
        }
        .interactiveDismissDisabled(viewModel.isGenerating)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isGenerating)
    }
}

private struct GeneratingOverlay: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: Theme.Spacing.l) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.Colors.primary)
                    .scaleEffect(pulse && !reduceMotion ? 1.15 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                Text("Generating your deck…")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("This can take up to a minute.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(Theme.Spacing.xxl)
            .cardSurface()
        }
        .onAppear { pulse = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Generating your deck. This can take up to a minute.")
        .transition(.opacity)
    }
}

#if DEBUG
#Preview("Create deck") {
    CreateDeckView(viewModel: CreateDeckViewModel(repository: PreviewDeckRepository()), onCreated: { _ in })
}
#endif
