import SwiftUI

/// The reminder control on the deck detail screen: a button, or the pending reminder with change / cancel.
struct DeckReminderSection: View {
    @Bindable var viewModel: DeckReminderViewModel

    var body: some View {
        Group {
            if let date = viewModel.scheduledDate {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(Theme.Colors.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reminder set")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(date.formatted(date: .omitted, time: .shortened))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    Button("Change") { viewModel.presentSheet() }
                    Button("Cancel", role: .destructive) { viewModel.cancel() }
                }
                .font(Theme.Typography.caption)
                .padding(Theme.Spacing.m)
                .cardSurface(cornerRadius: 16)
                .accessibilityElement(children: .contain)
            } else {
                Button { viewModel.presentSheet() } label: {
                    Label("Remind me today", systemImage: "bell")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .sheet(isPresented: $viewModel.isPresentingSheet) {
            RemindMeSheet(viewModel: viewModel)
        }
    }
}
