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
t.equal(StatusAggregator.headline(for: Array(repeating: .error, count: 22)), "22 deploye padły", "nagłówek 22 błędów")
t.equal(StatusAggregator.headline(for: []), "Brak obserwowanych projektów", "nagłówek pusty")
t.equal(StatusAggregator.headline(for: [.canceled, .unknown]), "Brak obserwowanych projektów", "canceled + unknown → nagłówek pusty")

t.suite("PollScheduler")
t.equal(PollScheduler.interval(anyActive: false), 30, "spokój → 30 s")
t.equal(PollScheduler.interval(anyActive: true), 10, "build w toku → 10 s")

t.finish()
