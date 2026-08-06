import Foundation
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

t.finish()
