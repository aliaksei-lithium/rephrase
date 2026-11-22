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
        #if DEBUG
        DemoMode.runIfRequested(app: model)
        #endif
    }

    var body: some Scene {
        MenuBarExtra("Rephrase", systemImage: "wand.and.sparkles") {
            MenuContent(rewriter: rewriter)
                .environment(model)
        }

        Window("Welcome to Rephrase", id: Onboarding.windowID) {
            OnboardingView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(Onboarding.shouldShowAtLaunch ? .presented : .suppressed)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

private struct MenuContent: View {
    let rewriter: RewriteController
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.statusText)

        if !AXIsProcessTrusted() {
            Button("Allow Accessibility Access…", action: Onboarding.openAccessibilitySettings)
        }

        Divider()

        Button("Rewrite Clipboard") {
            rewriter.rewriteClipboard()
        }

        if model.canTranslate {
            Button("Translate Clipboard") {
                Task { await rewriter.translateClipboard() }
            }
        }

        Divider()

        Button("Setup Guide…") {
            NSApp.activate()
            openWindow(id: Onboarding.windowID)
        }

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
