import Foundation

/// Reads the `anthropic-ratelimit-unified-*` headers that the Messages API
/// returns for subscription (OAuth) traffic.
public enum RateLimitParser {
    static let prefix = "anthropic-ratelimit-unified-"

    /// Returns nil when the response carries neither the 5h nor the 7d utilization.
    public static func parse(headers: [String: String], now: Date = Date()) -> UsageSnapshot? {
        var lowercased: [String: String] = [:]
        for (key, value) in headers {
            lowercased[key.lowercased()] = value.trimmingCharacters(in: .whitespaces)
        }

        func string(_ name: String) -> String? {
            guard let value = lowercased[prefix + name], !value.isEmpty else { return nil }
            return value
        }
        func double(_ name: String) -> Double? {
            string(name).flatMap(Double.init)
        }
        func date(_ name: String) -> Date? {
            guard let seconds = double(name), seconds > 0 else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }

        let sessionUtilization = double("5h-utilization")
        let weeklyUtilization = double("7d-utilization")
        guard sessionUtilization != nil || weeklyUtilization != nil else { return nil }

        return UsageSnapshot(
            session: UsageWindow(
                utilization: sessionUtilization ?? 0,
                resetsAt: date("5h-reset"),
                status: string("5h-status")
            ),
            weekly: UsageWindow(
                utilization: weeklyUtilization ?? 0,
                resetsAt: date("7d-reset"),
                status: string("7d-status")
            ),
            status: string("status"),
            representativeClaim: string("representative-claim"),
            fetchedAt: now
        )
    }

    public static func headers(from response: HTTPURLResponse) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let key = key as? String {
                result[key] = "\(value)"
            }
        }
        return result
    }
}
