import Foundation

/// Dobór interwału odpytywania API.
public enum PollScheduler {
    /// 30 s w spoczynku, 10 s gdy jakikolwiek obserwowany deploy jest aktywny.
    public static func interval(anyActive: Bool) -> TimeInterval {
        anyActive ? 10 : 30
    }

    /// Opóźnienie kolejnego odpytania z wykładniczym backoffem po 429/5xx:
    /// 0 porażek → base; n porażek → min(300, 30·2^n). Backoff świadomie ignoruje base.
    public static func delay(base: TimeInterval, consecutiveFailures: Int) -> TimeInterval {
        guard consecutiveFailures > 0 else { return base }
        return min(300, 30 * pow(2, Double(consecutiveFailures)))
    }
}
