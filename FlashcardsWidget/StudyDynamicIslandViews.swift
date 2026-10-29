import SwiftUI
import WidgetKit

// The Dynamic Island has four presentations. The system picks one:
//   expanded: user long-presses the island        compact: one activity, shown as two small pills
//   minimal:  more than one activity is running   (the pills sit left and right of the camera)
// The island is always dark, so colours resolve to their dark variants.

// MARK: Expanded

struct StudyIslandExpandedLeadingView: View {
    var body: some View {
        Image(systemName: "rectangle.stack.fill")
            .font(.title2)
            .foregroundStyle(Theme.Colors.lightBlue)
            .accessibilityHidden(true)
    }
}

struct StudyIslandExpandedTrailingView: View {
    let state: StudyActivityAttributes.ContentState

    var body: some View {
        Label("\(state.correctCount)", systemImage: "checkmark.circle.fill")
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.success)
            .accessibilityLabel("\(state.correctCount) correct")
    }
}

struct StudyIslandExpandedCenterView: View {
    let attributes: StudyActivityAttributes

    var body: some View {
        Text(attributes.deckName)
            .font(Theme.Typography.headline)
            .lineLimit(1)
    }
}

struct StudyIslandExpandedBottomView: View {
    let attributes: StudyActivityAttributes
    let state: StudyActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StudyProgressBar(progress: attributes.progress(for: state))
            Text(attributes.statusText(for: state))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Compact and minimal

struct StudyIslandCompactLeadingView: View {
    var body: some View {
        Image(systemName: "rectangle.stack.fill")
            .foregroundStyle(Theme.Colors.lightBlue)
            .accessibilityHidden(true)
    }
}

/// "5/12", or a check mark when the session is done.
struct StudyIslandCompactTrailingView: View {
    let attributes: StudyActivityAttributes
    let state: StudyActivityAttributes.ContentState

    var body: some View {
        if state.isFinished {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.Colors.success)
                .accessibilityLabel("Session complete")
        } else {
            Text("\(attributes.cardNumber(for: state))/\(attributes.totalCards)")
                .font(Theme.Typography.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.lightBlue)
                .accessibilityLabel(attributes.statusText(for: state))
        }
    }
}

struct StudyIslandMinimalView: View {
    let attributes: StudyActivityAttributes
    let state: StudyActivityAttributes.ContentState

    var body: some View {
        StudyProgressRing(progress: attributes.progress(for: state))
            .accessibilityLabel(attributes.statusText(for: state))
    }
}
