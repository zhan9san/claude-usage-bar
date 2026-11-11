import SwiftUI
import UsageCore

struct SettingsView: View {
    @Bindable var store: UsageStore
    var onDone: () -> Void
    @State private var tokenInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Button(action: onDone) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .help("Back")
                Text("Settings").font(.headline)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Token").font(.subheadline.weight(.medium))
                Text(store.tokenSource.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("sk-ant-oat01-…", text: $tokenInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                HStack {
                    Button("Save", action: save)
                        .disabled(tokenInput.isEmpty)
                    Button("Remove", role: .destructive) {
                        store.removeToken()
                    }
                    .disabled(store.tokenSource != .keychain)
                }
                if let message = store.tokenMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Create one with `claude setup-token`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Probe model").font(.subheadline.weight(.medium))
                TextField(UsageClient.defaultModel, text: $store.model)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { store.commitModel() }
                Text("Must be a Haiku model. Press Return to apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Refresh every", selection: $store.refreshMinutes) {
                ForEach(UsageStore.refreshChoices, id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }

            Picker("Menu bar", selection: $store.labelStyle) {
                ForEach(LabelStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }

            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                )
            )
        }
    }

    private func save() {
        if store.saveToken(tokenInput) {
            tokenInput = ""
        }
    }
}
