import AppKit
import Foundation
import Security
import VercelBarKit

// Lekki harness testowy (wzorzec skryba-tests; nie wymaga XCTest ani Xcode).

final class Runner {
    var passed = 0
    var failed = 0
    var skipped = 0
    var failures: [String] = []

    func suite(_ name: String) { print("\n▸ \(name)") }

    func check(_ condition: Bool, _ message: String) {
        if condition { passed += 1; print("  ✓ \(message)") }
        else { failed += 1; failures.append(message); print("  ✗ \(message)") }
    }

    func equal<T: Equatable>(_ a: T, _ b: T, _ message: String) {
        if a == b { check(true, message) }
        else { check(false, "\(message)  [oczekiwano: \(b), jest: \(a)]") }
    }

    // Dla przypadków niedostępnych w danym środowisku (np. Keychain w CI).
    func skip(_ message: String) { skipped += 1; print("  ⤼ POMINIĘTO: \(message)") }

    func finish() -> Never {
        if !failures.isEmpty {
            print("\nNiezaliczone:")
            for f in failures { print("  ✗ \(f)") }
        }
        print("\n— Wynik: \(passed) zaliczonych, \(failed) niezaliczonych, \(skipped) pominiętych —")
        fflush(stdout)
        exit(failed == 0 ? 0 : 1)
    }
}

let t = Runner()

t.suite("Harness")
t.check(true, "runner działa")

// MARK: - Modele i dekodowanie API

/// Dekoduje fixture i zwraca pierwszy deployment; porażkę odnotowuje zamiast ubijać runner.
func firstDeployment(_ json: String, _ label: String) -> DeploymentSummary? {
    do {
        guard let d = try APIDecoding.deployments(from: Data(json.utf8)).first else {
            t.check(false, "\(label): pusta lista deploymentów")
            return nil
        }
        return d
    } catch {
        t.check(false, "\(label): dekodowanie rzuciło: \(error)")
        return nil
    }
}

t.suite("DeployState")
t.equal(DeployState(rawAPI: "READY"), .ready, "READY parsuje się")
t.equal(DeployState(rawAPI: "error"), .error, "wielkość liter bez znaczenia")
t.equal(DeployState(rawAPI: "INITIALIZING"), .initializing, "INITIALIZING parsuje się")
t.equal(DeployState(rawAPI: "COŚNOWEGO"), .unknown, "nieznany stan spada do unknown")
t.equal(DeployState(rawAPI: ""), .unknown, "pusty stan spada do unknown")
t.check(DeployState.building.isActive && DeployState.queued.isActive && DeployState.initializing.isActive,
        "building/queued/initializing są aktywne")
t.check(!DeployState.ready.isActive && !DeployState.error.isActive && !DeployState.canceled.isActive,
        "ready/error/canceled nie są aktywne")
t.check(!DeployState.unknown.isActive, "unknown nie jest aktywny")

t.suite("Dekodowanie /v6/deployments")
let deploymentsJSON = Data("""
{"deployments":[{
  "uid":"dpl_abc123",
  "name":"sklep-online",
  "state":"BUILDING",
  "url":"sklep-online-git-feat-koszyk.vercel.app",
  "inspectorUrl":"https://vercel.com/studio-nord/sklep-online/dpl_abc123",
  "createdAt":1754470000000,
  "buildingAt":1754470005000,
  "meta":{"githubCommitRef":"feat/koszyk","githubCommitMessage":"dodaj podsumowanie zamówienia"}
}]}
""".utf8)
do {
    let list = try APIDecoding.deployments(from: deploymentsJSON)
    t.equal(list.count, 1, "jeden deployment")
    if let d = list.first {
        t.equal(d.id, "dpl_abc123", "id z uid")
        t.equal(d.state, .building, "stan BUILDING")
        t.equal(d.branch, "feat/koszyk", "gałąź z meta github")
        t.equal(d.commitMessage, "dodaj podsumowanie zamówienia", "commit z meta github")
        t.equal(d.previewURL?.absoluteString, "https://sklep-online-git-feat-koszyk.vercel.app", "previewURL dostaje https://")
        t.equal(d.inspectorURL?.absoluteString, "https://vercel.com/studio-nord/sklep-online/dpl_abc123", "inspectorURL wprost")
        t.equal(d.createdAt, Date(timeIntervalSince1970: 1_754_470_000), "createdAt z milisekund")
        t.equal(d.buildingAt, Date(timeIntervalSince1970: 1_754_470_005), "buildingAt z milisekund")
        t.equal(d.duration, nil, "brak duration bez ready")
    } else { t.check(false, "pusta lista deploymentów") }
} catch { t.check(false, "dekodowanie deploymentów rzuciło: \(error)") }

t.suite("Dekodowanie deploymentu READY + duration")
if let d = firstDeployment("""
{"deployments":[{
  "uid":"dpl_done","state":"READY","createdAt":1754470000000,
  "buildingAt":1754470002000,"ready":1754470040000,
  "meta":{"gitlabCommitRef":"main","gitlabCommitMessage":"aktualizacja zależności"}
}]}
""", "READY") {
    t.equal(d.duration, 38, "duration = ready − buildingAt")
    t.equal(d.branch, "main", "gałąź z meta gitlab")
}

t.suite("Fallbacki i odporność dekodera")

if let d = firstDeployment(#"{"deployments":[{"uid":"m","state":"READY","meta":{"githubCommitRef":"main","buildId":123}}]}"#,
                           "meta z liczbą") {
    t.equal(d.branch, "main", "nie-stringowa wartość w meta nie wywala koperty")
}

if let d = firstDeployment(#"{"deployments":[{"uid":"x","ready":1754470040000}]}"#, "brak createdAt") {
    t.equal(d.createdAt, nil, "brak createdAt zostaje nil")
    t.equal(d.duration, nil, "duration nil bez punktu startu")
    t.equal(d.state, .unknown, "brak state i readyState → unknown")
}

if let d = firstDeployment(#"{"deployments":[{"uid":"r","readyState":"READY"}]}"#, "readyState") {
    t.equal(d.state, .ready, "stan czytany z readyState")
}

if let d = firstDeployment(#"{"deployments":[{"uid":"c","created":1754470000000}]}"#, "created") {
    t.equal(d.createdAt, Date(timeIntervalSince1970: 1_754_470_000), "createdAt czytany z created")
}

if let d = firstDeployment(#"{"deployments":[{"uid":"b","meta":{"bitbucketCommitRef":"hotfix/logo","bitbucketCommitMessage":"popraw logo"}}]}"#,
                           "bitbucket") {
    t.equal(d.branch, "hotfix/logo", "gałąź z meta bitbucket")
    t.equal(d.commitMessage, "popraw logo", "commit z meta bitbucket")
}

if let d = firstDeployment(#"{"deployments":[{"uid":"d","state":"READY","createdAt":1754470000000,"ready":1754470030000}]}"#,
                           "duration bez buildingAt") {
    t.equal(d.duration, 30, "bez buildingAt duration liczone od createdAt")
}

if let d = firstDeployment(#"{"deployments":[{"uid":"u","url":"https://x.vercel.app"}]}"#, "url ze schematem") {
    t.equal(d.previewURL?.absoluteString, "https://x.vercel.app", "gotowy schemat nie jest doklejany drugi raz")
}

do {
    t.equal(try APIDecoding.deployments(from: Data(#"{"deployments":[]}"#.utf8)).count, 0, "pusta lista deploymentów")
} catch { t.check(false, "pusta lista rzuciła: \(error)") }

t.suite("Dekodowanie /v9/projects, /v2/user, /v2/teams")
let projectsJSON = Data("""
{"projects":[{"id":"prj_1","name":"sklep-online"},{"id":"prj_2","name":"blog-firmowy"}]}
""".utf8)
do {
    let ps = try APIDecoding.projects(from: projectsJSON)
    t.equal(ps.map(\.id), ["prj_1", "prj_2"], "projekty: id")
    t.equal(ps.map(\.name), ["sklep-online", "blog-firmowy"], "projekty: nazwy")
} catch { t.check(false, "dekodowanie projektów rzuciło: \(error)") }

let userJSON = Data(#"{"user":{"uid":"u_1","username":"marta","name":"Marta Kowalska"}}"#.utf8)
do {
    let u = try APIDecoding.user(from: userJSON)
    t.equal(u.username, "marta", "username")
    t.equal(u.name, "Marta Kowalska", "pełna nazwa")
} catch { t.check(false, "dekodowanie usera rzuciło: \(error)") }

let teamsJSON = Data(#"{"teams":[{"id":"team_1","name":"Studio Nord","slug":"studio-nord"}]}"#.utf8)
do {
    let ts = try APIDecoding.teams(from: teamsJSON)
    t.equal(ts.first?.slug, "studio-nord", "team slug")
} catch { t.check(false, "dekodowanie teamów rzuciło: \(error)") }

// MARK: - Agregacja stanu

t.suite("StatusAggregator")
t.equal(StatusAggregator.aggregate([.ready, .ready]), .ready, "same ready → ready")
t.equal(StatusAggregator.aggregate([.ready, .building]), .building, "building wygrywa z ready")
t.equal(StatusAggregator.aggregate([.building, .error]), .error, "error wygrywa ze wszystkim")
t.equal(StatusAggregator.aggregate([.ready, .queued]), .building, "queued liczy się jak building")
t.equal(StatusAggregator.aggregate([.ready, .initializing]), .building, "initializing liczy się jak building")
t.equal(StatusAggregator.aggregate([.canceled, .ready]), .ready, "canceled nie zmienia stanu")
t.equal(StatusAggregator.aggregate([.canceled]), .idle, "same canceled → idle")
t.equal(StatusAggregator.aggregate([.unknown, .ready]), .ready, "unknown nie zmienia stanu")
t.equal(StatusAggregator.aggregate([.unknown]), .idle, "same unknown → idle")
t.equal(StatusAggregator.aggregate([]), .idle, "pusto → idle")

t.suite("Nagłówek popovera")
t.equal(StatusAggregator.headline(for: [.ready, .ready]), "Wszystko wdrożone", "nagłówek ready")
t.equal(StatusAggregator.headline(for: [.ready, .building]), "Build w toku…", "nagłówek building")
t.equal(StatusAggregator.headline(for: [.error, .ready]), "1 deploy padł", "nagłówek 1 błąd")
t.equal(StatusAggregator.headline(for: [.error, .error, .ready]), "2 deploye padły", "nagłówek 2 błędy")
t.equal(StatusAggregator.headline(for: [.error, .error, .error, .error, .error]), "5 deployów padło", "nagłówek 5 błędów")
t.equal(StatusAggregator.headline(for: Array(repeating: .error, count: 12)), "12 deployów padło", "nagłówek 12 błędów (nastki)")
t.equal(StatusAggregator.headline(for: Array(repeating: .error, count: 21)), "21 deployów padło", "nagłówek 21 błędów (końcówka 1)")
t.equal(StatusAggregator.headline(for: Array(repeating: .error, count: 22)), "22 deploye padły", "nagłówek 22 błędów")
t.equal(StatusAggregator.headline(for: []), "Brak obserwowanych projektów", "nagłówek pusty")
t.equal(StatusAggregator.headline(for: [.canceled, .unknown]), "Brak aktywnych deployów", "canceled + unknown → brak aktywnych, nie brak projektów")

t.suite("PollScheduler")
t.equal(PollScheduler.interval(anyActive: false), 30, "spokój → 30 s")
t.equal(PollScheduler.interval(anyActive: true), 10, "build w toku → 10 s")

t.suite("PollScheduler.delay — backoff")
t.equal(PollScheduler.delay(base: 30, consecutiveFailures: 0), 30, "0 porażek → base")
t.equal(PollScheduler.delay(base: 10, consecutiveFailures: 0), 10, "0 porażek → base także przy buildzie")
t.equal(PollScheduler.delay(base: 30, consecutiveFailures: 1), 60, "1 porażka → 60 s")
t.equal(PollScheduler.delay(base: 30, consecutiveFailures: 2), 120, "2 porażki → 120 s")
t.equal(PollScheduler.delay(base: 30, consecutiveFailures: 3), 240, "3 porażki → 240 s")
t.equal(PollScheduler.delay(base: 30, consecutiveFailures: 4), 300, "4 porażki → sufit 300 s")
t.equal(PollScheduler.delay(base: 10, consecutiveFailures: 1), 60, "backoff ignoruje base")

// MARK: - Formatowanie czasu

t.suite("Format.relative")
let now = Date(timeIntervalSince1970: 1_754_470_000)
func ago(_ s: TimeInterval) -> Date { now.addingTimeInterval(-s) }
t.equal(Format.relative(ago(10), now: now), "teraz", "poniżej 45 s → teraz")
t.equal(Format.relative(ago(44), now: now), "teraz", "44 s → jeszcze teraz")
t.equal(Format.relative(ago(50), now: now), "50 s temu", "sekundy")
t.equal(Format.relative(ago(89), now: now), "89 s temu", "89 s → jeszcze sekundy")
t.equal(Format.relative(ago(90), now: now), "1 min temu", "90 s → już minuty")
t.equal(Format.relative(ago(120), now: now), "2 min temu", "minuty")
t.equal(Format.relative(ago(3600), now: now), "1 godz. temu", "godziny")
t.equal(Format.relative(ago(5 * 3600), now: now), "5 godz. temu", "kilka godzin")
t.equal(Format.relative(ago(86_399), now: now), "23 godz. temu", "tuż przed dobą")
t.equal(Format.relative(ago(86_400), now: now), "wczoraj", "dokładnie doba")
t.equal(Format.relative(ago(30 * 3600), now: now), "wczoraj", "24–48 h → wczoraj")
t.equal(Format.relative(ago(172_800), now: now), "2 dni temu", "dokładnie dwie doby")
t.equal(Format.relative(ago(3 * 86_400), now: now), "3 dni temu", "dni")

t.suite("Format.duration")
t.equal(Format.duration(0), "0 s", "zero")
t.equal(Format.duration(38), "38 s", "sekundy")
t.equal(Format.duration(126), "2 min 06 s", "minuty z zerem wiodącym sekund")
t.equal(Format.duration(60), "1 min 00 s", "równa minuta")
t.equal(Format.duration(3600), "60 min 00 s", "godzina bez rolowania — świadomy wybór")

t.suite("Format.clock")
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Europe/Warsaw")!
let noon = cal.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 12, minute: 4))!
t.equal(Format.clock(noon, timeZone: cal.timeZone), "12:04", "zegar HH:mm")
let afternoon = cal.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 13, minute: 0))!
t.equal(Format.clock(afternoon, timeZone: cal.timeZone), "13:00", "zegar 24-godzinny, nie 1:00 PM")

// MARK: - Silnik powiadomień

func summary(id: String, state: DeployState) -> DeploymentSummary {
    DeploymentSummary(id: id, state: state, branch: "main", commitMessage: "zmiana",
                      createdAt: Date(timeIntervalSince1970: 0), buildingAt: nil, readyAt: nil,
                      previewURL: nil, inspectorURL: nil)
}
func project(_ name: String, id: String, deploy: DeploymentSummary?) -> Project {
    Project(id: id, name: name, latest: deploy)
}

t.suite("NotificationEngine — cisza na starcie")
var engine = NotificationEngine()
let first = engine.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .error))])
t.equal(first, [], "pierwsze pobranie nie powiadamia nawet o błędzie")

t.suite("NotificationEngine — błąd")
var e2 = NotificationEngine()
_ = e2.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .building))])
let errEvents = e2.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .error))])
t.equal(errEvents.count, 1, "building → error daje zdarzenie")
t.equal(errEvents.first?.kind, .failed, "rodzaj: failed")
t.equal(errEvents.first?.projectName, "sklep", "nazwa projektu w zdarzeniu")
let errAgain = e2.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .error))])
t.equal(errAgain, [], "ten sam błąd nie powiadamia drugi raz")

t.suite("NotificationEngine — nowy deploy od razu w błędzie")
var e3 = NotificationEngine()
_ = e3.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .ready))])
let freshErr = e3.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d2", state: .error))])
t.equal(freshErr.count, 1, "nowy deployment z błędem powiadamia")

t.suite("NotificationEngine — sukces")
var e4 = NotificationEngine()
_ = e4.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .building))])
let okEvents = e4.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .ready))])
t.equal(okEvents.count, 1, "building → ready daje zdarzenie")
t.equal(okEvents.first?.kind, .succeeded, "rodzaj: succeeded")

var e5 = NotificationEngine()
_ = e5.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .ready))])
let silentOK = e5.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d2", state: .ready))])
t.equal(silentOK, [], "deploy, którego nie widzieliśmy w toku, nie powiadamia o sukcesie")

t.suite("NotificationEngine — nowy projekt w trakcie działania")
var e6 = NotificationEngine()
_ = e6.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .ready))])
let newProj = e6.ingest(projects: [
    project("sklep", id: "p1", deploy: summary(id: "d1", state: .ready)),
    project("blog", id: "p2", deploy: summary(id: "x1", state: .error)),
])
t.equal(newProj, [], "świeżo dodany projekt najpierw dostaje baseline")

t.suite("NotificationEngine — realne sekwencje pollingu")

// Start aplikacji przy projekcie, który leży w błędzie: kolejne odpytania mają milczeć.
var e7 = NotificationEngine()
_ = e7.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .error))])
let stillErr = e7.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .error))])
t.equal(stillErr, [], "błąd zastany na starcie nie powiadamia przy kolejnym odpytaniu")

// Pełny cykl: push → kolejka → build (kilka odpytań) → sukces.
var e8 = NotificationEngine()
_ = e8.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .ready))])
let pushed = e8.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d2", state: .queued))])
t.equal(pushed, [], "nowy deploy w kolejce nie powiadamia")
let mid1 = e8.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d2", state: .building))])
let mid2 = e8.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d2", state: .building))])
t.equal(mid1 + mid2, [], "kolejne odpytania w trakcie builda milczą")
let done = e8.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d2", state: .ready))])
t.equal(done.count, 1, "queued → building → ready powiadamia o sukcesie")
t.equal(done.first?.deployment.id, "d2", "zdarzenie niesie właściwy deployment")
let afterDone = e8.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d2", state: .ready))])
t.equal(afterDone, [], "sukces nie powtarza się przy kolejnym odpytaniu")

// Anulowanie builda to nie błąd — bez powiadomienia.
var e9 = NotificationEngine()
_ = e9.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .building))])
let canceled = e9.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .canceled))])
t.equal(canceled, [], "anulowany build nie powiadamia")

// Migawka bez deployu (świeży projekt albo luka w odpowiedzi API) nie kasuje baseline.
var e10 = NotificationEngine()
_ = e10.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .building))])
let hole = e10.ingest(projects: [project("sklep", id: "p1", deploy: nil)])
t.equal(hole, [], "projekt bez deployu nie generuje zdarzenia")
let afterHole = e10.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .ready))])
t.equal(afterHole.count, 1, "po luce nadal wiemy, że deploy był w toku")

// Dwa projekty psują się w tym samym odpytaniu — dwa zdarzenia, każde ze swoją nazwą.
var e11 = NotificationEngine()
_ = e11.ingest(projects: [
    project("sklep", id: "p1", deploy: summary(id: "d1", state: .building)),
    project("blog", id: "p2", deploy: summary(id: "x1", state: .building)),
])
let both = e11.ingest(projects: [
    project("sklep", id: "p1", deploy: summary(id: "d1", state: .error)),
    project("blog", id: "p2", deploy: summary(id: "x1", state: .error)),
])
t.equal(both.count, 2, "dwa błędy naraz dają dwa zdarzenia")
t.equal(both.map(\.projectName), ["sklep", "blog"], "kolejność zdarzeń idzie za kolejnością projektów")

t.suite("NotificationEngine — dedup przy powrocie starego deployu")
var e12 = NotificationEngine()
_ = e12.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .building))])
_ = e12.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .error))]) // 1. powiadomienie
_ = e12.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d2", state: .building))])
let backToErr = e12.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .error))])
t.equal(backToErr, [], "ten sam błąd po przetasowaniu deployów nie powiadamia drugi raz")

t.suite("NotificationEngine — sukces innego deployu niż obserwowany")
var e13 = NotificationEngine()
_ = e13.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .building))])
let otherReady = e13.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d2", state: .ready))])
t.equal(otherReady, [], "ready innego deployu niż widziany w toku nie powiadamia")

t.suite("NotificationEngine — odznaczenie i ponowne zaznaczenie projektu")
var e14 = NotificationEngine()
_ = e14.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .building))])
_ = e14.ingest(projects: []) // projekt odznaczony — baseline znika
let rewatch = e14.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .error))])
t.equal(rewatch, [], "po ponownym zaznaczeniu najpierw świeży baseline, bez powiadomienia o starym błędzie")

t.suite("NotificationEngine — dedup sukcesu po regresie stanu z API")
var e15 = NotificationEngine()
_ = e15.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .building))])
let okOnce = e15.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .ready))])
t.equal(okOnce.count, 1, "sukces zgłoszony raz")
_ = e15.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .building))]) // odczyt z cache API
let okTwice = e15.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .ready))])
t.equal(okTwice, [], "ten sam sukces nie wraca po regresie stanu z API")

// MARK: - Klient VercelAPI

/// Stub sesji HTTP. Stan chroniony lockiem — Task 10 poda tę samą instancję
/// do równoległego task group, więc zapisy muszą znieść współbieżność.
final class StubSession: HTTPSession, @unchecked Sendable {
    struct StubError: Error {}

    /// Runner wstrzyknięty, nie brany z globalnej `t` — `t` jest izolowane MainActorem,
    /// a `data(for:)` biegnie poza nim (w Swift 6 byłby to błąd, nie ostrzeżenie).
    private let runner: Runner
    init(runner: Runner) { self.runner = runner }

    private let lock = NSLock()
    private var storedResponses: [String: (Int, Data)] = [:] // fragment URL → (status, body)
    private var storedRequests: [URLRequest] = []
    private var storedError: Error?

    var responses: [String: (Int, Data)] {
        get { lock.withLock { storedResponses } }
        set { lock.withLock { storedResponses = newValue } }
    }

    var requests: [URLRequest] { lock.withLock { storedRequests } }
    var lastRequest: URLRequest? { lock.withLock { storedRequests.last } }

    var thrownError: Error? {
        get { lock.withLock { storedError } }
        set { lock.withLock { storedError = newValue } }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!.absoluteString
        let (error, matches) = lock.withLock { () -> (Error?, [(Int, Data)]) in
            storedRequests.append(request)
            return (storedError, storedResponses.filter { url.contains($0.key) }.map(\.value))
        }
        if let error { throw error }
        // Niejednoznaczne dopasowanie zgłaszamy jako porażkę testu zamiast ubijać runner.
        // Zgłoszenie pod tym samym lockiem — Runner nie jest bezpieczny wątkowo, a równoległy
        // task group może trafić w miss dwoma zapytaniami naraz.
        guard matches.count == 1, let (status, body) = matches.first else {
            lock.withLock { runner.check(false, "stub: \(matches.count) dopasowań dla \(url)") }
            throw StubError()
        }
        let resp = HTTPURLResponse(url: request.url!, statusCode: status,
                                   httpVersion: nil, headerFields: nil)!
        return (body, resp)
    }
}

t.suite("VercelAPI — nagłówki i parametry")
let stub = StubSession(runner: t)
stub.responses["/v2/user"] = (200, Data(#"{"user":{"uid":"u1","username":"marta","name":null}}"#.utf8))
let api = VercelAPI(token: "tok_123", teamID: "team_9", session: stub)
let user = try await api.user()
t.equal(user.username, "marta", "user dekoduje się")
t.equal(stub.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok_123", "nagłówek Bearer")
t.check(stub.lastRequest?.url?.query?.contains("teamId=team_9") == true, "teamId w query")
t.equal(stub.lastRequest?.timeoutInterval, 15, "timeout requestu 15 s")

t.suite("VercelAPI — latestDeployment")
stub.responses["/v6/deployments"] = (200, Data("""
{"deployments":[{"uid":"d9","state":"READY","createdAt":1754470000000,
 "buildingAt":1754470002000,"ready":1754470040000,"meta":{}}]}
""".utf8))
let latest = try await api.latestDeployment(projectID: "prj_1")
t.equal(latest?.id, "d9", "najnowszy deploy z /v6/deployments")
t.check(stub.lastRequest?.url?.query?.contains("projectId=prj_1") == true, "projectId w query")
t.check(stub.lastRequest?.url?.query?.contains("limit=1") == true, "limit=1 w query")

t.suite("VercelAPI — projects i teams")
stub.responses["/v9/projects"] = (200, Data(#"{"projects":[{"id":"p1","name":"sklep"}]}"#.utf8))
let projList = try await api.projects()
t.equal(projList.map(\.id), ["p1"], "projects dekoduje się")
t.check(stub.lastRequest?.url?.path == "/v9/projects", "ścieżka /v9/projects")
t.check(stub.lastRequest?.url?.query?.contains("limit=100") == true, "limit=100 w query")
t.check(stub.lastRequest?.url?.query?.contains("teamId=team_9") == true, "teamId na /v9/projects")

stub.responses["/v2/teams"] = (200, Data(#"{"teams":[{"id":"t1","name":"Nord","slug":"nord"}]}"#.utf8))
let teamList = try await api.teams()
t.equal(teamList.map(\.slug), ["nord"], "teams dekoduje się")

t.suite("VercelAPI — mapowanie błędów")
let stubErr = StubSession(runner: t)
stubErr.responses["/v2/user"] = (401, Data("{}".utf8))
do {
    _ = try await VercelAPI(token: "zły", session: stubErr).user()
    t.check(false, "401 powinien rzucić")
} catch let e as VercelAPIError {
    t.equal(e, .unauthorized, "401 → unauthorized")
} catch { t.check(false, "zły typ błędu: \(error)") }

stubErr.responses["/v2/user"] = (429, Data("{}".utf8))
do {
    _ = try await VercelAPI(token: "t", session: stubErr).user()
    t.check(false, "429 powinien rzucić")
} catch let e as VercelAPIError {
    t.equal(e, .rateLimited, "429 → rateLimited")
} catch { t.check(false, "zły typ błędu: \(error)") }

stubErr.responses["/v2/user"] = (500, Data("{}".utf8))
do {
    _ = try await VercelAPI(token: "t", session: stubErr).user()
    t.check(false, "500 powinien rzucić")
} catch let e as VercelAPIError {
    t.equal(e, .server(500), "500 → server(500)")
} catch { t.check(false, "zły typ błędu: \(error)") }

let stubOffline = StubSession(runner: t)
stubOffline.thrownError = URLError(.notConnectedToInternet)
do {
    _ = try await VercelAPI(token: "t", session: stubOffline).user()
    t.check(false, "URLError powinien rzucić")
} catch let e as VercelAPIError {
    t.equal(e, .offline, "URLError → offline")
} catch { t.check(false, "zły typ błędu: \(error)") }

t.suite("VercelAPI — anulowanie")
let stubCancel = StubSession(runner: t)
stubCancel.thrownError = URLError(.cancelled)
do {
    _ = try await VercelAPI(token: "t", session: stubCancel).user()
    t.check(false, "anulowanie powinno rzucić")
} catch is CancellationError {
    t.check(true, "URLError.cancelled → CancellationError, nie offline")
} catch { t.check(false, "anulowanie zmapowane źle: \(error)") }

let stubCancel2 = StubSession(runner: t)
stubCancel2.thrownError = CancellationError()
do {
    _ = try await VercelAPI(token: "t", session: stubCancel2).user()
    t.check(false, "CancellationError powinien się propagować")
} catch is CancellationError {
    t.check(true, "CancellationError przechodzi bez mapowania na offline")
} catch { t.check(false, "CancellationError zmapowany źle: \(error)") }

t.suite("VercelAPI — konfiguracja domyślnej sesji")
t.equal(VercelAPI.defaultConfiguration.timeoutIntervalForResource, 15, "twardy deadline 15 s")
t.check(VercelAPI.defaultConfiguration.requestCachePolicy == .reloadIgnoringLocalCacheData, "bez cache")

// MARK: - RefreshCore

t.suite("RefreshCore")
let rcStub = StubSession(runner: t)
rcStub.responses["/v9/projects"] = (200, Data("""
{"projects":[{"id":"p1","name":"sklep-online"},{"id":"p2","name":"blog-firmowy"},{"id":"p3","name":"inny"}]}
""".utf8))
rcStub.responses["projectId=p1"] = (200, Data("""
{"deployments":[{"uid":"d1","state":"BUILDING","createdAt":1754470000000,
 "meta":{"githubCommitRef":"feat/koszyk","githubCommitMessage":"dodaj podsumowanie"}}]}
""".utf8))
rcStub.responses["projectId=p2"] = (200, Data("""
{"deployments":[{"uid":"d2","state":"READY","createdAt":1754470000000,
 "buildingAt":1754470002000,"ready":1754470040000,"meta":{"githubCommitRef":"main","githubCommitMessage":"mdx"}}]}
""".utf8))
let rcAPI = VercelAPI(token: "t", session: rcStub)
let snapshot = try await RefreshCore.fetch(api: rcAPI, watchedProjectIDs: ["p1", "p2"])
t.equal(snapshot.projects.count, 2, "tylko obserwowane projekty")
t.equal(snapshot.projects.map(\.name).sorted(), ["blog-firmowy", "sklep-online"], "nazwy z /v9/projects")
t.equal(snapshot.overall, .building, "stan zbiorczy z najnowszych deployów")
t.equal(snapshot.anyActive, true, "anyActive gdy build w toku")

// MARK: - KeychainStore

t.suite("KeychainStore")

/// Statusy oznaczające brak dostępu do pęku kluczy (CI, sesja bez zalogowanego użytkownika,
/// zablokowany pęk) — wtedy suite jest pomijana, a nie failowana.
func keychainUnavailable(_ status: OSStatus) -> Bool {
    [errSecNotAvailable, errSecInteractionNotAllowed, errSecAuthFailed,
     errSecMissingEntitlement, errSecUserCanceled].contains(status)
}

// Osobna usługa testowa, żeby nie dotykać tokenu produkcyjnego; sprzątamy przed i po.
let kc = KeychainStore(service: "pl.zielinski.vercelbar.testy")
kc.deleteToken(account: "test")
do {
    t.equal(try kc.readToken(account: "test"), nil, "brak tokenu przed zapisem")
    try kc.writeToken("tok_abc", account: "test")
    t.equal(try kc.readToken(account: "test"), "tok_abc", "odczyt po zapisie")
    try kc.writeToken("tok_nowy", account: "test")
    t.equal(try kc.readToken(account: "test"), "tok_nowy", "nadpisanie tokenu")
    t.check(kc.deleteToken(account: "test"), "usunięcie istniejącego wpisu zwraca true")
    t.equal(try kc.readToken(account: "test"), nil, "brak tokenu po usunięciu")
    t.check(kc.deleteToken(account: "test"), "usunięcie nieistniejącego wpisu też zwraca true")
} catch let KeychainStore.KeychainError.status(st) where keychainUnavailable(st) {
    t.skip("Keychain niedostępny: OSStatus \(st)")
} catch {
    t.check(false, "Keychain rzucił: \(error)")
}
kc.deleteToken(account: "test") // gdyby zapis przerwał się w połowie

// MARK: - SettingsStore

t.suite("SettingsStore")
// Osobna domena UserDefaults, żeby nie ruszać ustawień produkcyjnych; czyścimy przed i po.
let suiteName = "pl.zielinski.vercelbar.testy"
let defaults = UserDefaults(suiteName: suiteName)!
defaults.removePersistentDomain(forName: suiteName)
let settings = SettingsStore(defaults: defaults)
t.equal(settings.watchedProjectIDs, [], "domyślnie brak obserwowanych")
t.equal(settings.notifySuccess, true, "sukcesy domyślnie włączone")
t.equal(settings.notifyFailure, true, "błędy domyślnie włączone")
t.equal(settings.teamID, nil, "domyślnie konto osobiste")

settings.watchedProjectIDs = ["prj_1", "prj_2"]
settings.notifySuccess = false
settings.notifyFailure = false
settings.teamID = "team_9"
let reloaded = SettingsStore(defaults: defaults)
t.equal(reloaded.watchedProjectIDs, ["prj_1", "prj_2"], "obserwowane trwają po ponownym wczytaniu")
t.equal(reloaded.notifySuccess, false, "wyłączenie sukcesów trwa")
t.equal(reloaded.notifyFailure, false, "wyłączenie błędów trwa")
t.equal(reloaded.teamID, "team_9", "team trwa")
reloaded.teamID = nil
t.equal(SettingsStore(defaults: defaults).teamID, nil, "powrót do konta osobistego")
defaults.removePersistentDomain(forName: suiteName)

// MARK: - Ikona paska menu

t.suite("StatusIconRenderer")
t.equal(StatusIconRenderer.pulseAlpha(phase: 0), 0.55, "puls w fazie 0 → 0,55")
t.equal(StatusIconRenderer.pulseAlpha(phase: 0.5), 1.0, "puls w fazie 0,5 → 1,0")
t.check(abs(StatusIconRenderer.pulseAlpha(phase: 1.0) - 0.55) < 0.0001, "puls w fazie 1,0 wraca do 0,55")
let icon = StatusIconRenderer.image(state: .ready)
t.equal(icon.size, NSSize(width: 15, height: 13), "rozmiar ikony 15×13 pt (design)")
t.check(!icon.isTemplate, "ikona kolorowa, nie szablonowa")

// MARK: - Mapowanie jasny/ciemny

// Kolor dynamiczny rozwiązuje się dopiero pod konkretnym wyglądem — bez tego zamiana light:/dark: przechodzi niezauważona.
func resolved(_ color: NSColor, _ appearance: NSAppearance.Name) -> NSColor {
    var out = color
    NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
        out = color.usingColorSpace(.sRGB) ?? color
    }
    return out
}

func matchesHex(_ color: NSColor, _ value: UInt32, alpha: CGFloat = 1) -> Bool {
    let tol: CGFloat = 1.0 / 255
    return abs(color.redComponent - CGFloat((value >> 16) & 0xFF) / 255) <= tol
        && abs(color.greenComponent - CGFloat((value >> 8) & 0xFF) / 255) <= tol
        && abs(color.blueComponent - CGFloat(value & 0xFF) / 255) <= tol
        && abs(color.alphaComponent - alpha) <= 0.005
}

t.suite("Theme — jasny/ciemny")
t.check(matchesHex(resolved(Theme.ready, .aqua), 0x1d7f38), "ready w jasnym to #1d7f38")
t.check(matchesHex(resolved(Theme.ready, .darkAqua), 0x30d158), "ready w ciemnym to #30d158")
t.check(matchesHex(resolved(Theme.badgeReadyBg, .aqua), 0x1d7f38, alpha: 0.10), "tło badge ready w jasnym to zieleń 10 %")
t.check(matchesHex(resolved(Theme.badgeReadyBg, .darkAqua), 0x30d158, alpha: 0.15), "tło badge ready w ciemnym to zieleń 15 %")
t.check(matchesHex(resolved(Theme.rowErrorBg, .aqua), 0xd70015, alpha: 0.055), "tło wiersza błędu w jasnym to czerwień 5,5 %")
t.check(matchesHex(resolved(Theme.rowErrorBg, .darkAqua), 0xff453a, alpha: 0.085), "tło wiersza błędu w ciemnym to czerwień 8,5 %")
t.check(matchesHex(resolved(Theme.successFlash, .darkAqua), 0x30d158, alpha: 0.20), "rozbłysk sukcesu w ciemnym to zieleń 20 %")

// MARK: - Orientacja trójkąta

// Rysujemy w powiększeniu 8×, żeby próbkować rogi poza antyaliasingiem krawędzi.
let iconScale = 8
let iconW = 15 * iconScale, iconH = 13 * iconScale
let iconRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: iconW, pixelsHigh: iconH,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: iconRep)
icon.draw(in: NSRect(x: 0, y: 0, width: iconW, height: iconH))
NSGraphicsContext.restoreGraphicsState()

// NSBitmapImageRep liczy wiersze od góry, więc y = 0 to szczyt ikony.
func iconAlpha(_ x: Int, _ y: Int) -> CGFloat { iconRep.colorAt(x: x, y: y)?.alphaComponent ?? 0 }
let inset = iconScale // 1 pt od krawędzi

t.suite("Orientacja ikony")
t.check(iconAlpha(inset, inset) == 0 && iconAlpha(iconW - 1 - inset, inset) == 0,
        "górne rogi puste — trójkąt nie stoi na wierzchołku")
t.check(iconAlpha(inset, iconH - 1 - inset) > 0 && iconAlpha(iconW - 1 - inset, iconH - 1 - inset) > 0,
        "dolne rogi wypełnione — podstawa na dole")
t.check(iconAlpha(iconW / 2, inset) > 0, "wierzchołek u góry, na środku")

t.finish()
