import Foundation
import Security

/// Where provider API keys live. Keys are never written to the settings file.
public protocol CredentialStore: Sendable {
    func apiKey(for provider: ProviderKind) -> String?
    func setAPIKey(_ key: String?, for provider: ProviderKind) throws
}

public extension CredentialStore {
    func deleteAllKeys() throws {
        for provider in ProviderKind.allCases {
            try setAPIKey(nil, for: provider)
        }
    }
}

public struct CredentialError: LocalizedError {
    public let status: OSStatus
    public var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
        return "Could not update the macOS Keychain: \(message)"
    }
}

/// One generic-password Keychain item per provider.
public struct KeychainCredentialStore: CredentialStore {
    private let service: String

    public init(service: String = "io.github.ancientcomputing.answersearch") {
        self.service = service
    }

    private func baseQuery(_ provider: ProviderKind) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
    }

    public func apiKey(for provider: ProviderKind) -> String? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }

    public func setAPIKey(_ key: String?, for provider: ProviderKind) throws {
        let status = SecItemDelete(baseQuery(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialError(status: status)
        }
        guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return }
        var attributes = baseQuery(provider)
        attributes[kSecValueData as String] = Data(key.utf8)
        // Available while the Mac is unlocked; never synced to iCloud.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw CredentialError(status: addStatus) }
    }
}

/// In-memory store for tests and previews.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [ProviderKind: String] = [:]

    public init() {}

    public func apiKey(for provider: ProviderKind) -> String? {
        lock.lock(); defer { lock.unlock() }
        return keys[provider]
    }

    public func setAPIKey(_ key: String?, for provider: ProviderKind) throws {
        lock.lock(); defer { lock.unlock() }
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        keys[provider] = trimmed.isEmpty ? nil : trimmed
    }
}
