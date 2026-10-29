import SwiftUI

/// Small building blocks shared by the Lock Screen banner and the Dynamic Island.

/// Horizontal progress bar. `progress` is 0...1.
struct StudyProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.border.opacity(0.5))
                Capsule()
                    .fill(Theme.Colors.primary)
                    .frame(width: max(proxy.size.width * progress, progress > 0 ? 8 : 0))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)   // the surrounding text already says "Card 5 of 12"
    }
}

/// Circular progress for the minimal Dynamic Island, where only a few points are available.
struct StudyProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(Theme.Colors.lightBlue.opacity(0.3), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.Colors.lightBlue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(2)
    }
}

extension StudyActivityAttributes {
    /// "8 of 12 correct" once finished, "Card 5 of 12" while studying.
    func statusText(for state: ContentState) -> String {
        state.isFinished
            ? "\(state.correctCount) of \(totalCards) correct"
            : "Card \(cardNumber(for: state)) of \(totalCards)"
    }
}
