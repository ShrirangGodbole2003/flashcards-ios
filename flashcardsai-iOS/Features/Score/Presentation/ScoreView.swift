import SwiftUI

struct ScoreView: View {
    @State var viewModel: ScoreViewModel

    init(viewModel: ScoreViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if viewModel.hasLoaded && viewModel.records.isEmpty {
                        EmptyStateView(systemImage: "chart.bar.xaxis",
                                       title: "No scores yet",
                                       message: "Finish a study session and your results will show up here.")
                            .padding(.top, 60)
                    } else {
                        statsGrid
                        history
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .background(AppBackground())
            .navigationTitle("Score")
            .task { await viewModel.load() }
            // The tab can be re-selected after studying: refresh whenever it shows.
            .onAppear { Task { await viewModel.load() } }
        }
    }

    private var statsGrid: some View {
        let stats = viewModel.stats
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.m) {
            StatTile(value: "\(stats.sessions)", label: "Study sessions", systemImage: "book.fill")
            StatTile(value: percent(stats.averageAccuracy), label: "Average accuracy", systemImage: "target")
            StatTile(value: "\(stats.cardsAnswered)", label: "Cards answered", systemImage: "rectangle.stack.fill")
            StatTile(value: percent(stats.bestAccuracy), label: "Best session", systemImage: "trophy.fill")
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Recent sessions")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            ForEach(viewModel.records.prefix(30)) { record in
                HStack(spacing: Theme.Spacing.m) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(record.deckTopic)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        Text(record.date.formatted(date: .abbreviated, time: .shortened))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                        Text("\(record.correct)/\(record.total)")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Badge(text: percent(record.accuracy), tint: tint(for: record.accuracy))
                    }
                }
                .padding(Theme.Spacing.m)
                .cardSurface(cornerRadius: 16)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private func tint(for accuracy: Double) -> Color {
        accuracy >= 0.7 ? Theme.Colors.success : (accuracy >= 0.4 ? Theme.Colors.primary : Theme.Colors.danger)
    }
}

#if DEBUG
#Preview("Score") {
    ScoreView(viewModel: ScoreViewModel(repository: PreviewScoreRepository()))
}
#Preview("Score (empty)") {
    ScoreView(viewModel: ScoreViewModel(repository: PreviewScoreRepository(records: [])))
}
#endif
