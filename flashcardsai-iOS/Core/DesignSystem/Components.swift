import SwiftUI

// MARK: Backgrounds & surfaces

struct AppBackground: View {
    var body: some View {
        LinearGradient(colors: [Theme.Colors.backgroundTop, Theme.Colors.background],
                       startPoint: .top, endPoint: .center)
            .ignoresSafeArea()
    }
}

extension View {
    /// White (navy in dark mode) rounded card with a soft light-blue shadow.
    func cardSurface(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.Colors.border, lineWidth: 1))
            .shadow(color: Theme.Colors.lightBlue.opacity(0.18), radius: 14, y: 6)
    }
}

// MARK: Buttons

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.onPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.Colors.primary.opacity(isEnabled ? 1 : 0.4),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.Colors.primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(tint.opacity(configuration.isPressed ? 0.16 : 0.09),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// Label that swaps its title for a spinner while loading.
struct LoadingLabel: View {
    let title: String
    let isLoading: Bool

    var body: some View {
        ZStack {
            Text(title).opacity(isLoading ? 0 : 1)
            if isLoading { ProgressView().tint(Theme.Colors.onPrimary) }
        }
    }
}

// MARK: Text input

struct AppTextField: View {
    let title: String
    @Binding var text: String
    var systemImage: String
    var isSecure = false
    var error: String?
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var submitLabel: SubmitLabel = .next

    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.Colors.primary)
                    .frame(width: 22)

                Group {
                    if isSecure && !isRevealed {
                        SecureField(title, text: $text)
                    } else {
                        TextField(title, text: $text)
                    }
                }
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(submitLabel)
                .focused($isFocused)
                .foregroundStyle(Theme.Colors.textPrimary)

                if isSecure {
                    Button {
                        isRevealed.toggle()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .frame(minHeight: 52)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isFocused || error != nil ? 1.5 : 1))

            if let error {
                Text(error)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.danger)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: error)
    }

    private var borderColor: Color {
        if error != nil { return Theme.Colors.danger }
        return isFocused ? Theme.Colors.primary : Theme.Colors.border
    }
}

// MARK: Feedback

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .font(Theme.Typography.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.Colors.danger)
        .padding(Theme.Spacing.m)
        .background(Theme.Colors.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.lightBlue)
            Text(title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Badges

struct Badge: View {
    let text: String
    var systemImage: String?
    var tint: Color = Theme.Colors.primary

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

extension Difficulty {
    var tint: Color {
        switch self {
        case .beginner: return Theme.Colors.success
        case .intermediate: return Theme.Colors.primary
        case .advanced: return Theme.Colors.danger
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.Colors.primary)
            Text(value)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.l)
        .cardSurface(cornerRadius: 20)
        .accessibilityElement(children: .combine)
    }
}
