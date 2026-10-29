import Foundation

/// A place in the app that a URL can point to. Pure value, no UI: the parser below turns
/// untrusted URL text into one of these cases (or nil), and the router decides what to show.
///
/// Supported URLs (custom scheme):
/// - `flashcardsai://decks`
/// - `flashcardsai://deck/42`   (deck detail, only if deck 42 is already loaded)
/// - `flashcardsai://score`
/// - `flashcardsai://profile`
enum DeepLink: Equatable, Sendable {
    case decks
    case deck(id: Int)
    case score
    case profile

    static let scheme = "flashcardsai"

    /// Returns nil for anything that is not exactly one of the supported shapes.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let host = url.host?.lowercased() else { return nil }

        // "/42" -> ["42"], "" -> []
        let segments = url.pathComponents.filter { $0 != "/" }

        switch (host, segments.count) {
        case ("decks", 0): self = .decks
        case ("score", 0): self = .score
        case ("profile", 0): self = .profile
        case ("deck", 1):
            guard let id = Int(segments[0]), id > 0 else { return nil }
            self = .deck(id: id)
        default:
            return nil
        }
    }

    /// The URL for this link, for widgets and notifications. `DeepLink(url: link.url) == link`.
    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .decks: components.host = "decks"
        case .deck(let id):
            components.host = "deck"
            components.path = "/\(id)"
        case .score: components.host = "score"
        case .profile: components.host = "profile"
        }
        // A scheme plus a plain host and numeric path always form a valid URL.
        return components.url!
    }
}
