import SwiftUI

struct DeckListView: View {
    @Bindable var viewModel: DeckListViewModel
    let onSelect: (DeckSummary) -> Void
    let onCreate: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.m) {
                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message)
                }

                if viewModel.decks.isEmpty {
                    emptyOrLoading
                } else {
                    ForEach(viewModel.decks) { deck in
                        Button { onSelect(deck) } label: { DeckRow(deck: deck) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(AppBackground())
        .navigationTitle("My Decks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onCreate) {
                    Label("New deck", systemImage: "plus.circle.fill")
                }
                .tint(Theme.Colors.primary)
            }
        }
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var emptyOrLoading: some View {
        if viewModel.isLoading || !viewModel.hasLoaded && viewModel.errorMessage == nil {
            ProgressView("Loading your decks…")
                .tint(Theme.Colors.primary)
                .padding(.top, 80)
        } else if viewModel.errorMessage != nil {
            Button("Try again") { Task { await viewModel.refresh() } }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, Theme.Spacing.l)
        } else {
            VStack(spacing: Theme.Spacing.xl) {
                EmptyStateView(systemImage: "rectangle.stack.badge.plus",
                               title: "No decks yet",
                               message: "Pick a topic and we'll generate a deck of flashcards for you.")
                Button(action: onCreate) { Label("Create your first deck", systemImage: "sparkles") }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.top, 60)
        }
    }
}

private struct DeckRow: View {
    let deck: DeckSummary

    var body: some View {
        HStack(spacing: Theme.Spacing.l) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.Colors.surfaceTint)
                    .frame(width: 52, height: 52)
                Image(systemName: "rectangle.stack.fill")
                    .foregroundStyle(Theme.Colors.primary)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(deck.topic)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                HStack(spacing: Theme.Spacing.s) {
                    Badge(text: deck.difficulty.displayName, tint: deck.difficulty.tint)
                    Text("\(deck.cardCount) cards")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.l)
        .cardSurface(cornerRadius: 20)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the deck")
    }
}
