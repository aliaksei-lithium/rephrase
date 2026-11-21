import KeyboardShortcuts

// Registered with RegisterEventHotKey via KeyboardShortcuts: the app only learns that its own
// shortcut was pressed and never sees other keystrokes. Since macOS 15 the system rejects
// shortcuts whose only modifiers are Option or Option+Shift, so the defaults include Control.
extension KeyboardShortcuts.Name {
    static let rewriteWithPopup = Self("rewriteWithPopup", default: .init(.c, modifiers: [.control, .option]))
    static let rewriteInPlace = Self("rewriteInPlace", default: .init(.x, modifiers: [.control, .option]))
    static let translate = Self("translate", default: .init(.z, modifiers: [.control, .option]))
}
