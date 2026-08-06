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

t.suite("DeployState")
t.equal(DeployState(rawAPI: "READY"), .ready, "READY parsuje się")
t.equal(DeployState(rawAPI: "error"), .error, "wielkość liter bez znaczenia")
t.equal(DeployState(rawAPI: "INITIALIZING"), .initializing, "INITIALIZING parsuje się")
t.equal(DeployState(rawAPI: "COŚNOWEGO"), .queued, "nieznany stan spada do queued")
t.check(DeployState.building.isActive && DeployState.queued.isActive && DeployState.initializing.isActive,
        "building/queued/initializing są aktywne")
t.check(!DeployState.ready.isActive && !DeployState.error.isActive && !DeployState.canceled.isActive,
        "ready/error/canceled nie są aktywne")

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
    let d = list[0]
    t.equal(d.id, "dpl_abc123", "id z uid")
    t.equal(d.state, .building, "stan BUILDING")
    t.equal(d.branch, "feat/koszyk", "gałąź z meta github")
    t.equal(d.commitMessage, "dodaj podsumowanie zamówienia", "commit z meta github")
    t.equal(d.previewURL?.absoluteString, "https://sklep-online-git-feat-koszyk.vercel.app", "previewURL dostaje https://")
    t.equal(d.inspectorURL?.absoluteString, "https://vercel.com/studio-nord/sklep-online/dpl_abc123", "inspectorURL wprost")
    t.equal(d.createdAt, Date(timeIntervalSince1970: 1_754_470_000), "createdAt z milisekund")
    t.equal(d.buildingAt, Date(timeIntervalSince1970: 1_754_470_005), "buildingAt z milisekund")
    t.equal(d.duration, nil, "brak duration bez ready")
} catch { t.check(false, "dekodowanie deploymentów rzuciło: \(error)") }

t.suite("Dekodowanie deploymentu READY + duration")
let readyJSON = Data("""
{"deployments":[{
  "uid":"dpl_done","state":"READY","createdAt":1754470000000,
  "buildingAt":1754470002000,"ready":1754470040000,
  "meta":{"gitlabCommitRef":"main","gitlabCommitMessage":"aktualizacja zależności"}
}]}
""".utf8)
do {
    let d = try APIDecoding.deployments(from: readyJSON)[0]
    t.equal(d.duration, 38, "duration = ready − buildingAt")
    t.equal(d.branch, "main", "gałąź z meta gitlab")
} catch { t.check(false, "dekodowanie READY rzuciło: \(error)") }

t.suite("Dekodowanie /v9/projects, /v2/user, /v2/teams")
let projectsJSON = Data("""
{"projects":[{"id":"prj_1","name":"sklep-online"},{"id":"prj_2","name":"blog-firmowy"}]}
""".utf8)
do {
    let ps = try APIDecoding.projects(from: projectsJSON)
    t.equal(ps.map(\.name), ["sklep-online", "blog-firmowy"], "projekty: id i nazwy")
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

t.finish()
