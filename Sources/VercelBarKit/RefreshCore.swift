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
