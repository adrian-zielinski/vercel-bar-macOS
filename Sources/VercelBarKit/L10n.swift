import Foundation

/// Język UI. Domyślnie za systemem (polski system → pl, każdy inny → en),
/// z możliwością ręcznego wyboru w Ustawieniach.
/// `String` rawValue niesie zapis w UserDefaults („pl"/„en").
public enum Lang: String, Sendable, Equatable {
    case pl
    case en

    /// `preferred` wstrzykiwane w testach; produkcyjnie Locale.preferredLanguages
    /// respektuje też per-aplikacyjne nadpisanie (argument -AppleLanguages).
    public static func system(preferred: [String] = Locale.preferredLanguages) -> Lang {
        preferred.first?.lowercased().hasPrefix("pl") == true ? .pl : .en
    }

    /// Język faktycznie użyty: ręczny wybór z Ustawień, a bez niego system.
    public static func effective(override: Lang?,
                                 preferred: [String] = Locale.preferredLanguages) -> Lang {
        override ?? system(preferred: preferred)
    }
}

/// Teksty UI. Widoki dostają instancję przez Environment (`\.l10n`), więc zmiana
/// języka w Ustawieniach przerysowuje je od razu.
public struct L10n: Sendable {
    public let lang: Lang

    public init(lang: Lang = .system()) { self.lang = lang }

    private func t(_ pl: String, _ en: String) -> String { lang == .pl ? pl : en }

    // MARK: popover

    public func refreshedAt(_ clock: String) -> String {
        t("odświeżono \(clock)", "refreshed \(clock)")
    }

    public var headlineOffline: String { t("Brak połączenia", "No connection") }
    public var headlineTokenInvalid: String { t("Token nieprawidłowy", "Invalid token") }

    public var onboardingMessage: String {
        t("Połącz konto Vercela, aby widzieć swoje deploye w pasku menu.",
          "Connect your Vercel account to see your deploys in the menu bar.")
    }

    public var connectButton: String { t("Połącz z Vercelem", "Connect to Vercel") }

    public var offlineMessage: String {
        t("Brak połączenia z internetem. Wznowię monitorowanie automatycznie.",
          "No internet connection. Monitoring will resume automatically.")
    }

    public var tokenInvalidMessage: String {
        t("Token dostępu został odrzucony przez Vercela. Wklej nowy w Ustawieniach.",
          "Vercel rejected the access token. Paste a new one in Settings.")
    }

    public var openSettingsButton: String { t("Otwórz Ustawienia", "Open Settings") }

    public var emptyWatchedMessage: String {
        t("Zaznacz projekty do obserwowania w Ustawieniach.",
          "Select projects to watch in Settings.")
    }

    public var footerRefresh: String { t("Odśwież", "Refresh") }
    public var footerSettings: String { t("Ustawienia", "Settings") }
    public var footerQuit: String { t("Zakończ", "Quit") }

    public var noCommitInfo: String { t("brak danych o commicie", "no commit info") }

    public var rowOpensInBrowserHint: String {
        t("Otwiera deploy w przeglądarce", "Opens the deploy in your browser")
    }

    // MARK: ustawienia

    public var settingsWindowTitle: String { t("Ustawienia VercelBar", "VercelBar Settings") }
    public var tabAccount: String { t("Konto", "Account") }
    public var tabProjects: String { t("Projekty", "Projects") }

    public var accessTokenLabel: String { t("Token dostępu", "Access token") }
    public var tokenPlaceholder: String { t("wklej token…", "paste token…") }
    public var saveButton: String { t("Zapisz", "Save") }

    public var tokenHintDefault: String {
        t("Token z panelu Vercela → Account Settings → Tokens. Zakres (scope): konto lub zespół, który chcesz obserwować.",
          "Token from Vercel → Account Settings → Tokens. Scope: the account or team you want to watch.")
    }

    public var tokenHintRejected: String {
        t("Vercel odrzucił ten token. Sprawdź, czy skopiowany w całości.",
          "Vercel rejected this token. Make sure you copied it in full.")
    }

    public var tokenHintNetwork: String {
        t("Brak połączenia z Vercelem. Sprawdź internet i spróbuj ponownie.",
          "Can't reach Vercel. Check your connection and try again.")
    }

    public var tokenHintKeychainFailure: String {
        t("Token poprawny, ale zapis w pęku kluczy się nie powiódł. Otwórz Keychain Access i sprawdź dostęp.",
          "Token is valid, but saving to the keychain failed. Open Keychain Access and check permissions.")
    }

    public var tokenHintUnexpectedResponse: String {
        t("Vercel odpowiedział w nieoczekiwanym formacie — to problem aplikacji, nie tokenu. Zgłoś to autorowi.",
          "Vercel responded in an unexpected format — this is an app issue, not your token. Please report it.")
    }

    public var connectionLabel: String { t("Połączenie", "Connection") }
    public var notConnected: String { t("Nie połączono", "Not connected") }
    public var connected: String { t("Połączono", "Connected") }
    public var pasteTokenAbove: String { t("Wklej token powyżej", "Paste your token above") }

    public var teamLabel: String { t("Zespół", "Team") }
    public var personalAccount: String { t("Konto osobiste", "Personal account") }

    /// Zespół jeszcze nieznany z listy — pokazujemy sam prefiks id.
    public func unknownTeam(idPrefix: String) -> String {
        t("Zespół (\(idPrefix)…)", "Team (\(idPrefix)…)")
    }

    public var searchProjectsPlaceholder: String { t("Szukaj projektów", "Search projects") }

    public func monitoredCount(_ n: Int, _ m: Int) -> String {
        t("\(n) z \(m) projektów monitorowanych", "\(n) of \(m) projects monitored")
    }

    public var projectsEmptyOffline: String {
        t("Brak połączenia z Vercelem.", "Can't reach Vercel.")
    }

    public var projectsEmptyLoading: String {
        t("Wczytywanie projektów…", "Loading projects…")
    }

    public var projectsEmptyNoToken: String {
        t("Połącz konto w zakładce Konto.", "Connect your account in the Account tab.")
    }

    public var languageLabel: String { t("Język", "Language") }
    /// Nazwy samych języków („Polski", „English") celowo nietłumaczone — każdy ma
    /// rozpoznać swój w liście. Tłumaczymy tylko pozycję „za systemem".
    public var languageSystem: String { t("Systemowy", "System") }

    public var feedLimitLabel: String { t("Historia deployów", "Deploy history") }
    public var launchAtLogin: String { t("Uruchamiaj przy logowaniu", "Launch at login") }
    public var notifySuccess: String { t("Powiadamiaj o sukcesach", "Notify on successful deploys") }
    public var notifyFailure: String { t("Powiadamiaj o błędach", "Notify on failed deploys") }
    public var notifyStart: String { t("Powiadamiaj o starcie deployu", "Notify when a deploy starts") }

    public var loginItemNeedsApproval: String {
        t("Zatwierdź w Ustawieniach systemowych → Elementy logowania",
          "Approve in System Settings → Login Items")
    }

    // MARK: aktualizacje

    public func updateAvailable(version: String) -> String {
        t("Dostępna wersja \(version)", "Version \(version) available")
    }

    public var updateInstallButton: String { t("Zaktualizuj", "Update") }
    public var updateDownloading: String { t("Pobieranie…", "Downloading…") }
    public var updateInstalling: String { t("Instalowanie…", "Installing…") }

    public var updateFailed: String {
        t("Aktualizacja się nie udała. Otworzyłem stronę wydania.",
          "The update failed. The release page is open in your browser.")
    }

    /// Paczka dojechała, ale nie nadaje się do instalacji — to wina wydania, nie komputera.
    public var updateDamaged: String {
        t("Paczka aktualizacji jest uszkodzona. Otworzyłem stronę wydania.",
          "The update package is damaged. The release page is open in your browser.")
    }

    /// Wynik ręcznego sprawdzenia w Ustawieniach, gdy coś się znalazło — sam pasek
    /// z przyciskiem siedzi w popoverze, więc tutaj kierujemy tam wzrok.
    public func updateFound(version: String) -> String {
        t("Znaleziono wersję \(version) — zobacz w pasku menu",
          "Found version \(version) — see the menu bar")
    }

    public var checkForUpdates: String { t("Sprawdź aktualizacje", "Check for updates") }
    public var upToDate: String { t("Masz najnowszą wersję", "You're up to date") }

    public func versionLabel(version: String) -> String {
        t("Wersja \(version)", "Version \(version)")
    }

    // MARK: powiadomienia

    public func deployStartedTitle(project: String) -> String {
        t("🚀 \(project): deploy ruszył", "🚀 \(project): deploy started")
    }

    public func deployStartedBody(branch: String) -> String {
        t("\(branch) · buduje się. Kliknij, aby otworzyć szczegóły.",
          "\(branch) · building. Click to open details.")
    }

    public func deployFailedTitle(project: String) -> String {
        t("❌ \(project): deploy padł", "❌ \(project): deploy failed")
    }

    public func deployFailedBody(branch: String) -> String {
        t("\(branch) · build przerwany. Kliknij, aby otworzyć logi.",
          "\(branch) · build failed. Click to open the logs.")
    }

    public func deploySucceededTitle(project: String) -> String {
        t("✅ \(project) wdrożony", "✅ \(project) deployed")
    }

    /// Czas trwania opcjonalny — API nie zawsze go podaje, a zdanie ma brzmieć naturalnie bez niego.
    public func deploySucceededBody(branch: String, duration: TimeInterval?) -> String {
        let pl = duration.map { " w " + Format.duration($0) } ?? ""
        let en = duration.map { " in " + Format.duration($0) } ?? ""
        return t("\(branch) · gotowe\(pl). Kliknij, aby otworzyć podgląd.",
                 "\(branch) · ready\(en). Click to open the preview.")
    }

    public var tokenInvalidNotificationTitle: String {
        t("VercelBar: token nieprawidłowy", "VercelBar: invalid token")
    }

    public var tokenInvalidNotificationBody: String {
        t("Otwórz Ustawienia i wklej nowy token dostępu.",
          "Open Settings and paste a new access token.")
    }

    public var sendTestNotification: String {
        t("Testuj powiadomienie", "Test notification")
    }

    public var testNotificationTitle: String {
        t("VercelBar działa", "VercelBar is working")
    }

    public var testNotificationBody: String {
        t("Tak będą wyglądać powiadomienia o deployach.",
          "This is how deploy notifications will look.")
    }
}
