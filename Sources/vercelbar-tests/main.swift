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

t.suite("Duration — BUILDING z polem ready z API nie udaje skończonego builda")
// Vercel często wysyła `ready` już w QUEUED/BUILDING (0 albo kopia createdAt).
// Stary kod liczył duration = 0 s i wyłączał TimelineView — stoper stał na 0s.
if let d = firstDeployment(#"{"deployments":[{"uid":"b","state":"BUILDING","createdAt":1754470000000,"buildingAt":1754470000000,"ready":1754470000000}]}"#,
                           "BUILDING z ready = createdAt") {
    t.equal(d.duration, nil, "trwający build nie ma skończonego duration")
    t.equal(d.elapsed(at: Date(timeIntervalSince1970: 1_754_470_038)), 38,
            "stoper liczy od startu, nie od ready")
}

if let d = firstDeployment(#"{"deployments":[{"uid":"q","state":"QUEUED","createdAt":1754470000000,"ready":0}]}"#,
                           "QUEUED z ready: 0") {
    t.equal(d.readyAt, nil, "ready = 0 to brak daty, nie 1970")
    t.equal(d.duration, nil, "zerowy ready nie daje duration")
    t.equal(d.elapsed(at: Date(timeIntervalSince1970: 1_754_470_012)), 12,
            "kolejka tyka od createdAt")
}

if let d = firstDeployment(#"{"deployments":[{"uid":"z","state":"READY","createdAt":1754470000000,"ready":0}]}"#,
                           "READY z ready: 0") {
    t.equal(d.readyAt, nil, "ready = 0 przy READY też jest pusty")
    t.equal(d.duration, nil, "bez sensownego ready nie ma duration")
}

if let d = firstDeployment(#"{"deployments":[{"uid":"n","state":"READY","createdAt":1754470030000,"ready":1754470000000}]}"#,
                           "READY z ready przed createdAt") {
    t.equal(d.duration, nil, "ujemny czas budowania zostaje nil, nie 0 s")
}

t.suite("DeploymentSummary.elapsed")
let building = DeploymentSummary(id: "live", state: .building,
                                 createdAt: Date(timeIntervalSince1970: 1000),
                                 buildingAt: Date(timeIntervalSince1970: 1005))
t.equal(building.duration, nil, "BUILDING bez ready → duration nil")
t.equal(building.elapsed(at: Date(timeIntervalSince1970: 1043)), 38,
        "elapsed od buildingAt")
t.equal(building.elapsed(at: Date(timeIntervalSince1970: 1000)), 0,
        "czas sprzed buildingAt nie idzie w minus")

let finished = DeploymentSummary(id: "finished", state: .ready,
                                 createdAt: Date(timeIntervalSince1970: 1000),
                                 buildingAt: Date(timeIntervalSince1970: 1002),
                                 readyAt: Date(timeIntervalSince1970: 1040))
t.equal(finished.elapsed(at: Date(timeIntervalSince1970: 9999)), 38,
        "zakończony deploy ma stałe elapsed = duration")

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

let userJSON = Data(#"{"user":{"id":"u_1","username":"marta","name":"Marta Kowalska"}}"#.utf8)
do {
    let u = try APIDecoding.user(from: userJSON)
    t.equal(u.id, "u_1", "id z pola id (realny kształt /v2/user wg OpenAPI Vercela)")
    t.equal(u.username, "marta", "username")
    t.equal(u.name, "Marta Kowalska", "pełna nazwa")
} catch { t.check(false, "dekodowanie usera rzuciło: \(error)") }

let legacyUserJSON = Data(#"{"user":{"uid":"u_9","username":"jan","name":null}}"#.utf8)
do {
    let u = try APIDecoding.user(from: legacyUserJSON)
    t.equal(u.id, "u_9", "fallback na historyczne uid")
} catch { t.check(false, "dekodowanie legacy usera rzuciło: \(error)") }

let teamsJSON = Data(#"{"teams":[{"id":"team_1","name":"Studio Nord","slug":"studio-nord"}]}"#.utf8)
do {
    let ts = try APIDecoding.teams(from: teamsJSON)
    t.equal(ts.first?.slug, "studio-nord", "team slug")
} catch { t.check(false, "dekodowanie teamów rzuciło: \(error)") }

let namelessTeamJSON = Data(#"{"teams":[{"id":"team_2","name":null,"slug":"cichy-team"}]}"#.utf8)
do {
    let ts = try APIDecoding.teams(from: namelessTeamJSON)
    t.equal(ts.first?.name, "cichy-team", "team bez nazwy spada na slug (name nullable wg OpenAPI)")
} catch { t.check(false, "dekodowanie teamu bez nazwy rzuciło: \(error)") }

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

t.suite("Lang.system — wybór za systemem")
t.equal(Lang.system(preferred: ["pl-PL"]), .pl, "pl-PL → polski")
t.equal(Lang.system(preferred: ["pl"]), .pl, "sam kod pl → polski")
t.equal(Lang.system(preferred: ["PL-pl"]), .pl, "wielkość liter bez znaczenia")
t.equal(Lang.system(preferred: ["en-US"]), .en, "en-US → angielski")
t.equal(Lang.system(preferred: ["de-DE"]), .en, "niemiecki → angielski, nie polski")
t.equal(Lang.system(preferred: []), .en, "brak preferencji → angielski")
t.equal(Lang.system(preferred: ["en-US", "pl-PL"]), .en, "liczy się tylko pierwszy język")

t.suite("Lang.effective — ręczny wybór z Ustawień")
t.equal(Lang.effective(override: .en, preferred: ["pl-PL"]), .en, "wybór en wygrywa z polskim systemem")
t.equal(Lang.effective(override: .pl, preferred: ["en-US"]), .pl, "wybór pl wygrywa z angielskim systemem")
t.equal(Lang.effective(override: nil, preferred: ["pl-PL"]), .pl, "brak wyboru → system (pl)")
t.equal(Lang.effective(override: nil, preferred: ["de-DE"]), .en, "brak wyboru → system (nie-pl → en)")
t.equal(Lang.effective(override: nil, preferred: []), .en, "brak wyboru i brak preferencji → en")

t.suite("Nagłówek popovera")
t.equal(StatusAggregator.headline(for: [.ready, .ready], lang: .pl), "Wszystko wdrożone", "nagłówek ready")
t.equal(StatusAggregator.headline(for: [.ready, .building], lang: .pl), "Build w toku…", "nagłówek building")
t.equal(StatusAggregator.headline(for: [.error, .ready], lang: .pl), "1 deploy padł", "nagłówek 1 błąd")
t.equal(StatusAggregator.headline(for: [.error, .error, .ready], lang: .pl), "2 deploye padły", "nagłówek 2 błędy")
t.equal(StatusAggregator.headline(for: [.error, .error, .error, .error, .error], lang: .pl), "5 deployów padło", "nagłówek 5 błędów")
t.equal(StatusAggregator.headline(for: Array(repeating: .error, count: 12), lang: .pl), "12 deployów padło", "nagłówek 12 błędów (nastki)")
t.equal(StatusAggregator.headline(for: Array(repeating: .error, count: 21), lang: .pl), "21 deployów padło", "nagłówek 21 błędów (końcówka 1)")
t.equal(StatusAggregator.headline(for: Array(repeating: .error, count: 22), lang: .pl), "22 deploye padły", "nagłówek 22 błędów")
t.equal(StatusAggregator.headline(for: [], lang: .pl), "Brak obserwowanych projektów", "nagłówek pusty")
t.equal(StatusAggregator.headline(for: [.canceled, .unknown], lang: .pl), "Brak aktywnych deployów", "canceled + unknown → brak aktywnych, nie brak projektów")

t.suite("Nagłówek popovera po angielsku")
t.equal(StatusAggregator.headline(for: [.ready, .ready], lang: .en), "All deployed", "nagłówek ready")
t.equal(StatusAggregator.headline(for: [.ready, .building], lang: .en), "Build in progress…", "nagłówek building")
t.equal(StatusAggregator.headline(for: [.error, .ready], lang: .en), "1 deploy failed", "nagłówek 1 błąd — liczba pojedyncza")
t.equal(StatusAggregator.headline(for: [.error, .error, .ready], lang: .en), "2 deploys failed", "nagłówek 2 błędy — liczba mnoga")
t.equal(StatusAggregator.headline(for: Array(repeating: .error, count: 22), lang: .en), "22 deploys failed", "angielski nie odmienia przez liczebniki")
t.equal(StatusAggregator.headline(for: [], lang: .en), "No watched projects", "nagłówek pusty")
t.equal(StatusAggregator.headline(for: [.canceled, .unknown], lang: .en), "No active deploys", "canceled + unknown → brak aktywnych")

t.suite("PollScheduler")
t.equal(PollScheduler.interval(anyActive: false), 10, "spokój → 10 s (szybszy start 🚀)")
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
t.equal(Format.relative(ago(10), now: now, lang: .pl), "teraz", "poniżej 45 s → teraz")
t.equal(Format.relative(ago(44), now: now, lang: .pl), "teraz", "44 s → jeszcze teraz")
t.equal(Format.relative(ago(50), now: now, lang: .pl), "50 s temu", "sekundy")
t.equal(Format.relative(ago(89), now: now, lang: .pl), "89 s temu", "89 s → jeszcze sekundy")
t.equal(Format.relative(ago(90), now: now, lang: .pl), "1 min temu", "90 s → już minuty")
t.equal(Format.relative(ago(120), now: now, lang: .pl), "2 min temu", "minuty")
t.equal(Format.relative(ago(3600), now: now, lang: .pl), "1 godz. temu", "godziny")
t.equal(Format.relative(ago(5 * 3600), now: now, lang: .pl), "5 godz. temu", "kilka godzin")
t.equal(Format.relative(ago(86_399), now: now, lang: .pl), "23 godz. temu", "tuż przed dobą")
t.equal(Format.relative(ago(86_400), now: now, lang: .pl), "wczoraj", "dokładnie doba")
t.equal(Format.relative(ago(30 * 3600), now: now, lang: .pl), "wczoraj", "24–48 h → wczoraj")
t.equal(Format.relative(ago(172_800), now: now, lang: .pl), "2 dni temu", "dokładnie dwie doby")
t.equal(Format.relative(ago(3 * 86_400), now: now, lang: .pl), "3 dni temu", "dni")

t.suite("Format.relative po angielsku")
t.equal(Format.relative(ago(10), now: now, lang: .en), "just now", "poniżej 45 s")
t.equal(Format.relative(ago(44), now: now, lang: .en), "just now", "44 s → jeszcze just now")
t.equal(Format.relative(ago(50), now: now, lang: .en), "50 s ago", "sekundy")
t.equal(Format.relative(ago(89), now: now, lang: .en), "89 s ago", "89 s → jeszcze sekundy")
t.equal(Format.relative(ago(90), now: now, lang: .en), "1 min ago", "90 s → już minuty")
t.equal(Format.relative(ago(120), now: now, lang: .en), "2 min ago", "minuty")
t.equal(Format.relative(ago(3600), now: now, lang: .en), "1 hr ago", "godziny")
t.equal(Format.relative(ago(5 * 3600), now: now, lang: .en), "5 hr ago", "kilka godzin")
t.equal(Format.relative(ago(86_399), now: now, lang: .en), "23 hr ago", "tuż przed dobą")
t.equal(Format.relative(ago(86_400), now: now, lang: .en), "yesterday", "dokładnie doba")
t.equal(Format.relative(ago(30 * 3600), now: now, lang: .en), "yesterday", "24–48 h → yesterday")
t.equal(Format.relative(ago(172_800), now: now, lang: .en), "2 days ago", "dokładnie dwie doby")
t.equal(Format.relative(ago(3 * 86_400), now: now, lang: .en), "3 days ago", "dni")

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

let plTexts = L10n(lang: .pl)
let enTexts = L10n(lang: .en)

t.suite("L10n — teksty UI")
t.equal(plTexts.refreshedAt("12:04"), "odświeżono 12:04", "stopka nagłówka po polsku")
t.equal(enTexts.refreshedAt("12:04"), "refreshed 12:04", "stopka nagłówka po angielsku")
t.equal(plTexts.monitoredCount(3, 12), "3 z 12 projektów monitorowanych", "licznik projektów po polsku")
t.equal(enTexts.monitoredCount(3, 12), "3 of 12 projects monitored", "licznik projektów po angielsku")
t.equal(plTexts.languageLabel, "Język", "etykieta języka po polsku")
t.equal(enTexts.languageLabel, "Language", "etykieta języka po angielsku")
t.equal(plTexts.languageSystem, "Systemowy", "opcja systemowa po polsku")
t.equal(enTexts.languageSystem, "System", "opcja systemowa po angielsku")
t.equal(plTexts.unknownTeam(idPrefix: "team_abc123"), "Zespół (team_abc123…)", "nieznany zespół po polsku")
t.equal(enTexts.unknownTeam(idPrefix: "team_abc123"), "Team (team_abc123…)", "nieznany zespół po angielsku")
t.equal(plTexts.deployFailedTitle(project: "sklep"), "❌ sklep: deploy padł", "tytuł porażki po polsku")
t.equal(enTexts.deployFailedTitle(project: "sklep"), "❌ sklep: deploy failed", "tytuł porażki po angielsku")
t.equal(plTexts.deploySucceededTitle(project: "sklep"), "✅ sklep wdrożony", "tytuł sukcesu po polsku")
t.equal(enTexts.deploySucceededTitle(project: "sklep"), "✅ sklep deployed", "tytuł sukcesu po angielsku")
t.equal(plTexts.deploySucceededBody(branch: "main", duration: 38),
        "main · gotowe w 38 s. Kliknij, aby otworzyć podgląd.", "treść sukcesu z czasem po polsku")
t.equal(enTexts.deploySucceededBody(branch: "main", duration: 38),
        "main · ready in 38 s. Click to open the preview.", "treść sukcesu z czasem po angielsku")
t.equal(plTexts.deploySucceededBody(branch: "main", duration: nil),
        "main · gotowe. Kliknij, aby otworzyć podgląd.", "bez czasu zdanie zostaje poprawne (pl)")
t.equal(enTexts.deploySucceededBody(branch: "main", duration: nil),
        "main · ready. Click to open the preview.", "bez czasu zdanie zostaje poprawne (en)")
t.equal(plTexts.deployFailedBody(branch: "main"),
        "main · build przerwany. Kliknij, aby otworzyć logi.", "treść porażki po polsku")
t.equal(enTexts.deployFailedBody(branch: "main"),
        "main · build failed. Click to open the logs.", "treść porażki po angielsku")
t.equal(plTexts.deployStartedTitle(project: "sklep"), "🚀 sklep: deploy ruszył", "tytuł startu po polsku")
t.equal(enTexts.deployStartedTitle(project: "sklep"), "🚀 sklep: deploy started", "tytuł startu po angielsku")
t.equal(plTexts.deployStartedBody(branch: "main"),
        "main · buduje się. Kliknij, aby otworzyć szczegóły.", "treść startu po polsku")
t.equal(enTexts.deployStartedBody(branch: "main"),
        "main · building. Click to open details.", "treść startu po angielsku")
t.equal(plTexts.notifyStart, "Powiadamiaj o starcie deployu", "przełącznik startu po polsku")
t.equal(enTexts.notifyStart, "Notify when a deploy starts", "przełącznik startu po angielsku")
t.equal(plTexts.feedLimitLabel, "Historia deployów", "etykieta głębokości historii po polsku")
t.equal(enTexts.feedLimitLabel, "Deploy history", "etykieta głębokości historii po angielsku")
t.equal(L10n(lang: .en).lang, .en, "L10n pamięta wybrany język")

t.suite("L10n — teksty aktualizacji")
t.equal(plTexts.updateAvailable(version: "1.2.0"), "Dostępna wersja 1.2.0", "baner aktualizacji po polsku")
t.equal(enTexts.updateAvailable(version: "1.2.0"), "Version 1.2.0 available", "baner aktualizacji po angielsku")
t.equal(plTexts.updateInstallButton, "Zaktualizuj", "przycisk aktualizacji po polsku")
t.equal(enTexts.updateInstallButton, "Update", "przycisk aktualizacji po angielsku")
t.equal(plTexts.updateDownloading, "Pobieranie…", "stan pobierania po polsku")
t.equal(enTexts.updateDownloading, "Downloading…", "stan pobierania po angielsku")
t.equal(plTexts.updateInstalling, "Instalowanie…", "stan instalacji po polsku")
t.equal(enTexts.updateInstalling, "Installing…", "stan instalacji po angielsku")
t.equal(plTexts.updateFailed, "Aktualizacja się nie udała. Otworzyłem stronę wydania.",
        "komunikat porażki po polsku")
t.equal(enTexts.updateFailed, "The update failed. The release page is open in your browser.",
        "komunikat porażki po angielsku")
t.equal(plTexts.checkForUpdates, "Sprawdź aktualizacje", "przycisk sprawdzania po polsku")
t.equal(enTexts.checkForUpdates, "Check for updates", "przycisk sprawdzania po angielsku")
t.equal(plTexts.upToDate, "Masz najnowszą wersję", "potwierdzenie aktualności po polsku")
t.equal(enTexts.upToDate, "You're up to date", "potwierdzenie aktualności po angielsku")
t.equal(plTexts.versionLabel(version: "1.1.0"), "Wersja 1.1.0", "etykieta wersji po polsku")
t.equal(enTexts.versionLabel(version: "1.1.0"), "Version 1.1.0", "etykieta wersji po angielsku")
t.equal(plTexts.updateFound(version: "1.2.1"), "Znaleziono wersję 1.2.1 — zobacz w pasku menu",
        "wynik ręcznego sprawdzenia po polsku")
t.equal(enTexts.updateFound(version: "1.2.1"), "Found version 1.2.1 — see the menu bar",
        "wynik ręcznego sprawdzenia po angielsku")
t.equal(plTexts.updateDamaged, "Paczka aktualizacji jest uszkodzona. Otworzyłem stronę wydania.",
        "komunikat uszkodzonej paczki po polsku")
t.equal(enTexts.updateDamaged, "The update package is damaged. The release page is open in your browser.",
        "komunikat uszkodzonej paczki po angielsku")

t.suite("L10n — teksty testu powiadomień")
t.equal(plTexts.sendTestNotification, "Testuj powiadomienie", "przycisk testu po polsku")
t.equal(enTexts.sendTestNotification, "Test notification", "przycisk testu po angielsku")
t.equal(plTexts.testNotificationTitle, "VercelBar działa", "tytuł testu po polsku")
t.equal(enTexts.testNotificationTitle, "VercelBar is working", "tytuł testu po angielsku")
t.equal(plTexts.testNotificationBody, "Tak będą wyglądać powiadomienia o deployach.",
        "treść testu po polsku")
t.equal(enTexts.testNotificationBody, "This is how deploy notifications will look.",
        "treść testu po angielsku")

// MARK: - Argumenty powiadomienia zapasowego

t.suite("ScriptNotification — kolejność argumentów")
let plainArgs = ScriptNotification.arguments(title: "Tytuł", body: "Treść")
t.equal(plainArgs.count, 5, "pięć argumentów: -e, skrypt, --, treść, tytuł")
t.equal(plainArgs[0], "-e", "skrypt idzie przez -e")
t.equal(plainArgs[1], ScriptNotification.script, "drugi argument to skrypt")
// Bez `--` osascript zjada treść zaczynającą się od myślnika jako własną opcję.
t.equal(plainArgs[2], "--", "separator kończy listę opcji osascripta")
t.equal(plainArgs[3], "Treść", "treść przed tytułem — tak czyta ją `item 1 of argv`")
t.equal(plainArgs[4], "Tytuł", "tytuł na końcu — `item 2 of argv`")
t.check(ScriptNotification.script.contains("item 1 of argv"),
        "skrypt bierze treść z argv, nie ze sklejenia")

t.suite("ScriptNotification — treść wroga trafia jako dane")
// Nazwy projektów i komunikaty commitów są danymi zewnętrznymi: cudzysłów,
// apostrof, nowa linia i `$(whoami)` muszą przejść dosłownie i nie wolno im
// wylądować w kodzie skryptu.
let hostileBody = "\"quote\" 'apo' $(whoami) `id`\ndruga linia \\ koniec"
let hostileTitle = "▲ \"projekt\"; do shell script \"rm -rf /\""
let hostileArgs = ScriptNotification.arguments(title: hostileTitle, body: hostileBody)
t.equal(hostileArgs[3], hostileBody, "treść przechodzi bez zmian, znak w znak")
t.equal(hostileArgs[4], hostileTitle, "tytuł przechodzi bez zmian, znak w znak")
t.check(!hostileArgs[1].contains("quote"), "skrypt nie zawiera treści użytkownika")
t.check(!hostileArgs[1].contains("whoami"), "skrypt nie zawiera podstawienia powłoki z treści")
t.check(!hostileArgs[1].contains("rm -rf"), "skrypt nie zawiera tytułu użytkownika")
t.equal(hostileArgs[1], ScriptNotification.script, "skrypt jest stałą, niezależną od danych")

// Argument zaczynający się od myślnika — najczęstszy powód, dla którego wywołanie
// bez separatora kończy się „illegal option" zamiast powiadomieniem.
let dashArgs = ScriptNotification.arguments(title: "-l", body: "-e rm")
t.equal(dashArgs[2], "--", "separator jest też przy treści zaczynającej się od myślnika")
t.equal(dashArgs[3], "-e rm", "treść z myślnikiem przechodzi jako dane")
t.equal(dashArgs[4], "-l", "tytuł z myślnikiem przechodzi jako dane")

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

// Build krótszy niż odstęp między odpytaniami: między migawkami doszedł nowy deployment
// i zdążył się zbudować. Wcześniej takie wdrożenie przechodziło bez słowa — teraz melduje sukces.
var e5 = NotificationEngine()
_ = e5.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .ready))])
let fastOK = e5.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d2", state: .ready))])
t.equal(fastOK.count, 1, "deploy zbudowany między odpytaniami powiadamia o sukcesie")
t.equal(fastOK.first?.kind, .succeeded, "rodzaj: succeeded, bez started")
t.equal(fastOK.first?.deployment.id, "d2", "zdarzenie niesie nowy deployment")
let fastOKAgain = e5.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d2", state: .ready))])
t.equal(fastOKAgain, [], "…i nie powtarza się przy kolejnym odpytaniu")

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
t.equal(pushed.map(\.kind), [.started], "nowy deploy w kolejce melduje start")
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

t.suite("NotificationEngine — build wyparty przez nowszy, gotowy deploy")
var e13 = NotificationEngine()
_ = e13.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .building))])
let otherReady = e13.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d2", state: .ready))])
t.equal(otherReady.map(\.kind), [.succeeded], "nowszy deploy zastany w ready melduje sukces raz")
t.equal(otherReady.first?.deployment.id, "d2", "…i to sukces nowego deploymentu, nie wypartego builda")

t.suite("NotificationEngine — odznaczenie i ponowne zaznaczenie projektu")
var e14 = NotificationEngine()
_ = e14.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .building))])
_ = e14.ingest(projects: []) // projekt odznaczony — baseline znika
let rewatch = e14.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .error))])
t.equal(rewatch, [], "po ponownym zaznaczeniu najpierw świeży baseline, bez powiadomienia o starym błędzie")

t.suite("NotificationEngine — start deployu")
var e16 = NotificationEngine()
_ = e16.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .ready))])
let started = e16.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d2", state: .building))])
t.equal(started.count, 1, "nowy deployment w buildzie daje zdarzenie")
t.equal(started.first?.kind, .started, "rodzaj: started")
t.equal(started.first?.projectName, "sklep", "nazwa projektu w zdarzeniu startu")
t.equal(started.first?.deployment.id, "d2", "zdarzenie niesie nowy deployment")
let startedAgain = e16.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d2", state: .building))])
t.equal(startedAgain, [], "ten sam build nie melduje startu drugi raz")
let startedThird = e16.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d2", state: .building))])
t.equal(startedThird, [], "…ani przy trzecim odpytaniu")

// Start i sukces tego samego deploymentu to dwa osobne zdarzenia — dedup jest po parze id|rodzaj.
var e17 = NotificationEngine()
_ = e17.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .ready))])
let cycleStart = e17.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d2", state: .building))])
let cycleEnd = e17.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d2", state: .ready))])
t.equal((cycleStart + cycleEnd).map(\.kind), [.started, .succeeded],
        "sekwencja started → succeeded dla jednego id daje dwa zdarzenia")

// Deploy zastany od razu w ready nie miał okazji zameldować startu — sam sukces.
var e18 = NotificationEngine()
_ = e18.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .ready))])
let readyStraightAway = e18.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d2", state: .ready))])
t.equal(readyStraightAway.map(\.kind), [.succeeded], "nowy deploy od razu w ready → tylko succeeded")

// Nowy deployment, który zdążył się wywrócić, też nie melduje startu.
var e19 = NotificationEngine()
_ = e19.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .ready))])
let brokeStraightAway = e19.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d2", state: .error))])
t.equal(brokeStraightAway.map(\.kind), [.failed], "nowy deploy od razu w błędzie → tylko failed")

// Pierwsza obserwacja zostaje cicha także dla startu.
var e20 = NotificationEngine()
let baselineBuilding = e20.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .building))])
t.equal(baselineBuilding, [], "build zastany przy pierwszym odpytaniu nie melduje startu")

// Ten sam build w kolejnych cyklach też milczy — bez `isNewDeployment` w regule startu
// aplikacja meldowałaby start builda, który użytkownik zastał już w toku.
let stillBuilding = e20.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .building))])
t.equal(stillBuilding, [], "build zastany na starcie nie melduje startu przy kolejnym odpytaniu")

// Regres stanu z cache'u API (ready → building przy tym samym id) nie cofa się do startu.
var e21 = NotificationEngine()
_ = e21.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .building))])
_ = e21.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .ready))])
let regressed = e21.ingest(projects: [project("sklep", id: "p1", deploy: summary(id: "d1", state: .building))])
t.equal(regressed, [], "regres ready → building nie melduje startu po fakcie")

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
    private var storedDelayNanos: UInt64 = 0
    private var inFlight = 0
    private var peakInFlight = 0

    /// Szczyt równoczesnych wywołań — dowód, że RefreshCore trzyma okno równoległości.
    var maxInFlight: Int { lock.withLock { peakInFlight } }

    /// Sztuczne opóźnienie odpowiedzi. Bez niego wywołania kończą się szybciej,
    /// niż zdążą się nałożyć, i pomiar równoległości pokazywałby 1.
    var delayNanos: UInt64 {
        get { lock.withLock { storedDelayNanos } }
        set { lock.withLock { storedDelayNanos = newValue } }
    }

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
        let (error, matches, delay) = lock.withLock { () -> (Error?, [(Int, Data)], UInt64) in
            storedRequests.append(request)
            inFlight += 1
            peakInFlight = max(peakInFlight, inFlight)
            return (storedError,
                    storedResponses.filter { url.contains($0.key) }.map(\.value),
                    storedDelayNanos)
        }
        defer { lock.withLock { inFlight -= 1 } } // także przy rzuceniu błędu
        // Sen POZA lockiem — pod lockiem wywołania ustawiłyby się w kolejkę i szczyt
        // równoległości zawsze wynosiłby 1, niezależnie od tego, co robi RefreshCore.
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
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
stub.responses["/v2/user"] = (200, Data(#"{"user":{"id":"u1","username":"marta","name":null}}"#.utf8))
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

t.suite("VercelAPI — recentDeployments")
stub.responses["/v6/deployments"] = (200, Data("""
{"deployments":[{"uid":"d9","state":"READY","createdAt":1754470030000},
                {"uid":"d8","state":"ERROR","createdAt":1754470020000},
                {"uid":"d7","state":"READY","createdAt":1754470010000}]}
""".utf8))
let recent = try await api.recentDeployments(projectID: "prj_1", limit: 5)
t.equal(recent.map(\.id), ["d9", "d8", "d7"], "cała lista, nie tylko pierwszy")
t.check(stub.lastRequest?.url?.query?.contains("limit=5") == true, "limit=5 w query")
t.check(stub.lastRequest?.url?.query?.contains("projectId=prj_1") == true, "projectId w query")
let latestOfMany = try await api.latestDeployment(projectID: "prj_1")
t.equal(latestOfMany?.id, "d9", "latestDeployment bierze pierwszy z listy")
t.check(stub.lastRequest?.url?.query?.contains("limit=1") == true, "latestDeployment nadal pyta o limit=1")

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

t.suite("RefreshCore — stabilna kolejność przy równym createdAt")
// Task group kończy się w losowej kolejności, więc remis po createdAt musi rozstrzygać nazwa.
let tieStub = StubSession(runner: t)
tieStub.responses["/v9/projects"] = (200, Data("""
{"projects":[{"id":"pz","name":"zebra"},{"id":"pa","name":"alfa"},{"id":"pm","name":"Migdał"}]}
""".utf8))
for pid in ["pz", "pa", "pm"] {
    tieStub.responses["projectId=\(pid)"] = (200, Data("""
    {"deployments":[{"uid":"d-\(pid)","state":"READY","createdAt":1754470000000}]}
    """.utf8))
}
let tieAPI = VercelAPI(token: "t", session: tieStub)
var tieOrders: [[String]] = []
for _ in 0..<5 {
    tieOrders.append(try await RefreshCore.fetch(api: tieAPI,
                                                 watchedProjectIDs: ["pz", "pa", "pm"]).projects.map(\.name))
}
t.equal(Set(tieOrders.map { $0.joined(separator: "|") }).count, 1, "pięć przebiegów daje tę samą kolejność")
// „Migdał" pośrodku pilnuje, żeby porównanie zostało nieczułe na wielkość liter (ASCII dałby „Migdał" na przedzie).
t.equal(tieOrders.first ?? [], ["alfa", "Migdał", "zebra"], "remis rozstrzyga nazwa, bez względu na wielkość liter")

t.suite("RefreshCore — brzegi migawki")
rcStub.responses["projectId=p3"] = (200, Data(#"{"deployments":[]}"#.utf8))

let rcMissing = try await RefreshCore.fetch(api: rcAPI, watchedProjectIDs: ["p1", "prj_usuniety"])
t.equal(rcMissing.projects.map(\.name), ["sklep-online"], "obserwowany projekt spoza /v9/projects jest pomijany")

let rcEmpty = try await RefreshCore.fetch(api: rcAPI, watchedProjectIDs: [])
t.equal(rcEmpty.projects.count, 0, "brak obserwowanych → pusta migawka")
t.equal(rcEmpty.overall, .idle, "pusta migawka → idle")
t.equal(rcEmpty.anyActive, false, "pusta migawka → nic aktywnego")

let rcNoDeploys = try await RefreshCore.fetch(api: rcAPI, watchedProjectIDs: ["p3"])
t.equal(rcNoDeploys.projects.count, 1, "projekt bez deployów zostaje w migawce")
t.check(rcNoDeploys.projects.first?.latest == nil, "projekt bez deployów ma latest == nil")
t.equal(rcNoDeploys.overall, .idle, "sam projekt bez deployów → idle")

t.suite("RefreshCore — błąd deploymentów wywraca całą migawkę")
// Świadomy trade-off „wszystko albo nic": lepiej zostawić poprzednie dane niż pokazać dziurawe.
let rcErrStub = StubSession(runner: t)
rcErrStub.responses["/v9/projects"] = (200, Data(#"{"projects":[{"id":"p1","name":"sklep"},{"id":"p2","name":"blog"}]}"#.utf8))
rcErrStub.responses["projectId=p1"] = (500, Data("{}".utf8))
rcErrStub.responses["projectId=p2"] = (200, Data(#"{"deployments":[{"uid":"d2","state":"READY"}]}"#.utf8))
do {
    _ = try await RefreshCore.fetch(api: VercelAPI(token: "t", session: rcErrStub),
                                    watchedProjectIDs: ["p1", "p2"])
    t.check(false, "500 na deploymentach powinien rzucić")
} catch let e as VercelAPIError {
    t.equal(e, .server(500), "500 jednego projektu przerywa cały fetch")
} catch { t.check(false, "zły typ błędu: \(error)") }

t.suite("RefreshCore — feed scalony z wielu projektów")
// Dwa projekty po trzy deploye, naprzemienne createdAt: feed ma je przepleść po czasie,
// a nie skleić projekt po projekcie.
let feedStub = StubSession(runner: t)
let feedBase = 1_754_470_000_000.0
feedStub.responses["/v9/projects"] = (200, Data("""
{"projects":[{"id":"fp1","name":"sklep-online"},{"id":"fp2","name":"blog-firmowy"},{"id":"fp3","name":"pusty"}]}
""".utf8))
func deployJSON(_ uid: String, offsetSeconds: Double) -> String {
    #"{"uid":"\#(uid)","state":"READY","createdAt":\#(Int(feedBase + offsetSeconds * 1000))}"#
}
feedStub.responses["projectId=fp1"] = (200, Data("""
{"deployments":[\(deployJSON("d1a", offsetSeconds: 100)),\
\(deployJSON("d1b", offsetSeconds: 80)),\
\(deployJSON("d1c", offsetSeconds: 60))]}
""".utf8))
feedStub.responses["projectId=fp2"] = (200, Data("""
{"deployments":[\(deployJSON("d2a", offsetSeconds: 90)),\
\(deployJSON("d2b", offsetSeconds: 70)),\
\(deployJSON("d2c", offsetSeconds: 50))]}
""".utf8))
feedStub.responses["projectId=fp3"] = (200, Data(#"{"deployments":[]}"#.utf8))
let feedAPI = VercelAPI(token: "t", session: feedStub)

let feed5 = try await RefreshCore.fetch(api: feedAPI, watchedProjectIDs: ["fp1", "fp2"], feedLimit: 5)
t.equal(feed5.feed.map(\.id), ["d1a", "d2a", "d1b", "d2b", "d1c"],
        "najnowszy deploy obu projektów + historia do 5 pozycji, posortowane malejąco")
t.equal(feed5.feed.map(\.projectName), ["sklep-online", "blog-firmowy", "sklep-online", "blog-firmowy", "sklep-online"],
        "każda pozycja niesie nazwę swojego projektu")
t.equal(feed5.feed.map(\.projectID), ["fp1", "fp2", "fp1", "fp2", "fp1"], "pozycja niesie też id projektu")
t.equal(feed5.projects.count, 2, "agregat dalej liczy projekty, nie pozycje listy")
t.equal(feed5.projects.first(where: { $0.id == "fp1" })?.latest?.id, "d1a",
        "Project.latest to najnowszy deploy projektu")
t.equal(feed5.projects.first(where: { $0.id == "fp2" })?.latest?.id, "d2a", "to samo dla drugiego projektu")
t.equal(feed5.overall, .ready, "stan zbiorczy bez zmian — liczy się tylko najnowszy deploy projektu")

let feed3 = try await RefreshCore.fetch(api: feedAPI, watchedProjectIDs: ["fp1", "fp2"], feedLimit: 3)
t.equal(feed3.feed.map(\.id), ["d1a", "d2a", "d1b"], "limit 3 zostawia miejsce na jedną pozycję historii")

let feedDefault = try await RefreshCore.fetch(api: feedAPI, watchedProjectIDs: ["fp1", "fp2"])
t.equal(feedDefault.feed.count, 5, "domyślny feedLimit to 5")

let feedHole = try await RefreshCore.fetch(api: feedAPI, watchedProjectIDs: ["fp1", "fp3"], feedLimit: 5)
t.equal(feedHole.feed.map(\.id), ["d1a", "d1b", "d1c"], "projekt bez deployów nie psuje feedu")
t.equal(feedHole.projects.count, 2, "projekt bez deployów zostaje wśród projektów")
t.check(feedHole.projects.first(where: { $0.id == "fp3" })?.latest == nil, "…z latest == nil")

let feedNone = try await RefreshCore.fetch(api: feedAPI, watchedProjectIDs: [], feedLimit: 5)
t.equal(feedNone.feed.count, 0, "brak obserwowanych → pusty feed")

t.suite("RefreshCore — każdy projekt ma gwarantowany wiersz")
// Projekt padnięty dwa dni temu przegrywał globalne przycięcie z projektami wdrażanymi dziś:
// ikona świeciła na czerwono, nagłówek meldował „1 deploy padł", a w popoverze nie było czego kliknąć.
let guardStub = StubSession(runner: t)
let guardBase = 1_754_470_000_000.0
guardStub.responses["/v9/projects"] = (200, Data("""
{"projects":[{"id":"gp1","name":"padniety"},{"id":"gp2","name":"alfa"},\
{"id":"gp3","name":"beta"},{"id":"gp4","name":"gamma"}]}
""".utf8))
func guardDeploy(_ uid: String, _ state: String, offsetSeconds: Double) -> String {
    #"{"uid":"\#(uid)","state":"\#(state)","createdAt":\#(Int(guardBase + offsetSeconds * 1000))}"#
}
guardStub.responses["projectId=gp1"] = (200, Data("""
{"deployments":[\(guardDeploy("e1", "ERROR", offsetSeconds: -172_800)),\
\(guardDeploy("e2", "READY", offsetSeconds: -259_200))]}
""".utf8))
guardStub.responses["projectId=gp2"] = (200, Data("""
{"deployments":[\(guardDeploy("a1", "READY", offsetSeconds: 0)),\
\(guardDeploy("a2", "READY", offsetSeconds: -100))]}
""".utf8))
guardStub.responses["projectId=gp3"] = (200, Data("""
{"deployments":[\(guardDeploy("b1", "READY", offsetSeconds: -10)),\
\(guardDeploy("b2", "READY", offsetSeconds: -200))]}
""".utf8))
guardStub.responses["projectId=gp4"] = (200, Data("""
{"deployments":[\(guardDeploy("g1", "READY", offsetSeconds: -20)),\
\(guardDeploy("g2", "READY", offsetSeconds: -300))]}
""".utf8))
let guardAPI = VercelAPI(token: "t", session: guardStub)
let guardIDs: Set<String> = ["gp1", "gp2", "gp3", "gp4"]

let tight = try await RefreshCore.fetch(api: guardAPI, watchedProjectIDs: guardIDs, feedLimit: 3)
t.equal(tight.overall, .error, "agregat melduje błąd")
t.check(tight.feed.contains { $0.projectID == "gp1" }, "padnięty projekt jest w feedzie mimo limitu 3")
t.equal(tight.feed.map(\.id), ["a1", "b1", "g1", "e1"],
        "cztery projekty → cztery wiersze; limit ustępuje gwarancji")
t.equal(Set(tight.feed.map(\.projectID)).count, tight.feed.count,
        "żaden projekt nie zajmuje drugiego wiersza, zanim każdy dostanie pierwszy")

let roomy = try await RefreshCore.fetch(api: guardAPI, watchedProjectIDs: guardIDs, feedLimit: 10)
t.equal(roomy.feed.map(\.id), ["a1", "b1", "g1", "a2", "b2", "g2", "e1", "e2"],
        "przy zapasie miejsca historia dopełnia listę po najnowszych każdego projektu")
t.check(roomy.feed.contains { $0.id == "e1" } && roomy.feed.contains { $0.id == "e2" },
        "historia padniętego projektu też wchodzi")

t.suite("RefreshCore — remisy i brak createdAt w feedzie")
// Task group kończy się w losowej kolejności, więc remis po createdAt i pozycje bez daty
// muszą mieć rozstrzygnięcie deterministyczne — inaczej lista tasuje się co odświeżenie.
let tieFeedStub = StubSession(runner: t)
tieFeedStub.responses["/v9/projects"] = (200, Data("""
{"projects":[{"id":"tz","name":"zebra"},{"id":"ta","name":"alfa"}]}
""".utf8))
tieFeedStub.responses["projectId=tz"] = (200, Data("""
{"deployments":[{"uid":"z1","state":"READY","createdAt":1754470000000},{"uid":"z0","state":"READY"}]}
""".utf8))
tieFeedStub.responses["projectId=ta"] = (200, Data("""
{"deployments":[{"uid":"a1","state":"READY","createdAt":1754470000000}]}
""".utf8))
let tieFeedAPI = VercelAPI(token: "t", session: tieFeedStub)
var tieFeedOrders: [[String]] = []
for _ in 0..<5 {
    tieFeedOrders.append(try await RefreshCore.fetch(api: tieFeedAPI,
                                                     watchedProjectIDs: ["tz", "ta"],
                                                     feedLimit: 10).feed.map(\.id))
}
t.equal(Set(tieFeedOrders.map { $0.joined(separator: "|") }).count, 1, "pięć przebiegów daje ten sam feed")
t.equal(tieFeedOrders.first ?? [], ["a1", "z1", "z0"],
        "remis rozstrzyga nazwa projektu, a deploy bez createdAt ląduje na końcu")

t.suite("RefreshCore — okno równoległości")
// Bez limitu salwa requestów przy kilkudziesięciu projektach łapie 429, a jeden 429
// wywraca całą migawkę (patrz suita wyżej). Stub mierzy szczyt równoczesnych wywołań.
let concStub = StubSession(runner: t)
concStub.delayNanos = 20_000_000 // 20 ms — tyle, żeby wywołania zdążyły się nałożyć
// ID dwucyfrowe z zerem wiodącym: stub dopasowuje klucze przez `contains`, więc „cw1"
// trafiłoby także w URL projektu „cw11" i dało niejednoznaczne dopasowanie.
let concIDs = (1...12).map { String(format: "cw%02d", $0) }
concStub.responses["/v9/projects"] = (200, Data("""
{"projects":[\(concIDs.map { #"{"id":"\#($0)","name":"\#($0)"}"# }.joined(separator: ","))]}
""".utf8))
for (i, pid) in concIDs.enumerated() {
    concStub.responses["projectId=\(pid)"] = (200, Data("""
    {"deployments":[{"uid":"d-\(pid)","state":"READY","createdAt":\(1754470000000 + i * 1000)}]}
    """.utf8))
}
let concSnap = try await RefreshCore.fetch(api: VercelAPI(token: "t", session: concStub),
                                           watchedProjectIDs: Set(concIDs))
t.equal(concSnap.projects.count, 12, "okno dokłada zadania — wracają wszystkie projekty, nie pierwsze 4")
t.check(concStub.maxInFlight <= 4, "szczyt równoległości \(concStub.maxInFlight) nie przekracza 4")
t.check(concStub.maxInFlight >= 2, "requesty faktycznie biegną równolegle (szczyt \(concStub.maxInFlight))")

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
t.equal(settings.notifyStart, true, "start deployu domyślnie włączony")
t.equal(settings.feedLimit, 5, "domyślnie 5 pozycji na liście")
t.equal(settings.teamID, nil, "domyślnie konto osobiste")

settings.watchedProjectIDs = ["prj_1", "prj_2"]
settings.notifySuccess = false
settings.notifyFailure = false
settings.notifyStart = false
settings.feedLimit = 10
settings.teamID = "team_9"
let reloaded = SettingsStore(defaults: defaults)
t.equal(reloaded.watchedProjectIDs, ["prj_1", "prj_2"], "obserwowane trwają po ponownym wczytaniu")
t.equal(reloaded.notifySuccess, false, "wyłączenie sukcesów trwa")
t.equal(reloaded.notifyFailure, false, "wyłączenie błędów trwa")
t.equal(reloaded.notifyStart, false, "wyłączenie startu trwa")
t.equal(reloaded.feedLimit, 10, "liczba pozycji trwa po ponownym wczytaniu")
t.equal(reloaded.teamID, "team_9", "team trwa")
reloaded.teamID = nil
t.equal(SettingsStore(defaults: defaults).teamID, nil, "powrót do konta osobistego")

t.suite("SettingsStore — sanityzacja feedLimit")
t.equal(SettingsStore.allowedFeedLimits, [3, 5, 10], "dopuszczalne wartości listy")
for value in [3, 5, 10] {
    settings.feedLimit = value
    t.equal(settings.feedLimit, value, "\(value) przechodzi bez zmian")
}
// Ręczna edycja plist albo plik po starszej wersji: wartość spoza zbioru nie może
// dojechać do zapytania `limit=<n>` ani do przycięcia listy.
defaults.set(7, forKey: "feedLimit")
t.equal(settings.feedLimit, 5, "wartość spoza 3/5/10 czytana jako 5")
defaults.set(0, forKey: "feedLimit")
t.equal(settings.feedLimit, 5, "zero czytane jako 5")

t.suite("SettingsStore — ręczny wybór języka")
t.equal(SettingsStore(defaults: defaults).languageOverride, nil, "domyślnie język za systemem")
settings.languageOverride = .pl
t.equal(SettingsStore(defaults: defaults).languageOverride, .pl, "wybór polskiego trwa po ponownym wczytaniu")
settings.languageOverride = .en
t.equal(SettingsStore(defaults: defaults).languageOverride, .en, "wybór angielskiego trwa po ponownym wczytaniu")
settings.languageOverride = nil
t.equal(SettingsStore(defaults: defaults).languageOverride, nil, "powrót do systemowego czyści klucz")
// Ręczna edycja plist albo plik po innej wersji nie może wywrócić języka.
defaults.set("klingon", forKey: "languageOverride")
t.equal(settings.languageOverride, nil, "nieznany kod czytany jako systemowy")
defaults.set(42, forKey: "languageOverride")
t.equal(settings.languageOverride, nil, "wartość innego typu czytana jako systemowy")
defaults.removeObject(forKey: "languageOverride")
defaults.set(-2, forKey: "feedLimit")
t.equal(settings.feedLimit, 5, "wartość ujemna czytana jako 5")
defaults.set("dużo", forKey: "feedLimit")
t.equal(settings.feedLimit, 5, "wartość nie-liczbowa czytana jako 5")
settings.feedLimit = 4
t.equal(SettingsStore(defaults: defaults).feedLimit, 5, "zapis złej wartości też ląduje na 5")
defaults.removePersistentDomain(forName: suiteName)

// MARK: - Aktualizacje: porównanie wersji

t.suite("SemVer.isNewer")
t.check(SemVer.isNewer("1.1.0", than: "1.0.1"), "1.1.0 jest nowsze od 1.0.1")
t.check(SemVer.isNewer("v1.2.0", than: "1.1.0"), "prefiks v nie przeszkadza")
t.check(!SemVer.isNewer("1.1.0", than: "1.1.0"), "ta sama wersja to nie aktualizacja")
t.check(SemVer.isNewer("1.10.0", than: "1.9.0"), "1.10.0 > 1.9.0 — porównanie liczbowe, nie leksykalne")
t.check(!SemVer.isNewer("1.9.0", than: "1.10.0"), "1.9.0 nie jest nowsze od 1.10.0")
t.check(SemVer.isNewer("2.0", than: "1.9.9"), "różna liczba członów: 2.0 > 1.9.9")
t.check(!SemVer.isNewer("1.2", than: "1.2.0"), "1.2 to ta sama wersja co 1.2.0")
t.check(!SemVer.isNewer("wersja-testowa", than: "1.0.0"), "śmieciowy kandydat → false")
t.check(!SemVer.isNewer("2.0.0", than: "śmieć"), "śmieciowa wersja bieżąca → false")
t.check(!SemVer.isNewer("1.2.3-beta", than: "1.2.2"), "człon nieliczbowy wywraca porównanie")
t.check(!SemVer.isNewer("", than: "1.0.0"), "pusty string → false")
t.check(SemVer.equals("1.2", "1.2.0"), "equals dopełnia zerami")
t.check(!SemVer.equals("1.2.1", "1.2.0"), "equals rozróżnia patche")
t.check(!SemVer.equals("śmieć", "śmieć"), "dwa śmiecie to nie ta sama wersja")

// MARK: - Aktualizacje: parsowanie wydania GitHuba

let zipAssetURL = "https://github.com/adrian-zielinski/vercel-bar-macOS/releases/download/v1.2.0/VercelBar.zip"

func releaseJSON(tag: String,
                 assetName: String? = "VercelBar.zip",
                 prerelease: Bool = false,
                 draft: Bool = false) -> Data {
    let assets = assetName.map {
        #"[{"name":"\#($0)","browser_download_url":"\#(zipAssetURL)"}]"#
    } ?? "[]"
    return Data("""
    {"tag_name":"\(tag)",
     "html_url":"https://github.com/adrian-zielinski/vercel-bar-macOS/releases/tag/\(tag)",
     "draft":\(draft),"prerelease":\(prerelease),
     "assets":\(assets)}
    """.utf8)
}

t.suite("UpdateChecker.parseLatestRelease")
do {
    let info = try UpdateChecker.parseLatestRelease(from: releaseJSON(tag: "v1.2.0"),
                                                    currentVersion: "1.1.0")
    t.equal(info?.version, "1.2.0", "nowszy tag daje UpdateInfo bez prefiksu v")
    t.equal(info?.zipURL.absoluteString, zipAssetURL, "URL paczki z assetu")
    t.equal(info?.releaseURL.absoluteString,
            "https://github.com/adrian-zielinski/vercel-bar-macOS/releases/tag/v1.2.0",
            "URL wydania z html_url")

    t.equal(try UpdateChecker.parseLatestRelease(from: releaseJSON(tag: "v1.1.0"),
                                                 currentVersion: "1.1.0"), nil,
            "równy tag → brak aktualizacji")
    t.equal(try UpdateChecker.parseLatestRelease(from: releaseJSON(tag: "v1.0.0"),
                                                 currentVersion: "1.1.0"), nil,
            "starszy tag → brak aktualizacji")
    t.equal(try UpdateChecker.parseLatestRelease(from: releaseJSON(tag: "v1.2.0", assetName: "VercelBar.dmg"),
                                                 currentVersion: "1.1.0"), nil,
            "wydanie bez VercelBar.zip → brak aktualizacji")
    t.equal(try UpdateChecker.parseLatestRelease(from: releaseJSON(tag: "v1.2.0", assetName: nil),
                                                 currentVersion: "1.1.0"), nil,
            "wydanie bez assetów → brak aktualizacji")
    t.equal(try UpdateChecker.parseLatestRelease(from: releaseJSON(tag: "v1.2.0", prerelease: true),
                                                 currentVersion: "1.1.0"), nil,
            "prerelease pomijany")
    t.equal(try UpdateChecker.parseLatestRelease(from: releaseJSON(tag: "v1.2.0", draft: true),
                                                 currentVersion: "1.1.0"), nil,
            "szkic wydania pomijany")
    t.equal(try UpdateChecker.parseLatestRelease(from: releaseJSON(tag: "1.2.0"),
                                                 currentVersion: "1.1.0")?.version, "1.2.0",
            "tag bez prefiksu też przechodzi")

    // Wersja z tagu trafia wprost do paska, więc idzie do UI znormalizowana.
    // `\\n` jest tu escape'em JSON-a (w tagu ląduje prawdziwy znak nowej linii), nie Swifta.
    for tag in ["V1.3.0", " 1.3.0\\n", "1.03.0", "v1.3.0"] {
        t.equal(try UpdateChecker.parseLatestRelease(from: releaseJSON(tag: tag),
                                                     currentVersion: "1.1.0")?.version, "1.3.0",
                "tag \(tag.debugDescription) daje wersję 1.3.0")
    }
    t.equal(try UpdateChecker.parseLatestRelease(from: releaseJSON(tag: "nightly"),
                                                 currentVersion: "1.1.0"), nil,
            "tag nieliczbowy → brak aktualizacji")

    let overHTTP = Data("""
    {"tag_name":"v1.2.0","html_url":"https://github.com/adrian-zielinski/vercel-bar-macOS/releases/tag/v1.2.0",
     "draft":false,"prerelease":false,
     "assets":[{"name":"VercelBar.zip","browser_download_url":"http://example.com/VercelBar.zip"}]}
    """.utf8)
    t.equal(try UpdateChecker.parseLatestRelease(from: overHTTP, currentVersion: "1.1.0"), nil,
            "paczka spoza HTTPS odrzucona")
} catch {
    t.check(false, "parsowanie wydania rzuciło: \(error)")
}

// Kształt wprost z /releases/latest: mnóstwo pól obok, `label` bywa nullem,
// a paczka .dmg stoi na liście przed .zip.
let realShapedRelease = Data("""
{"url":"https://api.github.com/repos/adrian-zielinski/vercel-bar-macOS/releases/1",
 "id":1,"node_id":"RE_kw","tag_name":"v1.3.0","target_commitish":"main","name":"1.3.0",
 "draft":false,"prerelease":false,"created_at":"2026-08-07T09:00:00Z",
 "published_at":"2026-08-07T09:10:00Z","body":"## Co nowego\\n- silnik aktualizacji",
 "html_url":"https://github.com/adrian-zielinski/vercel-bar-macOS/releases/tag/v1.3.0",
 "author":{"login":"adrian-zielinski","id":2},
 "assets":[
   {"id":10,"name":"VercelBar.dmg","label":null,"size":1234567,"download_count":3,
    "content_type":"application/x-apple-diskimage","state":"uploaded",
    "browser_download_url":"https://github.com/adrian-zielinski/vercel-bar-macOS/releases/download/v1.3.0/VercelBar.dmg"},
   {"id":11,"name":"VercelBar.zip","label":null,"size":460800,"download_count":7,
    "content_type":"application/zip","state":"uploaded",
    "browser_download_url":"https://github.com/adrian-zielinski/vercel-bar-macOS/releases/download/v1.3.0/VercelBar.zip"}]}
""".utf8)
do {
    let info = try UpdateChecker.parseLatestRelease(from: realShapedRelease, currentVersion: "1.1.0")
    t.equal(info?.version, "1.3.0", "realistyczna odpowiedź GitHuba parsuje się")
    t.equal(info?.zipURL.lastPathComponent, "VercelBar.zip", "spośród assetów wybrany jest zip, nie dmg")
} catch {
    t.check(false, "realistyczna odpowiedź rzuciła: \(error)")
}

t.suite("UpdateChecker.checkForUpdate — sieć")
t.equal(UpdateEndpoint.latestReleaseURL.absoluteString,
        "https://api.github.com/repos/adrian-zielinski/vercel-bar-macOS/releases/latest",
        "adres najnowszego wydania")

let updStub = StubSession(runner: t)
updStub.responses["releases/latest"] = (200, releaseJSON(tag: "v1.2.0"))
let found = await UpdateChecker.checkForUpdate(session: updStub, currentVersion: "1.1.0")
t.equal(found?.version, "1.2.0", "200 z nowszym tagiem → UpdateInfo")
t.equal(updStub.lastRequest?.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json",
        "nagłówek Accept dla API GitHuba")
t.check(updStub.lastRequest?.value(forHTTPHeaderField: "Authorization") == nil,
        "sprawdzanie aktualizacji idzie anonimowo")

let rateLimited = StubSession(runner: t)
rateLimited.responses["releases/latest"] = (403, Data(#"{"message":"API rate limit exceeded"}"#.utf8))
t.equal(await UpdateChecker.checkForUpdate(session: rateLimited, currentVersion: "1.1.0"), nil,
        "403 (limit zapytań) połykany do nil")

let updOffline = StubSession(runner: t)
updOffline.thrownError = URLError(.notConnectedToInternet)
t.equal(await UpdateChecker.checkForUpdate(session: updOffline, currentVersion: "1.1.0"), nil,
        "brak sieci połykany do nil")

let garbage = StubSession(runner: t)
garbage.responses["releases/latest"] = (200, Data("nie-json".utf8))
t.equal(await UpdateChecker.checkForUpdate(session: garbage, currentVersion: "1.1.0"), nil,
        "nieparsowalna odpowiedź połykana do nil")

// MARK: - Aktualizacje: podmiana bundla na atrapie

@discardableResult
func shell(_ executable: String, _ arguments: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: executable)
    p.arguments = arguments
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return -1 }
    p.waitUntilExit()
    return p.terminationStatus
}

/// Atrapa aplikacji: katalog `.app` z Info.plist, wykonywalną atrapą binarki i podpisem
/// ad-hoc — silnik wymaga nienaruszonej pieczęci, więc fikstura musi być podpisana jak
/// prawdziwa paczka. Testy nigdy nie dotykają prawdziwego VercelBar.app ani kosza użytkownika.
func makeFakeApp(at url: URL, version: String, bundleID: String) throws {
    let fm = FileManager.default
    try fm.createDirectory(at: url.appendingPathComponent("Contents/MacOS"),
                           withIntermediateDirectories: true)
    let plist: [String: Any] = ["CFBundleIdentifier": bundleID,
                                "CFBundleShortVersionString": version,
                                "CFBundleName": "VercelBar",
                                "CFBundleExecutable": "VercelBar"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: url.appendingPathComponent("Contents/Info.plist"))
    let executable = url.appendingPathComponent("Contents/MacOS/VercelBar")
    try Data("atrapa".utf8).write(to: executable)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    if shell("/usr/bin/codesign", ["--force", "--sign", "-", url.path]) != 0 {
        t.check(false, "nie udało się podpisać atrapy \(url.lastPathComponent)")
    }
}

func zipApp(_ app: URL, to zip: URL) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", app.path, zip.path]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
}

func bundleVersion(at app: URL) -> String? {
    guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
          let info = try? PropertyListSerialization.propertyList(from: data, format: nil)
            as? [String: Any] else { return nil }
    return info["CFBundleShortVersionString"] as? String
}

t.suite("UpdateInstallEngine — podmiana na atrapie")
let updRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    .appendingPathComponent("vercelbar-testy-\(UUID().uuidString)", isDirectory: true)
do {
    let fm = FileManager.default

    // Scenariusz 1: zgodna paczka wchodzi na miejsce starej wersji.
    let dest = updRoot.appendingPathComponent("Applications/VercelBar.app")
    try makeFakeApp(at: dest, version: "1.1.0", bundleID: "pl.zielinski.vercelbar")
    let staging = updRoot.appendingPathComponent("staging/VercelBar.app")
    try makeFakeApp(at: staging, version: "1.2.0", bundleID: "pl.zielinski.vercelbar")
    let zip = updRoot.appendingPathComponent("VercelBar.zip")
    t.check(zipApp(staging, to: zip), "ditto spakował atrapę nowej wersji")

    let work = updRoot.appendingPathComponent("work")
    // `moveOldToTrash: false` — atrapa nie ma po co lądować w koszu użytkownika;
    // to ta sama ścieżka kodu, którą aplikacja wybiera, gdy kosz odmówi.
    let outcome = try UpdateInstallEngine.install(zip: zip, destination: dest,
                                                  expectedVersion: "1.2.0",
                                                  workDirectory: work, moveOldToTrash: false)
    t.equal(bundleVersion(at: dest), "1.2.0", "w miejscu docelowym stoi nowa wersja")
    t.equal(outcome.installed, dest, "outcome wskazuje miejsce docelowe")
    if let retired = outcome.retiredOld {
        t.check(fm.fileExists(atPath: retired.path), "stary bundel istnieje po odstawieniu")
        t.equal(bundleVersion(at: retired), "1.1.0", "odstawiony bundel to stara wersja")
        t.check(retired.path.hasPrefix(work.path), "bez kosza stara wersja ląduje w katalogu roboczym")
    } else {
        t.check(false, "brak informacji, gdzie trafiła stara wersja")
    }
    t.check(((try? fm.contentsOfDirectory(atPath: dest.deletingLastPathComponent().path)) ?? [])
                == ["VercelBar.app"],
            "po udanej podmianie obok celu nie zostaje nic poza aplikacją")
    t.check(shell("/usr/bin/codesign", ["--verify", "--strict", dest.path]) == 0,
            "podpis nowej wersji przeżywa podmianę")

    // Scenariusz 2: obcy bundle id — fallback bez podmiany.
    let dest2 = updRoot.appendingPathComponent("Applications2/VercelBar.app")
    try makeFakeApp(at: dest2, version: "1.1.0", bundleID: "pl.zielinski.vercelbar")
    let fake = updRoot.appendingPathComponent("podrobka/VercelBar.app")
    try makeFakeApp(at: fake, version: "1.2.0", bundleID: "pl.zielinski.podrobka")
    let fakeZip = updRoot.appendingPathComponent("Podrobka.zip")
    t.check(zipApp(fake, to: fakeZip), "ditto spakował atrapę z obcym identyfikatorem")
    do {
        _ = try UpdateInstallEngine.install(zip: fakeZip, destination: dest2,
                                            expectedVersion: "1.2.0",
                                            workDirectory: updRoot.appendingPathComponent("work2"),
                                            moveOldToTrash: false)
        t.check(false, "obcy bundle id powinien wywrócić instalację")
    } catch UpdateInstallError.identifierMismatch(let id) {
        t.equal(id, "pl.zielinski.podrobka", "błąd niesie napotkany identyfikator")
    } catch {
        t.check(false, "oczekiwano identifierMismatch, jest: \(error)")
    }
    t.equal(bundleVersion(at: dest2), "1.1.0", "przy obcym bundle id stara wersja zostaje na miejscu")

    // Scenariusz 3: wersja w paczce inna niż zapowiadana przez wydanie.
    do {
        _ = try UpdateInstallEngine.install(zip: zip, destination: dest2,
                                            expectedVersion: "1.3.0",
                                            workDirectory: updRoot.appendingPathComponent("work3"),
                                            moveOldToTrash: false)
        t.check(false, "niezgodna wersja powinna wywrócić instalację")
    } catch UpdateInstallError.versionMismatch(let v) {
        t.equal(v, "1.2.0", "błąd niesie wersję znalezioną w paczce")
    } catch {
        t.check(false, "oczekiwano versionMismatch, jest: \(error)")
    }
    t.equal(bundleVersion(at: dest2), "1.1.0", "przy niezgodnej wersji stara wersja zostaje na miejscu")

    // Scenariusz 4: paczka bez bundla w środku.
    let junk = updRoot.appendingPathComponent("junk/notes.txt")
    try fm.createDirectory(at: junk.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("nic tu nie ma".utf8).write(to: junk)
    let junkZip = updRoot.appendingPathComponent("Junk.zip")
    t.check(zipApp(junk, to: junkZip), "ditto spakował paczkę bez bundla")
    do {
        _ = try UpdateInstallEngine.install(zip: junkZip, destination: dest2,
                                            expectedVersion: "1.2.0",
                                            workDirectory: updRoot.appendingPathComponent("work4"),
                                            moveOldToTrash: false)
        t.check(false, "paczka bez VercelBar.app powinna wywrócić instalację")
    } catch UpdateInstallError.bundleMissing {
        t.check(true, "paczka bez VercelBar.app → bundleMissing")
    } catch {
        t.check(false, "oczekiwano bundleMissing, jest: \(error)")
    }
    t.equal(bundleVersion(at: dest2), "1.1.0", "po odrzuconej paczce stara wersja nadal stoi")

    // Scenariusz 5a: podmiana pada, zanim cokolwiek ruszy starą wersję.
    // Kopiowanie nowego bundla idzie OBOK celu, więc porażka na tym etapie
    // nie ma prawa dotknąć działającej aplikacji.
    let dest5 = updRoot.appendingPathComponent("Applications5/VercelBar.app")
    try makeFakeApp(at: dest5, version: "1.1.0", bundleID: "pl.zielinski.vercelbar")
    let work5 = updRoot.appendingPathComponent("work5")
    do {
        _ = try UpdateInstallEngine.replace(destination: dest5,
                                            with: updRoot.appendingPathComponent("nie-ma-mnie/VercelBar.app"),
                                            workDirectory: work5, moveOldToTrash: false)
        t.check(false, "podmiana nieistniejącym bundlem powinna paść")
    } catch UpdateInstallError.replaceFailed {
        t.check(true, "nieudane przygotowanie nowej wersji → replaceFailed")
    } catch {
        t.check(false, "oczekiwano replaceFailed, jest: \(error)")
    }
    t.equal(bundleVersion(at: dest5), "1.1.0", "porażka przed podmianą zostawia starą wersję na miejscu")
    t.check(((try? fm.contentsOfDirectory(atPath: dest5.deletingLastPathComponent().path)) ?? [])
                .allSatisfy { !$0.hasPrefix(".VercelBar.app.new-") },
            "po porażce nie zostaje ogryzek stagingu obok celu")

    // Scenariusz 5b: krok niszczący już się wykonał — stara wersja jest odstawiona,
    // a wejście nowej pada. To jedyna ścieżka, na której `dest` może zostać pusty,
    // więc ma własny test: rollback musi oddać starą wersję na miejsce.
    let dest5b = updRoot.appendingPathComponent("Applications5b/VercelBar.app")
    try makeFakeApp(at: dest5b, version: "1.1.0", bundleID: "pl.zielinski.vercelbar")
    let retired5b = updRoot.appendingPathComponent("retired5b/VercelBar.app")
    try fm.createDirectory(at: retired5b.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fm.moveItem(at: dest5b, to: retired5b) // odpowiednik `retire`
    do {
        _ = try UpdateInstallEngine.commitReplacement(
            staged: updRoot.appendingPathComponent("nie-ma-mnie/VercelBar.app"),
            destination: dest5b,
            retired: retired5b)
        t.check(false, "wejście nieistniejącej wersji powinno paść")
    } catch UpdateInstallError.replaceFailed {
        t.check(true, "nieudane wejście nowej wersji → replaceFailed")
    } catch {
        t.check(false, "oczekiwano replaceFailed, jest: \(error)")
    }
    t.equal(bundleVersion(at: dest5b), "1.1.0", "rollback oddaje starą wersję na miejsce docelowe")
    t.check(!fm.fileExists(atPath: retired5b.path), "po rollbacku nie zostaje osierocona kopia")

    // Scenariusz 6: bundel bez pliku wykonywalnego — Info.plist to za mało.
    let dest6 = updRoot.appendingPathComponent("Applications6/VercelBar.app")
    try makeFakeApp(at: dest6, version: "1.1.0", bundleID: "pl.zielinski.vercelbar")
    let hollow = updRoot.appendingPathComponent("hollow/VercelBar.app")
    try makeFakeApp(at: hollow, version: "1.2.0", bundleID: "pl.zielinski.vercelbar")
    try fm.removeItem(at: hollow.appendingPathComponent("Contents/MacOS"))
    let hollowZip = updRoot.appendingPathComponent("Hollow.zip")
    t.check(zipApp(hollow, to: hollowZip), "ditto spakował bundel bez binarki")
    do {
        _ = try UpdateInstallEngine.install(zip: hollowZip, destination: dest6,
                                            expectedVersion: "1.2.0",
                                            workDirectory: updRoot.appendingPathComponent("work6"),
                                            moveOldToTrash: false)
        t.check(false, "bundel bez binarki powinien wywrócić instalację")
    } catch UpdateInstallError.executableMissing {
        t.check(true, "bundel bez Contents/MacOS → executableMissing")
    } catch {
        t.check(false, "oczekiwano executableMissing, jest: \(error)")
    }
    t.equal(bundleVersion(at: dest6), "1.1.0", "pusty bundel nie rusza starej wersji")

    // Scenariusz 7: dowiązanie udające bundel.
    let linkDir = updRoot.appendingPathComponent("linked", isDirectory: true)
    try fm.createDirectory(at: linkDir, withIntermediateDirectories: true)
    let linkTarget = updRoot.appendingPathComponent("linkTarget/VercelBar.app")
    try makeFakeApp(at: linkTarget, version: "1.2.0", bundleID: "pl.zielinski.vercelbar")
    try fm.createSymbolicLink(at: linkDir.appendingPathComponent("VercelBar.app"),
                              withDestinationURL: linkTarget)
    do {
        _ = try UpdateInstallEngine.verifiedBundle(in: linkDir, expectedVersion: "1.2.0")
        t.check(false, "dowiązanie nie może udawać bundla")
    } catch UpdateInstallError.bundleMissing {
        t.check(true, "symlink zamiast VercelBar.app → bundleMissing")
    } catch {
        t.check(false, "oczekiwano bundleMissing, jest: \(error)")
    }

    // Scenariusz 7b: paczka naruszona po podpisaniu (obcięty upload, podmieniony zasób).
    let tampered = updRoot.appendingPathComponent("tampered/VercelBar.app")
    try makeFakeApp(at: tampered, version: "1.2.0", bundleID: "pl.zielinski.vercelbar")
    try Data("co innego".utf8).write(to: tampered.appendingPathComponent("Contents/MacOS/VercelBar"))
    do {
        _ = try UpdateInstallEngine.verifiedBundle(in: tampered.deletingLastPathComponent(),
                                                   expectedVersion: "1.2.0")
        t.check(false, "naruszony bundel nie może przejść weryfikacji")
    } catch UpdateInstallError.signatureInvalid {
        t.check(true, "naruszona pieczęć podpisu → signatureInvalid")
    } catch {
        t.check(false, "oczekiwano signatureInvalid, jest: \(error)")
    }

    // Scenariusz 8: prawdziwa paczka z build-app.sh przechodzi weryfikację razem z podpisem.
    // Wersję bierzemy z samej paczki, nie z build-app.sh: sprawdzamy, czy potok pakowania
    // produkuje bundel, który silnik przyjmie, a nie czy ktoś właśnie podbił numer wydania.
    let releaseZip = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("build/VercelBar.zip")
    if fm.fileExists(atPath: releaseZip.path) {
        let unpacked = updRoot.appendingPathComponent("release-unpacked", isDirectory: true)
        do {
            try UpdateInstallEngine.unpack(zip: releaseZip, into: unpacked)
            let built = unpacked.appendingPathComponent("VercelBar.app")
            guard let builtVersion = bundleVersion(at: built) else {
                throw UpdateInstallError.infoPlistUnreadable
            }
            _ = try UpdateInstallEngine.verifiedBundle(in: unpacked, expectedVersion: builtVersion)
            t.check(true, "paczka z build-app.sh przechodzi weryfikację (binarka + podpis)")
        } catch {
            t.check(false, "paczka z build-app.sh odrzucona: \(error)")
        }
    } else {
        t.skip("brak build/VercelBar.zip — uruchom ./Scripts/build-app.sh")
    }
} catch {
    t.check(false, "test podmiany rzucił: \(error)")
}
try? FileManager.default.removeItem(at: updRoot)

t.suite("UpdateInstallEngine — katalog roboczy i restart")
do {
    let work = try UpdateInstallEngine.makeWorkDirectory()
    t.check(FileManager.default.fileExists(atPath: work.path), "katalog roboczy powstaje")
    t.check(work.lastPathComponent.hasPrefix("vercelbar-update-"), "katalog roboczy w tmp, z rozpoznawalną nazwą")
    let second = try UpdateInstallEngine.makeWorkDirectory()
    t.check(second != work, "każde wywołanie daje osobny katalog")
    try? FileManager.default.removeItem(at: work)
    try? FileManager.default.removeItem(at: second)
} catch {
    t.check(false, "tworzenie katalogu roboczego rzuciło: \(error)")
}

let restartCmd = UpdateInstallEngine.restartShellCommand(pid: 4242,
                                                         destination: URL(fileURLWithPath: "/Applications/VercelBar.app"))
t.check(restartCmd.contains("kill -0 4242"), "polecenie czeka na wyjście procesu o podanym pid")
t.check(restartCmd.contains("-lt 150"), "czekanie ma granicę — powłoka nie wisi w nieskończoność")
t.check(restartCmd.contains("for i in 1 2 3"), "trzy podejścia do open")
t.check(restartCmd.contains("open -R '/Applications/VercelBar.app'"),
        "ostatnia deska ratunku pokazuje aplikację w Finderze")

/// Cytowanie sprawdzone wykonaniem: funkcja powłoki przesłania `open` i zapisuje
/// argument, który do niej faktycznie doszedł. Pid nieistniejącego procesu wychodzi
/// z pętli od razu, więc nic się nie uruchamia.
func capturedOpenArgument(_ path: String) -> String? {
    let out = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("vercelbar-open-\(UUID().uuidString)")
    let command = UpdateInstallEngine.restartShellCommand(pid: 999_999,
                                                          destination: URL(fileURLWithPath: path))
    let script = "open() { printf '%s' \"$1\" > '\(out.path)'; }; " + command
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", script]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    p.waitUntilExit()
    defer { try? FileManager.default.removeItem(at: out) }
    return try? String(contentsOf: out, encoding: .utf8)
}

for path in ["/Applications/VercelBar.app",
             "/Users/x/My Apps/VercelBar.app",
             "/Users/o'brien/VercelBar.app",
             "/Users/x/$(whoami)/VercelBar.app",
             "/Users/x/`id`;rm -rf ~/VercelBar.app"] {
    t.equal(capturedOpenArgument(path), path, "ścieżka dochodzi do open dosłownie: \(path)")
}

// MARK: - Ikona paska menu

t.suite("StatusIconRenderer")
t.equal(StatusIconRenderer.pulseAlpha(phase: 0), 0.55, "puls w fazie 0 → 0,55")
t.equal(StatusIconRenderer.pulseAlpha(phase: 0.5), 1.0, "puls w fazie 0,5 → 1,0")
t.check(abs(StatusIconRenderer.pulseAlpha(phase: 1.0) - 0.55) < 0.0001, "puls w fazie 1,0 wraca do 0,55")
let phaseOrigin = Date(timeIntervalSinceReferenceDate: 0)
t.equal(StatusIconRenderer.pulsePhase(at: phaseOrigin), 0, "faza w zerze odniesienia → 0")
t.equal(StatusIconRenderer.pulsePhase(at: Date(timeIntervalSinceReferenceDate: 0.55)), 0.5,
        "pół okresu (1,1 s) → faza 0,5")
t.check(abs(StatusIconRenderer.pulsePhase(at: Date(timeIntervalSinceReferenceDate: 1.1))) < 0.0001,
        "pełny okres wraca do fazy 0")
t.equal(StatusIconRenderer.pulsePeriod, 1.1, "okres pulsu 1,1 s")
t.equal(StatusIconRenderer.pulseFrameInterval, 0.125, "8 FPS")

t.suite("PulsePolicy")
let t0 = Date(timeIntervalSince1970: 1_754_470_000)
let buildIDs: Set<String> = ["dpl_1"]
let idle = PulsePolicy.evaluate(overall: .ready, buildingDeployIDs: [], previous: .init(),
                                now: t0, reduceMotion: false)
t.equal(idle.shouldPulse, false, "brak builda → bez pulsu")
t.equal(idle.state, PulsePolicy.State(), "spoczynek czyści śledzenie")

let start = PulsePolicy.evaluate(overall: .building, buildingDeployIDs: buildIDs, previous: .init(),
                                 now: t0, reduceMotion: false)
t.equal(start.shouldPulse, true, "nowy build pulsuje")
t.equal(start.state.deployIDs, buildIDs, "śledzi id aktywnych deployów")
t.equal(start.state.startedAt, t0, "zeruje stoper pulsu")

let still = PulsePolicy.evaluate(overall: .building, buildingDeployIDs: buildIDs, previous: start.state,
                                 now: t0.addingTimeInterval(20 * 60), reduceMotion: false)
t.equal(still.shouldPulse, true, "ten sam build po 20 min nadal pulsuje")
t.equal(still.state.startedAt, t0, "stoper pulsu nie restartuje się przy tym samym id")

let capped = PulsePolicy.evaluate(overall: .building, buildingDeployIDs: buildIDs, previous: start.state,
                                  now: t0.addingTimeInterval(PulsePolicy.maxContinuous),
                                  reduceMotion: false)
t.equal(capped.shouldPulse, false, "ten sam build po 45 min przestaje pulsować")
t.equal(capped.state.deployIDs, buildIDs, "śledzenie zostaje, żeby nie odpalić pulsu od nowa")

let reduced = PulsePolicy.evaluate(overall: .building, buildingDeployIDs: buildIDs, previous: .init(),
                                   now: t0, reduceMotion: true)
t.equal(reduced.shouldPulse, false, "Reduce Motion → bez pulsu")

let errored = PulsePolicy.evaluate(overall: .error, buildingDeployIDs: buildIDs, previous: start.state,
                                   now: t0.addingTimeInterval(5), reduceMotion: false)
t.equal(errored.shouldPulse, false, "ERROR ma pierwszeństwo — ikona nie pulsuje")
t.equal(errored.state, PulsePolicy.State(), "błąd czyści śledzenie")

let nextBuild = PulsePolicy.evaluate(overall: .building, buildingDeployIDs: ["dpl_2"],
                                     previous: start.state,
                                     now: t0.addingTimeInterval(46 * 60), reduceMotion: false)
t.equal(nextBuild.shouldPulse, true, "nowe id po limicie znowu pulsuje")
t.equal(nextBuild.state.deployIDs, ["dpl_2"], "śledzi nowy deploy")

let pA = Project(id: "p1", name: "a", latest: summary(id: "d1", state: .building))
let pB = Project(id: "p2", name: "b", latest: summary(id: "d2", state: .ready))
t.equal(PulsePolicy.activeDeployIDs(in: [pA, pB]), ["d1"], "tylko aktywne latest wchodzą do pulsu")
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
t.check(matchesHex(resolved(Theme.updateBarBg, .aqua), 0x0064e0, alpha: 0.07), "pasek aktualizacji w jasnym to błękit 7 %")
t.check(matchesHex(resolved(Theme.updateBarBg, .darkAqua), 0x0a84ff, alpha: 0.12), "pasek aktualizacji w ciemnym to błękit 12 %")

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
