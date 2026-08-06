import Foundation
import Security

/// Token Vercela w Keychain (kSecClassGenericPassword).
public struct KeychainStore: Sendable {
    /// Usługa w pęku kluczy; testy podmieniają ją na własną, żeby nie ruszać tokenu produkcyjnego.
    public let service: String

    public init(service: String = "pl.zielinski.vercelbar") {
        self.service = service
    }

    public enum KeychainError: Error {
        case status(OSStatus)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// `nil`, gdy wpisu nie ma albo pęk kluczy go nie oddał — wołający traktuje to jak brak tokenu.
    public func readToken(account: String = "vercel-token") -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Nadpisuje istniejący wpis, a przy jego braku zakłada nowy.
    public func writeToken(_ token: String, account: String = "vercel-token") throws {
        let data = Data(token.utf8)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(account: account) as CFDictionary,
                                   update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(account: account)
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    /// Brak wpisu to nie błąd — wylogowanie ma być idempotentne.
    public func deleteToken(account: String = "vercel-token") {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
