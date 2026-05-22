import Foundation
import Security

public struct KeychainClient: Sendable {
    public static let defaultService = "com.ebiinsights.JamfMapper"

    private let service: String

    public init(service: String = Self.defaultService) {
        self.service = service
    }

    public func saveClientSecret(_ secret: String, connectionID: UUID) throws {
        let data = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectionID.uuidString
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }
        if status != errSecItemNotFound {
            throw JamfMapperError.keychain(status)
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw JamfMapperError.keychain(insertStatus)
        }
    }

    public func clientSecret(connectionID: UUID) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectionID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw JamfMapperError.keychain(status)
        }
        guard let data = item as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw JamfMapperError.invalidResponse
        }
        return secret
    }

    public func deleteClientSecret(connectionID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectionID.uuidString
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw JamfMapperError.keychain(status)
        }
    }
}
