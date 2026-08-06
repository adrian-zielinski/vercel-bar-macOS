import Foundation

/// Formatowanie czasu po polsku dla popovera i powiadomień.
public enum Format {

    /// Czas względny: „teraz", „50 s temu", „2 min temu", „1 godz. temu", „wczoraj", „3 dni temu".
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
    public static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s < 60 { return "\(s) s" }
        return "\(s / 60) min \(String(format: "%02d", s % 60)) s"
    }

    /// Zegar HH:mm do stopki „odświeżono 12:04".
    public static func clock(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        // Format stały: locale POSIX, żeby systemowe ustawienie 12/24 h nie przepisało wzorca.
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        f.timeZone = timeZone
        return f.string(from: date)
    }
}
