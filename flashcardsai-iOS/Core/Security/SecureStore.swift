import Foundation
import OSLog
import Security

/// Minimal secret storage abstraction (Keychain in the app, in-memory in tests).
protocol SecureStore: Sendable {
    func read(_ key: String) throws -> String?
    func save(_ value: String, for key: String) throws
    func delete(_ key: String) throws
}

struct KeychainSecureStore: SecureStore {
    struct KeychainError: Error, Equatable { let status: OSStatus }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "flashcardsai", category: "keychain")

    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "flashcardsai") {
        self.service = service
    }

    func read(_ key: String) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            Self.logger.error("Keychain read failed, OSStatus \(status)")
            throw KeychainError(status: status)
        }
    }

    func save(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(baseQuery(for: key) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = baseQuery(for: key)
            attributes[kSecValueData as String] = data
            // Readable after the first unlock so future background work (e.g. notifications)
            // can refresh; never synced to other devices or iCloud backups.
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                // -34018 (errSecMissingEntitlement) means the app is unsigned, e.g. built with CODE_SIGNING_ALLOWED=NO
                Self.logger.error("Keychain add failed, OSStatus \(addStatus)")
                throw KeychainError(status: addStatus)
            }
        } else if status != errSecSuccess {
            Self.logger.error("Keychain update failed, OSStatus \(status)")
            throw KeychainError(status: status)
        }
    }

    func delete(_ key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }
}
