import Foundation

/// Stan zbiorczy dla ikony paska menu i nagłówka popovera.
public enum AggregateState: Equatable, Sendable {
    case ready
    case building
    case error
    /// Brak danych albo same canceled/unknown.
    case idle
}

public enum StatusAggregator {

    /// Priorytet: Error > Building (w tym Queued/Initializing) > Ready. Canceled i unknown pomijane.
    public static func aggregate(_ states: [DeployState]) -> AggregateState {
        if states.contains(.error) { return .error }
        if states.contains(where: { $0.isActive }) { return .building }
        if states.contains(.ready) { return .ready }
        return .idle
    }

    public static func headline(for states: [DeployState]) -> String {
        switch aggregate(states) {
        case .error: return fallenDeploys(states.filter { $0 == .error }.count)
        case .building: return "Build w toku…"
        case .ready: return "Wszystko wdrożone"
        case .idle: return "Brak obserwowanych projektów"
        }
    }

    /// Odmiana przez liczebniki: 1 deploy padł, 2–4 deploye padły, reszta deployów padło.
    private static func fallenDeploys(_ n: Int) -> String {
        if n == 1 { return "1 deploy padł" }
        let last = n % 10, lastTwo = n % 100
        if (2...4).contains(last) && !(12...14).contains(lastTwo) { return "\(n) deploye padły" }
        return "\(n) deployów padło"
    }
}
