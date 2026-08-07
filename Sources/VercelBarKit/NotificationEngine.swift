import Foundation

/// Zdarzenie do pokazania użytkownikowi.
public struct DeployEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case started
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
    /// "deployID|kind" — rośnie przez całe życie procesu świadomie: przycinanie groziłoby
    /// powtórnym powiadomieniem, gdyby stary deploy wrócił na szczyt listy projektu.
    private var notified: Set<String> = []

    public init() {}

    public mutating func ingest(projects: [Project]) -> [DeployEvent] {
        var events: [DeployEvent] = []
        for p in projects {
            guard let current = p.latest else { continue }
            defer { lastSeen[p.id] = current }
            guard let previous = lastSeen[p.id] else { continue } // baseline — bez powiadomień
            let isNewDeployment = previous.id != current.id

            // Dedup po parze deploy+rodzaj: start i sukces tego samego builda to dwa zdarzenia,
            // ale każde ma polecieć dokładnie raz.
            func emit(_ kind: DeployEvent.Kind) {
                let key = current.id + "|\(kind)"
                guard !notified.contains(key) else { return }
                notified.insert(key)
                events.append(DeployEvent(kind: kind, projectName: p.name, deployment: current))
            }

            if isNewDeployment && current.state.isActive {
                emit(.started)
            }

            if current.state == .error {
                let alreadyErrored = !isNewDeployment && previous.state == .error
                if !alreadyErrored { emit(.failed) }
            }

            if current.state == .ready {
                // Build widziany w toku albo nowy deployment zastany już gotowym — ten drugi
                // przypadek to build krótszy niż odstęp między odpytaniami; wcześniej przechodził cicho.
                let watchedInProgress = !isNewDeployment && previous.state.isActive
                if watchedInProgress || isNewDeployment { emit(.succeeded) }
            }
        }

        // Projekt odznaczony traci baseline — po ponownym zaznaczeniu najpierw dostaje świeży,
        // zamiast wystrzelić powiadomieniem o zdarzeniu sprzed przerwy w obserwacji.
        // Projekt obecny w migawce bez deployu (`latest == nil`) zostaje — to czkawka API, nie odznaczenie.
        let currentIDs = Set(projects.map(\.id))
        lastSeen = lastSeen.filter { currentIDs.contains($0.key) }

        return events
    }
}
