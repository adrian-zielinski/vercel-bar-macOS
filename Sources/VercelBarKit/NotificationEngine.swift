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
