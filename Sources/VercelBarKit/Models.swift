import Foundation

/// Stan deployu z API Vercela.
public enum DeployState: String, Equatable, Sendable {
    case ready = "READY"
    case error = "ERROR"
    case building = "BUILDING"
    case queued = "QUEUED"
    case initializing = "INITIALIZING"
    case canceled = "CANCELED"
    /// Stan spoza znanego zbioru (np. DELETED, puste pole) — nie udaje builda w toku.
    case unknown = "UNKNOWN"

    /// Nieznane wartości spadają do `.unknown` (neutralny szary, bez pollingu co 10 s).
    public init(rawAPI: String) {
        self = DeployState(rawValue: rawAPI.uppercased()) ?? .unknown
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
    /// Brak pola w odpowiedzi API zostaje `nil` — bez sentinela 1970, który psuł `duration`.
    public let createdAt: Date?
    public let buildingAt: Date?
    public let readyAt: Date?
    public let previewURL: URL?
    public let inspectorURL: URL?

    public init(id: String, state: DeployState, branch: String? = nil, commitMessage: String? = nil,
                createdAt: Date? = nil, buildingAt: Date? = nil, readyAt: Date? = nil,
                previewURL: URL? = nil, inspectorURL: URL? = nil) {
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

    /// Czas budowania w sekundach (dla zakończonych deployów ze znanym początkiem).
    public var duration: TimeInterval? {
        guard let readyAt, let start = buildingAt ?? createdAt else { return nil }
        return readyAt.timeIntervalSince(start)
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
