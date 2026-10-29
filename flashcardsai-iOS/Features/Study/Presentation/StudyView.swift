import SwiftUI

struct StudyView: View {
    @State var viewModel: StudyViewModel
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: StudyViewModel, onClose: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onClose = onClose
    }

    private var session: StudySession { viewModel.session }

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            header

            if session.isFinished {
                StudySummaryView(session: session,
                                 onRestart: { withAnimation(.snappy) { viewModel.restart() } },
                                 onDone: onClose)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if let card = session.currentCard {
                cardArea(for: card)
                ActionBar(session: session, viewModel: viewModel, card: card)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.bottom, Theme.Spacing.l)
            }
        }
        .background(AppBackground())
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.success, trigger: session.correctCount)
        .sensoryFeedback(.error, trigger: session.results.count - session.correctCount)
        .animation(reduceMotion ? nil : .snappy, value: session.isFinished)
        .onAppear { viewModel.begin() }
        .onDisappear { viewModel.didLeave() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")

            ProgressView(value: session.progress)
                .tint(Theme.Colors.primary)
                .animation(reduceMotion ? nil : .easeInOut, value: session.progress)
                .accessibilityLabel("Progress")

            Text(counterText)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .monospacedDigit()
                .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.top, Theme.Spacing.s)
    }

    private var counterText: String {
        let position = min(session.currentIndex + 1, session.totalCount)
        return "\(position)/\(session.totalCount)"
    }

    // MARK: Card

    @ViewBuilder
    private func cardArea(for card: Card) -> some View {
        // `.id(card.id)` gives every card a fresh StudyCardStage (and so fresh gesture state).
        StudyCardStage(card: card, viewModel: viewModel)
            .padding(.horizontal, Theme.Spacing.l)
            .id(card.id)
            .transition(reduceMotion
                        ? .opacity
                        : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                      removal: .move(edge: .leading).combined(with: .opacity)))
    }
}

// MARK: - Card stage: flip + gestures

/// Hosts the flip card and its gestures (QA cards only; MCQ and True/False must be
/// answered by choosing an option, a swipe would let people skip the question):
///  - drag the question side sideways: the card turns with the finger; past ~45 degrees,
///    or with a quick flick, it completes the flip and reveals the answer
///  - after the answer is shown: swipe right = "Got it", swipe left = "Missed it"
/// The buttons below the card stay as the accessible / discoverable alternative.
private struct StudyCardStage: View {
    let card: Card
    let viewModel: StudyViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragAngle = 0.0
    @State private var flipDirection = 1.0
    @State private var swipeOffset: CGFloat = 0
    @State private var isFlyingOff = false
    @GestureState private var isDragging = false

    private var session: StudySession { viewModel.session }
    private var canFlipByDrag: Bool { card.type == .qa && !session.isRevealed }
    private var canSwipeToGrade: Bool { session.needsSelfGrade && !isFlyingOff }

    var body: some View {
        face
            .offset(x: swipeOffset)
            .rotationEffect(.degrees(Double(swipeOffset) / 25), anchor: .bottom)
            .overlay(alignment: .top) { gradeHint }
            .simultaneousGesture(dragGesture)
            .onChange(of: isDragging) { _, dragging in
                // A gesture that was cancelled (alert, system gesture) never calls onEnded: settle the card.
                guard !dragging, !isFlyingOff else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    dragAngle = 0
                    swipeOffset = 0
                }
            }
            .sensoryFeedback(trigger: session.isRevealed) { _, revealed in
                revealed && card.type == .qa ? .impact(weight: .light) : nil
            }
    }

    // MARK: Face

    @ViewBuilder
    private var face: some View {
        if reduceMotion {
            // No 3D motion for people who asked for less of it: cross-fade instead.
            ZStack {
                if session.isRevealed {
                    CardBackFace(card: card, phase: session.phase)
                } else {
                    CardFrontFace(card: card, viewModel: viewModel)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: session.isRevealed)
        } else {
            FlipCardView(isFlipped: session.isRevealed, flipDirection: flipDirection, dragAngle: dragAngle) {
                CardFrontFace(card: card, viewModel: viewModel)
            } back: {
                CardBackFace(card: card, phase: session.phase)
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.82), value: session.isRevealed)
        }
    }

    /// "Got it" / "Missed it" stamp that fades in while the card is being swiped.
    @ViewBuilder
    private var gradeHint: some View {
        if abs(swipeOffset) > 8 {
            let knewIt = swipeOffset > 0
            Label(knewIt ? "Got it" : "Missed it", systemImage: knewIt ? "checkmark" : "xmark")
                .font(Theme.Typography.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
                .background(knewIt ? Theme.Colors.success : Theme.Colors.danger, in: Capsule())
                .opacity(min(1, Double(abs(swipeOffset)) / 100))
                .padding(.top, Theme.Spacing.xl)
                .allowsHitTesting(false)
        }
    }

    // MARK: Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in
                // Mostly-vertical drags belong to the text's ScrollView, not to the card.
                guard isHorizontal(value.translation) else { return }
                if canFlipByDrag {
                    if !reduceMotion {
                        dragAngle = max(-170, min(170, Double(value.translation.width) * 0.5))
                    }
                } else if canSwipeToGrade {
                    swipeOffset = value.translation.width
                }
            }
            .onEnded { value in
                if canFlipByDrag {
                    finishFlip(value)
                } else if canSwipeToGrade {
                    finishGrade(value)
                }
            }
    }

    private func isHorizontal(_ translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height)
    }

    private func finishFlip(_ value: DragGesture.Value) {
        let width = value.translation.width
        let flicked = abs(value.predictedEndTranslation.width) > 220
        let pulledFarEnough = reduceMotion ? abs(width) > 80 : abs(dragAngle) > 45

        guard (pulledFarEnough || flicked), isHorizontal(value.translation) else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { dragAngle = 0 }   // snap back
            return
        }

        flipDirection = (dragAngle != 0 ? dragAngle : width) < 0 ? -1 : 1
        withAnimation(.spring(response: 0.6, dampingFraction: 0.82)) {
            dragAngle = 0
            viewModel.revealAnswer()
        }
    }

    private func finishGrade(_ value: DragGesture.Value) {
        let predicted = value.predictedEndTranslation.width
        let decisive = abs(swipeOffset) > 110 || abs(predicted) > 260

        guard decisive else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { swipeOffset = 0 }
            return
        }

        let knewIt = (swipeOffset != 0 ? swipeOffset : predicted) > 0
        isFlyingOff = true
        withAnimation(.easeIn(duration: 0.22)) { swipeOffset = knewIt ? 700 : -700 }

        // Let the card leave the screen, then grade it and move on to the next one.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(230))
            viewModel.grade(correct: knewIt)
            withAnimation(.snappy) { viewModel.next() }
        }
    }
}

// MARK: - Bottom action bar

private struct ActionBar: View {
    let session: StudySession
    let viewModel: StudyViewModel
    let card: Card

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if session.needsSelfGrade {
                HStack(spacing: Theme.Spacing.m) {
                    Button { viewModel.grade(correct: false) } label: {
                        Label("Missed it", systemImage: "xmark")
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: Theme.Colors.danger))

                    Button { viewModel.grade(correct: true) } label: {
                        Label("Got it", systemImage: "checkmark")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            } else if session.canAdvance {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy) { viewModel.next() }
                } label: {
                    Label(session.isLastCard ? "See results" : "Next card",
                          systemImage: session.isLastCard ? "flag.checkered" : "arrow.right")
                }
                .buttonStyle(PrimaryButtonStyle())
            } else if card.type == .qa {
                Button { viewModel.revealAnswer() } label: {
                    Label("Reveal answer", systemImage: "eye")
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Text(card.type == .mcq ? "Choose an answer" : "True or false?")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.phase)
    }
}

// MARK: - Front face (the question)

private struct CardFrontFace: View {
    let card: Card
    let viewModel: StudyViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack {
                Badge(text: card.type.displayName, systemImage: card.type.systemImage)
                Spacer()
                if let hint = card.hint, !hint.isEmpty {
                    Button { withAnimation(.easeInOut) { viewModel.toggleHint() } } label: {
                        Image(systemName: viewModel.isHintVisible ? "lightbulb.fill" : "lightbulb")
                            .font(.title3)
                            .foregroundStyle(Theme.Colors.primary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(viewModel.isHintVisible ? "Hide hint" : "Show hint")
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Text(card.question)
                        .font(Theme.Typography.cardQuestion)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if viewModel.isHintVisible, let hint = card.hint {
                        Label(hint, systemImage: "lightbulb")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.primary)
                            .padding(Theme.Spacing.m)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.Colors.surfaceTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    switch card.type {
                    case .mcq:
                        VStack(spacing: Theme.Spacing.m) {
                            ForEach(Array(card.options.enumerated()), id: \.offset) { index, option in
                                OptionButton(letter: letter(for: index), text: option) {
                                    viewModel.selectOption(index)
                                }
                            }
                        }
                    case .trueFalse:
                        HStack(spacing: Theme.Spacing.m) {
                            TrueFalseButton(title: "True", systemImage: "checkmark") { viewModel.answerTrueFalse(true) }
                            TrueFalseButton(title: "False", systemImage: "xmark") { viewModel.answerTrueFalse(false) }
                        }
                    case .qa:
                        EmptyView()
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            if card.type == .qa {
                Label("Tap or swipe the card to reveal the answer", systemImage: "hand.draw")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface()
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .onTapGesture {
            if card.type == .qa { viewModel.revealAnswer() }
        }
    }

    private func letter(for index: Int) -> String {
        String(UnicodeScalar(UInt8(65 + index % 26)))
    }
}

private struct OptionButton: View {
    let letter: String
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                Text(letter)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.primary)
                    .frame(width: 28, height: 28)
                    .background(Theme.Colors.surfaceTint, in: Circle())
                Text(text)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.m)
            .frame(minHeight: 52)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(Theme.Colors.border, lineWidth: 1.5))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Option \(letter): \(text)")
    }
}

private struct TrueFalseButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.primary)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Theme.Colors.surfaceTint, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(Theme.Colors.border, lineWidth: 1.5))
        }
        .buttonStyle(PressableStyle())
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Back face (the answer)

private struct CardBackFace: View {
    let card: Card
    let phase: StudySession.Phase

    private var isCorrect: Bool? {
        if case .revealed(_, let correct) = phase { return correct }
        return nil
    }

    private var selection: StudySession.Selection? {
        if case .revealed(let selection, _) = phase { return selection }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            outcomeHeader

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Text(card.question)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    if card.type == .mcq {
                        VStack(spacing: Theme.Spacing.s) {
                            ForEach(Array(card.options.enumerated()), id: \.offset) { index, option in
                                OptionResultRow(text: option, state: state(forOption: index))
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("ANSWER")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(card.answer)
                                .font(Theme.Typography.cardQuestion)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let explanation = card.explanation, !explanation.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Label("Why", systemImage: "info.circle")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.primary)
                            Text(explanation)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        .padding(Theme.Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Colors.surfaceTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            if card.type == .qa, isCorrect == nil {
                Label("Swipe right if you knew it, left if you missed it", systemImage: "hand.draw")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface()
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(outcomeTint.opacity(isCorrect == nil ? 0 : 0.8), lineWidth: 2))
    }

    private var outcomeTint: Color {
        switch isCorrect {
        case .some(true): return Theme.Colors.success
        case .some(false): return Theme.Colors.danger
        case nil: return Theme.Colors.primary
        }
    }

    private var outcomeHeader: some View {
        HStack(spacing: Theme.Spacing.s) {
            switch isCorrect {
            case .some(true):
                Label("Correct!", systemImage: "checkmark.seal.fill")
            case .some(false):
                Label("Not quite", systemImage: "xmark.seal.fill")
            case nil:
                Label("Answer", systemImage: "eye.fill")
            }
            Spacer()
        }
        .font(Theme.Typography.title)
        .foregroundStyle(outcomeTint)
    }

    private func state(forOption index: Int) -> OptionResultRow.State {
        let isRight: Bool
        if let correctIndex = card.correctIndex { isRight = index == correctIndex }
        else { isRight = card.options[index] == card.answer }

        if isRight { return .correct }
        if case .option(let chosen)? = selection, chosen == index { return .wrong }
        return .neutral
    }
}

private struct OptionResultRow: View {
    enum State { case correct, wrong, neutral }
    let text: String
    let state: State

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.m)
        .background(tint.opacity(state == .neutral ? 0 : 0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            .strokeBorder(tint.opacity(state == .neutral ? 0.25 : 0.7), lineWidth: 1.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text), \(accessibilityState)")
    }

    private var icon: String {
        switch state {
        case .correct: return "checkmark.circle.fill"
        case .wrong: return "xmark.circle.fill"
        case .neutral: return "circle"
        }
    }

    private var tint: Color {
        switch state {
        case .correct: return Theme.Colors.success
        case .wrong: return Theme.Colors.danger
        case .neutral: return Theme.Colors.textSecondary
        }
    }

    private var accessibilityState: String {
        switch state {
        case .correct: return "correct answer"
        case .wrong: return "your answer, incorrect"
        case .neutral: return "not selected"
        }
    }
}

#if DEBUG
#Preview("Study session") {
    NavigationStack {
        StudyView(viewModel: StudyViewModel(deck: PreviewData.deck, scoreRepository: PreviewScoreRepository()),
                  onClose: {})
    }
}
#endif
