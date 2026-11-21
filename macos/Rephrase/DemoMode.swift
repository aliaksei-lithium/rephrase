#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only: renders the real popup, with a live rewrite, over a sample document for
/// README screenshots.
///
///     REPHRASE_DEMO_TEXT="..." REPHRASE_DEMO_PASSWORD=... [REPHRASE_DEMO_MODEL=...] \
///         Rephrase.app/Contents/MacOS/Rephrase -serverURL http://localhost:8788
///
/// The demo window sits behind every other window and ignores the mouse, so it never gets in
/// the way. When the rewrite is done it prints `DEMO_READY <window id>` for
/// `screencapture -l <window id>`, which captures a window even when it is covered.
/// The process quits on its own after three minutes.
enum DemoMode {
    private static var window: NSWindow?

    static func runIfRequested(app: AppModel) {
        let env = ProcessInfo.processInfo.environment
        guard let text = env["REPHRASE_DEMO_TEXT"] else { return }
        Task {
            try? await Task.sleep(for: .seconds(180))
            NSApp.terminate(nil)
        }
        Task {
            if let password = env["REPHRASE_DEMO_PASSWORD"] {
                await app.signIn(password: password)
            }
            guard case .signedIn = app.auth else {
                print("DEMO_FAILED \(app.lastError ?? "not signed in")")
                fflush(stdout)
                return
            }
            let model = PopupModel(
                original: text,
                options: app.options,
                model: env["REPHRASE_DEMO_MODEL"] ?? app.effectiveModel,
                catalog: app.catalog,
                makeClient: { [app] in try app.client() }
            )
            model.onReplace = { _ in }
            showWindow(text: text, model: model)
            model.run()
            while model.phase == .streaming {
                try? await Task.sleep(for: .milliseconds(200))
            }
            try? await Task.sleep(for: .seconds(1))
            print("DEMO_READY \(window?.windowNumber ?? 0)")
            fflush(stdout)
        }
    }

    private static func showWindow(text: String, model: PopupModel) {
        let size = CGSize(width: 980, height: 620)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let frame = CGRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .transient]
        window.contentView = NSHostingView(rootView: DemoScene(text: text, model: model))
        window.orderBack(nil)
        self.window = window
    }
}

/// A plain document on a soft background, the sample text selected, and the popup below it.
private struct DemoScene: View {
    let text: String
    let model: PopupModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.80, green: 0.87, blue: 0.98), Color(red: 0.93, green: 0.88, blue: 0.97)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            document
                .padding(.leading, 80)
                .padding(.top, 50)
            PopupView(model: model)
                .shadow(color: .black.opacity(0.22), radius: 28, y: 12)
                .padding(.leading, 150)
                .padding(.top, 236)
        }
        .frame(width: 980, height: 620)
        .environment(\.colorScheme, .light)
    }

    private var document: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.85)).frame(width: 12, height: 12) }
                Spacer()
                Text("Status update").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Color.clear.frame(width: 52)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                Text(text)
                    .font(.system(size: 17))
                    .padding(.horizontal, 2)
                    .background(Color.accentColor.opacity(0.28), in: .rect(cornerRadius: 3))
                Text("Next week we start on the onboarding flow. Design is ready and the backend work is planned for Wednesday.")
                    .font(.system(size: 17))
                    .foregroundStyle(.primary.opacity(0.85))
            }
            .lineSpacing(5)
            .padding(.horizontal, 40)
            .padding(.top, 34)
            Spacer()
        }
        .frame(width: 820, height: 520)
        .background(.white, in: .rect(cornerRadius: 14))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
    }
}
#endif
