import SwiftUI

struct TranslateView: View {
    @Bindable var model: TranslateModel
    @State private var textHeight: CGFloat = 0

    private static let maxTextHeight: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
            footer
        }
        .padding(16)
        .frame(width: 440)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(1)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "translate")
                .foregroundStyle(.tint)
            Text("Translate")
                .font(.headline)
            Spacer()
            if model.source != nil {
                Text(model.name(of: model.source))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            targetMenu
            Button("Close", systemImage: "xmark", action: model.close)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("Close (Esc)")
        }
    }

    private var targetMenu: some View {
        let current = model.usedTarget ?? model.options.target
        return Menu {
            Picker("Translate to", selection: Binding(get: { current }, set: model.retarget)) {
                if !model.languages.contains(where: { $0.code == current }) {
                    Text(model.name(of: current)).tag(current)
                }
                ForEach(model.languages) { Text($0.name).tag($0.code) }
            }
            .pickerStyle(.inline)
        } label: {
            Text(model.name(of: current))
        }
        .menuStyle(.button)
        .controlSize(.small)
        .fixedSize()
        .help("Translate to")
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .loading:
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
        case .done:
            ScrollView {
                Text(model.result)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(textHeight, 18), Self.maxTextHeight))
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.phase == .done && !model.isUnchanged && model.copyOnlyReason == nil {
                Text(model.engine == .apple ? "Apple, on this Mac" : "Google Translate")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.isUnchanged {
                Text("Already in \(model.name(of: model.usedTarget))").font(.caption).foregroundStyle(.secondary)
            } else if let reason = model.copyOnlyReason, model.phase == .done {
                Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if model.needsLanguageDownload {
                Button("Open Language & Region…", action: model.openTranslationLanguages)
            }
            if case .failed = model.phase {
                Button("Retry", action: model.run)
                    .keyboardShortcut("r")
            }
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
        .controlSize(.regular)
    }
}
