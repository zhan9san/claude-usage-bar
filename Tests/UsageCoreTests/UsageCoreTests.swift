import Foundation
import Testing
@testable import UsageCore

private let now = Date(timeIntervalSince1970: 1_794_370_000)

/// Headers captured from a real Haiku probe on 2026-11-11.
private let realHeaders = [
    "anthropic-ratelimit-unified-5h-status": "allowed",
    "anthropic-ratelimit-unified-representative-claim": "five_hour",
    "anthropic-ratelimit-unified-overage-status": "rejected",
    "anthropic-ratelimit-unified-reset": "1794378600",
    "anthropic-ratelimit-unified-5h-utilization": "0.04",
    "anthropic-ratelimit-unified-7d-reset": "1794466800",
    "anthropic-ratelimit-unified-5h-reset": "1794378600",
    "anthropic-ratelimit-unified-7d-status": "allowed",
    "anthropic-ratelimit-unified-fallback-percentage": "0.5",
    "anthropic-ratelimit-unified-7d-utilization": "0.24",
    "anthropic-ratelimit-unified-status": "allowed",
]

@Suite struct RateLimitParserTests {
    @Test func parsesRealHeaders() throws {
        let snapshot = try #require(RateLimitParser.parse(headers: realHeaders, now: now))
        #expect(snapshot.session.percent(at: now) == 4)
        #expect(snapshot.weekly.percent(at: now) == 24)
        #expect(snapshot.session.resetsAt == Date(timeIntervalSince1970: 1_794_378_600))
        #expect(snapshot.weekly.resetsAt == Date(timeIntervalSince1970: 1_794_466_800))
        #expect(snapshot.session.status == "allowed")
        #expect(snapshot.status == "allowed")
        #expect(snapshot.representativeClaim == "five_hour")
        #expect(snapshot.fetchedAt == now)
    }

    @Test func headerNamesAreCaseInsensitive() throws {
        let headers = [
            "Anthropic-Ratelimit-Unified-5h-Utilization": "0.5",
            "ANTHROPIC-RATELIMIT-UNIFIED-7D-UTILIZATION": " 0.75 ",
        ]
        let snapshot = try #require(RateLimitParser.parse(headers: headers, now: now))
        #expect(snapshot.session.percent(at: now) == 50)
        #expect(snapshot.weekly.percent(at: now) == 75)
        #expect(snapshot.session.resetsAt == nil)
    }

    @Test func returnsNilWithoutUtilizationHeaders() {
        #expect(RateLimitParser.parse(headers: [:], now: now) == nil)
        #expect(RateLimitParser.parse(
            headers: ["anthropic-ratelimit-unified-status": "allowed"],
            now: now
        ) == nil)
    }

    @Test func ignoresUnparseableValues() throws {
        let headers = [
            "anthropic-ratelimit-unified-5h-utilization": "abc",
            "anthropic-ratelimit-unified-7d-utilization": "0.1",
            "anthropic-ratelimit-unified-7d-reset": "0",
        ]
        let snapshot = try #require(RateLimitParser.parse(headers: headers, now: now))
        #expect(snapshot.session.utilization == 0)
        #expect(snapshot.weekly.percent(at: now) == 10)
        #expect(snapshot.weekly.resetsAt == nil)
    }
}

@Suite struct UsageWindowTests {
    @Test func expiredWindowReadsAsZero() {
        let window = UsageWindow(utilization: 0.6, resetsAt: now.addingTimeInterval(-1))
        #expect(window.utilization(at: now) == 0)
        #expect(window.percent(at: now) == 0)
        #expect(window.upcomingReset(after: now) == nil)
    }

    @Test func activeWindowKeepsValue() {
        let reset = now.addingTimeInterval(600)
        let window = UsageWindow(utilization: 0.255, resetsAt: reset)
        #expect(window.percent(at: now) == 26)
        #expect(window.upcomingReset(after: now) == reset)
    }

    @Test func peakUsesTheHigherWindow() {
        let snapshot = UsageSnapshot(
            session: UsageWindow(utilization: 0.9, resetsAt: now.addingTimeInterval(-5)),
            weekly: UsageWindow(utilization: 0.3, resetsAt: nil),
            status: nil,
            representativeClaim: nil,
            fetchedAt: now
        )
        #expect(snapshot.peakUtilization(at: now) == 0.3)
    }
}

@Suite struct InterpretTests {
    private func body(_ message: String) -> Data {
        Data(#"{"type":"error","error":{"type":"x","message":"\#(message)"}}"#.utf8)
    }

    @Test func successWithHeaders() throws {
        let snapshot = try UsageClient.interpret(statusCode: 200, headers: realHeaders, body: Data(), now: now)
        #expect(snapshot.weekly.percent(at: now) == 24)
    }

    @Test func successWithoutHeaders() {
        #expect(throws: UsageError.noUsageHeaders) {
            try UsageClient.interpret(statusCode: 200, headers: [:], body: Data(), now: now)
        }
    }

    @Test func rateLimitedWithHeadersStillReportsUsage() throws {
        let snapshot = try UsageClient.interpret(statusCode: 429, headers: realHeaders, body: Data(), now: now)
        #expect(snapshot.session.percent(at: now) == 4)
    }

    @Test func rateLimitedWithoutHeaders() {
        #expect(throws: UsageError.rejectedWithoutUsage) {
            try UsageClient.interpret(statusCode: 429, headers: [:], body: body("Error"), now: now)
        }
    }

    @Test func unauthorizedCarriesApiMessage() {
        #expect(throws: UsageError.unauthorized(status: 401, message: "invalid token")) {
            try UsageClient.interpret(statusCode: 401, headers: [:], body: body("invalid token"), now: now)
        }
    }

    @Test func badModel() {
        #expect(throws: UsageError.badRequest(status: 404, message: "model: nope")) {
            try UsageClient.interpret(statusCode: 404, headers: [:], body: body("model: nope"), now: now)
        }
    }

    @Test func serverErrorWithoutJSON() {
        #expect(throws: UsageError.server(status: 529, message: nil)) {
            try UsageClient.interpret(statusCode: 529, headers: [:], body: Data("oops".utf8), now: now)
        }
    }
}

@Suite struct RequestTests {
    @Test func buildsMinimalProbe() throws {
        let request = try UsageClient.makeRequest(token: "sk-ant-oat01-abc", model: "claude-haiku-4-5-20251001")
        #expect(request.url == UsageClient.endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-ant-oat01-abc")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")

        let data = try #require(request.httpBody)
        let body = try JSONDecoder().decode(ProbeBody.self, from: data)
        #expect(body == ProbeBody(
            model: "claude-haiku-4-5-20251001",
            maxTokens: 1,
            messages: [.init(role: "user", content: "hi")]
        ))
        #expect(String(decoding: data, as: UTF8.self).contains(#""max_tokens":1"#))
    }
}

@Suite struct TokenValidatorTests {
    @Test func acceptsAndTrimsSetupToken() {
        #expect(TokenValidator.normalize("  sk-ant-oat01-abcdefghijkl\n") == "sk-ant-oat01-abcdefghijkl")
    }

    @Test func rejectsOtherValues() {
        #expect(TokenValidator.normalize("") == nil)
        #expect(TokenValidator.normalize("sk-ant-api03-abcdefghijkl") == nil)
        #expect(TokenValidator.normalize("sk-ant-sid01-abcdefghijkl") == nil)
        #expect(TokenValidator.normalize("sk-ant-oat01") == nil)
        #expect(TokenValidator.normalize("sk-ant-oat01-abc defghijkl") == nil)
    }
}

@Suite struct UsageFormatTests {
    @Test(arguments: [
        (0, "now"),
        (-30, "now"),
        (30, "<1m"),
        (9 * 60 + 5, "9m"),
        (2 * 3_600 + 14 * 60, "2h 14m"),
        (3 * 86_400 + 4 * 3_600 + 59, "3d 4h"),
    ])
    func countdown(seconds: Int, expected: String) {
        #expect(UsageFormat.countdown(to: now.addingTimeInterval(TimeInterval(seconds)), from: now) == expected)
    }

    @Test(arguments: [
        (10, "just now"),
        (4 * 60, "4m ago"),
        (2 * 3_600 + 10, "2h ago"),
        (2 * 86_400, "2d ago"),
    ])
    func ago(seconds: Int, expected: String) {
        #expect(UsageFormat.ago(now.addingTimeInterval(TimeInterval(-seconds)), now: now) == expected)
    }
}
