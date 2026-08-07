import Foundation

/// Jeden krok odświeżenia: lista projektów + ostatnie deploye każdego obserwowanego.
public enum RefreshCore {

    /// Pozycja listy w popoverze: jeden deploy z przypiętą nazwą projektu.
    public struct FeedEntry: Sendable, Identifiable {
        public let id: String // id deploymentu
        public let projectID: String
        public let projectName: String
        public let deployment: DeploymentSummary

        public init(id: String, projectID: String, projectName: String, deployment: DeploymentSummary) {
            self.id = id
            self.projectID = projectID
            self.projectName = projectName
            self.deployment = deployment
        }
    }

    public struct Snapshot: Sendable {
        public let projects: [Project]     // posortowane: najnowszy deploy pierwszy
        public let feed: [FeedEntry]       // deploye wszystkich projektów, najnowszy pierwszy
        public let overall: AggregateState
        public let anyActive: Bool
    }

    public static func fetch(api: VercelAPI,
                             watchedProjectIDs: Set<String>,
                             feedLimit: Int = 5) async throws -> Snapshot {
        let all = try await api.projects()
        let watched = all.filter { watchedProjectIDs.contains($0.id) }

        // Okno przesuwne zamiast wystrzelenia wszystkiego naraz: przy kilkudziesięciu
        // obserwowanych projektach salwa requestów łapie 429, a ten wywraca całą migawkę.
        var filled: [Project] = []
        var feed: [FeedEntry] = []
        try await withThrowingTaskGroup(of: (Project, [DeploymentSummary]).self) { group in
            var iterator = watched.makeIterator()
            func addNext() {
                guard let p = iterator.next() else { return }
                group.addTask {
                    let recent = try await api.recentDeployments(projectID: p.id, limit: feedLimit)
                    var copy = p
                    copy.latest = recent.first // agregat i powiadomienia patrzą tylko na najnowszy
                    return (copy, recent)
                }
            }
            for _ in 0..<4 { addNext() } // limit równoległości: maks. 4 requesty naraz
            while let (project, recent) = try await group.next() {
                filled.append(project)
                feed.append(contentsOf: recent.map {
                    FeedEntry(id: $0.id, projectID: project.id, projectName: project.name, deployment: $0)
                })
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
        feed.sort(by: newerFirst)

        let states = filled.compactMap { $0.latest?.state }
        return Snapshot(projects: filled,
                        feed: Array(feed.prefix(feedLimit)),
                        overall: StatusAggregator.aggregate(states),
                        anyActive: states.contains { $0.isActive })
    }

    /// Malejąco po `createdAt`; deploy bez daty ląduje na końcu. Remis rozstrzyga nazwa
    /// projektu, a na końcu id deploymentu — kolejność ma być ta sama przy każdym odświeżeniu.
    private static func newerFirst(_ a: FeedEntry, _ b: FeedEntry) -> Bool {
        switch (a.deployment.createdAt, b.deployment.createdAt) {
        case let (l?, r?) where l != r: return l > r
        case (nil, _?): return false
        case (_?, nil): return true
        default: break
        }
        switch a.projectName.localizedCaseInsensitiveCompare(b.projectName) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return a.id < b.id
        }
    }
}
