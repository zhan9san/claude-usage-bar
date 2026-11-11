import Foundation

public enum UsageError: Error, Equatable, LocalizedError {
    case missingToken
    case unauthorized(status: Int, message: String?)
    case badRequest(status: Int, message: String?)
    case rejectedWithoutUsage
    case noUsageHeaders
    case server(status: Int, message: String?)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "No token. Add your setup-token in Settings."
        case let .unauthorized(status, message):
            return "Token rejected (\(status))\(Self.detail(message)). "
                + "Create a new one with `claude setup-token`."
        case let .badRequest(status, message):
            return "Request rejected (\(status))\(Self.detail(message)). "
                + "Check the probe model in Settings."
        case .rejectedWithoutUsage:
            return "Rejected (429) without usage data. Use a Haiku probe model."
        case .noUsageHeaders:
            return "The response had no usage headers."
        case let .server(status, message):
            return "Server error (\(status))\(Self.detail(message))."
        case let .network(message):
            return message
        }
    }

    private static func detail(_ message: String?) -> String {
        guard let message, !message.isEmpty else { return "" }
        return ": \(message)"
    }
}
