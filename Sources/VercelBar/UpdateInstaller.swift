import AppKit
import Foundation
import VercelBarKit

/// Aktualizacja jednym kliknięciem: pobranie paczki, weryfikacja bundla, podmiana
/// w miejscu działania i restart już w nowej wersji.
///
/// Każda porażka kończy się tak samo — strona wydania w przeglądarce i stan `.failed`.
/// Aplikacja nigdy nie zostaje w połowie zainstalowana ani nie znika z dysku:
/// operacje na plikach robi `UpdateInstallEngine`, który przy błędzie oddaje starą wersję.
@MainActor
enum UpdateInstaller {

    enum State: Equatable, Sendable {
        case idle
        case downloading
        case installing
        case failed
    }

    static func install(_ update: UpdateInfo, onState: @escaping @MainActor (State) -> Void) async {
        // Poza bundlem (`swift run`) nie ma czego podmieniać ani czym się restartować.
        guard Bundle.main.bundleIdentifier == UpdateInstallEngine.expectedBundleID else {
            fallback(update, workDirectory: nil, onState: onState)
            return
        }
        let destination = Bundle.main.bundleURL

        let workDirectory: URL
        do {
            workDirectory = try UpdateInstallEngine.makeWorkDirectory()
        } catch {
            fallback(update, workDirectory: nil, onState: onState)
            return
        }

        onState(.downloading)
        let zip = workDirectory.appendingPathComponent(UpdateEndpoint.assetName)
        do {
            let (downloaded, response) = try await URLSession.shared.download(from: update.zipURL)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                throw UpdateInstallError.downloadFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
            }
            // Plik z `download` znika zaraz po powrocie z wywołania — przenieś od razu.
            try FileManager.default.moveItem(at: downloaded, to: zip)
        } catch {
            fallback(update, workDirectory: workDirectory, onState: onState)
            return
        }

        onState(.installing)
        let outcome: UpdateInstallEngine.Outcome
        do {
            // Rozpakowanie (ditto) i podmiana blokują wątek — poza MainActorem,
            // żeby ikona paska menu nie zamarła na czas instalacji.
            let version = update.version
            outcome = try await Task.detached(priority: .userInitiated) {
                try UpdateInstallEngine.install(zip: zip,
                                                destination: destination,
                                                expectedVersion: version,
                                                workDirectory: workDirectory)
            }.value
        } catch {
            fallback(update, workDirectory: workDirectory, onState: onState)
            return
        }

        // Katalog roboczy sprzątamy tylko wtedy, gdy nie ma w nim poprzedniej wersji
        // (kosz odmówił). Resztę i tak zabierze system przy czyszczeniu /tmp.
        let retiredInWorkDirectory = outcome.retiredOld?.path.hasPrefix(workDirectory.path) == true
        if !retiredInWorkDirectory { try? FileManager.default.removeItem(at: workDirectory) }

        restartAfterQuit(destination: destination)
    }

    /// Odłączona powłoka czeka, aż ten proces zniknie, i otwiera nową wersję.
    /// Odpalona przed `terminate`, bo po nim nie ma już kto tego zrobić.
    private static func restartAfterQuit(destination: URL) {
        let command = UpdateInstallEngine.restartShellCommand(pid: ProcessInfo.processInfo.processIdentifier,
                                                              destination: destination)
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", command]
        shell.standardOutput = FileHandle.nullDevice
        shell.standardError = FileHandle.nullDevice
        // Nawet gdyby powłoka nie ruszyła, wychodzimy: bundel tego procesu jest już w koszu,
        // więc dalsze działanie na jego zasobach to proszenie się o kłopoty. Nowa wersja
        // stoi pod tą samą ścieżką i czeka na kliknięcie.
        try? shell.run()
        NSApp.terminate(nil)
    }

    /// Ostatnia deska ratunku: strona wydania w przeglądarce i sprzątnięcie po sobie.
    private static func fallback(_ update: UpdateInfo,
                                 workDirectory: URL?,
                                 onState: @MainActor (State) -> Void) {
        if let workDirectory { try? FileManager.default.removeItem(at: workDirectory) }
        NSWorkspace.shared.open(update.releaseURL)
        onState(.failed)
    }
}
