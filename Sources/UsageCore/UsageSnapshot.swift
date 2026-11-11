import Foundation

/// One rate-limit window (the 5-hour session or the 7-day week).
public struct UsageWindow: Sendable, Equatable {
    /// Fraction of the window used, 0.0 to 1.0. Can exceed 1.0 when over the limit.
    public var utilization: Double
    public var resetsAt: Date?
    public var status: String?

    public init(utilization: Double, resetsAt: Date?, status: String? = nil) {
        self.utilization = utilization
        self.resetsAt = resetsAt
        self.status = status
    }

    /// Utilization as of `now`. A window whose reset time has passed has rolled
    /// over, so it reads as empty until the next fetch says otherwise.
    public func utilization(at now: Date) -> Double {
        if let resetsAt, resetsAt <= now { return 0 }
        return utilization
    }

    public func percent(at now: Date) -> Int {
        Int((utilization(at: now) * 100).rounded())
    }

    /// The reset time, if it is still in the future.
    public func upcomingReset(after now: Date) -> Date? {
        guard let resetsAt, resetsAt > now else { return nil }
        return resetsAt
    }
}

public struct UsageSnapshot: Sendable, Equatable {
    public var session: UsageWindow
    public var weekly: UsageWindow
    /// Overall limit status: `allowed`, `allowed_warning` or `rejected`.
    public var status: String?
    /// Which window is currently binding, e.g. `five_hour` or `seven_day`.
    public var representativeClaim: String?
    public var fetchedAt: Date

    public init(
        session: UsageWindow,
        weekly: UsageWindow,
        status: String?,
        representativeClaim: String?,
        fetchedAt: Date
    ) {
        self.session = session
        self.weekly = weekly
        self.status = status
        self.representativeClaim = representativeClaim
        self.fetchedAt = fetchedAt
    }

    public func peakUtilization(at now: Date) -> Double {
        max(session.utilization(at: now), weekly.utilization(at: now))
    }
}
