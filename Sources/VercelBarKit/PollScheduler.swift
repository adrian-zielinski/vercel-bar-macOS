import Foundation

/// Dobór interwału odpytywania API.
public enum PollScheduler {
    /// 30 s w spoczynku, 10 s gdy jakikolwiek obserwowany deploy jest aktywny.
    public static func interval(anyActive: Bool) -> TimeInterval {
        anyActive ? 10 : 30
    }
}
