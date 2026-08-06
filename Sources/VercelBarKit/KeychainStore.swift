import Foundation
import Security

/// Token Vercela w Keychain (kSecClassGenericPassword).
///
/// Świadoma decyzja: klasyczny pęk login (`login.keychain-db`), BEZ `kSecUseDataProtectionKeychain`.
/// Data-protection keychain wymaga entitlementu `keychain-access-groups`, którego podpis ad-hoc
/// nie ma — zapytania kończyłyby się błędem -34018 (`errSecMissingEntitlement`).
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

    /// nil = tokenu naprawdę nie ma (`errSecItemNotFound`). Inne niepowodzenia rzucają —
    /// wołający decyduje, czy to chwilowe (nie zrywaj sesji), czy trwałe.
    /// Po aktualizacji aplikacji podpisanej ad-hoc pęk oddaje `errSecAuthFailed`; to nie jest
    /// „użytkownik się wylogował".
    public func readToken(account: String = "vercel-token") throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.status(errSecDecode)
        }
        return token
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

    /// true = wpis usunięty albo nie istniał; false = usunięcie się nie powiodło.
    /// Brak wpisu to nie błąd — wylogowanie ma być idempotentne.
    @discardableResult
    public func deleteToken(account: String = "vercel-token") -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
