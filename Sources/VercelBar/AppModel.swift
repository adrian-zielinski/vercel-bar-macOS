import Foundation
import AppKit
import SwiftUI
import VercelBarKit

/// Stan aplikacji i pętla odpytywania.
@MainActor
final class AppModel: ObservableObject {

    enum Phase: Equatable {
        case onboarding      // brak tokenu
        case tokenInvalid    // 401 z API
        case offline         // błąd transportu
        case normal
    }

    enum ConnectResult: Equatable {
        case ok
        case rejected        // Vercel odrzucił token (albo pusty)
        case keychainFailure // token poprawny, ale zapis do pęku się nie powiódł
    }

    @Published var phase: Phase = .onboarding
    @Published var projects: [Project] = []
    @Published var allProjects: [Project] = []   // do listy w Ustawieniach
    @Published var overall: AggregateState = .idle
    @Published var anyActive = false // z migawki; overall == .error może maskować trwający build
    @Published var lastRefreshed: Date?
    @Published var iconAlpha: Double = 1
    @Published var account: VercelUser?
    @Published var teams: [Team] = []
    @Published var hasToken = false // dla UI — widoki nie dotykają Keychaina w body

    let keychain = KeychainStore()
    let settings = SettingsStore()

    private var engine = NotificationEngine()
    private var pollTask: Task<Void, Never>?
    private var pulseTimer: Timer?
    private var tokenAlertShown = false
    private var started = false
    private var consecutiveFailures = 0 // backoff dla 429/5xx
    private var refreshInFlight = false

    var iconState: AggregateState {
        switch phase {
        case .normal: return overall
        default: return .idle
        }
    }

    /// Idempotentny — wołany z onAppear etykiety paska menu i popovera.
    func start() {
        guard !started else { return }
        started = true
        NotificationPresenter.shared.setUp()
        // Odśwież po obudzeniu Maca ze snu.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        do {
            let stored = try keychain.readToken()
            hasToken = stored != nil
            guard hasToken else { phase = .onboarding; return }
        } catch {
            // Pęk chwilowo niedostępny (np. ACL po aktualizacji podpisu) — nie zakładaj braku
            // tokenu; pętla odpytywania da odczytowi kolejne szanse.
            hasToken = true
        }
        phase = .normal
        restartPolling()
    }

    func restartPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let self else { return }
                let base = PollScheduler.interval(anyActive: self.anyActive)
                let delay = PollScheduler.delay(base: base,
                                                consecutiveFailures: self.consecutiveFailures)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    func refresh() async {
        // Osłona przed reentrancją: pętla + przycisk Odśwież + didWake mogą się nałożyć,
        // a starsza migawka podana do ingest po nowszej wystrzeliłaby stare zdarzenia.
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }
        let storedToken: String?
        do { storedToken = try keychain.readToken() } catch {
            return // Keychain chwilowo niedostępny (np. po aktualizacji podpisu) — nie zrywaj sesji
        }
        guard let token = storedToken else { phase = .onboarding; hasToken = false; return }
        let api = VercelAPI(token: token, teamID: settings.teamID)
        do {
            let snapshot = try await RefreshCore.fetch(api: api,
                                                       watchedProjectIDs: settings.watchedProjectIDs)
            withAnimation(reduceMotion ? nil : .spring(duration: 0.22)) {
                projects = snapshot.projects
                overall = snapshot.overall
                anyActive = snapshot.anyActive
                phase = .normal
            }
            lastRefreshed = Date()
            consecutiveFailures = 0
            updatePulse(active: snapshot.overall == .building)

            for event in engine.ingest(projects: snapshot.projects) {
                let wanted = event.kind == .failed ? settings.notifyFailure : settings.notifySuccess
                if wanted { NotificationPresenter.shared.show(event: event) }
            }
        } catch VercelAPIError.unauthorized {
            phase = .tokenInvalid
            updatePulse(active: false)
            if !tokenAlertShown {
                tokenAlertShown = true
                NotificationPresenter.shared.showTokenInvalid()
            }
        } catch VercelAPIError.offline {
            phase = .offline
            updatePulse(active: false)
        } catch is CancellationError {
            // Anulowany polling (restart pętli) — nie zmieniaj stanu.
        } catch {
            // 429/5xx/dekodowanie: zostaw poprzednie dane; pętla ponowi z backoffem.
            consecutiveFailures += 1
        }
    }

    /// Walidacja tokenu i zapis.
    func connect(token: String) async -> ConnectResult {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .rejected }
        do {
            let api = VercelAPI(token: trimmed)
            account = try await api.user()
            teams = (try? await api.teams()) ?? []
            try keychain.writeToken(trimmed)
            hasToken = true
            tokenAlertShown = false
            phase = .normal
            await loadAllProjects()
            restartPolling()
            return .ok
        } catch is KeychainStore.KeychainError {
            return .keychainFailure
        } catch {
            return .rejected
        }
    }

    /// Lista wszystkich projektów dla Ustawień (zakładka Projekty).
    func loadAllProjects() async {
        guard let token = (try? keychain.readToken()) ?? nil else { return }
        let api = VercelAPI(token: token, teamID: settings.teamID)
        allProjects = (try? await api.projects()) ?? []
        if account == nil { account = try? await api.user() }
        if teams.isEmpty { teams = (try? await VercelAPI(token: token).teams()) ?? [] }
    }

    func toggleWatched(projectID: String) {
        var ids = settings.watchedProjectIDs
        if ids.contains(projectID) { ids.remove(projectID) } else { ids.insert(projectID) }
        settings.watchedProjectIDs = ids
        Task { await refresh() }
    }

    func selectTeam(id: String?) {
        settings.teamID = id
        engine = NotificationEngine() // nowy scope → nowy baseline
        Task {
            await loadAllProjects()
            await refresh()
        }
    }

    // MARK: puls ikony przy buildzie

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func updatePulse(active: Bool) {
        if active && !reduceMotion {
            guard pulseTimer == nil else { return }
            let start = Date()
            pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    let phase = (Date().timeIntervalSince(start)).truncatingRemainder(dividingBy: 1.1) / 1.1
                    self?.iconAlpha = StatusIconRenderer.pulseAlpha(phase: phase)
                }
            }
        } else {
            pulseTimer?.invalidate()
            pulseTimer = nil
            iconAlpha = 1
        }
    }
}
