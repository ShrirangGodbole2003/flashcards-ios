import Foundation

/// Runtime configuration. Nothing secret lives here (the app holds no API keys,
/// the Gemini key stays on the backend). Only the API base URL is configurable.
///
/// Resolution order for the base URL:
///  0. DEBUG builds only: the address typed in the app (`DebugServerOverride`, stored on the device)
///  1. Environment variable `API_BASE_URL` (Xcode scheme -> Run -> Arguments -> Environment Variables;
///     only present when Xcode launches the app)
///  2. Info.plist key `API_BASE_URL` (set per build configuration via an .xcconfig)
///  3. DEBUG builds only: `http://localhost:8080`
/// Release builds have no default and require https.
struct AppConfig: Sendable, Equatable {
    static let baseURLKey = "API_BASE_URL"

    let apiBaseURL: URL

    enum ConfigError: LocalizedError, Equatable {
        case missingBaseURL
        case invalidBaseURL(String)
        case insecureBaseURL(String)

        var errorDescription: String? {
            switch self {
            case .missingBaseURL:
                return "API_BASE_URL is not configured. Set it in the Xcode scheme environment or the Info.plist."
            case .invalidBaseURL(let value):
                return "API_BASE_URL is not a valid http(s) URL: \(value)"
            case .insecureBaseURL(let value):
                return "Release builds require an https API_BASE_URL, got: \(value)"
            }
        }
    }

    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary,
        isDebugBuild: Bool = AppConfig.isDebugBuild,
        debugOverride: String? = nil
    ) throws -> AppConfig {
        let rawValue = (isDebugBuild ? nonEmpty(debugOverride) : nil)
            ?? nonEmpty(environment[baseURLKey])
            ?? nonEmpty(infoDictionary?[baseURLKey] as? String)
            ?? (isDebugBuild ? "http://localhost:8080" : nil)

        guard let rawValue else { throw ConfigError.missingBaseURL }

        guard let url = parse(rawValue), let scheme = url.scheme?.lowercased() else {
            throw ConfigError.invalidBaseURL(rawValue)
        }

        if !isDebugBuild && scheme != "https" {
            throw ConfigError.insecureBaseURL(rawValue)
        }

        return AppConfig(apiBaseURL: url)
    }

    /// A usable base URL: http(s) scheme and a host. Also used to validate what a developer types in the app.
    static func parse(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host() != nil else { return nil }
        return url
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
