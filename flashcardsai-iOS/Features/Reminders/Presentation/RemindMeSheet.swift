import SwiftUI

/// Sheet to choose when to be reminded (today only).
struct RemindMeSheet: View {
    @Bindable var viewModel: DeckReminderViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    if let message = viewModel.errorMessage {
                        ErrorBanner(message: message)
                        if viewModel.permission == .denied {
                            Button("Open Settings") {
                                if let url = URL(string: "app-settings:") { openURL(url) }
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }

                    ForEach(viewModel.quickOptions) { option in
                        Button {
                            Task { await viewModel.schedule(at: option.date) }
                        } label: {
                            HStack {
                                Text(option.title)
                                
                                Spacer()
                                Text(option.date.formatted(date: .omitted, time: .shortened))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            .padding(.horizontal, Theme.Spacing.l)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(viewModel.isWorking)
                    }

                    if let range = viewModel.pickerRange {
                        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                            Text("Or pick a time today")
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            DatePicker("Time", selection: $viewModel.customDate, in: range, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                            Button {
                                Task { await viewModel.schedule(at: viewModel.customDate) }
                            } label: {
                                LoadingLabel(title: "Set reminder", isLoading: viewModel.isWorking)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(viewModel.isWorking)
                        }
                    } else if viewModel.quickOptions.isEmpty {
                        Text("It's too late in the day to set a reminder for today.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .background(AppBackground())
            .navigationTitle("Remind me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.isPresentingSheet = false }
                }
            }
        }
        .presentationDetents([.large])
    }
}
