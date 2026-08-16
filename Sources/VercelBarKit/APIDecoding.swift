import Foundation

/// Dekodowanie surowych odpowiedzi API Vercela na modele domeny.
public enum APIDecoding {

    /// Słownik metadanych odporny na wartości nie-stringowe — pomija je zamiast wywalać dekodowanie.
    struct LossyStringDict: Decodable {
        let values: [String: String]

        struct DynamicKey: CodingKey {
            var stringValue: String
            init?(stringValue: String) { self.stringValue = stringValue }
            var intValue: Int? { nil }
            init?(intValue: Int) { nil }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: DynamicKey.self)
            var out: [String: String] = [:]
            for key in c.allKeys {
                if let v = try? c.decode(String.self, forKey: key) { out[key.stringValue] = v }
            }
            values = out
        }
    }

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
            let meta: LossyStringDict?
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
            // /v2/user zwraca `id` (wg OpenAPI Vercela `uid` nie istnieje);
            // `uid` zostaje jako fallback dla historycznych odpowiedzi.
            let id: String?
            let uid: String?
            let username: String
            let name: String?
        }
        let user: U
    }

    struct TeamsEnvelope: Decodable {
        struct Item: Decodable {
            let id: String
            let name: String? // nullable wg OpenAPI — zespół bez nazwy pokazujemy po slugu
            let slug: String
        }
        let teams: [Item]
    }

    /// 0 i liczby ujemne to brak daty — Vercel wysyła `ready: 0` przy jeszcze niegotowym deployu.
    /// Sentinel 1970 psuł `duration` (ujemny czas → „0 s" w UI).
    private static func date(fromMs ms: Double?) -> Date? {
        guard let ms, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    /// Gałąź/commit siedzą w meta pod kluczem zależnym od dostawcy gita.
    private static func metaValue(_ meta: LossyStringDict?, suffix: String) -> String? {
        guard let values = meta?.values else { return nil }
        for provider in ["github", "gitlab", "bitbucket"] {
            if let v = values[provider + suffix] { return v }
        }
        return nil
    }

    public static func deployments(from data: Data) throws -> [DeploymentSummary] {
        let env = try JSONDecoder().decode(DeploymentsEnvelope.self, from: data)
        return env.deployments.map { item in
            DeploymentSummary(
                id: item.uid,
                state: DeployState(rawAPI: item.state ?? item.readyState ?? ""),
                branch: metaValue(item.meta, suffix: "CommitRef"),
                commitMessage: metaValue(item.meta, suffix: "CommitMessage"),
                createdAt: date(fromMs: item.createdAt ?? item.created),
                buildingAt: date(fromMs: item.buildingAt),
                readyAt: date(fromMs: item.ready),
                previewURL: item.url.flatMap { raw in
                    URL(string: raw.contains("://") ? raw : "https://\(raw)")
                },
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
        guard let id = u.id ?? u.uid else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "odpowiedź /v2/user bez id ani uid"))
        }
        return VercelUser(id: id, username: u.username, name: u.name)
    }

    public static func teams(from data: Data) throws -> [Team] {
        try JSONDecoder().decode(TeamsEnvelope.self, from: data)
            .teams.map { Team(id: $0.id, name: $0.name ?? $0.slug, slug: $0.slug) }
    }
}
