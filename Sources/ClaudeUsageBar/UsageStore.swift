import AppKit
import Foundation
import Observation
import ServiceManagement
import UsageCore

enum LabelStyle: String, CaseIterable, Identifiable {
    case full, compact, sessionOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: "5h 4% · 7d 24%"
        case .compact: "4% · 24%"
        case .sessionOnly: "4%"
        }
    }
}

enum TokenSource: Equatable {
    case keychain, environment, none

    var description: String {
        switch self {
        case .keychain: "Using the token saved in Keychain."
        case .environment: "Using CLAUDE_CODE_OAUTH_TOKEN from the environment."
        case .none: "No token configured."
        }
    }
}

@MainActor
@Observable
final class UsageStore {
    static let refreshChoices = [1, 5, 10, 15, 30]

    private(set) var snapshot: UsageSnapshot?
    private(set) var lastError: String?
    private(set) var isRefreshing = false
    private(set) var tokenSource: TokenSource = .none
    private(set) var tokenMessage: String?
    private(set) var launchAtLogin = false
    /// Ticks every minute so countdowns and expired windows update between fetches.
    private(set) var now = Date()

    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Keys.model) }
    }

    var refreshMinutes: Int {
        didSet {
            UserDefaults.standard.set(refreshMinutes, forKey: Keys.refreshMinutes)
            restartPolling()
        }
    }

    var labelStyle: LabelStyle {
        didSet { UserDefaults.standard.set(labelStyle.rawValue, forKey: Keys.labelStyle) }
    }

    @ObservationIgnored private let keychain = KeychainStore(
        service: "dev.local.claude-usage-bar",
        account: "oauth-token"
    )
    @ObservationIgnored private let client = UsageClient()
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var generation = 0

    private enum Keys {
        static let model = "probeModel"
        static let refreshMinutes = "refreshMinutes"
        static let labelStyle = "labelStyle"
    }

    init() {
        let defaults = UserDefaults.standard
        model = defaults.string(forKey: Keys.model) ?? UsageClient.defaultModel
        let minutes = defaults.integer(forKey: Keys.refreshMinutes)
        refreshMinutes = Self.refreshChoices.contains(minutes) ? minutes : 5
        labelStyle = defaults.string(forKey: Keys.labelStyle).flatMap(LabelStyle.init) ?? .full
        launchAtLogin = SMAppService.mainApp.status == .enabled

        loadToken()
        observeWake()
        startClock()
        restartPolling()
    }

    // MARK: - Menu bar label

    var labelText: String {
        guard let snapshot else { return tokenSource == .none ? "Set token" : "—" }
        let session = snapshot.session.percent(at: now)
        let weekly = snapshot.weekly.percent(at: now)
        switch labelStyle {
        case .full: return "5h \(session)% · 7d \(weekly)%"
        case .compact: return "\(session)% · \(weekly)%"
        case .sessionOnly: return "\(session)%"
        }
    }

    var iconName: String {
        if tokenSource == .none { return "exclamationmark.triangle" }
        guard let snapshot else { return "gauge.with.dots.needle.0percent" }
        let peak = snapshot.peakUtilization(at: now)
        if peak >= 0.8 { return "gauge.with.dots.needle.100percent" }
        if peak >= 0.5 { return "gauge.with.dots.needle.67percent" }
        return "gauge.with.dots.needle.33percent"
    }

    // MARK: - Refresh

    func refresh() async {
        generation += 1
        let current = generation
        isRefreshing = true
        defer {
            if current == generation { isRefreshing = false }
        }

        guard let token else {
            snapshot = nil
            lastError = nil
            return
        }

        do {
            let result = try await client.fetch(token: token, model: model)
            guard current == generation else { return }
            snapshot = result
            lastError = nil
        } catch is CancellationError {
            return
        } catch {
            guard current == generation else { return }
            lastError = error.localizedDescription
        }
    }

    /// Cancels the current schedule and starts a new one that fetches right away.
    func restartPolling(initialDelay: TimeInterval = 0) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            if initialDelay > 0 {
                try? await Task.sleep(for: .seconds(initialDelay))
            }
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval = TimeInterval(self.refreshMinutes * 60)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func startClock() {
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.now = Date()
            }
        }
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.now = Date()
                // Give Wi-Fi a moment to reconnect before fetching.
                self?.restartPolling(initialDelay: 5)
            }
        }
    }

    // MARK: - Token

    private func loadToken() {
        if let saved = keychain.read(), let valid = TokenValidator.normalize(saved) {
            token = valid
            tokenSource = .keychain
        } else if let env = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"],
                  let valid = TokenValidator.normalize(env) {
            token = valid
            tokenSource = .environment
        } else {
            token = nil
            tokenSource = .none
        }
    }

    /// Returns true when the token was valid and saved.
    @discardableResult
    func saveToken(_ raw: String) -> Bool {
        guard let valid = TokenValidator.normalize(raw) else {
            tokenMessage = "That doesn't look like a setup-token (sk-ant-oat…)."
            return false
        }
        do {
            try keychain.save(valid)
        } catch {
            tokenMessage = error.localizedDescription
            return false
        }
        tokenMessage = "Token saved."
        loadToken()
        restartPolling()
        return true
    }

    func removeToken() {
        do {
            try keychain.delete()
            tokenMessage = "Token removed."
        } catch {
            tokenMessage = error.localizedDescription
        }
        loadToken()
        restartPolling()
    }

    // MARK: - Settings

    func commitModel() {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        model = trimmed.isEmpty ? UsageClient.defaultModel : trimmed
        restartPolling()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            tokenMessage = nil
        } catch {
            tokenMessage = "Launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
