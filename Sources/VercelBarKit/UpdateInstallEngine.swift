import Foundation

public enum UpdateInstallError: Error, Equatable, Sendable {
    case downloadFailed(Int)
    case unpackFailed(Int32)
    case bundleMissing
    case infoPlistUnreadable
    case identifierMismatch(String?)
    case versionMismatch(String?)
    case executableMissing
    case signatureInvalid
    case destinationNotWritable
    case replaceFailed

    /// Paczka dojechała, ale jej zawartość jest nie do użytku — UI mówi o tym wprost,
    /// bo to co innego niż brak praw zapisu czy zerwane pobieranie.
    public var meansDamagedPackage: Bool {
        switch self {
        case .unpackFailed, .bundleMissing, .infoPlistUnreadable,
             .identifierMismatch, .versionMismatch, .executableMissing, .signatureInvalid:
            return true
        case .downloadFailed, .destinationNotWritable, .replaceFailed:
            return false
        }
    }
}

/// Operacje na plikach przy aktualizacji: rozpakowanie paczki, weryfikacja bundla
/// i podmiana starej aplikacji nową. Wszystko z `destination` w parametrze, więc
/// całość da się przepuścić przez atrapę bundla w testach, bez ruszania działającej aplikacji.
public enum UpdateInstallEngine {

    public static let expectedBundleID = "pl.zielinski.vercelbar"
    public static let bundleName = "VercelBar.app"

    public struct Outcome: Equatable, Sendable {
        /// Gdzie stanęła nowa wersja (to samo miejsce, co stara).
        public let installed: URL
        /// Gdzie wylądował stary bundel: kosz albo katalog roboczy. Nil, gdy w miejscu docelowym nic nie było.
        public let retiredOld: URL?
    }

    // MARK: katalog roboczy

    /// Świeży katalog w `NSTemporaryDirectory()` na paczkę i rozpakowany bundel.
    public static func makeWorkDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("vercelbar-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: rozpakowanie

    /// `ditto -x -k` zamiast `unzip`: tylko ditto odtwarza bundel bez plików AppleDouble,
    /// które psują pieczęć podpisu (tym samym narzędziem paczka jest tworzona).
    public static func unpack(zip: URL, into directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let status = run("/usr/bin/ditto", ["-x", "-k", zip.path, directory.path])
        guard status == 0 else { throw UpdateInstallError.unpackFailed(status) }
    }

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    // MARK: weryfikacja

    /// Bundel z paczki musi być tą samą aplikacją i dokładnie tą wersją, po którą sięgaliśmy.
    /// Inaczej podmiana jest odmawiana — przekierowany host, podmieniony asset czy zwykła
    /// pomyłka w wydaniu nie mają prawa wejść na miejsce działającej aplikacji.
    @discardableResult
    public static func verifiedBundle(in directory: URL, expectedVersion: String) throws -> URL {
        let bundle = directory.appendingPathComponent(bundleName, isDirectory: true)
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: bundle.path, isDirectory: &isDir), isDir.boolValue,
              FileManager.default.fileExists(atPath: plist.path) else {
            throw UpdateInstallError.bundleMissing
        }
        // `fileExists` podąża za dowiązaniem, więc symlink przeszedłby jako katalog i został
        // zainstalowany jako symlink. `attributesOfItem` używa lstat i widzi prawdę.
        if let type = (try? FileManager.default.attributesOfItem(atPath: bundle.path))?[.type]
            as? FileAttributeType, type == .typeSymbolicLink {
            throw UpdateInstallError.bundleMissing
        }
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any] else {
            throw UpdateInstallError.infoPlistUnreadable
        }
        let identifier = info["CFBundleIdentifier"] as? String
        guard identifier == expectedBundleID else {
            throw UpdateInstallError.identifierMismatch(identifier)
        }
        let version = info["CFBundleShortVersionString"] as? String
        guard let version, SemVer.equals(version, expectedVersion) else {
            throw UpdateInstallError.versionMismatch(version)
        }

        // Info.plist to za mało: paczka bywa obcięta albo pusta w środku, a wtedy podmiana
        // kończy się aplikacją, która nie startuje — ze starą już w koszu.
        let executable = (info["CFBundleExecutable"] as? String) ?? "VercelBar"
        guard FileManager.default.isExecutableFile(
                atPath: bundle.appendingPathComponent("Contents/MacOS/\(executable)").path) else {
            throw UpdateInstallError.executableMissing
        }

        // Pieczęć podpisu ad-hoc obejmuje każdy plik bundla, więc `codesign --verify` wyłapie
        // obcięcie, uszkodzenie i podmianę pojedynczego zasobu. To samo polecenie, którym
        // `Scripts/build-app.sh` przyjmuje paczkę przed wrzuceniem na wydanie.
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", bundle.path]) == 0 else {
            throw UpdateInstallError.signatureInvalid
        }
        return bundle
    }

    // MARK: podmiana

    /// Podmiana z jak najkrótszym oknem, w którym pod ścieżką docelową nie ma aplikacji.
    ///
    /// Nowy bundel ląduje najpierw OBOK celu, na tym samym woluminie: kosztowne kopiowanie
    /// dzieje się, gdy stara wersja jeszcze stoi na miejscu, a krok niszczący to jedno
    /// `rename()`. Bez tego `moveItem` z katalogu tymczasowego degraduje się na innym
    /// woluminie (dysk zewnętrzny, druga partycja) do kopiowania, które przerwane w połowie
    /// zostawia ogryzek pod ścieżką docelową — i wtedy stara wersja nie ma dokąd wrócić.
    ///
    /// `moveOldToTrash: false` używane w testach: atrapa nie ma po co lądować w koszu użytkownika.
    public static func replace(destination: URL,
                               with newBundle: URL,
                               workDirectory: URL,
                               moveOldToTrash: Bool = true) throws -> Outcome {
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parent.path) else {
            throw UpdateInstallError.destinationNotWritable
        }

        // `ditto`, bo tylko ono kopiuje bundel bez naruszenia pieczęci podpisu.
        let staged = parent.appendingPathComponent(".\(bundleName).new-\(UUID().uuidString)")
        try? fm.removeItem(at: staged)
        guard run("/usr/bin/ditto", [newBundle.path, staged.path]) == 0 else {
            try? fm.removeItem(at: staged)
            throw UpdateInstallError.replaceFailed
        }

        var retired: URL?
        if fm.fileExists(atPath: destination.path) {
            guard fm.isWritableFile(atPath: destination.path) else {
                try? fm.removeItem(at: staged)
                throw UpdateInstallError.destinationNotWritable
            }
            do {
                retired = try retire(destination, workDirectory: workDirectory, useTrash: moveOldToTrash)
            } catch {
                try? fm.removeItem(at: staged)
                throw error
            }
        }
        return try commitReplacement(staged: staged, destination: destination, retired: retired)
    }

    /// Ostatni krok podmiany, wydzielony, bo to jedyne miejsce, w którym pod ścieżką docelową
    /// może chwilowo nie być aplikacji — i jedyne, które trzeba umieć przetestować wprost.
    /// Gdy wejście nowej wersji padnie, `retired` wraca na miejsce.
    @discardableResult
    public static func commitReplacement(staged: URL,
                                         destination: URL,
                                         retired: URL?) throws -> Outcome {
        let fm = FileManager.default
        do {
            try fm.moveItem(at: staged, to: destination)
        } catch {
            // Ogryzek sprzątamy tylko wtedy, gdy mamy co przywrócić: bez `retired` pod
            // ścieżką docelową może stać cudza aplikacja, której nie wolno nam skasować.
            if let retired {
                try? fm.removeItem(at: destination)
                try? fm.moveItem(at: retired, to: destination)
            }
            try? fm.removeItem(at: staged)
            throw UpdateInstallError.replaceFailed
        }
        return Outcome(installed: destination, retiredOld: retired)
    }

    /// Kosz jest pierwszym wyborem (użytkownik może cofnąć aktualizację), ale nie zawsze istnieje —
    /// na woluminie bez kosza albo przy odmowie systemu stara wersja idzie do katalogu roboczego.
    private static func retire(_ url: URL, workDirectory: URL, useTrash: Bool) throws -> URL {
        let fm = FileManager.default
        if useTrash {
            var trashed: NSURL?
            if (try? fm.trashItem(at: url, resultingItemURL: &trashed)) != nil {
                return (trashed as URL?) ?? url
            }
        }
        let backup = workDirectory.appendingPathComponent("previous-\(UUID().uuidString)-\(url.lastPathComponent)")
        try fm.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        try fm.moveItem(at: url, to: backup)
        return backup
    }

    // MARK: całość

    /// Paczka → zweryfikowany bundel → podmiana. Rzuca przy każdej niezgodności,
    /// zostawiając miejsce docelowe nietknięte.
    @discardableResult
    public static func install(zip: URL,
                               destination: URL,
                               expectedVersion: String,
                               workDirectory: URL,
                               moveOldToTrash: Bool = true) throws -> Outcome {
        let unpacked = workDirectory.appendingPathComponent("unpacked", isDirectory: true)
        try unpack(zip: zip, into: unpacked)
        let bundle = try verifiedBundle(in: unpacked, expectedVersion: expectedVersion)
        return try replace(destination: destination,
                           with: bundle,
                           workDirectory: workDirectory,
                           moveOldToTrash: moveOldToTrash)
    }

    // MARK: restart

    /// Polecenie dla odłączonej powłoki: poczekaj, aż proces zniknie, i odpal nową wersję.
    /// `kill -0` tylko sprawdza istnienie procesu, niczego nie ubija.
    public static func restartShellCommand(pid: Int32, destination: URL) -> String {
        // Ścieżka w apostrofach; apostrof w nazwie katalogu zamykamy i doklejamy jako literał.
        let quoted = "'" + destination.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        // Czekanie ograniczone do 30 s: gdyby proces nie zniknął albo pid trafił do ponownego
        // użycia, powłoka odpala nową wersję zamiast wisieć bez końca. Trzy podejścia do
        // `open`, bo LaunchServices bywa zajęte tuż po podmianie bundla pod tą samą ścieżką.
        // Ostatnia deska ratunku: pokaż aplikację w Finderze, żeby użytkownik wiedział, gdzie stoi.
        return "n=0; while kill -0 \(pid) 2>/dev/null && [ $n -lt 150 ]; do sleep 0.2; n=$((n+1)); done; "
             + "for i in 1 2 3; do open \(quoted) && exit 0; sleep 1; done; open -R \(quoted)"
    }
}
