import Foundation

/// Kiedy ikona paska ma pulsować. Osobne od `anyActive`: ERROR + BUILDING
/// zostawia polling, ale ikona jest czerwona i stoi.
public enum PulsePolicy {
    /// Po tylu sekundach tego samego zestawu deployów gasimy puls.
    /// Wiszący BUILDING z API nie ma prawa jechać 10 Hz do rana.
    public static let maxContinuous: TimeInterval = 45 * 60

    public struct State: Equatable, Sendable {
        public var deployIDs: Set<String>
        public var startedAt: Date?

        public init(deployIDs: Set<String> = [], startedAt: Date? = nil) {
            self.deployIDs = deployIDs
            self.startedAt = startedAt
        }
    }

    public struct Decision: Equatable, Sendable {
        public var shouldPulse: Bool
        public var state: State

        public init(shouldPulse: Bool, state: State) {
            self.shouldPulse = shouldPulse
            self.state = state
        }
    }

    public static func activeDeployIDs(in projects: [Project]) -> Set<String> {
        Set(projects.compactMap { project in
            guard let deploy = project.latest, deploy.state.isActive else { return nil }
            return deploy.id
        })
    }

    public static func evaluate(overall: AggregateState,
                                buildingDeployIDs: Set<String>,
                                previous: State,
                                now: Date,
                                reduceMotion: Bool,
                                maxContinuous: TimeInterval = maxContinuous) -> Decision {
        guard !reduceMotion, overall == .building, !buildingDeployIDs.isEmpty else {
            return Decision(shouldPulse: false, state: State())
        }
        let startedAt: Date
        if previous.deployIDs == buildingDeployIDs, let existing = previous.startedAt {
            startedAt = existing
        } else {
            startedAt = now
        }
        let elapsed = now.timeIntervalSince(startedAt)
        return Decision(shouldPulse: elapsed < maxContinuous,
                        state: State(deployIDs: buildingDeployIDs, startedAt: startedAt))
    }
}
