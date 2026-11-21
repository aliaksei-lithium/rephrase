import SwiftUI

struct PopupView: View {
    @Bindable var model: PopupModel
    @State private var textHeight: CGFloat = 0

    private static let maxTextHeight: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
            if model.catalog != nil {
                controls
            }
            footer
        }
        .padding(16)
        .frame(width: 440)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(1)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "wand.and.sparkles")
                .foregroundStyle(.tint)
            Text("Rephrase")
                .font(.headline)
            Spacer()
            if let label = model.modelLabel {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Close", systemImage: "xmark", action: model.close)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("Close (Esc)")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .failed(let message) where model.result.isEmpty:
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        default:
            ScrollView {
                Text(model.highlighted ?? AttributedString(model.result.isEmpty ? " " : model.result))
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(textHeight, 18), Self.maxTextHeight))
            .overlay(alignment: .topLeading) {
                if model.phase == .streaming && model.result.isEmpty {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Picker("Mode", selection: rerunBinding(\.mode)) {
                ForEach(model.catalog?.modes ?? [], id: \.self) { Text(Labels.mode($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer(minLength: 0)
            optionMenu("Style", \.style, model.catalog?.styles ?? [], Labels.style)
            optionMenu("Tone", \.tone, model.catalog?.tones ?? [], Labels.tone)
            optionMenu("Language", \.language, model.catalog?.languages ?? [], Labels.language) { id in
                id == "auto" ? "Auto" : id.uppercased()
            }
        }
        .controlSize(.small)
    }

    /// A compact menu whose button shows the option name until a value other than "keep" is picked.
    private func optionMenu(
        _ title: String,
        _ key: WritableKeyPath<RephraseOptions, String>,
        _ ids: [String],
        _ label: @escaping (String) -> String,
        short: ((String) -> String)? = nil
    ) -> some View {
        let value = model.options[keyPath: key]
        return Menu {
            Picker(title, selection: rerunBinding(key)) {
                ForEach(ids, id: \.self) { Text(label($0)).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Text(short?(value) ?? (value == "keep" ? title : label(value)))
        }
        .menuStyle(.button)
        .fixedSize()
        .help(title)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let note = model.note {
                Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else if model.isUnchanged {
                Text("Already looks good").font(.caption).foregroundStyle(.secondary)
            } else if let reason = model.copyOnlyReason, model.phase == .done {
                Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            } else if case .failed(let message) = model.phase, !model.result.isEmpty {
                Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
            }
            Spacer()
            if model.catalog != nil {
                Button("Retry", action: model.run)
                    .keyboardShortcut("r")
                    .disabled(model.phase == .streaming)
                Button("Copy", action: model.copy)
                    .keyboardShortcut("c")
                    .disabled(model.result.isEmpty)
                if model.copyOnlyReason == nil {
                    Button("Replace", action: model.replace)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.glassProminent)
                        .disabled(!model.canReplace)
                }
            }
        }
        .controlSize(.regular)
    }

    /// Changing an option re-runs the request with it.
    private func rerunBinding(_ key: WritableKeyPath<RephraseOptions, String>) -> Binding<String> {
        Binding(
            get: { model.options[keyPath: key] },
            set: { value in
                guard model.options[keyPath: key] != value else { return }
                model.options[keyPath: key] = value
                model.run()
            }
        )
    }
}
