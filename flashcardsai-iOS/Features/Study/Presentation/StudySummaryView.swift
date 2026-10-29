import SwiftUI

struct StudySummaryView: View {
    let session: StudySession
    let onRestart: () -> Void
    let onDone: () -> Void

    @State private var ringProgress = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                ring
                    .padding(.top, Theme.Spacing.l)

                VStack(spacing: Theme.Spacing.xs) {
                    Text(headline)
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("\(session.correctCount) correct · \(session.totalCount - session.correctCount) to review")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                if !session.missedCards.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        Text("Review these")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        ForEach(session.missedCards) { card in
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text(card.question)
                                    .font(Theme.Typography.body.weight(.semibold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text(card.answer)
                                    .font(Theme.Typography.body)
                                    .foregroundStyle(Theme.Colors.success)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.Spacing.m)
                            .cardSurface(cornerRadius: 16)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                VStack(spacing: Theme.Spacing.m) {
                    Button(action: onRestart) { Label("Study again", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Done", action: onDone)
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .onAppear {
            if reduceMotion { ringProgress = session.accuracy }
            else { withAnimation(.easeOut(duration: 1.0).delay(0.15)) { ringProgress = session.accuracy } }
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Theme.Colors.border, lineWidth: 16)
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(LinearGradient(colors: [Theme.Colors.lightBlue, Theme.Colors.primary],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(Int((session.accuracy * 100).rounded()))%")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("\(session.correctCount) of \(session.totalCount)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(width: 190, height: 190)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score: \(session.correctCount) of \(session.totalCount) correct")
    }

    private var headline: String {
        switch session.accuracy {
        case 0.9...: return "Outstanding!"
        case 0.7...: return "Great job!"
        case 0.4...: return "Good progress"
        default: return "Let's review"
        }
    }
}
