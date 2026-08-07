import Foundation

/// Nowsze wydanie znalezione na GitHubie: co pobrać i dokąd odesłać użytkownika,
/// gdy instalacja się nie powiedzie.
public struct UpdateInfo: Equatable, Sendable {
    public let version: String
    public let zipURL: URL
    public let releaseURL: URL

    public init(version: String, zipURL: URL, releaseURL: URL) {
        self.version = version
        self.zipURL = zipURL
        self.releaseURL = releaseURL
    }
}

/// Porównanie wersji X.Y.Z. Świadomie minimalne: tagi wydań mają jeden kształt,
/// a pełny SemVer (prerelease, build metadata) nie jest tu do niczego potrzebny.
public enum SemVer {

    /// Liczby wersji, bez prefiksu „v". Cokolwiek innego niż cyfry i kropki → nil.
    static func parse(_ raw: String) -> [Int]? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        guard !text.isEmpty else { return nil }
        var out: [Int] = []
        for part in text.split(separator: ".", omittingEmptySubsequences: false) {
            // Int("1a") to nil, więc śmieciowy człon wywraca cały numer — i dobrze.
            guard let n = Int(part), n >= 0 else { return nil }
            out.append(n)
        }
        return out
    }

    /// Czy `candidate` jest wyższe od `current`. Nieparsowalna którakolwiek strona → false
    /// (nie wiemy, co porównujemy — lepiej nie proponować aktualizacji).
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = parse(candidate), let b = parse(current) else { return false }
        // Dopełnienie zerami: „2.0" i „2.0.0" to ta sama wersja, nie dwie różne.
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Ta sama wersja mimo różnej liczby członów („1.2" == „1.2.0"). Nieparsowalna strona → false,
    /// więc śmieciowy numer w Info.plist nie przechodzi jako „zgodny" przy weryfikacji paczki.
    public static func equals(_ a: String, _ b: String) -> Bool {
        guard let x = parse(a), let y = parse(b) else { return false }
        for i in 0..<max(x.count, y.count) where (i < x.count ? x[i] : 0) != (i < y.count ? y[i] : 0) {
            return false
        }
        return true
    }
}

/// Adres sprawdzania aktualizacji. Osobno, bo runner testów weryfikuje sam URL.
public struct UpdateEndpoint {
    public static let latestReleaseURL =
        URL(string: "https://api.github.com/repos/adrian-zielinski/vercel-bar-macOS/releases/latest")!
    /// Nazwa assetu z bundlem — ta sama, którą wypluwa `Scripts/build-app.sh`.
    public static let assetName = "VercelBar.zip"
}

/// Odpytanie GitHub Releases o najnowsze wydanie. Jeden anonimowy request na dobę,
/// bez tokenu — limit 60/h na IP wystarcza z zapasem.
public enum UpdateChecker {

    private struct ReleaseEnvelope: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let htmlURL: String
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft, prerelease, assets
        }
    }

    /// Zwraca opis aktualizacji tylko wtedy, gdy tag jest nowszy od bieżącej wersji
    /// I wydanie niesie gotowy do pobrania `VercelBar.zip`.
    public static func parseLatestRelease(from data: Data,
                                          currentVersion: String) throws -> UpdateInfo? {
        let release = try JSONDecoder().decode(ReleaseEnvelope.self, from: data)
        // Szkic i prerelease nie są dla wszystkich — nie proponuj ich w pasku.
        guard release.draft != true, release.prerelease != true else { return nil }
        guard SemVer.isNewer(release.tagName, than: currentVersion) else { return nil }
        guard let asset = release.assets.first(where: { $0.name == UpdateEndpoint.assetName }),
              let zipURL = URL(string: asset.browserDownloadURL),
              let releaseURL = URL(string: release.htmlURL) else { return nil }
        // Paczka podmieni działającą aplikację, więc bierzemy ją wyłącznie po HTTPS —
        // nawet gdyby odpowiedź API kiedyś wskazała inaczej.
        guard zipURL.scheme == "https", releaseURL.scheme == "https" else { return nil }
        // Wersja znormalizowana (bez „v", bez białych znaków, same człony liczbowe) —
        // trafia wprost do tekstu w UI i do porównania z Info.plist w paczce.
        guard let parts = SemVer.parse(release.tagName) else { return nil }
        let version = parts.map(String.init).joined(separator: ".")
        return UpdateInfo(version: version, zipURL: zipURL, releaseURL: releaseURL)
    }

    private static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Każda porażka (brak sieci, limit zapytań, zmiana formatu) kończy się `nil` —
    /// sprawdzanie aktualizacji nie ma prawa niczego zgłaszać użytkownikowi.
    public static func checkForUpdate(session: (any HTTPSession)? = nil,
                                      currentVersion: String) async -> UpdateInfo? {
        var request = URLRequest(url: UpdateEndpoint.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await (session ?? defaultSession).data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }
            return try parseLatestRelease(from: data, currentVersion: currentVersion)
        } catch {
            return nil
        }
    }
}
