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
