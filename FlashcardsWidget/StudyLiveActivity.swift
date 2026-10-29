import ActivityKit
import SwiftUI
import WidgetKit

/// The Live Activity for a study session. The app starts and updates it (ActivityKit);
/// this file only describes how each presentation looks.
struct StudyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StudyActivityAttributes.self) { context in
            // Lock Screen / banner
            StudyLockScreenBannerView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Theme.Colors.surfaceTint)
                .activitySystemActionForegroundColor(Theme.Colors.primary)
                .widgetURL(DeepLink.deck(id: context.attributes.deckID).url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { StudyIslandExpandedLeadingView() }
                DynamicIslandExpandedRegion(.trailing) { StudyIslandExpandedTrailingView(state: context.state) }
                DynamicIslandExpandedRegion(.center) { StudyIslandExpandedCenterView(attributes: context.attributes) }
                DynamicIslandExpandedRegion(.bottom) {
                    StudyIslandExpandedBottomView(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                StudyIslandCompactLeadingView()
            } compactTrailing: {
                StudyIslandCompactTrailingView(attributes: context.attributes, state: context.state)
            } minimal: {
                StudyIslandMinimalView(attributes: context.attributes, state: context.state)
            }
            .widgetURL(DeepLink.deck(id: context.attributes.deckID).url)
            .keylineTint(Theme.Colors.lightBlue)
        }
    }
}

// MARK: - Previews (Xcode canvas: pick Lock Screen / Expanded / Compact / Minimal)

private extension StudyActivityAttributes {
    static let preview = StudyActivityAttributes(deckID: 1, deckName: "Swift Concurrency", totalCards: 12)
}

private extension StudyActivityAttributes.ContentState {
    static let start = Self(answeredCount: 0, correctCount: 0, isFinished: false)
    static let midway = Self(answeredCount: 4, correctCount: 3, isFinished: false)
    static let done = Self(answeredCount: 12, correctCount: 9, isFinished: true)
}

#Preview("Lock Screen", as: .content, using: StudyActivityAttributes.preview) {
    StudyLiveActivity()
} contentStates: {
    StudyActivityAttributes.ContentState.start
    StudyActivityAttributes.ContentState.midway
    StudyActivityAttributes.ContentState.done
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: StudyActivityAttributes.preview) {
    StudyLiveActivity()
} contentStates: {
    StudyActivityAttributes.ContentState.midway
    StudyActivityAttributes.ContentState.done
}

#Preview("Compact", as: .dynamicIsland(.compact), using: StudyActivityAttributes.preview) {
    StudyLiveActivity()
} contentStates: {
    StudyActivityAttributes.ContentState.midway
    StudyActivityAttributes.ContentState.done
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: StudyActivityAttributes.preview) {
    StudyLiveActivity()
} contentStates: {
    StudyActivityAttributes.ContentState.midway
}
