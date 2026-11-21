import SwiftUI

@main
struct RephraseApp: App {
    @State private var model: AppModel
    private let rewriter: RewriteController

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        rewriter = RewriteController(app: model)
        rewriter.registerHotkeys()
    }

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

        if !AXIsProcessTrusted() {
            Button("Allow Accessibility Access…") {
                SelectionReader.requestTrust()
            }
        }

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
