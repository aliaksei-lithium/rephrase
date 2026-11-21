import Carbon.HIToolbox
import CoreGraphics

/// Posts ⌘C / ⌘V to the front app. Sending events needs the Accessibility permission;
/// nothing here observes the keyboard.
enum KeySender {
    static func copy() { press(CGKeyCode(kVK_ANSI_C)) }
    static func paste() { press(CGKeyCode(kVK_ANSI_V)) }

    /// The shortcut's Control and Option may still be held; a ⌘C sent now would arrive as ⌃⌥⌘C.
    static func waitForModifierRelease(timeout: Duration = .milliseconds(600)) async {
        let held: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        let deadline = ContinuousClock.now + timeout
        while !CGEventSource.flagsState(.combinedSessionState).intersection(held).isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(15))
        }
    }

    private static func press(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .privateState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
