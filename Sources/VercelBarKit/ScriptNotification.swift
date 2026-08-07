import Foundation

/// Powiadomienie wysyłane przez `/usr/bin/osascript` — droga zapasowa na wypadek,
/// gdy macOS nie przyzna aplikacji natywnych uprawnień powiadomień.
///
/// Nazwy projektów, nazwy gałęzi i komunikaty commitów pochodzą z zewnątrz.
/// Cudzysłów, apostrof czy `$(whoami)` w treści nie mogą trafić do kodu skryptu,
/// więc skrypt jest stałą, a tytuł i treść idą osobno jako argumenty (`argv`).
public enum ScriptNotification {
    /// Czyta treść i tytuł z `argv` — zero interpolacji, zero sklejania stringów.
    public static let script = """
    on run argv
        display notification (item 1 of argv) with title (item 2 of argv) sound name "Ping"
    end run
    """

    /// Argumenty dla `/usr/bin/osascript`.
    ///
    /// `--` jest obowiązkowe: bez niego treść zaczynająca się od myślnika
    /// (np. komunikat commita „-fix crash") ląduje w parserze opcji osascripta
    /// i cały wywołanie kończy się błędem „illegal option".
    /// Kolejność po separatorze to treść, potem tytuł — dokładnie tak,
    /// jak skrypt czyta `item 1 of argv` i `item 2 of argv`.
    public static func arguments(script: String = ScriptNotification.script,
                                 title: String,
                                 body: String) -> [String] {
        ["-e", script, "--", body, title]
    }
}
