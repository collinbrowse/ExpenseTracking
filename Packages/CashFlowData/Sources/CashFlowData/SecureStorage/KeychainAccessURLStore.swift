import Foundation
import Security
import CashFlowKit

public protocol AccessURLStoring: Sendable {
    func save(_ accessURL: String) throws
    func load() throws -> String?
    func delete() throws
}

public struct KeychainAccessURLStore: AccessURLStoring, Sendable {
    private let service: String
    private let account: String

    public init(
        service: String = "com.expensetracking.simplefin",
        account: String = "accessURL"
    ) {
        self.service = service
        self.account = account
    }

    public func save(_ accessURL: String) throws {
        try delete()
        let data = Data(accessURL.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CashFlowError.persistence(message: "Keychain save failed (\(status))")
        }
    }

    public func load() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CashFlowError.persistence(message: "Keychain load failed (\(status))")
        }
        return String(data: data, encoding: .utf8)
    }

    public func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CashFlowError.persistence(message: "Keychain delete failed (\(status))")
        }
    }
}
