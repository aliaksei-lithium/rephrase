import KeyboardShortcuts
import ServiceManagement
import SwiftUI

enum Onboarding {
    static let windowID = "onboarding"
    private static let doneKey = "onboardingDone"

    /// Show the guide until it was finished once, and again whenever Accessibility access is missing
    /// (ad-hoc builds lose it on every rebuild).
    static var shouldShowAtLaunch: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["REPHRASE_DEMO_TEXT"] != nil { return false }
        #endif
        return !UserDefaults.standard.bool(forKey: doneKey) || !AXIsProcessTrusted()
    }

    static func markDone() {
        UserDefaults.standard.set(true, forKey: doneKey)
    }

    static func openAccessibilitySettings() {
        SelectionReader.requestTrust()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var trusted = AXIsProcessTrusted()

    private var signedIn: Bool {
        if case .signedIn = model.auth { true } else { false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "wand.and.sparkles")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Rephrase").font(.title2.bold())
                    Text("Rewrite selected text in any app without leaving it.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                StepRow(
                    number: 1,
                    title: model.isDemo ? "Trying the demo" : "Sign in",
                    detail: model.isDemo
                        ? "The demo uses the free Gemma model with a daily limit. Sign in with the password in Settings for Claude."
                        : "Use the Rephrase app password, or try the demo with the free Gemma model.",
                    done: signedIn
                ) {
                    HStack {
                        if model.demoAvailable == true {
                            Button("Try Demo") { Task { await model.startDemo() } }
                                .disabled(model.isBusy)
                        }
                        Button("Open Settings") {
                            NSApp.activate()
                            openSettings()
                        }
                    }
                }
                StepRow(
                    number: 2,
                    title: "Allow Accessibility access",
                    detail: "Lets Rephrase read the selected text and paste the result when you press a shortcut. It never watches what you type.",
                    done: trusted
                ) {
                    Button("Allow…", action: Onboarding.openAccessibilitySettings)
                }
                if !trusted {
                    Text("Already on in System Settings but not working? Remove Rephrase with − and add it again. A rebuilt app counts as a new app until it is signed with your Apple Development certificate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 38)
                }
                StepRow(number: 3, title: "Select text anywhere and press", detail: nil, done: false) {
                    EmptyView()
                }
                VStack(alignment: .leading, spacing: 6) {
                    ShortcutLine(name: .rewriteWithPopup, text: "rewrite in a popup")
                    ShortcutLine(name: .rewriteInPlace, text: "rewrite and replace with your defaults")
                }
                .padding(.leading, 38)
            }

            HStack {
                Text("Shortcuts can be changed in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    Onboarding.markDone()
                    dismissWindow(id: Onboarding.windowID)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 500)
        .onAppear { NSApp.activate() }
        .task {
            // The permission is granted in System Settings; reflect it as soon as it changes.
            while !Task.isCancelled {
                trusted = AXIsProcessTrusted()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private struct StepRow<Action: View>: View {
    let number: Int
    let title: String
    let detail: String?
    let done: Bool
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.secondary.opacity(0.2))
                if done {
                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.caption.bold())
                }
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            if !done { action() }
        }
    }
}

private struct ShortcutLine: View {
    let name: KeyboardShortcuts.Name
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Text(KeyboardShortcuts.getShortcut(for: name)?.description ?? "Not set")
                .font(.body.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: .rect(cornerRadius: 6))
            Text(text).foregroundStyle(.secondary)
        }
    }
}

/// Settings toggle backed by SMAppService.
struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    var body: some View {
        Toggle("Open at login", isOn: Binding(
            get: { enabled },
            set: { newValue in
                do {
                    if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    error = nil
                } catch {
                    self.error = error.localizedDescription
                }
                enabled = SMAppService.mainApp.status == .enabled
            }
        ))
        if let error {
            Text(error).font(.callout).foregroundStyle(.red)
        }
    }
}
