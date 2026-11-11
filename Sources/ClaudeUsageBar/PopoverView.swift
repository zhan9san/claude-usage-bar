import AppKit
import SwiftUI
import UsageCore

struct PopoverView: View {
    @Bindable var store: UsageStore
    @State private var showingSettings = false

    var body: some View {
        Group {
            if showingSettings {
                SettingsView(store: store) { showingSettings = false }
            } else {
                usage
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var usage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Claude Usage").font(.headline)
                Spacer()
                if let status = store.snapshot?.status, status != "allowed" {
                    StatusBadge(status: status)
                }
            }

            if let snapshot = store.snapshot {
                UsageRow(
                    title: "Session",
                    caption: "5-hour window",
                    window: snapshot.session,
                    now: store.now,
                    isBinding: snapshot.representativeClaim == "five_hour"
                )
                UsageRow(
                    title: "Weekly",
                    caption: "7-day window",
                    window: snapshot.weekly,
                    now: store.now,
                    isBinding: snapshot.representativeClaim == "seven_day"
                )
            } else if store.tokenSource == .none {
                Text("Add your setup-token in Settings to start.")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading…").foregroundStyle(.secondary)
                }
            }

            if let error = store.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(spacing: 12) {
                Text(updatedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh now")
                .disabled(store.isRefreshing || store.tokenSource == .none)

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit")
            }
            .buttonStyle(.borderless)
        }
    }

    private var updatedText: String {
        if store.isRefreshing { return "Refreshing…" }
        guard let fetchedAt = store.snapshot?.fetchedAt else { return "Not updated yet" }
        return "Updated \(UsageFormat.ago(fetchedAt, now: store.now))"
    }
}

private struct UsageRow: View {
    let title: String
    let caption: String
    let window: UsageWindow
    let now: Date
    let isBinding: Bool

    var body: some View {
        let utilization = window.utilization(at: now)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.medium))
                Text(caption).font(.caption).foregroundStyle(.secondary)
                if isBinding {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("This window is the one currently limiting you")
                }
                Spacer()
                Text("\(window.percent(at: now))%")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            ProgressView(value: min(max(utilization, 0), 1))
                .tint(color(for: utilization))
            Text(resetText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var resetText: String {
        guard let reset = window.upcomingReset(after: now) else {
            return window.resetsAt == nil ? "No reset time reported" : "Window reset; refresh for new data"
        }
        let format: Date.FormatStyle = reset.timeIntervalSince(now) < 86_400
            ? .dateTime.hour().minute()
            : .dateTime.weekday(.abbreviated).hour().minute()
        return "Resets in \(UsageFormat.countdown(to: reset, from: now)) · \(reset.formatted(format))"
    }

    private func color(for utilization: Double) -> Color {
        if utilization >= 0.95 { return .red }
        if utilization >= 0.8 { return .orange }
        return .accentColor
    }
}

private struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(status == "rejected" ? "Limited" : "Warning")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(status == "rejected" ? Color.red : Color.orange))
            .foregroundStyle(.white)
            .help("Limit status: \(status)")
    }
}
