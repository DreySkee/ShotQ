import SwiftUI

@main
struct ShotQApp: App {
    @StateObject private var watcher = ClipboardWatcher(store: VaultStore())

    init() {
        UserDefaults.standard.register(defaults: [
            SettingsKeys.multiPaste: true,
            SettingsKeys.eraseAfterPaste: true,
            SettingsKeys.pasteDelaySeconds: 0.4,
        ])

        // Register as a login item once, on first launch. The menu toggle
        // remains the source of truth afterwards, so opting out sticks.
        let key = "didAttemptAutoLaunchRegistration"
        if !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
            try? LaunchAtLogin.set(true)
        }
    }

    var body: some Scene {
        MenuBarExtra("ShotQ", systemImage: "camera.viewfinder") {
            VaultMenuView()
                .environmentObject(watcher)
        }
        .menuBarExtraStyle(.window)
    }
}
