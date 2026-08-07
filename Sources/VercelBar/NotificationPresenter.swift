import Foundation
import AppKit
import UserNotifications
import VercelBarKit

/// Wysyła powiadomienia systemowe i otwiera deploy po kliknięciu.
/// UNUserNotificationCenter wymaga bundla .app — przy `swift run` tylko logujemy.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    private let l10n = L10n()

    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func setUp() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func show(event: DeployEvent) {
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
        guard available else { print("POWIADOMIENIE: \(l10n.tokenInvalidNotificationTitle)"); return }
        let content = UNMutableNotificationContent()
        content.title = l10n.tokenInvalidNotificationTitle
        content.body = l10n.tokenInvalidNotificationBody
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "token-invalid", content: content, trigger: nil))
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
