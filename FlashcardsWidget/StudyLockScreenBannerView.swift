import SwiftUI
import WidgetKit

/// The Live Activity as shown on the Lock Screen (and as the banner on devices without a Dynamic Island).
struct StudyLockScreenBannerView: View {
    let attributes: StudyActivityAttributes
    let state: StudyActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: state.isFinished ? "checkmark.seal.fill" : "rectangle.stack.fill")
                    .foregroundStyle(Theme.Colors.primary)
                Text(attributes.deckName)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(state.isFinished ? "Done" : "Studying")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.primary)
            }

            StudyProgressBar(progress: attributes.progress(for: state))

            HStack {
                Text(attributes.statusText(for: state))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                if !state.isFinished {
                    Label("\(state.correctCount) correct", systemImage: "checkmark.circle.fill")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.success)
                }
            }
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}
