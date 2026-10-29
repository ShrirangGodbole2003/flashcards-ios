import Foundation

/// DEBUG-only: lets a developer point the app at another backend from the UI (for example the
/// Mac's LAN address on a real iPhone) without depending on how Xcode launched the app.
/// Saved in UserDefaults on the device. `AppConfig` ignores it in Release builds, and an
/// invalid saved value is ignored here, so a typo can never leave the app unable to start.
enum DebugServerOverride {
    static let key = "debug.apiBaseURL"

    static func read(defaults: UserDefaults = .standard) -> String? {
        guard let stored = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !stored.isEmpty,
              AppConfig.parse(stored) != nil else { return nil }
        return stored
    }

    static func save(_ value: String, defaults: UserDefaults = .standard) {
        defaults.set(value.trimmingCharacters(in: .whitespacesAndNewlines), forKey: key)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
