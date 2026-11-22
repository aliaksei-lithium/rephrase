import KeyboardShortcuts
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

        // The menu closes before the action runs and Rephrase never activates,
        // so the app behind it keeps its selection, just like with the shortcut.
        Button("Rewrite Selection…") {
            Task { await rewriter.showPopup() }
        }
        .globalKeyboardShortcut(.rewriteWithPopup)

        Button("Rewrite and Replace") {
            Task { await rewriter.rewriteInPlace() }
        }
        .globalKeyboardShortcut(.rewriteInPlace)

        if model.canTranslate {
            Button("Translate Selection…") {
                Task { await rewriter.translate() }
            }
            .globalKeyboardShortcut(.translate)
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

        if case .signedIn = model.auth {
            Button(model.isDemo ? "Leave Demo" : "Sign Out") {
                model.signOut()
            }
        }

        Divider()

        Text("Version \(AppInfo.version)")

        Button("Quit Rephrase") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

enum AppInfo {
    /// "0.2.0 (2)": CFBundleShortVersionString and CFBundleVersion.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }
}

