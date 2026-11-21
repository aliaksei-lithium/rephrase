import SwiftUI

@main
struct RephraseApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Rephrase", systemImage: "wand.and.sparkles") {
            MenuContent()
                .environment(model)
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

private struct MenuContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(model.statusText)

        Divider()

        Button("Settings…") {
            // A menu bar app is never active on its own, so the window would open behind others.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        Button("Quit Rephrase") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
