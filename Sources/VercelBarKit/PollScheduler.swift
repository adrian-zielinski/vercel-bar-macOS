import Foundation

/// Dobór interwału odpytywania API.
public enum PollScheduler {
    /// 10 s zawsze: start 🚀 ma dojść w jednym cyklu, a po tanim pulsie
    /// różnica 10 vs 30 s nie broni baterii. `anyActive` zostaje w sygnaturze,
    /// backoff i tak nadpisuje bazę przy 429/5xx.
    public static func interval(anyActive: Bool) -> TimeInterval {
        _ = anyActive
        return 10
    }

    /// Opóźnienie kolejnego odpytania z wykładniczym backoffem po 429/5xx:
    /// 0 porażek → base; n porażek → min(300, 30·2^n). Backoff świadomie ignoruje base.
    public static func delay(base: TimeInterval, consecutiveFailures: Int) -> TimeInterval {
        guard consecutiveFailures > 0 else { return base }
        return min(300, 30 * pow(2, Double(consecutiveFailures)))
    }
}
