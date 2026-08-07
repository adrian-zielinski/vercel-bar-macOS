import Foundation

/// Ustawienia aplikacji w UserDefaults (token trzyma KeychainStore).
public final class SettingsStore {
    private let defaults: UserDefaults

    private enum Key {
        static let watched = "watchedProjectIDs"
        static let notifySuccess = "notifySuccess"
        static let notifyFailure = "notifyFailure"
        static let notifyStart = "notifyStart"
        static let feedLimit = "feedLimit"
        static let teamID = "teamID"
    }

    /// Wartości oferowane w Ustawieniach; wprost sterują też parametrem `limit` zapytania o deploye.
    public static let allowedFeedLimits = [3, 5, 10]
    private static let defaultFeedLimit = 5

    /// Testy podstawiają własną domenę, żeby nie ruszać ustawień produkcyjnych.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Pusty zbiór = nic nie obserwujemy (interpretację „puste znaczy wszystko" zostawiamy wołającemu).
    public var watchedProjectIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.watched) ?? []) }
        // Sortujemy, żeby plist nie zmieniał się przy każdym zapisie tego samego zbioru.
        set { defaults.set(Array(newValue).sorted(), forKey: Key.watched) }
    }

    /// Brak klucza = domyślnie włączone; `object(forKey:)` odróżnia to od zapisanego `false`.
    public var notifySuccess: Bool {
        get { defaults.object(forKey: Key.notifySuccess) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.notifySuccess) }
    }

    public var notifyFailure: Bool {
        get { defaults.object(forKey: Key.notifyFailure) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.notifyFailure) }
    }

    public var notifyStart: Bool {
        get { defaults.object(forKey: Key.notifyStart) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.notifyStart) }
    }

    /// Ile ostatnich deployów pokazuje popover (łącznie, ze wszystkich obserwowanych projektów).
    /// Wartość spoza `allowedFeedLimits` — ręczna edycja plist, plik po innej wersji — wraca
    /// do domyślnej po obu stronach, bo leci wprost do zapytania `limit=<n>`.
    public var feedLimit: Int {
        get { Self.sanitized(defaults.object(forKey: Key.feedLimit) as? Int) }
        set { defaults.set(Self.sanitized(newValue), forKey: Key.feedLimit) }
    }

    private static func sanitized(_ value: Int?) -> Int {
        guard let value, allowedFeedLimits.contains(value) else { return defaultFeedLimit }
        return value
    }

    /// nil = konto osobiste.
    public var teamID: String? {
        get { defaults.string(forKey: Key.teamID) }
        set {
            if let newValue { defaults.set(newValue, forKey: Key.teamID) }
            else { defaults.removeObject(forKey: Key.teamID) }
        }
    }
}
