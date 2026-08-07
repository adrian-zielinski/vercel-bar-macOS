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
        case network         // nie dojechaliśmy do Vercela — token nie jest niczemu winien
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
    private var keychainReadFailures = 0 // pojedyncza czkawka pęku ≠ utrata sesji
    private var refreshInFlight = false
    private var refreshQueued = false

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

    /// Osłona przed reentrancją: pętla + przycisk Odśwież + didWake mogą się nałożyć,
    /// a starsza migawka podana do ingest po nowszej wystrzeliłaby stare zdarzenia.
    func refresh() async {
        // Koalescencja: żądanie w trakcie trwającego cyklu wykona się zaraz po nim,
        // zamiast ginąć (toggle projektu, przycisk Odśwież, didWake).
        if refreshInFlight { refreshQueued = true; return }
        refreshInFlight = true
        repeat {
            refreshQueued = false
            await performRefresh()
        } while refreshQueued
        refreshInFlight = false
    }

    private func performRefresh() async {
        // SecItemCopyMatching jest synchroniczne i przy systemowym promptcie potrafi stanąć
        // na kilka sekund — na MainActorze zamroziłoby ikonę paska menu.
        let kc = keychain
        let readResult: Result<String?, Error> = await Task.detached { Result { try kc.readToken() } }.value
        let storedToken: String?
        switch readResult {
        case .success(let value):
            storedToken = value
            keychainReadFailures = 0
        case .failure:
            // Chwilowa niedostępność pęku (np. ACL po aktualizacji podpisu) nie zrywa sesji;
            // dopiero seria porażek znaczy trwały problem i wymaga wyjścia przez Ustawienia.
            keychainReadFailures += 1
            if keychainReadFailures >= 3 {
                phase = .tokenInvalid
                updatePulse(active: false)
            }
            return
        }
        guard let token = storedToken else {
            phase = .onboarding
            hasToken = false
            updatePulse(active: false) // bez tego ikona pulsuje dalej po usunięciu tokenu
            return
        }
        let api = VercelAPI(token: token, teamID: settings.teamID)
        do {
            let snapshot = try await RefreshCore.fetch(api: api,
                                                       watchedProjectIDs: settings.watchedProjectIDs)
            withAnimation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.3)) {
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
            consecutiveFailures += 1 // bez sensu młócić 401 co 30 s; connect() zeruje licznik
            updatePulse(active: false)
            if !tokenAlertShown {
                tokenAlertShown = true
                NotificationPresenter.shared.showTokenInvalid()
            }
        } catch VercelAPIError.offline {
            phase = .offline
            anyActive = false // stara migawka nie może trzymać pętli na 10 s bez sieci
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
            let user = try await api.user()
            // Stan „Połączono" dopiero po udanym zapisie — inaczej przy porażce pęku
            // UI melduje połączenie, którego następny odczyt tokenu nie potwierdzi.
            try keychain.writeToken(trimmed)
            account = user
            teams = (try? await api.teams()) ?? []
            hasToken = true
            tokenAlertShown = false
            keychainReadFailures = 0
            consecutiveFailures = 0 // świeży token wraca do pełnego tempa, bez backoffu po 401
            phase = .normal
            await loadAllProjects()
            restartPolling()
            return .ok
        } catch let e as VercelAPIError {
            // Brak sieci, 429 i 5xx nie mówią nic o tokenie — nie zwalaj na niego winy.
            switch e {
            case .offline, .rateLimited, .server: return .network
            default: return .rejected
            }
        } catch is KeychainStore.KeychainError {
            return .keychainFailure
        } catch {
            return .rejected
        }
    }

    /// Lista wszystkich projektów dla Ustawień (zakładka Projekty).
    func loadAllProjects() async {
        let kc = keychain
        let stored: String? = await Task.detached { (try? kc.readToken()) ?? nil }.value
        guard let token = stored else { return }
        let api = VercelAPI(token: token, teamID: settings.teamID)
        if let fetched = try? await api.projects() { allProjects = fetched } // błąd nie zeruje listy
        if account == nil { account = try? await api.user() }
        if teams.isEmpty { teams = (try? await VercelAPI(token: token).teams()) ?? [] }
    }

    func toggleWatched(projectID: String) {
        var ids = settings.watchedProjectIDs
        if ids.contains(projectID) { ids.remove(projectID) } else { ids.insert(projectID) }
        // SettingsStore to zwykła klasa nad UserDefaults, nie ObservableObject — bez tego
        // licznik w Ustawieniach czeka na przerysowanie aż do końca refresh(), a gdy
        // refresh odbije się od refreshInFlight albo padnie na 5xx, nie doczeka się wcale.
        objectWillChange.send()
        settings.watchedProjectIDs = ids
        Task { await refresh() }
    }

    func selectTeam(id: String?) {
        objectWillChange.send()
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
