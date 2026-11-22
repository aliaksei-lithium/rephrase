import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings()
            }
            Tab("Shortcuts", systemImage: "keyboard") {
                ShortcutSettings()
            }
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var password = ""
    @State private var server = ""

    var body: some View {
        @Bindable var model = model

        Form {
            Section("Account") {
                TextField("Server", text: $server)
                    .textContentType(.URL)
                    .onSubmit(applyServer)

                switch model.auth {
                case .signedIn(_, demo: true):
                    LabeledContent("Status") {
                        HStack {
                            Text("Demo: Gemma only, limited per day")
                            Spacer()
                            Button("Leave Demo") { model.signOut() }
                        }
                    }
                    passwordFields
                case .signedIn(let expiresAt, _):
                    LabeledContent("Status") {
                        HStack {
                            Text(expiresAt.map { "Signed in until \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Signed in")
                            Spacer()
                            Button("Sign Out", role: .destructive) { model.signOut() }
                        }
                    }
                case .signedOut, .unknown:
                    passwordFields
                    if model.demoAvailable == true {
                        LabeledContent("No password?") {
                            Button("Try the Demo") { Task { await model.startDemo() } }
                                .disabled(model.isBusy)
                        }
                    }
                }

                if let error = model.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            Section("App") {
                LaunchAtLoginToggle()
            }

            Section("Defaults") {
                if let catalog = model.catalog {
                    Picker("Model", selection: Binding(
                        get: { model.effectiveModel ?? "" },
                        set: { model.options.model = $0 }
                    )) {
                        ForEach(catalog.models) { item in
                            Text(item.hint.map { "\(item.title) (\($0))" } ?? item.title).tag(item.id)
                        }
                    }
                    Picker("Mode", selection: $model.options.mode) {
                        ForEach(catalog.modes, id: \.self) { Text(Labels.mode($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Style", selection: $model.options.style) {
                        ForEach(catalog.styles, id: \.self) { Text(Labels.style($0)).tag($0) }
                    }
                    Picker("Tone", selection: $model.options.tone) {
                        ForEach(catalog.tones, id: \.self) { Text(Labels.tone($0)).tag($0) }
                    }
                    Picker("Language", selection: $model.options.language) {
                        ForEach(catalog.languages, id: \.self) { Text(Labels.language($0)).tag($0) }
                    }
                } else {
                    Text("Sign in to load models and options.")
                        .foregroundStyle(.secondary)
                }
            }

            if model.canTranslate {
                TranslateSettings()
            }
        }
        .formStyle(.grouped)
        .onAppear { server = model.serverURL }
    }

    @ViewBuilder private var passwordFields: some View {
        SecureField("Password", text: $password)
            .onSubmit(signIn)
        LabeledContent("") {
            Button("Sign In", action: signIn)
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty || model.isBusy)
        }
    }

    private func applyServer() {
        let trimmed = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != model.serverURL else { return }
        model.serverURL = trimmed.isEmpty ? AppModel.defaultServer : trimmed
        server = model.serverURL
        Task { await model.refresh() }
    }

    private func signIn() {
        applyServer()
        let candidate = password
        Task {
            await model.signIn(password: candidate)
            if case .signedIn(_, demo: false) = model.auth { password = "" }
        }
    }
}

private struct ShortcutSettings: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Rewrite in popup", name: .rewriteWithPopup)
                KeyboardShortcuts.Recorder("Rewrite and replace", name: .rewriteInPlace)
                KeyboardShortcuts.Recorder("Translate", name: .translate)
            } footer: {
                Text("macOS does not allow global shortcuts that use only Option or Option-Shift.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// ⌃⌥Z defaults. Shown only when the server has a Google Translate key.
private struct TranslateSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let languages = model.translateLanguages

        Section {
            Picker("Translate to", selection: $model.translateOptions.target) {
                missingTag(model.translateOptions.target, in: languages)
                ForEach(languages) { Text($0.name).tag($0.code) }
            }
            Picker("If already in that language", selection: $model.translateOptions.alternate) {
                Text("Leave it").tag(String?.none)
                if let alternate = model.translateOptions.alternate, !languages.contains(where: { $0.code == alternate }) {
                    Text(Self.name(alternate)).tag(String?.some(alternate))
                }
                ForEach(languages.filter { $0.code != model.translateOptions.target }) {
                    Text("Translate to \($0.name)").tag(String?.some($0.code))
                }
            }
        } header: {
            Text("Translate")
        } footer: {
            Text("The source language is detected. Uses Google Translate on the server.")
                .foregroundStyle(.secondary)
        }
        .task { await model.loadTranslateLanguages() }
    }

    @ViewBuilder private func missingTag(_ code: String, in languages: [TranslateLanguage]) -> some View {
        if !languages.contains(where: { $0.code == code }) {
            Text(Self.name(code)).tag(code)
        }
    }

    private static func name(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }
}
