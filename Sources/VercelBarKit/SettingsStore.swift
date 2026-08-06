import Foundation

/// Ustawienia aplikacji w UserDefaults (token trzyma KeychainStore).
public final class SettingsStore {
    private let defaults: UserDefaults

    private enum Key {
        static let watched = "watchedProjectIDs"
        static let notifySuccess = "notifySuccess"
        static let notifyFailure = "notifyFailure"
        static let teamID = "teamID"
    }

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

    /// nil = konto osobiste.
    public var teamID: String? {
        get { defaults.string(forKey: Key.teamID) }
        set {
            if let newValue { defaults.set(newValue, forKey: Key.teamID) }
            else { defaults.removeObject(forKey: Key.teamID) }
        }
    }
}
