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
