# VercelBar — plan implementacji

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Natywna aplikacja paska menu macOS pokazująca na żywo stan deployów wybranych projektów Vercel, z powiadomieniami o błędach i sukcesach.

**Architecture:** SwiftPM z dwoma modułami: `VercelBarKit` (modele, klient API, agregacja stanu, silnik powiadomień, Keychain, ustawienia — wszystko testowalne bez UI) i `VercelBar` (SwiftUI `MenuBarExtra` + okno ustawień). Testy jako wykonywalny runner `vercelbar-tests` (wzorzec `skryba-tests`). Odpytywanie REST API Vercela co 30 s (10 s przy aktywnym buildzie).

**Tech Stack:** Swift 6 (language mode v5), SwiftUI MenuBarExtra (macOS 14+), URLSession, Security (Keychain), UserNotifications, ServiceManagement. Zero zależności zewnętrznych.

**Źródła prawdy:**
- Spec: `docs/superpowers/specs/2026-08-06-vercelbar-design.md`
- Makiety (dokładne kolory, wymiary, animacje): `docs/design/VercelBar.dc.html`, `docs/design/VercelBar Popover.dc.html`, `docs/design/VercelBar Settings.dc.html`

**Konwencje:** komentarze i komunikaty po polsku (jak w Skrybie). Wszystkie komendy uruchamiaj z katalogu głównego repo VercelBar: `~/VercelBar`. Commity po polsku, z dopiskiem `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

**Kolory ze schematu (jasny / ciemny):**

| Stan | Tekst/kropka jasny | Tekst/kropka ciemny | Tło badge jasny | Tło badge ciemny |
|---|---|---|---|---|
| Ready | `#1d7f38` | `#30d158` | zieleń 10 % | zieleń 15 % |
| Building | `#0064e0` | `#0a84ff` | błękit 10 % | błękit 17 % |
| Error | `#d70015` | `#ff453a` | czerwień 9 % | czerwień 17 % |
| Queued/szary | `#6e6e73` | `#98989d` | szarość 8 % | biel 11 % |

---

## Struktura plików (docelowa)

```
Package.swift
Sources/
  VercelBarKit/
    Models.swift            — DeployState, DeploymentSummary, Project, Team, VercelUser
    APIDecoding.swift       — dekodowanie JSON z API (v2/user, v2/teams, v9/projects, v6/deployments)
    VercelAPI.swift         — klient HTTP (protokół HTTPSession do wstrzykiwania w testach)
    StatusAggregator.swift  — stan zbiorczy + nagłówek popovera
    PollScheduler.swift     — dobór interwału odpytywania
    Format.swift            — czas względny i czas trwania po polsku
    NotificationEngine.swift— przejścia stanów → zdarzenia powiadomień, deduplikacja
    KeychainStore.swift     — token w Keychain
    SettingsStore.swift     — UserDefaults: obserwowane projekty, przełączniki, team
    Theme.swift             — kolory jasne/ciemne (NSColor dynamiczne)
    StatusIconRenderer.swift— ikona paska menu (NSImage) + funkcja pulsu
  VercelBar/
    VercelBarApp.swift      — @main, MenuBarExtra + Window ustawień
    AppModel.swift          — pętla odpytywania, fazy, powiadomienia, puls ikony
    NotificationPresenter.swift — UNUserNotificationCenter + klik otwiera URL
    PopoverView.swift       — popover: nagłówek, lista, stopka, warianty
    ProjectRowView.swift    — wiersz projektu (hover, badge, pasek postępu, rozbłysk)
    SettingsView.swift      — okno 480×380: Konto / Projekty / przełączniki
  vercelbar-tests/
    main.swift              — runner testów rdzenia
Scripts/
  MakeIcon.swift            — generuje AppIcon.icns (trójkąt na ciemnym tle)
  build-app.sh              — buduje VercelBar.app + zip (adaptacja ze Skryby)
```

---

### Task 1: Szkielet pakietu i harness testowy

**Files:**
- Create: `Package.swift`
- Create: `Sources/VercelBarKit/Models.swift` (tymczasowo pusty typ)
- Create: `Sources/VercelBar/VercelBarApp.swift` (tymczasowa zaślepka)
- Create: `Sources/vercelbar-tests/main.swift`
- Create: `.gitignore`

- [ ] **Step 1: Napisz `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VercelBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VercelBarKit", targets: ["VercelBarKit"]),
        .executable(name: "vercelbar", targets: ["VercelBar"]),
        .executable(name: "vercelbar-tests", targets: ["vercelbar-tests"]),
    ],
    targets: [
        // Rdzeń: modele, klient API, logika stanów i powiadomień. Bez UI.
        .target(name: "VercelBarKit", swiftSettings: [.swiftLanguageMode(.v5)]),

        // Aplikacja paska menu (SwiftUI).
        .executableTarget(
            name: "VercelBar",
            dependencies: ["VercelBarKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // Testy rdzenia jako wykonywalny runner (działa bez XCTest).
        .executableTarget(
            name: "vercelbar-tests",
            dependencies: ["VercelBarKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

- [ ] **Step 2: Napisz `.gitignore`**

```
.build/
build/
.DS_Store
```

- [ ] **Step 3: Napisz zaślepki źródeł**

`Sources/VercelBarKit/Models.swift`:

```swift
import Foundation

// Modele domeny — wypełniane w Tasku 2.
public enum VercelBarKitMarker {}
```

`Sources/VercelBar/VercelBarApp.swift`:

```swift
import SwiftUI
import VercelBarKit

@main
struct VercelBarApp: App {
    var body: some Scene {
        // Docelowe MenuBarExtra powstaje w Tasku 11.
        Settings { Text("VercelBar") }
    }
}
```

`Sources/vercelbar-tests/main.swift`:

```swift
import Foundation
import VercelBarKit

// Lekki harness testowy (wzorzec skryba-tests; nie wymaga XCTest ani Xcode).

final class Runner {
    var passed = 0
    var failed = 0

    func suite(_ name: String) { print("\n▸ \(name)") }

    func check(_ condition: Bool, _ message: String) {
        if condition { passed += 1; print("  ✓ \(message)") }
        else { failed += 1; print("  ✗ \(message)") }
    }

    func equal<T: Equatable>(_ a: T, _ b: T, _ message: String) {
        check(a == b, "\(message)  [\(a) == \(b)]")
    }

    func finish() -> Never {
        print("\n— Wynik: \(passed) zaliczonych, \(failed) niezaliczonych —")
        fflush(stdout)
        exit(failed == 0 ? 0 : 1)
    }
}

let t = Runner()

t.suite("Harness")
t.check(true, "runner działa")

t.finish()
```

- [ ] **Step 4: Zbuduj i odpal testy**

Run: `swift build && swift run vercelbar-tests`
Expected: build OK, wyjście zawiera `✓ runner działa` i `0 niezaliczonych`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Szkielet pakietu SwiftPM i harness testowy"
```

---

### Task 2: Modele domeny i parsowanie odpowiedzi API

Vercel zwraca stany deployu jako `READY`, `ERROR`, `BUILDING`, `QUEUED`, `INITIALIZING`, `CANCELED` (pole `state` w `/v6/deployments`, `readyState` w innych miejscach). Czasy to epoch w milisekundach. Gałąź i commit siedzą w `meta` pod kluczami zależnymi od dostawcy gita (`githubCommitRef`, `gitlabCommitRef`, `bitbucketCommitRef` itd.).

**Files:**
- Modify: `Sources/VercelBarKit/Models.swift` (zastąp całość)
- Create: `Sources/VercelBarKit/APIDecoding.swift`
- Modify: `Sources/vercelbar-tests/main.swift` (dopisz suity przed `t.finish()`)

- [ ] **Step 1: Dopisz failujące testy do `Sources/vercelbar-tests/main.swift`** (przed `t.finish()`)

```swift
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
```

- [ ] **Step 2: Odpal testy — mają failować kompilacją**

Run: `swift run vercelbar-tests`
Expected: błąd kompilacji (`cannot find 'DeployState'`).

- [ ] **Step 3: Zastąp `Sources/VercelBarKit/Models.swift`**

```swift
import Foundation

/// Stan deployu z API Vercela.
public enum DeployState: String, Equatable, Sendable {
    case ready = "READY"
    case error = "ERROR"
    case building = "BUILDING"
    case queued = "QUEUED"
    case initializing = "INITIALIZING"
    case canceled = "CANCELED"

    /// Nieznane wartości spadają do `.queued` (neutralny szary).
    public init(rawAPI: String) {
        self = DeployState(rawValue: rawAPI.uppercased()) ?? .queued
    }

    /// Deploy w toku — INITIALIZING traktujemy jak BUILDING (spec).
    public var isActive: Bool {
        self == .building || self == .initializing || self == .queued
    }
}

/// Najnowszy deploy projektu w formie potrzebnej UI i powiadomieniom.
public struct DeploymentSummary: Equatable, Sendable {
    public let id: String
    public let state: DeployState
    public let branch: String?
    public let commitMessage: String?
    public let createdAt: Date
    public let buildingAt: Date?
    public let readyAt: Date?
    public let previewURL: URL?
    public let inspectorURL: URL?

    public init(id: String, state: DeployState, branch: String?, commitMessage: String?,
                createdAt: Date, buildingAt: Date?, readyAt: Date?,
                previewURL: URL?, inspectorURL: URL?) {
        self.id = id
        self.state = state
        self.branch = branch
        self.commitMessage = commitMessage
        self.createdAt = createdAt
        self.buildingAt = buildingAt
        self.readyAt = readyAt
        self.previewURL = previewURL
        self.inspectorURL = inspectorURL
    }

    /// Czas budowania w sekundach (dla zakończonych deployów).
    public var duration: TimeInterval? {
        guard let readyAt else { return nil }
        return readyAt.timeIntervalSince(buildingAt ?? createdAt)
    }
}

public struct Project: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public var latest: DeploymentSummary?

    public init(id: String, name: String, latest: DeploymentSummary? = nil) {
        self.id = id
        self.name = name
        self.latest = latest
    }
}

public struct Team: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let slug: String

    public init(id: String, name: String, slug: String) {
        self.id = id
        self.name = name
        self.slug = slug
    }
}

public struct VercelUser: Equatable, Sendable {
    public let id: String
    public let username: String
    public let name: String?

    public init(id: String, username: String, name: String?) {
        self.id = id
        self.username = username
        self.name = name
    }
}
```

- [ ] **Step 4: Napisz `Sources/VercelBarKit/APIDecoding.swift`**

```swift
import Foundation

/// Dekodowanie surowych odpowiedzi API Vercela na modele domeny.
public enum APIDecoding {

    struct DeploymentsEnvelope: Decodable {
        struct Item: Decodable {
            let uid: String
            let state: String?
            let readyState: String?
            let url: String?
            let inspectorUrl: String?
            let createdAt: Double?
            let created: Double?
            let buildingAt: Double?
            let ready: Double?
            let meta: [String: String]?
        }
        let deployments: [Item]
    }

    struct ProjectsEnvelope: Decodable {
        struct Item: Decodable {
            let id: String
            let name: String
        }
        let projects: [Item]
    }

    struct UserEnvelope: Decodable {
        struct U: Decodable {
            let uid: String
            let username: String
            let name: String?
        }
        let user: U
    }

    struct TeamsEnvelope: Decodable {
        struct Item: Decodable {
            let id: String
            let name: String
            let slug: String
        }
        let teams: [Item]
    }

    private static func date(fromMs ms: Double?) -> Date? {
        ms.map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    /// Gałąź/commit siedzą w meta pod kluczem zależnym od dostawcy gita.
    private static func metaValue(_ meta: [String: String]?, suffix: String) -> String? {
        guard let meta else { return nil }
        for provider in ["github", "gitlab", "bitbucket"] {
            if let v = meta[provider + suffix] { return v }
        }
        return nil
    }

    public static func deployments(from data: Data) throws -> [DeploymentSummary] {
        let env = try JSONDecoder().decode(DeploymentsEnvelope.self, from: data)
        return env.deployments.map { item in
            DeploymentSummary(
                id: item.uid,
                state: DeployState(rawAPI: item.state ?? item.readyState ?? "QUEUED"),
                branch: metaValue(item.meta, suffix: "CommitRef"),
                commitMessage: metaValue(item.meta, suffix: "CommitMessage"),
                createdAt: date(fromMs: item.createdAt ?? item.created) ?? Date(timeIntervalSince1970: 0),
                buildingAt: date(fromMs: item.buildingAt),
                readyAt: date(fromMs: item.ready),
                previewURL: item.url.flatMap { URL(string: "https://\($0)") },
                inspectorURL: item.inspectorUrl.flatMap(URL.init(string:))
            )
        }
    }

    public static func projects(from data: Data) throws -> [Project] {
        try JSONDecoder().decode(ProjectsEnvelope.self, from: data)
            .projects.map { Project(id: $0.id, name: $0.name) }
    }

    public static func user(from data: Data) throws -> VercelUser {
        let u = try JSONDecoder().decode(UserEnvelope.self, from: data).user
        return VercelUser(id: u.uid, username: u.username, name: u.name)
    }

    public static func teams(from data: Data) throws -> [Team] {
        try JSONDecoder().decode(TeamsEnvelope.self, from: data)
            .teams.map { Team(id: $0.id, name: $0.name, slug: $0.slug) }
    }
}
```

- [ ] **Step 5: Odpal testy**

Run: `swift run vercelbar-tests`
Expected: wszystkie suity zielone, `0 niezaliczonych`.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "Modele domeny i dekodowanie odpowiedzi API Vercela"
```

---

### Task 3: Agregacja stanu zbiorczego i nagłówek popovera

**Files:**
- Create: `Sources/VercelBarKit/StatusAggregator.swift`
- Create: `Sources/VercelBarKit/PollScheduler.swift`
- Modify: `Sources/vercelbar-tests/main.swift` (dopisz przed `t.finish()`)

- [ ] **Step 1: Dopisz failujące testy**

```swift
// MARK: - Agregacja stanu

t.suite("StatusAggregator")
t.equal(StatusAggregator.aggregate([.ready, .ready]), .ready, "same ready → ready")
t.equal(StatusAggregator.aggregate([.ready, .building]), .building, "building wygrywa z ready")
t.equal(StatusAggregator.aggregate([.building, .error]), .error, "error wygrywa ze wszystkim")
t.equal(StatusAggregator.aggregate([.ready, .queued]), .building, "queued liczy się jak building")
t.equal(StatusAggregator.aggregate([.canceled, .ready]), .ready, "canceled nie zmienia stanu")
t.equal(StatusAggregator.aggregate([.canceled]), .idle, "same canceled → idle")
t.equal(StatusAggregator.aggregate([]), .idle, "pusto → idle")

t.suite("Nagłówek popovera")
t.equal(StatusAggregator.headline(for: [.ready, .ready]), "Wszystko wdrożone", "nagłówek ready")
t.equal(StatusAggregator.headline(for: [.ready, .building]), "Build w toku…", "nagłówek building")
t.equal(StatusAggregator.headline(for: [.error, .ready]), "1 deploy padł", "nagłówek 1 błąd")
t.equal(StatusAggregator.headline(for: [.error, .error, .ready]), "2 deploye padły", "nagłówek 2 błędy")
t.equal(StatusAggregator.headline(for: [.error, .error, .error, .error, .error]), "5 deployów padło", "nagłówek 5 błędów")
t.equal(StatusAggregator.headline(for: []), "Brak obserwowanych projektów", "nagłówek pusty")

t.suite("PollScheduler")
t.equal(PollScheduler.interval(anyActive: false), 30, "spokój → 30 s")
t.equal(PollScheduler.interval(anyActive: true), 10, "build w toku → 10 s")
```

- [ ] **Step 2: Odpal testy — fail kompilacji**

Run: `swift run vercelbar-tests`
Expected: `cannot find 'StatusAggregator'`.

- [ ] **Step 3: Napisz `Sources/VercelBarKit/StatusAggregator.swift`**

```swift
import Foundation

/// Stan zbiorczy dla ikony paska menu i nagłówka popovera.
public enum AggregateState: Equatable, Sendable {
    case ready
    case building
    case error
    case idle // brak danych albo same canceled
}

public enum StatusAggregator {

    /// Priorytet: Error > Building (w tym Queued/Initializing) > Ready. Canceled pomijany.
    public static func aggregate(_ states: [DeployState]) -> AggregateState {
        if states.contains(.error) { return .error }
        if states.contains(where: { $0.isActive }) { return .building }
        if states.contains(.ready) { return .ready }
        return .idle
    }

    public static func headline(for states: [DeployState]) -> String {
        switch aggregate(states) {
        case .error:
            let n = states.filter { $0 == .error }.count
            return "\(n) \(polishDeploys(n)) \(polishFell(n))"
        case .building: return "Build w toku…"
        case .ready: return "Wszystko wdrożone"
        case .idle: return "Brak obserwowanych projektów"
        }
    }

    private static func polishDeploys(_ n: Int) -> String {
        if n == 1 { return "deploy" }
        let last = n % 10, lastTwo = n % 100
        if (2...4).contains(last) && !(12...14).contains(lastTwo) { return "deploye" }
        return "deployów"
    }

    private static func polishFell(_ n: Int) -> String {
        if n == 1 { return "padł" }
        let last = n % 10, lastTwo = n % 100
        if (2...4).contains(last) && !(12...14).contains(lastTwo) { return "padły" }
        return "padło"
    }
}
```

- [ ] **Step 4: Napisz `Sources/VercelBarKit/PollScheduler.swift`**

```swift
import Foundation

/// Dobór interwału odpytywania API.
public enum PollScheduler {
    /// 30 s w spoczynku, 10 s gdy jakikolwiek obserwowany deploy jest aktywny.
    public static func interval(anyActive: Bool) -> TimeInterval {
        anyActive ? 10 : 30
    }
}
```

- [ ] **Step 5: Odpal testy**

Run: `swift run vercelbar-tests`
Expected: zielono, `0 niezaliczonych`.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "Agregacja stanu zbiorczego, nagłówek popovera i interwały odpytywania"
```

---

### Task 4: Formatowanie czasu po polsku

Design pokazuje: „teraz", „40 s temu", „2 min temu", „1 godz. temu", „wczoraj" oraz czasy trwania „38 s", „2 min 06 s" i zegar „odświeżono 12:04".

**Files:**
- Create: `Sources/VercelBarKit/Format.swift`
- Modify: `Sources/vercelbar-tests/main.swift`

- [ ] **Step 1: Dopisz failujące testy**

```swift
// MARK: - Formatowanie czasu

t.suite("Format.relative")
let now = Date(timeIntervalSince1970: 1_754_470_000)
func ago(_ s: TimeInterval) -> Date { now.addingTimeInterval(-s) }
t.equal(Format.relative(ago(10), now: now), "teraz", "poniżej 45 s → teraz")
t.equal(Format.relative(ago(50), now: now), "50 s temu", "sekundy")
t.equal(Format.relative(ago(120), now: now), "2 min temu", "minuty")
t.equal(Format.relative(ago(3600), now: now), "1 godz. temu", "godziny")
t.equal(Format.relative(ago(5 * 3600), now: now), "5 godz. temu", "kilka godzin")
t.equal(Format.relative(ago(30 * 3600), now: now), "wczoraj", "24–48 h → wczoraj")
t.equal(Format.relative(ago(3 * 86_400), now: now), "3 dni temu", "dni")

t.suite("Format.duration")
t.equal(Format.duration(38), "38 s", "sekundy")
t.equal(Format.duration(126), "2 min 06 s", "minuty z zerem wiodącym sekund")
t.equal(Format.duration(60), "1 min 00 s", "równa minuta")

t.suite("Format.clock")
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Europe/Warsaw")!
let noon = cal.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 12, minute: 4))!
t.equal(Format.clock(noon, timeZone: cal.timeZone), "12:04", "zegar HH:mm")
```

- [ ] **Step 2: Odpal testy — fail kompilacji**

Run: `swift run vercelbar-tests`
Expected: `cannot find 'Format'`.

- [ ] **Step 3: Napisz `Sources/VercelBarKit/Format.swift`**

```swift
import Foundation

/// Formatowanie czasu po polsku dla popovera i powiadomień.
public enum Format {

    public static func relative(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(date))
        if s < 45 { return "teraz" }
        if s < 90 { return "\(Int(s)) s temu" }
        let minutes = Int(s / 60)
        if minutes < 60 { return "\(minutes) min temu" }
        let hours = Int(s / 3600)
        if hours < 24 { return "\(hours) godz. temu" }
        let days = Int(s / 86_400)
        if days < 2 { return "wczoraj" }
        return "\(days) dni temu"
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s < 60 { return "\(s) s" }
        return "\(s / 60) min \(String(format: "%02d", s % 60)) s"
    }

    public static func clock(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = timeZone
        return f.string(from: date)
    }
}
```

- [ ] **Step 4: Odpal testy**

Run: `swift run vercelbar-tests`
Expected: zielono. Uwaga: `relative(ago(50))` przechodzi przez gałąź `s < 90` → „50 s temu".

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Formatowanie czasu względnego i czasu trwania po polsku"
```

---

### Task 5: Silnik powiadomień

Reguły ze specu: powiadom o przejściu najnowszego deployu w ERROR; powiadom o sukcesie tylko, gdy widzieliśmy ten deploy jako aktywny; cisza przy pierwszym pobraniu (baseline); deduplikacja po id deploymentu.

**Files:**
- Create: `Sources/VercelBarKit/NotificationEngine.swift`
- Modify: `Sources/vercelbar-tests/main.swift`

- [ ] **Step 1: Dopisz failujące testy**

```swift
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
```

- [ ] **Step 2: Odpal testy — fail kompilacji**

Run: `swift run vercelbar-tests`
Expected: `cannot find 'NotificationEngine'`.

- [ ] **Step 3: Napisz `Sources/VercelBarKit/NotificationEngine.swift`**

```swift
import Foundation

/// Zdarzenie do pokazania użytkownikowi.
public struct DeployEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case failed
        case succeeded
    }
    public let kind: Kind
    public let projectName: String
    public let deployment: DeploymentSummary
}

/// Zamienia kolejne migawki stanu projektów na zdarzenia powiadomień.
/// Trzyma baseline per projekt (cisza na pierwszą obserwację) i deduplikuje po id deploymentu.
public struct NotificationEngine {
    private var lastSeen: [String: DeploymentSummary] = [:] // projectID → ostatni znany deploy
    private var notified: Set<String> = []                  // "deployID|kind"

    public init() {}

    public mutating func ingest(projects: [Project]) -> [DeployEvent] {
        var events: [DeployEvent] = []
        for p in projects {
            guard let current = p.latest else { continue }
            defer { lastSeen[p.id] = current }
            guard let previous = lastSeen[p.id] else { continue } // baseline — bez powiadomień

            if current.state == .error {
                let key = current.id + "|failed"
                let alreadyErrored = previous.id == current.id && previous.state == .error
                if !alreadyErrored && !notified.contains(key) {
                    notified.insert(key)
                    events.append(DeployEvent(kind: .failed, projectName: p.name, deployment: current))
                }
            }

            if current.state == .ready {
                let key = current.id + "|succeeded"
                let watchedInProgress = previous.id == current.id && previous.state.isActive
                if watchedInProgress && !notified.contains(key) {
                    notified.insert(key)
                    events.append(DeployEvent(kind: .succeeded, projectName: p.name, deployment: current))
                }
            }
        }
        return events
    }
}
```

- [ ] **Step 4: Odpal testy**

Run: `swift run vercelbar-tests`
Expected: zielono.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Silnik powiadomień: przejścia stanów, baseline i deduplikacja"
```

---

### Task 6: Klient VercelAPI

**Files:**
- Create: `Sources/VercelBarKit/VercelAPI.swift`
- Modify: `Sources/vercelbar-tests/main.swift`

- [ ] **Step 1: Dopisz failujące testy** (stub sesji + await w main.swift działa, bo to top-level code)

```swift
// MARK: - Klient VercelAPI

final class StubSession: HTTPSession, @unchecked Sendable {
    var responses: [String: (Int, Data)] = [:] // fragment URL → (status, body)
    var lastRequest: URLRequest?
    var thrownError: Error?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        if let thrownError { throw thrownError }
        let url = request.url!.absoluteString
        for (fragment, (status, body)) in responses where url.contains(fragment) {
            let resp = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
            return (body, resp)
        }
        fatalError("brak stubu dla \(url)")
    }
}

t.suite("VercelAPI — nagłówki i parametry")
let stub = StubSession()
stub.responses["/v2/user"] = (200, Data(#"{"user":{"uid":"u1","username":"marta","name":null}}"#.utf8))
let api = VercelAPI(token: "tok_123", teamID: "team_9", session: stub)
let user = try await api.user()
t.equal(user.username, "marta", "user dekoduje się")
t.equal(stub.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok_123", "nagłówek Bearer")
t.check(stub.lastRequest?.url?.query?.contains("teamId=team_9") == true, "teamId w query")

t.suite("VercelAPI — latestDeployment")
stub.responses["/v6/deployments"] = (200, Data("""
{"deployments":[{"uid":"d9","state":"READY","createdAt":1754470000000,
 "buildingAt":1754470002000,"ready":1754470040000,"meta":{}}]}
""".utf8))
let latest = try await api.latestDeployment(projectID: "prj_1")
t.equal(latest?.id, "d9", "najnowszy deploy z /v6/deployments")
t.check(stub.lastRequest?.url?.query?.contains("projectId=prj_1") == true, "projectId w query")
t.check(stub.lastRequest?.url?.query?.contains("limit=1") == true, "limit=1 w query")

t.suite("VercelAPI — mapowanie błędów")
let stubErr = StubSession()
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

let stubOffline = StubSession()
stubOffline.thrownError = URLError(.notConnectedToInternet)
do {
    _ = try await VercelAPI(token: "t", session: stubOffline).user()
    t.check(false, "URLError powinien rzucić")
} catch let e as VercelAPIError {
    t.equal(e, .offline, "URLError → offline")
} catch { t.check(false, "zły typ błędu: \(error)") }
```

- [ ] **Step 2: Odpal testy — fail kompilacji**

Run: `swift run vercelbar-tests`
Expected: `cannot find 'HTTPSession'`.

- [ ] **Step 3: Napisz `Sources/VercelBarKit/VercelAPI.swift`**

```swift
import Foundation

/// Warstwa sieci do wstrzykiwania w testach.
public protocol HTTPSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPSession {}

public enum VercelAPIError: Error, Equatable, Sendable {
    case unauthorized
    case rateLimited
    case server(Int)
    case offline
    case invalidResponse
}

/// Klient REST API Vercela. Tylko odczyt.
public struct VercelAPI: Sendable {
    private let token: String
    private let teamID: String?
    private let session: any HTTPSession
    private static let base = URL(string: "https://api.vercel.com")!

    public init(token: String, teamID: String? = nil, session: any HTTPSession = URLSession.shared) {
        self.token = token
        self.teamID = teamID
        self.session = session
    }

    public func user() async throws -> VercelUser {
        try APIDecoding.user(from: await get("/v2/user"))
    }

    public func teams() async throws -> [Team] {
        try APIDecoding.teams(from: await get("/v2/teams"))
    }

    public func projects() async throws -> [Project] {
        try APIDecoding.projects(from: await get("/v9/projects", query: ["limit": "100"]))
    }

    public func latestDeployment(projectID: String) async throws -> DeploymentSummary? {
        let data = try await get("/v6/deployments", query: ["projectId": projectID, "limit": "1"])
        return try APIDecoding.deployments(from: data).first
    }

    private func get(_ path: String, query: [String: String] = [:]) async throws -> Data {
        var comps = URLComponents(url: Self.base.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)!
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        if let teamID { items.append(URLQueryItem(name: "teamId", value: teamID)) }
        if !items.isEmpty { comps.queryItems = items.sorted { $0.name < $1.name } }

        var request = URLRequest(url: comps.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw VercelAPIError.offline // każdy błąd transportu traktujemy jak brak sieci
        }
        guard let http = response as? HTTPURLResponse else { throw VercelAPIError.invalidResponse }
        switch http.statusCode {
        case 200...299: return data
        case 401, 403: throw VercelAPIError.unauthorized
        case 429: throw VercelAPIError.rateLimited
        case 500...599: throw VercelAPIError.server(http.statusCode)
        default: throw VercelAPIError.invalidResponse
        }
    }
}
```

- [ ] **Step 4: Odpal testy**

Run: `swift run vercelbar-tests`
Expected: zielono.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Klient VercelAPI z wstrzykiwaną sesją i mapowaniem błędów"
```

---

### Task 7: KeychainStore

**Files:**
- Create: `Sources/VercelBarKit/KeychainStore.swift`
- Modify: `Sources/vercelbar-tests/main.swift`

- [ ] **Step 1: Dopisz failujące testy** (konto testowe, sprzątanie po sobie)

```swift
// MARK: - KeychainStore

t.suite("KeychainStore")
let kc = KeychainStore(service: "pl.zielinski.vercelbar.testy")
kc.deleteToken(account: "test")
t.equal(kc.readToken(account: "test"), nil, "brak tokenu przed zapisem")
do {
    try kc.writeToken("tok_abc", account: "test")
    t.equal(kc.readToken(account: "test"), "tok_abc", "odczyt po zapisie")
    try kc.writeToken("tok_nowy", account: "test")
    t.equal(kc.readToken(account: "test"), "tok_nowy", "nadpisanie tokenu")
    kc.deleteToken(account: "test")
    t.equal(kc.readToken(account: "test"), nil, "brak tokenu po usunięciu")
} catch { t.check(false, "Keychain rzucił: \(error)") }
```

- [ ] **Step 2: Odpal testy — fail kompilacji**

Run: `swift run vercelbar-tests`
Expected: `cannot find 'KeychainStore'`.

- [ ] **Step 3: Napisz `Sources/VercelBarKit/KeychainStore.swift`**

```swift
import Foundation
import Security

/// Token Vercela w Keychain (kSecClassGenericPassword).
public struct KeychainStore {
    public let service: String

    public init(service: String = "pl.zielinski.vercelbar") {
        self.service = service
    }

    public enum KeychainError: Error {
        case status(OSStatus)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func readToken(account: String = "vercel-token") -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func writeToken(_ token: String, account: String = "vercel-token") throws {
        let data = Data(token.utf8)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(account: account) as CFDictionary,
                                   update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(account: account)
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    public func deleteToken(account: String = "vercel-token") {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
```

- [ ] **Step 4: Odpal testy**

Run: `swift run vercelbar-tests`
Expected: zielono (Keychain użytkownika działa z terminala; przy pierwszym razie macOS może pokazać monit o dostęp — zaakceptuj).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "KeychainStore: token Vercela w pęku kluczy"
```

---

### Task 8: SettingsStore

**Files:**
- Create: `Sources/VercelBarKit/SettingsStore.swift`
- Modify: `Sources/vercelbar-tests/main.swift`

- [ ] **Step 1: Dopisz failujące testy** (osobna suita UserDefaults, czyszczona na starcie)

```swift
// MARK: - SettingsStore

t.suite("SettingsStore")
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
settings.teamID = "team_9"
let reloaded = SettingsStore(defaults: defaults)
t.equal(reloaded.watchedProjectIDs, ["prj_1", "prj_2"], "obserwowane trwają po ponownym wczytaniu")
t.equal(reloaded.notifySuccess, false, "wyłączenie sukcesów trwa")
t.equal(reloaded.teamID, "team_9", "team trwa")
reloaded.teamID = nil
t.equal(SettingsStore(defaults: defaults).teamID, nil, "powrót do konta osobistego")
defaults.removePersistentDomain(forName: suiteName)
```

- [ ] **Step 2: Odpal testy — fail kompilacji**

Run: `swift run vercelbar-tests`
Expected: `cannot find 'SettingsStore'`.

- [ ] **Step 3: Napisz `Sources/VercelBarKit/SettingsStore.swift`**

```swift
import Foundation

/// Ustawienia aplikacji w UserDefaults (token trzyma KeychainStore).
public final class SettingsStore {
    private let defaults: UserDefaults

    private enum Key {
        static let watched = "watchedProjectIDs"
        static let notifySuccess = "notifySuccess"
        static let notifyFailure = "notifyFailure"
        static let teamID = "teamID"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var watchedProjectIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.watched) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.watched) }
    }

    public var notifySuccess: Bool {
        get { defaults.object(forKey: Key.notifySuccess) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.notifySuccess) }
    }

    public var notifyFailure: Bool {
        get { defaults.object(forKey: Key.notifyFailure) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.notifyFailure) }
    }

    /// nil = konto osobiste.
    public var teamID: String? {
        get { defaults.string(forKey: Key.teamID) }
        set {
            if let newValue { defaults.set(newValue, forKey: Key.teamID) }
            else { defaults.removeObject(forKey: Key.teamID) }
        }
    }
}
```

- [ ] **Step 4: Odpal testy**

Run: `swift run vercelbar-tests`
Expected: zielono.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "SettingsStore: obserwowane projekty, przełączniki i team w UserDefaults"
```

---

### Task 9: Theme i StatusIconRenderer

Kolory dynamiczne (jasny/ciemny) i ikona trójkąta do paska menu. Puls przy buildzie to funkcja czysta `pulseAlpha` — testowalna.

**Files:**
- Create: `Sources/VercelBarKit/Theme.swift`
- Create: `Sources/VercelBarKit/StatusIconRenderer.swift`
- Modify: `Sources/vercelbar-tests/main.swift`

- [ ] **Step 1: Dopisz failujące testy**

```swift
// MARK: - Ikona paska menu

t.suite("StatusIconRenderer")
t.equal(StatusIconRenderer.pulseAlpha(phase: 0), 0.55, "puls w fazie 0 → 0,55")
t.equal(StatusIconRenderer.pulseAlpha(phase: 0.5), 1.0, "puls w fazie 0,5 → 1,0")
t.check(abs(StatusIconRenderer.pulseAlpha(phase: 1.0) - 0.55) < 0.0001, "puls w fazie 1,0 wraca do 0,55")
let icon = StatusIconRenderer.image(state: .ready)
t.equal(icon.size, NSSize(width: 15, height: 13), "rozmiar ikony 15×13 pt (design)")
t.check(!icon.isTemplate, "ikona kolorowa, nie szablonowa")
```

- [ ] **Step 2: Odpal testy — fail kompilacji**

Run: `swift run vercelbar-tests`
Expected: `cannot find 'StatusIconRenderer'`. Dodaj też `import AppKit` na górze `Sources/vercelbar-tests/main.swift` (dla `NSSize`).

- [ ] **Step 3: Napisz `Sources/VercelBarKit/Theme.swift`**

```swift
import AppKit

/// Kolory z makiet Claude Design — pary jasny/ciemny jako NSColor dynamiczne.
public enum Theme {

    public static func dynamicColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    public static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: alpha)
    }

    // Kolory stanów (kropka, badge, ikona) — wartości wprost z makiet.
    public static let ready = dynamicColor(light: hex(0x1d7f38), dark: hex(0x30d158))
    public static let building = dynamicColor(light: hex(0x0064e0), dark: hex(0x0a84ff))
    public static let error = dynamicColor(light: hex(0xd70015), dark: hex(0xff453a))
    public static let gray = dynamicColor(light: hex(0x8e8e93), dark: hex(0x98989d))

    public static let badgeReadyBg = dynamicColor(light: hex(0x1d7f38, alpha: 0.10), dark: hex(0x30d158, alpha: 0.15))
    public static let badgeBuildingBg = dynamicColor(light: hex(0x0064e0, alpha: 0.10), dark: hex(0x0a84ff, alpha: 0.17))
    public static let badgeErrorBg = dynamicColor(light: hex(0xd70015, alpha: 0.09), dark: hex(0xff453a, alpha: 0.17))
    public static let badgeQueuedFg = dynamicColor(light: hex(0x6e6e73), dark: hex(0x98989d))
    public static let badgeQueuedBg = dynamicColor(light: NSColor(srgbRed: 60/255, green: 60/255, blue: 67/255, alpha: 0.08),
                                                   dark: NSColor(srgbRed: 235/255, green: 235/255, blue: 245/255, alpha: 0.11))
}
```

- [ ] **Step 4: Napisz `Sources/VercelBarKit/StatusIconRenderer.swift`**

```swift
import AppKit

/// Ikona trójkąta do paska menu, kolorowana stanem zbiorczym.
public enum StatusIconRenderer {

    /// Alpha pulsu ikony przy buildzie: 0,55 → 1,0 → 0,55 (cosinusoida, okres = faza 0…1).
    public static func pulseAlpha(phase: Double) -> Double {
        0.55 + 0.45 * (0.5 - 0.5 * cos(2 * .pi * phase))
    }

    public static func color(for state: AggregateState) -> NSColor {
        switch state {
        case .ready: return Theme.ready
        case .building: return Theme.building
        case .error: return Theme.error
        case .idle: return Theme.gray
        }
    }

    /// Trójkąt 15×13 pt (proporcje logo Vercela, viewBox 26×23 z makiet).
    public static func image(state: AggregateState, alpha: Double = 1) -> NSImage {
        let size = NSSize(width: 15, height: 13)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.midX, y: rect.maxY - 0.5))
            path.line(to: NSPoint(x: rect.maxX - 0.3, y: rect.minY + 0.5))
            path.line(to: NSPoint(x: rect.minX + 0.3, y: rect.minY + 0.5))
            path.close()
            color(for: state).withAlphaComponent(alpha).setFill()
            path.fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
```

- [ ] **Step 5: Odpal testy**

Run: `swift run vercelbar-tests`
Expected: zielono.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "Theme z kolorami makiet i renderer ikony paska menu z pulsem"
```

---

### Task 10: AppModel — pętla odpytywania i integracja

Serce aplikacji: fazy (onboarding / offline / zły token / normalna), odświeżanie, dobór interwału, zdarzenia powiadomień, puls ikony. Logika w `VercelBarKit` już przetestowana; tu test integracyjny na stubie: „refresh składa wiersze i stan zbiorczy".

**Files:**
- Create: `Sources/VercelBar/AppModel.swift`
- Create: `Sources/VercelBar/NotificationPresenter.swift`
- Modify: `Sources/vercelbar-tests/main.swift` (test `RefreshCore` — patrz niżej)
- Create: `Sources/VercelBarKit/RefreshCore.swift`

Żeby pętla była testowalna bez UI, sam krok odświeżenia trafia do `VercelBarKit` jako `RefreshCore`.

- [ ] **Step 1: Dopisz failujące testy**

```swift
// MARK: - RefreshCore

t.suite("RefreshCore")
let rcStub = StubSession()
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
```

- [ ] **Step 2: Odpal testy — fail kompilacji**

Run: `swift run vercelbar-tests`
Expected: `cannot find 'RefreshCore'`.

- [ ] **Step 3: Napisz `Sources/VercelBarKit/RefreshCore.swift`**

```swift
import Foundation

/// Jeden krok odświeżenia: lista projektów + najnowszy deploy każdego obserwowanego.
public enum RefreshCore {

    public struct Snapshot: Sendable {
        public let projects: [Project]     // posortowane: najnowszy deploy pierwszy
        public let overall: AggregateState
        public let anyActive: Bool
    }

    public static func fetch(api: VercelAPI, watchedProjectIDs: Set<String>) async throws -> Snapshot {
        let all = try await api.projects()
        let watched = all.filter { watchedProjectIDs.contains($0.id) }

        var filled: [Project] = []
        try await withThrowingTaskGroup(of: Project.self) { group in
            for p in watched {
                group.addTask {
                    var copy = p
                    copy.latest = try await api.latestDeployment(projectID: p.id)
                    return copy
                }
            }
            for try await p in group { filled.append(p) }
        }
        filled.sort { ($0.latest?.createdAt ?? .distantPast) > ($1.latest?.createdAt ?? .distantPast) }

        let states = filled.compactMap { $0.latest?.state }
        return Snapshot(projects: filled,
                        overall: StatusAggregator.aggregate(states),
                        anyActive: states.contains { $0.isActive })
    }
}
```

- [ ] **Step 4: Odpal testy**

Run: `swift run vercelbar-tests`
Expected: zielono.

- [ ] **Step 5: Napisz `Sources/VercelBar/NotificationPresenter.swift`**

```swift
import Foundation
import AppKit
import UserNotifications
import VercelBarKit

/// Wysyła powiadomienia systemowe i otwiera deploy po kliknięciu.
/// UNUserNotificationCenter wymaga bundla .app — przy `swift run` tylko logujemy.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

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
        case .failed:
            title = "❌ \(event.projectName): deploy padł"
            body = "\(branch) · build przerwany. Kliknij, aby otworzyć logi."
            url = d.inspectorURL ?? d.previewURL
        case .succeeded:
            title = "✅ \(event.projectName) wdrożony"
            let time = d.duration.map { " w " + Format.duration($0) } ?? ""
            body = "\(branch) · gotowe\(time). Kliknij, aby otworzyć podgląd."
            url = d.previewURL ?? d.inspectorURL
        }

        guard available else {
            print("POWIADOMIENIE: \(title) — \(body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let url { content.userInfo = ["url": url.absoluteString] }
        let request = UNNotificationRequest(identifier: "\(d.id).\(event.kind)",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func showTokenInvalid() {
        guard available else { print("POWIADOMIENIE: token nieprawidłowy"); return }
        let content = UNMutableNotificationContent()
        content.title = "VercelBar: token nieprawidłowy"
        content.body = "Otwórz Ustawienia i wklej nowy token dostępu."
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
```

- [ ] **Step 6: Napisz `Sources/VercelBar/AppModel.swift`**

```swift
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

    @Published var phase: Phase = .onboarding
    @Published var projects: [Project] = []
    @Published var allProjects: [Project] = []   // do listy w Ustawieniach
    @Published var overall: AggregateState = .idle
    @Published var lastRefreshed: Date?
    @Published var iconAlpha: Double = 1
    @Published var account: VercelUser?
    @Published var teams: [Team] = []

    let keychain = KeychainStore()
    let settings = SettingsStore()

    private var engine = NotificationEngine()
    private var pollTask: Task<Void, Never>?
    private var pulseTimer: Timer?
    private var tokenAlertShown = false
    private var started = false
    private var consecutiveFailures = 0 // backoff dla 429/5xx

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
        guard keychain.readToken() != nil else { phase = .onboarding; return }
        phase = .normal
        restartPolling()
    }

    func restartPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let self else { return }
                let base = PollScheduler.interval(anyActive: self.overall == .building)
                // Wykładniczy backoff po 429/5xx: 60 s, 120 s, 240 s… maks. 300 s.
                let delay = self.consecutiveFailures > 0
                    ? min(300, 30 * pow(2, Double(self.consecutiveFailures)))
                    : base
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    func refresh() async {
        guard let token = keychain.readToken() else { phase = .onboarding; return }
        let api = VercelAPI(token: token, teamID: settings.teamID)
        do {
            let snapshot = try await RefreshCore.fetch(api: api,
                                                       watchedProjectIDs: settings.watchedProjectIDs)
            withAnimation(reduceMotion ? nil : .spring(duration: 0.22)) {
                projects = snapshot.projects
                overall = snapshot.overall
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
        } catch {
            // 429/5xx: zostaw poprzednie dane; pętla ponowi z backoffem.
            consecutiveFailures += 1
        }
    }

    /// Walidacja tokenu i zapis. Zwraca false przy odrzuceniu.
    func connect(token: String) async -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            let api = VercelAPI(token: trimmed)
            account = try await api.user()
            teams = (try? await api.teams()) ?? []
            try keychain.writeToken(trimmed)
            tokenAlertShown = false
            phase = .normal
            await loadAllProjects()
            restartPolling()
            return true
        } catch {
            return false
        }
    }

    /// Lista wszystkich projektów dla Ustawień (zakładka Projekty).
    func loadAllProjects() async {
        guard let token = keychain.readToken() else { return }
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
```

- [ ] **Step 7: Zbuduj całość i odpal testy**

Run: `swift build && swift run vercelbar-tests`
Expected: build OK (UI jeszcze zaślepkowe), testy zielone.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "AppModel: pętla odpytywania, fazy, powiadomienia i puls ikony"
```

---

### Task 11: Popover i MenuBarExtra

Wierne odwzorowanie makiety `VercelBar Popover.dc.html`: szerokość 340, nagłówek z kropką, wiersze z badge'em/gałęzią/commitem/czasem, hover ze strzałką, pasek postępu przy buildzie, rozbłysk Building→Ready, warianty onboarding/offline/zły token, stopka Odśwież · Ustawienia · Zakończ. Krzywa sprężysta z makiet `cubic-bezier(.34,1.30,.64,1)` ≈ `.spring(duration: 0.22, bounce: 0.3)`.

**Files:**
- Create: `Sources/VercelBar/PopoverView.swift`
- Create: `Sources/VercelBar/ProjectRowView.swift`
- Modify: `Sources/VercelBar/VercelBarApp.swift` (zastąp całość)

- [ ] **Step 1: Napisz `Sources/VercelBar/ProjectRowView.swift`**

```swift
import SwiftUI
import VercelBarKit

/// Jeden wiersz projektu w popoverze.
struct ProjectRowView: View {
    let project: Project
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    @State private var flash = false

    private var deploy: DeploymentSummary? { project.latest }
    private var isError: Bool { deploy?.state == .error }
    private var isBuilding: Bool { deploy?.state == .building || deploy?.state == .initializing }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    badge
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(deploy?.branch ?? "—")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(deploy?.commitMessage ?? "brak danych o commicie")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if isBuilding { progressBar.padding(.top, 5) }
            }
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text((deploy?.createdAt).map { Format.relative($0) } ?? "")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    durationLabel
                }
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .opacity(hovered ? 1 : 0)
                    .offset(x: hovered ? 0 : -6)
            }
        }
        .padding(EdgeInsets(top: 7, leading: 9, bottom: 7, trailing: 8))
        .background(rowBackground)
        .overlay( // rozbłysk Building → Ready
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: Theme.ready).opacity(flash ? 0.16 : 0))
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 5)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { open() }
        .onChange(of: deploy?.state) { old, new in
            guard !reduceMotion, old == .building || old == .initializing, new == .ready else { return }
            withAnimation(.spring(duration: 0.12, bounce: 0.3)) { flash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                withAnimation(.easeOut(duration: 0.3)) { flash = false }
            }
        }
    }

    private var badge: some View {
        Text(badgeLabel)
            .font(.system(size: 9.5, weight: .bold))
            .padding(.horizontal, 5.5).padding(.vertical, 1.5)
            .background(Color(nsColor: badgeBg))
            .foregroundStyle(Color(nsColor: badgeFg))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .id(badgeLabel) // wymusza przejście przy zmianie stanu
            .transition(reduceMotion ? .identity :
                .asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity),
                            removal: .opacity))
    }

    private var badgeLabel: String {
        switch deploy?.state {
        case .ready: "Ready"
        case .error: "Error"
        case .building, .initializing: "Building"
        case .canceled: "Canceled"
        case .unknown: "—"
        default: "Queued"
        }
    }

    private var badgeFg: NSColor {
        switch deploy?.state {
        case .ready: Theme.ready
        case .error: Theme.error
        case .building, .initializing: Theme.building
        default: Theme.badgeQueuedFg
        }
    }

    private var badgeBg: NSColor {
        switch deploy?.state {
        case .ready: Theme.badgeReadyBg
        case .error: Theme.badgeErrorBg
        case .building, .initializing: Theme.badgeBuildingBg
        default: Theme.badgeQueuedBg
        }
    }

    @ViewBuilder private var durationLabel: some View {
        if let text = durationText {
            HStack(spacing: 3) {
                Image(systemName: "stopwatch").font(.system(size: 7.5))
                Text(text).monospacedDigit()
            }
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
        }
    }

    private var durationText: String? {
        guard let deploy else { return nil }
        if let done = deploy.duration { return Format.duration(done) }
        if isBuilding, let start = deploy.buildingAt ?? deploy.createdAt {
            return Format.duration(Date().timeIntervalSince(start))
        }
        return nil
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(isError
                  ? Color(nsColor: Theme.error).opacity(hovered ? 0.085 : 0.055)
                  : Color.primary.opacity(hovered ? 0.045 : 0))
            .overlay {
                if isError {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color(nsColor: Theme.error).opacity(0.20), lineWidth: 0.5)
                }
            }
    }

    /// Pasek postępu (nieokreślony) przy buildzie — jak w makiecie: 34 % szerokości, przelot 1,5 s.
    private var progressBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                if reduceMotion {
                    Capsule().fill(Color(nsColor: Theme.building)).frame(width: w * 0.34)
                } else {
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 1.5) / 1.5
                        Capsule()
                            .fill(Color(nsColor: Theme.building))
                            .frame(width: w * 0.34)
                            .offset(x: (w * 1.34) * t - w * 0.34)
                    }
                }
            }
        }
        .frame(height: 2)
        .clipShape(Capsule())
    }

    private func open() {
        guard let url = deploy?.inspectorURL ?? deploy?.previewURL else { return }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 2: Napisz `Sources/VercelBar/PopoverView.swift`**

```swift
import SwiftUI
import VercelBarKit

/// Zawartość okna MenuBarExtra: nagłówek, lista wierszy albo wariant specjalny, stopka.
struct PopoverView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if model.phase != .onboarding { header; Divider() }
            content
            if model.phase != .onboarding { Divider(); footer }
        }
        .frame(width: 340)
    }

    // MARK: nagłówek

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(nsColor: StatusIconRenderer.color(for: model.iconState)))
                .frame(width: 8, height: 8)
                .opacity(model.overall == .building ? model.iconAlpha : 1)
            Text(headline).font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(model.lastRefreshed.map { "odświeżono \(Format.clock($0))" } ?? "")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .padding(EdgeInsets(top: 11, leading: 14, bottom: 10, trailing: 13))
    }

    private var headline: String {
        switch model.phase {
        case .offline: "Brak połączenia"
        case .tokenInvalid: "Token nieprawidłowy"
        default: StatusAggregator.headline(for: model.projects.compactMap { $0.latest?.state })
        }
    }

    // MARK: treść

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .onboarding: onboarding
        case .offline: offline
        case .tokenInvalid: tokenInvalid
        case .normal:
            if model.projects.isEmpty {
                emptyWatched
            } else {
                VStack(spacing: 0) {
                    ForEach(model.projects) { ProjectRowView(project: $0) }
                }
                .padding(.top, 5).padding(.bottom, 6)
                .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.3),
                           value: model.projects.map(\.id))
            }
        }
    }

    private var onboarding: some View {
        VStack(spacing: 12) {
            Image(nsImage: StatusIconRenderer.image(state: .idle))
                .resizable().frame(width: 26, height: 23)
                .opacity(0.4)
            Text("Połącz konto Vercela, aby widzieć swoje deploye w pasku menu.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 232)
            Button("Połącz z Vercelem") { openSettings() }
                .buttonStyle(.borderedProminent)
                .tint(.primary)
                .controlSize(.regular)
        }
        .padding(EdgeInsets(top: 30, leading: 26, bottom: 26, trailing: 26))
    }

    private var offline: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text("Brak połączenia z internetem. Wznowię monitorowanie automatycznie.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 236)
        }
        .padding(EdgeInsets(top: 26, leading: 30, bottom: 24, trailing: 30))
    }

    private var tokenInvalid: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.slash")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text("Token dostępu został odrzucony przez Vercela. Wklej nowy w Ustawieniach.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 236)
            Button("Otwórz Ustawienia") { openSettings() }
                .buttonStyle(.borderedProminent)
                .tint(.primary)
        }
        .padding(EdgeInsets(top: 26, leading: 26, bottom: 24, trailing: 26))
    }

    private var emptyWatched: some View {
        Text("Zaznacz projekty do obserwowania w Ustawieniach.")
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(EdgeInsets(top: 26, leading: 30, bottom: 24, trailing: 30))
    }

    // MARK: stopka

    private var footer: some View {
        HStack(spacing: 2) {
            footerButton("Odśwież", system: "arrow.clockwise") {
                Task { await model.refresh() }
            }
            footerButton("Ustawienia", system: "gearshape") { openSettings() }
            Spacer()
            footerButton("Zakończ", system: "power") { NSApp.terminate(nil) }
        }
        .padding(EdgeInsets(top: 5, leading: 7, bottom: 6, trailing: 7))
    }

    private func footerButton(_ title: String, system: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: system).font(.system(size: 10))
                Text(title).font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(FooterButtonStyle())
    }

    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
        Task { await model.loadAllProjects() }
    }
}

/// Delikatne tło na hover, jak w makiecie stopki.
struct FooterButtonStyle: ButtonStyle {
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(hovered || configuration.isPressed ? 0.05 : 0)))
            .onHover { hovered = $0 }
    }
}
```

- [ ] **Step 3: Zastąp `Sources/VercelBar/VercelBarApp.swift`**

```swift
import SwiftUI
import VercelBarKit

@main
struct VercelBarApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
                .onAppear { model.start() }
        } label: {
            Image(nsImage: StatusIconRenderer.image(state: model.iconState,
                                                    alpha: model.iconAlpha))
                .onAppear { model.start() } // etykieta renderuje się od razu — pętla rusza bez klikania
        }
        .menuBarExtraStyle(.window)

        Window("Ustawienia VercelBar", id: "settings") {
            SettingsPlaceholderView(model: model) // zastąpione w Tasku 12
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// Tymczasowa zaślepka — Task 12 wstawia właściwe SettingsView.
struct SettingsPlaceholderView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Text("Ustawienia — w budowie").padding(40)
    }
}
```

- [ ] **Step 4: Zbuduj i sprawdź manualnie**

Run: `swift build && swift run vercelbar-tests && swift run vercelbar &`
Expected: testy zielone; w pasku menu pojawia się szary trójkąt; klik pokazuje popover z onboardingiem („Połącz z Vercelem"). `swift run` bez bundla pokaże też ikonę w Docku — to znika po spakowaniu w Tasku 13. Zamknij: `pkill -f vercelbar` (binarka z `swift run` nazywa się `vercelbar`).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Popover MenuBarExtra: wiersze projektów, warianty stanów i stopka"
```

---

### Task 12: Okno ustawień i start przy logowaniu

Odwzorowanie `VercelBar Settings.dc.html`: 480×380, segmentowane zakładki Konto/Projekty, pole tokenu, status połączenia, wybór teamu, lista projektów z haczykami i wyszukiwarką, stopka z trzema przełącznikami. Start przy logowaniu przez `SMAppService` (działa dopiero w bundlu .app — przy `swift run` przełącznik pokazuje ostrzeżenie).

**Files:**
- Create: `Sources/VercelBar/SettingsView.swift`
- Modify: `Sources/VercelBar/VercelBarApp.swift` (podmień zaślepkę)

- [ ] **Step 1: Napisz `Sources/VercelBar/SettingsView.swift`**

```swift
import SwiftUI
import ServiceManagement
import VercelBarKit

/// Okno ustawień 480×380: zakładki Konto/Projekty + stopka z przełącznikami.
struct SettingsView: View {
    @ObservedObject var model: AppModel

    enum Tab: String, CaseIterable {
        case konto = "Konto"
        case projekty = "Projekty"
    }

    @State private var tab: Tab = .konto
    @State private var tokenField = ""
    @State private var tokenRejected = false
    @State private var search = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var notifySuccess = true
    @State private var notifyFailure = true

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            .padding(.top, 12)

            Group {
                switch tab {
                case .konto: kontoTab
                case .projekty: projektyTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(EdgeInsets(top: 18, leading: 22, bottom: 14, trailing: 22))

            Divider()
            togglesFooter
        }
        .frame(width: 480, height: 380)
        .onAppear {
            notifySuccess = model.settings.notifySuccess
            notifyFailure = model.settings.notifyFailure
            Task { await model.loadAllProjects() }
        }
    }

    // MARK: zakładka Konto

    private var kontoTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            row(label: "Token dostępu") {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        SecureField(model.keychain.readToken() == nil
                                    ? "wklej token…" : "••••••••••••••••••••",
                                    text: $tokenField)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                        Button("Zapisz") {
                            Task {
                                tokenRejected = !(await model.connect(token: tokenField))
                                if !tokenRejected { tokenField = "" }
                            }
                        }
                        .disabled(tokenField.isEmpty)
                    }
                    Text(tokenRejected
                         ? "Vercel odrzucił ten token. Sprawdź, czy skopiowany w całości."
                         : "Token z panelu Vercela → Account Settings → Tokens. Zakres: tylko odczyt.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(tokenRejected ? Color(nsColor: Theme.error) : .secondary)
                }
            }

            row(label: "Połączenie") {
                HStack(spacing: 9) {
                    Circle()
                        .fill(Color.primary.opacity(0.07))
                        .frame(width: 26, height: 26)
                        .overlay(Text(initials)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.secondary))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.account?.name ?? model.account?.username ?? "Nie połączono")
                            .font(.system(size: 12.5, weight: .semibold))
                        HStack(spacing: 4) {
                            Circle()
                                .fill(model.account != nil
                                      ? Color(nsColor: Theme.ready) : Color.secondary)
                                .frame(width: 6, height: 6)
                            Text(model.account != nil ? "Połączono" : "Wklej token powyżej")
                                .font(.system(size: 10.5))
                                .foregroundStyle(model.account != nil
                                                 ? Color(nsColor: Theme.ready) : .secondary)
                        }
                    }
                }
            }

            row(label: "Zespół") {
                Picker("", selection: Binding(
                    get: { model.settings.teamID ?? "" },
                    set: { model.selectTeam(id: $0.isEmpty ? nil : $0) }
                )) {
                    Text("Konto osobiste").tag("")
                    ForEach(model.teams) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .frame(width: 196)
            }
        }
    }

    private var initials: String {
        let source = model.account?.name ?? model.account?.username ?? "?"
        let parts = source.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }

    private func row<Content: View>(label: String,
                                    @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 104, alignment: .trailing)
                .padding(.top, 4)
            content()
            Spacer(minLength: 0)
        }
    }

    // MARK: zakładka Projekty

    private var projektyTab: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                TextField("Szukaj projektów", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                Text("\(model.settings.watchedProjectIDs.count) z \(model.allProjects.count) projektów monitorowanych")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
            List(filteredProjects) { project in
                Toggle(isOn: Binding(
                    get: { model.settings.watchedProjectIDs.contains(project.id) },
                    set: { _ in model.toggleWatched(projectID: project.id) }
                )) {
                    Text(project.name).font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
            }
            .listStyle(.bordered)
            .scrollContentBackground(.hidden)
        }
    }

    private var filteredProjects: [Project] {
        guard !search.isEmpty else { return model.allProjects }
        return model.allProjects.filter {
            $0.name.localizedCaseInsensitiveContains(search)
        }
    }

    // MARK: stopka z przełącznikami

    private var togglesFooter: some View {
        VStack(spacing: 4) {
            Toggle("Uruchamiaj przy logowaniu", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
            Toggle("Powiadamiaj o sukcesach", isOn: $notifySuccess)
                .onChange(of: notifySuccess) { _, on in model.settings.notifySuccess = on }
            Toggle("Powiadamiaj o błędach", isOn: $notifyFailure)
                .onChange(of: notifyFailure) { _, on in model.settings.notifyFailure = on }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .font(.system(size: 12))
        .padding(EdgeInsets(top: 11, leading: 22, bottom: 14, trailing: 22))
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        // SMAppService działa tylko w bundlu .app; przy `swift run` cicho ignorujemy.
        guard Bundle.main.bundleIdentifier != nil else { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
```

- [ ] **Step 2: Podmień zaślepkę w `Sources/VercelBar/VercelBarApp.swift`**

Usuń `struct SettingsPlaceholderView` i w scenie `Window` zamień
`SettingsPlaceholderView(model: model)` na `SettingsView(model: model)`.

- [ ] **Step 3: Zbuduj i sprawdź manualnie**

Run: `swift build && swift run vercelbar &`
Expected: popover → „Połącz z Vercelem" otwiera okno ustawień 480×380 z zakładkami. Bez tokenu: „Nie połączono". Wklejenie prawdziwego tokenu → „Połączono", zakładka Projekty pokazuje listę z haczykami; zaznaczenie projektów wypełnia popover wierszami. Zamknij: `pkill -f vercelbar`.

- [ ] **Step 4: Odpal testy regresyjne**

Run: `swift run vercelbar-tests`
Expected: zielono.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Okno ustawień: konto, wybór projektów i przełączniki + start przy logowaniu"
```

---

### Task 13: Ikona aplikacji, pakowanie .app i README

**Files:**
- Create: `Scripts/MakeIcon.swift`
- Create: `Scripts/build-app.sh`
- Create: `README.md`

- [ ] **Step 1: Napisz `Scripts/MakeIcon.swift`** (uruchamiany `swift Scripts/MakeIcon.swift`)

```swift
// Generuje Resources/AppIcon.icns: biały trójkąt na ciemnym zaokrąglonym tle
// (jak ikona powiadomień w makietach). Wymaga tylko CLT (AppKit + iconutil).
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for size in sizes {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s), flipped: false) { rect in
        let bg = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.06, dy: s * 0.06),
                              xRadius: s * 0.22, yRadius: s * 0.22)
        NSColor(srgbRed: 28/255, green: 28/255, blue: 30/255, alpha: 1).setFill()
        bg.fill()
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: rect.midX, y: rect.maxY - s * 0.30))
        tri.line(to: NSPoint(x: rect.maxX - s * 0.26, y: rect.minY + s * 0.30))
        tri.line(to: NSPoint(x: rect.minX + s * 0.26, y: rect.minY + s * 0.30))
        tri.close()
        NSColor.white.setFill()
        tri.fill()
        return true
    }
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("nie udało się narysować ikony \(size)")
    }
    try png.write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
}

let out = root.appendingPathComponent("Resources/AppIcon.icns")
try? fm.createDirectory(at: root.appendingPathComponent("Resources"),
                        withIntermediateDirectories: true)
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "OK: \(out.path)" : "BŁĄD iconutil")
exit(task.terminationStatus)
```

- [ ] **Step 2: Napisz `Scripts/build-app.sh`** (adaptacja ze Skryby: staging poza iCloud, ad-hoc codesign, zip; różnice: brak frameworków, `LSUIElement`)

```bash
#!/usr/bin/env bash
# Buduje VercelBar.app i VercelBar.zip. Wymaga tylko Swift toolchain (CLT wystarczą).
# Składanie i podpis w katalogu tymczasowym poza iCloud, bo atrybuty
# iCloud (com.apple.fileprovider.*) psują podpis kodu.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="VercelBar"
BUNDLE_ID="pl.zielinski.vercelbar"
VERSION="1.0.0"
OUT_DIR="$ROOT/build"
STAGE="$(mktemp -d)/$APP_NAME.app"

if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
    echo "▸ Generuję ikonę..."
    swift "$ROOT/Scripts/MakeIcon.swift"
fi

echo "▸ Kompilacja (release)..."
swift build -c release --product vercelbar

BIN_DIR="$(swift build -c release --product vercelbar --show-bin-path)"
EXECUTABLE="$BIN_DIR/vercelbar"
[ -f "$EXECUTABLE" ] || { echo "BŁĄD: brak binarki: $EXECUTABLE"; exit 1; }

echo "▸ Składanie bundla (staging poza iCloud)..."
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$EXECUTABLE" "$STAGE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/AppIcon.icns" "$STAGE/Contents/Resources/AppIcon.icns"

cat > "$STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key><string>MIT</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST

echo "▸ Czyszczenie atrybutów i podpis ad-hoc..."
xattr -cr "$STAGE"
find "$STAGE" -name '._*' -delete 2>/dev/null || true
find "$STAGE" -name '.DS_Store' -delete 2>/dev/null || true
codesign --force --sign - "$STAGE"

echo "▸ Weryfikacja podpisu..."
codesign --verify --deep --strict "$STAGE"

echo "▸ Kopiowanie do build/ i zip..."
mkdir -p "$OUT_DIR"
rm -rf "$OUT_DIR/$APP_NAME.app" "$OUT_DIR/$APP_NAME.zip"
cp -R "$STAGE" "$OUT_DIR/$APP_NAME.app"
(cd "$OUT_DIR" && ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip")

echo "✓ Gotowe: $OUT_DIR/$APP_NAME.app oraz $OUT_DIR/$APP_NAME.zip"
```

- [ ] **Step 3: Nadaj prawa i zbuduj**

Run: `chmod +x Scripts/build-app.sh && ./Scripts/build-app.sh`
Expected: `✓ Gotowe: .../build/VercelBar.app ...`, weryfikacja podpisu bez błędów.

- [ ] **Step 4: Smoke test bundla**

Run: `open build/VercelBar.app`
Sprawdź ręcznie:
1. W pasku menu trójkąt, bez ikony w Docku (LSUIElement).
2. Onboarding → Ustawienia → wklej token → „Połączono".
3. Zakładka Projekty → zaznacz 2–3 projekty → popover pokazuje wiersze.
4. Klik wiersza otwiera deploy w przeglądarce.
5. Wypchnij commit do któregoś projektu: ikona niebieszczeje i pulsuje, wiersz dostaje pasek postępu, po buildzie przychodzi powiadomienie ✅ (macOS zapyta o zgodę na powiadomienia przy pierwszym razie).
6. Wyłącz Wi-Fi na chwilę: popover pokazuje wariant offline, ikona szarzeje; po powrocie sieci dane wracają.
7. „Uruchamiaj przy logowaniu" włącza się bez błędu.
Zamknij aplikację przez „Zakończ" w popoverze.

- [ ] **Step 5: Napisz `README.md`**

```markdown
# VercelBar

Aplikacja paska menu macOS: stan deployów Vercela na żywo. Trójkąt w pasku
zmienia kolor (zielony = wdrożone, niebieski pulsujący = build w toku,
czerwony = błąd), popover pokazuje obserwowane projekty, a powiadomienia
zgłaszają padnięte i ukończone deploye.

## Instalacja

1. Zbuduj: `./Scripts/build-app.sh` (wymaga Swift toolchain / Command Line Tools).
2. Przenieś `build/VercelBar.app` do Programów.
3. Przy pierwszym uruchomieniu: prawy przycisk → Otwórz (aplikacja bez płatnego
   podpisu Apple).

## Konfiguracja

1. Wygeneruj token: vercel.com → Account Settings → Tokens (wystarczy odczyt).
2. Klik w trójkąt → Połącz z Vercelem → wklej token.
3. Zakładka Projekty → zaznacz, co obserwować.

Token ląduje w Keychain. Aplikacja odpytuje API co 30 s (10 s podczas builda).

## Rozwój

- `swift run vercelbar` — uruchomienie deweloperskie (z ikoną w Docku; bundle jej nie ma).
- `swift run vercelbar-tests` — testy rdzenia.
- Spec i makiety: `docs/`.
```

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "Pakowanie VercelBar.app, ikona aplikacji i README"
```

---

## Zatwierdzone odstępstwa od planu (obowiązują w kolejnych taskach)

Po przeglądach jakości Tasków 1–2 wprowadzono zmiany względem kodu wklejonego wyżej. Implementując Taski 3–13 traktuj poniższe jako nadrzędne wobec snippetów planu:

1. **`DeployState` ma case `.unknown`** — fallback dla nieznanych stanów API (nie `.queued`). `unknown` NIE jest aktywny. Każdy `switch` po stanie (badge, kolory) obsługuje `.unknown` jak `.canceled`/szary.
2. **`DeploymentSummary.createdAt` to `Date?`** (bez sentinela 1970). `duration` wymaga `readyAt` i znanego startu. W UI: czas względny i sortowanie muszą znosić `nil` (`latest?.createdAt` → spłaszczone `Date?`, sortowanie z `?? .distantPast`).
3. **`DeploymentSummary.init`** ma domyślne `nil` dla parametrów opcjonalnych.
4. **`APIDecoding`**: `meta` dekodowane odpornie (`LossyStringDict` — nie-stringi pomijane); `previewURL` dokleja `https://` tylko gdy brak schematu.
5. **Runner testów** ma dodatkowo `skip()`, zbiorczą sekcję „Niezaliczone:" i format porażki `[oczekiwano: X, jest: Y]`.
6. **Architektura zapytań bez zmian** (N+1: `/v9/projects` + `/v6/deployments?projectId=`) — świadoma decyzja: gwarantowany `inspectorUrl`, limity API z zapasem. Ewentualna optymalizacja przez `latestDeployments` z `/v9/projects` to osobny task po v1.

---

## Weryfikacja końcowa (po wszystkich taskach)

- [ ] `swift run vercelbar-tests` — komplet zielony.
- [ ] `./Scripts/build-app.sh` — buduje i podpisuje bez błędów.
- [ ] Checklist manualny z Tasku 13 Step 4 zaliczony w całości.
- [ ] Wygląd zgodny z makietami (`docs/design/*.dc.html`): szerokość 340, kolory badge'ów, hover ze strzałką, puls kropki, pasek postępu, warianty onboarding/offline.
