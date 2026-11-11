import AppKit
import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @State private var store = UsageStore()

    init() {
        // The bundled app hides its Dock icon via LSUIElement; this covers `swift run`.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: store.iconName)
                Text(store.labelText)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
