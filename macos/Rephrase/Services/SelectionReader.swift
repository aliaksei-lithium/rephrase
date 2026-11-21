import AppKit
import ApplicationServices

/// Text selected in the front app, plus where it is on screen.
struct Selection {
    let text: String
    /// Selection rectangle in AppKit screen coordinates, when the app reports it.
    let bounds: CGRect?
    let app: NSRunningApplication
    /// The focused element when the selection was read, to check the paste target is unchanged.
    let element: AXUIElement?
}

enum SelectionError: LocalizedError, Equatable {
    case notTrusted
    case nothingSelected
    case secureField

    var errorDescription: String? {
        switch self {
        case .notTrusted: "Rephrase needs the Accessibility permission to read the selection."
        case .nothingSelected: "Select some text first."
        case .secureField: "Password fields can't be rewritten."
        }
    }
}

/// Reads the selection through the Accessibility API, falling back to a temporary ⌘C.
enum SelectionReader {
    static func read() async throws -> Selection {
        guard AXIsProcessTrusted() else { throw SelectionError.notTrusted }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { throw SelectionError.nothingSelected }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.5)
        // Electron apps (Slack, VS Code) build their accessibility tree only when asked.
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        let focused = focusedElement(of: appElement)
        if let focused {
            let role: String? = value(focused, kAXRoleAttribute)
            let subrole: String? = value(focused, kAXSubroleAttribute)
            if role == "AXSecureTextField" || subrole == kAXSecureTextFieldSubrole {
                throw SelectionError.secureField
            }
            if let text: String = value(focused, kAXSelectedTextAttribute), !text.isEmpty {
                return Selection(text: text, bounds: selectionBounds(focused), app: app, element: focused)
            }
        }

        let text = try await copySelection()
        return Selection(text: text, bounds: focused.flatMap(selectionBounds), app: app, element: focused)
    }

    static func focusedElement(of appElement: AXUIElement) -> AXUIElement? {
        element(appElement, kAXFocusedUIElementAttribute)
    }

    /// Opens the system prompt that lists Rephrase in Privacy & Security > Accessibility.
    @discardableResult
    static func requestTrust() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    private static func copySelection() async throws -> String {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(of: pasteboard)
        let before = pasteboard.changeCount

        await KeySender.waitForModifierRelease()
        KeySender.copy()

        let deadline = ContinuousClock.now + .milliseconds(300)
        while pasteboard.changeCount == before, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        let copied = pasteboard.changeCount != before ? pasteboard.string(forType: .string) : nil
        if pasteboard.changeCount != before { snapshot.restore(to: pasteboard) }

        guard let copied, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SelectionError.nothingSelected
        }
        return copied
    }

    private static func selectionBounds(_ element: AXUIElement) -> CGRect? {
        guard let range: AXValue = axValue(element, kAXSelectedTextRangeAttribute) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &result) == .success,
              let result, CFGetTypeID(result) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(result as! AXValue, .cgRect, &rect), rect.width > 0 || rect.height > 0 else { return nil }
        return appKitRect(fromAX: rect)
    }

    /// AX uses a top-left origin on the primary screen; AppKit uses bottom-left.
    static func appKitRect(fromAX rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: AX helpers

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        copy(element, attribute) as? T
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}

/// Puts text into the front app by pasting, so the app's own undo works.
enum TextReplacer {
    enum Outcome { case replaced, copiedInstead }

    static func replace(_ selection: Selection, with text: String) async -> Outcome {
        let text = preservingEdges(of: selection.text, in: text)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == selection.app.processIdentifier,
              AXIsProcessTrusted(),
              focusUnchanged(selection)
        else {
            NSPasteboard.general.setTransientString(text)
            return .copiedInstead
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(of: pasteboard)
        pasteboard.setTransientString(text)

        await KeySender.waitForModifierRelease()
        KeySender.paste()

        // Give the app time to read the pasteboard before putting the user's clipboard back.
        try? await Task.sleep(for: .milliseconds(400))
        snapshot.restore(to: pasteboard)
        return .replaced
    }
}

extension TextReplacer {
    /// The server trims its answer; keep the selection's own leading and trailing whitespace
    /// (a triple-clicked paragraph ends with a newline) so the surrounding text stays intact.
    static func preservingEdges(of original: String, in result: String) -> String {
        let leading = original.prefix { $0.isWhitespace }
        let trailing = String(original.reversed().prefix { $0.isWhitespace }.reversed())
        guard leading.count < original.count else { return result }
        return leading + result.trimmingCharacters(in: .whitespacesAndNewlines) + trailing
    }

    private static func focusUnchanged(_ selection: Selection) -> Bool {
        guard let before = selection.element else { return true }
        let appElement = AXUIElementCreateApplication(selection.app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.5)
        guard let now = SelectionReader.focusedElement(of: appElement) else { return true }
        return CFEqual(before, now)
    }
}
