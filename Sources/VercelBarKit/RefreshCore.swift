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

        // Okno przesuwne zamiast wystrzelenia wszystkiego naraz: przy kilkudziesięciu
        // obserwowanych projektach salwa requestów łapie 429, a ten wywraca całą migawkę.
        var filled: [Project] = []
        try await withThrowingTaskGroup(of: Project.self) { group in
            var iterator = watched.makeIterator()
            func addNext() {
                guard let p = iterator.next() else { return }
                group.addTask {
                    var copy = p
                    copy.latest = try await api.latestDeployment(projectID: p.id)
                    return copy
                }
            }
            for _ in 0..<4 { addNext() } // limit równoległości: maks. 4 requesty naraz
            while let done = try await group.next() {
                filled.append(done)
                addNext()
            }
        }
        // Nazwa rozstrzyga remisy: task group kończy się w losowej kolejności, a bez tego
        // wiersze popovera tasowałyby się między odświeżeniami przy równym createdAt.
        filled.sort {
            let l = $0.latest?.createdAt ?? .distantPast
            let r = $1.latest?.createdAt ?? .distantPast
            if l != r { return l > r }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let states = filled.compactMap { $0.latest?.state }
        return Snapshot(projects: filled,
                        overall: StatusAggregator.aggregate(states),
                        anyActive: states.contains { $0.isActive })
    }
}
