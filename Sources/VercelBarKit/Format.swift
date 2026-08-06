import Foundation

/// Formatowanie czasu po polsku dla popovera i powiadomień.
public enum Format {

    /// Czas względny: „teraz", „50 s temu", „2 min temu", „1 godz. temu", „wczoraj", „3 dni temu".
    /// Obcina w dół (89 s to wciąż „89 s temu") — inaczej niż `duration`, które zaokrągla. Świadoma różnica:
    /// wiek deployu nie może wybiegać w przyszłość, czas trwania ma się zgadzać z sumą sekund.
    public static func relative(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(date))
        if s < 45 { return "teraz" }
        if s < 90 { return "\(Int(s)) s temu" }
        let minutes = Int(s / 60)
        if minutes < 60 { return "\(minutes) min temu" }
        let hours = Int(s / 3600)
        if hours < 24 { return "\(hours) godz. temu" }
        let days = Int(s / 86_400)
        if days < 2 { return "wczoraj" }
        return "\(days) dni temu"
    }

    /// Czas trwania builda: „38 s" poniżej minuty, dalej „2 min 06 s".
    /// Zaokrągla do najbliższej sekundy (inaczej niż obcinające `relative`). Powyżej godziny zostaje
    /// w minutach („60 min 00 s") — świadomy wybór, buildy tej długości to margines.
    public static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s < 60 { return "\(s) s" }
        return "\(s / 60) min \(String(format: "%02d", s % 60)) s"
    }

    /// Wzorzec stały, więc locale POSIX — systemowe ustawienie 12/24 h nie przepisze „HH:mm" na „h:mm a".
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Zegar HH:mm do stopki „odświeżono 12:04".
    /// Formatter współdzielony: podmieniamy tylko strefę, więc wołaj z głównego wątku (UI).
    public static func clock(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = clockFormatter
        f.timeZone = timeZone
        return f.string(from: date)
    }
}
