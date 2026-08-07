import Foundation
import AppKit
import UserNotifications
import VercelBarKit

/// Wysyła powiadomienia systemowe i otwiera deploy po kliknięciu.
/// UNUserNotificationCenter wymaga bundla .app — przy `swift run` tylko logujemy.
///
/// Dwie drogi wysyłki. Natywna (UNUserNotificationCenter) daje klikalny baner,
/// ale macOS przyznaje ją tylko aplikacjom, którym ufa. Przy podpisie, którego
/// system nie zna, `requestAuthorization` potrafi nigdy nie zawołać callbacka —
/// dialog zgody się nie pokazuje i żadne powiadomienie nie wychodzi. Wtedy
/// wchodzi droga zapasowa przez osascript, która działa niezależnie od podpisu.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    /// Presenter to singleton żyjący całą sesję, więc język bierzemy w chwili wysyłki —
    /// inaczej powiadomienia zostałyby w języku sprzed przełączenia w Ustawieniach.
    private var currentL10n: L10n {
        L10n(lang: Lang.effective(override: SettingsStore().languageOverride))
    }

    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    /// Czy wolno korzystać z drogi natywnej. Domyślnie nie — dopiero potwierdzone
    /// uprawnienie je włącza. Czytane i pisane wyłącznie na głównym wątku.
    private var nativeAllowed = false

    /// Ile czekamy na odpowiedź systemu o uprawnieniach. Bez limitu milczenie
    /// systemu zablokowałoby powiadomienia na zawsze — po limicie idziemy drogą zapasową.
    private static let settingsTimeout: TimeInterval = 3

    func setUp() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Odpalamy i idziemy dalej: przy podpisie, któremu system nie ufa,
        // ten callback nie przychodzi nigdy. O stan pytamy osobno, z limitem czasu.
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        checkAuthorization()
    }

    /// Pyta o faktyczny stan uprawnień i zapisuje wynik. Odpowiedź po limicie
    /// czasu jest ignorowana — inaczej stan przełączyłby się w środku sesji.
    private func checkAuthorization() {
        var answered = false
        let deadline = DispatchWorkItem { [weak self] in
            guard !answered else { return }
            answered = true
            self?.nativeAllowed = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settingsTimeout, execute: deadline)

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let granted = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            DispatchQueue.main.async {
                guard !answered else { return }
                answered = true
                deadline.cancel()
                self.nativeAllowed = granted
            }
        }
    }

    func show(event: DeployEvent) {
        let l10n = currentL10n
        let d = event.deployment
        let branch = d.branch ?? "?"
        let title: String
        let body: String
        let url: URL?
        switch event.kind {
        case .started:
            title = l10n.deployStartedTitle(project: event.projectName)
            body = l10n.deployStartedBody(branch: branch)
            url = d.inspectorURL ?? d.previewURL // buduje się — jest co pokazać tylko w logach
        case .failed:
            title = l10n.deployFailedTitle(project: event.projectName)
            body = l10n.deployFailedBody(branch: branch)
            url = d.inspectorURL ?? d.previewURL
        case .succeeded:
            title = l10n.deploySucceededTitle(project: event.projectName)
            body = l10n.deploySucceededBody(branch: branch, duration: d.duration)
            url = d.previewURL ?? d.inspectorURL
        }

        guard available else {
            print("POWIADOMIENIE: \(title) — \(body)")
            return
        }
        guard nativeAllowed else {
            showViaAppleScript(title: title, body: body)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default // bez tego baner wchodzi bezgłośnie i ginie w kącie ekranu
        if let url { content.userInfo = ["url": url.absoluteString] }
        let request = UNNotificationRequest(identifier: "\(d.id).\(event.kind)",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func showTokenInvalid() {
        let l10n = currentL10n
        send(title: l10n.tokenInvalidNotificationTitle,
             body: l10n.tokenInvalidNotificationBody,
             identifier: "token-invalid")
    }

    /// Powiadomienie z przycisku w Ustawieniach — pokazuje, którą drogą
    /// aplikacja faktycznie wysyła i czy w ogóle coś dociera.
    func showTest() {
        let l10n = currentL10n
        send(title: l10n.testNotificationTitle,
             body: l10n.testNotificationBody,
             identifier: "test-notification")
    }

    /// Powiadomienie bez URL-a: natywnie albo drogą zapasową.
    private func send(title: String, body: String, identifier: String) {
        guard available else {
            print("POWIADOMIENIE: \(title) — \(body)")
            return
        }
        guard nativeAllowed else {
            showViaAppleScript(title: title, body: body)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    /// Powiadomienie przez systemowy mechanizm skryptów — działa nawet, gdy macOS
    /// nie ufa naszemu podpisowi. Tytuł i treść idą argumentami: komunikat commita
    /// może zawierać cudzysłowy i nie wolno mu trafić do kodu skryptu.
    ///
    /// Ograniczenie: baner z tej drogi nie należy do nas, więc kliknięcie w niego
    /// nie otwiera deployu (wiersz w popoverze nadal otwiera).
    private func showViaAppleScript(title: String, body: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ScriptNotification.arguments(title: title, body: body)
        try? p.run()
    }

    // Klik w powiadomienie otwiera deploy.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let raw = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: raw) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }

    // Pokazuj banery także, gdy aplikacja jest „aktywna" (menu bar app zwykle jest).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
