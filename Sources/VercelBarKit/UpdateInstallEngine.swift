import Foundation

public enum UpdateInstallError: Error, Equatable, Sendable {
    case downloadFailed(Int)
    case unpackFailed(Int32)
    case bundleMissing
    case infoPlistUnreadable
    case identifierMismatch(String?)
    case versionMismatch(String?)
    case destinationNotWritable
    case replaceFailed
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
        return bundle
    }

    // MARK: podmiana

    /// Podmiana atomowa na tyle, na ile pozwala system plików: najpierw stary bundel znika
    /// z miejsca docelowego, potem wchodzi nowy. Gdy wejście nowego padnie, stary wraca —
    /// żadnego stanu „aplikacja zniknęła".
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

        var retired: URL?
        if fm.fileExists(atPath: destination.path) {
            guard fm.isWritableFile(atPath: destination.path) else {
                throw UpdateInstallError.destinationNotWritable
            }
            retired = try retire(destination, workDirectory: workDirectory, useTrash: moveOldToTrash)
        }

        do {
            try fm.moveItem(at: newBundle, to: destination)
        } catch {
            // Miejsce docelowe zostało puste — oddaj starą wersję, zanim zgłosisz porażkę.
            if let retired, !fm.fileExists(atPath: destination.path) {
                try? fm.moveItem(at: retired, to: destination)
            }
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
        return "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \(quoted)"
    }
}
