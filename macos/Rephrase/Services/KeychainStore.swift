import Foundation
import Security

/// Stores the session token per server host as a generic password item.
struct KeychainStore {
    var service = "dev.rephrase.mac.session"

    func token(for host: String) -> String? {
        var query = baseQuery(host)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setToken(_ token: String, for host: String) throws {
        let data = Data(token.utf8)
        let status = SecItemUpdate(baseQuery(host) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(host)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func deleteToken(for host: String) {
        SecItemDelete(baseQuery(host) as CFDictionary)
    }

    private func baseQuery(_ host: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host,
        ]
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
        return "Keychain: \(message)"
    }
}
