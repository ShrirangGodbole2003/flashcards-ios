import Foundation

/// Identifiers shared by the app and the widget extension. Must match the App Groups
/// capability on BOTH targets (Signing & Capabilities), otherwise the widget sees no data.
/// This is an identifier, not a secret.
enum AppGroup {
    static let identifier = "group.com.flashcardsai.flashcardsai-iOS"
}
