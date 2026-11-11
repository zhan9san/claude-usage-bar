import Foundation

public enum TokenValidator {
    /// `claude setup-token` issues OAuth tokens that start with `sk-ant-oat`.
    /// API keys (`sk-ant-api…`) do not return subscription usage headers.
    public static let requiredPrefix = "sk-ant-oat"

    /// Returns the trimmed token, or nil when it does not look like a setup token.
    public static func normalize(_ raw: String) -> String? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.hasPrefix(requiredPrefix),
              token.count > requiredPrefix.count + 10,
              !token.contains(where: \.isWhitespace)
        else { return nil }
        return token
    }
}
