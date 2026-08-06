import Foundation

/// Warstwa sieci do wstrzykiwania w testach.
public protocol HTTPSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPSession {}

public enum VercelAPIError: Error, Equatable, Sendable {
    case unauthorized
    case rateLimited
    case server(Int)
    case offline
    case invalidResponse
}

/// Klient REST API Vercela. Tylko odczyt.
public struct VercelAPI: Sendable {
    private let token: String
    private let teamID: String?
    private let session: any HTTPSession
    private static let base = URL(string: "https://api.vercel.com")!

    /// Sesja z twardym deadline'em (15 s na cały request) i bez cache —
    /// stan deployu ma być świeży, a wiszący request nie może blokować pętli odświeżania.
    private static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// `session: nil` bierze `defaultSession`. Sentinel zamiast domyślnej wartości argumentu,
    /// bo publiczny init nie może sięgnąć po prywatną statyczną własność.
    public init(token: String, teamID: String? = nil, session: (any HTTPSession)? = nil) {
        self.token = token
        self.teamID = teamID
        self.session = session ?? VercelAPI.defaultSession
    }

    public func user() async throws -> VercelUser {
        let data = try await get("/v2/user")
        return try APIDecoding.user(from: data)
    }

    public func teams() async throws -> [Team] {
        let data = try await get("/v2/teams")
        return try APIDecoding.teams(from: data)
    }

    public func projects() async throws -> [Project] {
        let data = try await get("/v9/projects", query: ["limit": "100"])
        return try APIDecoding.projects(from: data)
    }

    public func latestDeployment(projectID: String) async throws -> DeploymentSummary? {
        let data = try await get("/v6/deployments", query: ["projectId": projectID, "limit": "1"])
        return try APIDecoding.deployments(from: data).first
    }

    private func get(_ path: String, query: [String: String] = [:]) async throws -> Data {
        var comps = URLComponents(url: Self.base.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)!
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        if let teamID { items.append(URLQueryItem(name: "teamId", value: teamID)) }
        if !items.isEmpty { comps.queryItems = items.sorted { $0.name < $1.name } }

        var request = URLRequest(url: comps.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15 // krócej niż domyślne 60 s — przy pollingu co 10 s requesty by się nawarstwiały

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError() // anulowany polling to nie brak sieci
        } catch let e as URLError where e.code == .cancelled {
            throw CancellationError()
        } catch {
            throw VercelAPIError.offline // każdy inny błąd transportu = brak sieci
        }
        guard let http = response as? HTTPURLResponse else { throw VercelAPIError.invalidResponse }
        switch http.statusCode {
        case 200...299: return data
        case 401, 403: throw VercelAPIError.unauthorized
        case 429: throw VercelAPIError.rateLimited
        case 500...599: throw VercelAPIError.server(http.statusCode)
        default: throw VercelAPIError.invalidResponse
        }
    }
}
