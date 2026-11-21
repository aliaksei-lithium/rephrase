import AppKit

/// A copy of everything on a pasteboard, so a temporary ⌘C / ⌘V can put the user's clipboard back.
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(of pasteboard: NSPasteboard = .general) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var types: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { types[type] = data }
            }
            return types
        }
    }

    var isEmpty: Bool { items.isEmpty }

    func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}

extension NSPasteboard.PasteboardType {
    /// nspasteboard.org marker: clipboard managers skip items that carry it.
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
}

extension NSPasteboard {
    /// Writes a plain string marked as transient.
    func setTransientString(_ string: String) {
        clearContents()
        let item = NSPasteboardItem()
        item.setString(string, forType: .string)
        item.setData(Data(), forType: .transient)
        writeObjects([item])
    }
}
