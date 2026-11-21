# Rephrase for macOS: Plan

Status: written 2026-11-21. Phases 1 to 4 and the repo housekeeping (section 7) are done; phases 3 and 4 still need the manual test matrix. Next is Phase 5. Target: macOS 26 (Tahoe) and later, built with Xcode 27, Swift 6.2.

## 1. What it does

A menu bar app with no Dock icon. It never watches the keyboard. It only acts when you press one of its two global shortcuts:

| Shortcut (default) | Action |
| --- | --- |
| ⌃⌥C | Read the selected text in the front app and open a small popup next to it that streams the rewritten text. Enter replaces, ⌘C copies, Esc closes. Mode, style, tone, and language can be changed in the popup and the request re-runs. |
| ⌃⌥X | Rewrite the selection with the default settings and replace it in place. A small "Rewriting..." badge shows near the selection; Esc cancels; ⌘Z in the app undoes the replace. |

Both shortcuts can be changed in Settings.

### Why not ⇧⌥C / ⇧⌥X

Since macOS 15, `RegisterEventHotKey` (the only global hotkey API that needs no permission and sees no other keystrokes) rejects shortcuts whose only modifiers are Option or Option+Shift. Apple confirmed this is deliberate, to stop key loggers from grabbing character keys ([Apple forums](https://developer.apple.com/forums/thread/763878), [Shottr notes](https://shottr.cc/kb/sequoia)). The only way to get ⇧⌥C back is an event tap that inspects every keystroke, which needs the Input Monitoring permission and is exactly the keylogging this app avoids. So the defaults add Control. ⌃⌥C and ⌃⌥X are not taken by macOS or common apps.

## 2. Privacy and permissions

- **Accessibility** is the only permission. It is needed to read the selection from another app and to send ⌘C / ⌘V. The app asks for it on first launch with a short explanation screen and a button that opens System Settings.
- **No Input Monitoring, no event tap, no global key monitor.** The hotkeys are registered with `RegisterEventHotKey` via the [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) package, so the app is told only "your shortcut was pressed".
- Text leaves the Mac only after you press a shortcut, and only the selected text. Nothing is stored except settings and the session token (Keychain).
- Secure text fields (`AXSecureTextField`) are never read.
- When the app has to go through the clipboard (see 4.2), it saves the clipboard first, restores it afterwards, and marks its own temporary items with `org.nspasteboard.TransientType` so clipboard managers ignore them.

## 3. Backend: reuse the existing API

The app talks to the deployed Pages site exactly like the web app. No new endpoints are required.

| Call | Use |
| --- | --- |
| `POST /api/auth/login { password }` | Settings > Sign in. Returns `token`; the app stores it in the Keychain and sends `Authorization: Bearer <token>` (already supported by `functions/lib/auth.js`). Token lasts `SESSION_DAYS` (180). |
| `GET /api/models` | Fills the model, mode, style, tone, and language pickers, and the default model. |
| `POST /api/rephrase` with `stream: true` | Popup. Parse `data: {...}` SSE lines (`delta`, `info`, `done`, `error`). |
| `POST /api/rephrase` with `stream: false` | Quick replace. One JSON response is simpler and the result is not shown while it arrives. |
| `GET /api/auth/me` | Check the token at launch; on 401 show "Sign in again" in the menu. |

### One small backend change

Selections from other apps are plain text, while the prompt tells the model the input is Markdown. Plain text containing `*`, `_`, `#`, or a leading `-` could come back escaped or reformatted. Add an optional `format: "markdown" | "plain"` field to `/api/rephrase` (default `markdown`, so the web app is unchanged). With `plain`, `buildSystemPrompt` swaps the Markdown rule for "The input is plain text. Keep line breaks and paragraph breaks exactly. Do not add Markdown." Files: `functions/api/rephrase.js`, `functions/lib/prompts.js`, `functions/api/models.js` (advertise `formats`), plus a case in `test-rephrase.js`.

## 4. How the native parts work

### 4.1 Reading the selection

1. Remember the front app (`NSWorkspace.shared.frontmostApplication`, its pid).
2. Accessibility first: system-wide element → `kAXFocusedUIElementAttribute` → `kAXSelectedTextAttribute`. Also read `kAXSelectedTextRangeAttribute` and `kAXBoundsForRangeParameterizedAttribute` to get the selection's screen rectangle for the popup.
3. Electron and Chromium apps (Slack, VS Code, Chrome) expose little until asked: set `AXManualAccessibility` (Electron) / `AXEnhancedUserInterface` (Chromium) on the app element once, then retry.
4. Fallback when AX returns nothing: save the clipboard, post ⌘C with `CGEvent`, wait up to ~250 ms for `NSPasteboard.changeCount` to change, read the string, restore the clipboard.
5. Nothing selected: show a short "Select some text first" badge and stop.

### 4.2 Replacing the selection

Replace by pasting, not by setting `kAXSelectedTextAttribute`. Setting the AX value fails in most Electron and web editors and often skips the app's undo stack; paste works almost everywhere and ⌘Z undoes it.

1. Check the front app is still the same pid and the focused element is unchanged. If not, copy the result to the clipboard instead and say so.
2. Save the clipboard, write the result (plain string; later also RTF/HTML, see Phase 6), post ⌘V, restore the clipboard after ~400 ms.

Clipboard privacy: macOS 15.4 introduced pasteboard access alerts for programmatic reads (`NSPasteboard.accessBehavior`, [Apple docs](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum/default)). Whether Tahoe shows them by default is unclear ([summary](https://mjtsai.com/blog/2025/05/12/pasteboard-privacy-preview-in-macos-15-4)). If it does, the user allows the app once. The AX path in 4.1 avoids clipboard reads in most native apps anyway.

### 4.3 The popup

- An `NSPanel` subclass with `.nonactivatingPanel`, `.floating` level, `canBecomeKey = true`. It takes keyboard focus (Enter, Esc, ⌘C) without activating Rephrase, so the source app stays frontmost and its selection stays intact for the paste.
- Positioned just below the selection rectangle, flipped above it near the bottom of the screen, clamped to `NSScreen.visibleFrame`. Without a rectangle, it opens at the mouse pointer.
- SwiftUI content with Tahoe's Liquid Glass (`.glassEffect()`, `GlassEffectContainer`) and a 420 pt wide card that grows with the text up to a max height, then scrolls.
- Layout: the rewritten text (selectable) with inserted words tinted, a row of compact pickers (Mode, Style, Tone, Language), and a footer with the model name, `Replace ↩`, `Copy ⌘C`, `Retry ⌘R`. While streaming, a subtle shimmer; on error, the message and a Retry button.
- Word diff: tokenize old and new text into words and whitespace, use Swift's `CollectionDifference`, build an `AttributedString`.
- Closing the popup cancels the request (the streaming `Task` is cancelled, which closes the `URLSession` stream).
- Clicking outside closes it.

### 4.4 Quick replace badge

A tiny non-activating panel near the selection (or pointer) showing a spinner, then a check mark for ~1 s. Esc while it is visible cancels the request and leaves the text untouched.

## 5. App structure

```
macos/
  Rephrase.xcodeproj
  Rephrase/
    RephraseApp.swift          @main; MenuBarExtra + Settings scenes; LSUIElement = YES
    AppModel.swift             @Observable @MainActor: settings, auth state, models list
    Settings/
      SettingsView.swift       Server URL, sign in/out, defaults, shortcuts recorder, launch at login
      KeychainStore.swift      token storage (SecItem, kSecClassGenericPassword)
    Services/
      Hotkeys.swift            KeyboardShortcuts names and handlers
      SelectionReader.swift    AX read, Electron/Chromium flags, ⌘C fallback, selection bounds
      TextReplacer.swift       pasteboard save/restore, ⌘V, target checks
      PasteboardSnapshot.swift save and restore all items and types
      RephraseClient.swift     URLSession; login, me, models, rephrase (SSE via bytes(for:).lines)
      SSEParser.swift          "data:" lines to Event enum
    UI/
      PopupPanel.swift         NSPanel subclass and positioning
      PopupView.swift          SwiftUI card
      BadgePanel.swift         quick replace badge
      DiffText.swift           word diff to AttributedString
      OnboardingView.swift     Accessibility explanation and check
  RephraseTests/
    SSEParserTests.swift, DiffTextTests.swift, PasteboardSnapshotTests.swift
```

Tech choices:
- Swift 6.2 with strict concurrency, `@Observable`, `@MainActor` UI, `async`/`await` networking.
- SwiftUI for all views; AppKit only for the panels, AX, `CGEvent`, and pasteboard.
- One dependency: KeyboardShortcuts (hotkey registration plus the SwiftUI recorder). Everything else is system frameworks.
- Settings in `@AppStorage` / `UserDefaults`: server URL (default `https://rephrase-eey.pages.dev`), mode, style, tone, language, model.
- Launch at login with `SMAppService.mainApp`.
- Not sandboxed: the App Sandbox does not allow controlling other apps through Accessibility or posting key events. Hardened runtime on.

## 6. Phases

1. **Backend `format: "plain"`** (section 3). Test with `npm run dev` and `test-rephrase.js`.
2. **Skeleton.** Xcode project in `macos/`, menu bar icon, Settings window, sign in with the app password, token in Keychain, models loaded from `/api/models`. Done when the menu shows "Signed in" and the pickers are filled.
3. **Popup (⌃⌥C).** Selection reader (AX plus ⌘C fallback), popup panel, streaming client, Replace / Copy / Esc. Done when it works in TextEdit, Notes, Mail, and Safari.
4. **Quick replace (⌃⌥X).** Non-streaming call, paste, badge, cancel. Done when ⌘Z restores the original in each app from the test list.
5. **Polish.** Word diff, Liquid Glass styling, positioning edge cases (multiple screens, full-screen apps, bottom of screen), onboarding screen, launch at login, shortcut recorder, "Sign in again" handling, menu item "Rewrite clipboard" for apps where reading fails.
6. **Rich text (optional).** Read `public.rtf` / `public.html` from the ⌘C path, convert to Markdown, send `format: "markdown"`, render the answer with `AttributedString(markdown:)`, and paste RTF and HTML alongside the plain string so Slack and Mail keep bold, lists, and links.
7. **Distribution.** For personal use: build and sign with your Apple Development certificate. A stable signature matters: Accessibility trust is tied to it, and ad-hoc builds lose the permission on every rebuild. For sharing: Developer ID signing plus `xcrun notarytool`, a DMG, and optionally Sparkle for updates.

### Test matrix (phases 3 to 5)

TextEdit, Notes, Mail, Pages, Safari textarea and contenteditable, Chrome, Slack desktop, VS Code, Messages, Terminal (read only, so Replace falls back to copy), a password field (must be refused).

## 7. Repo housekeeping

`wrangler.toml` sets `pages_build_output_dir = "."`, so every file in the repo, including `macos/`, is served as a static asset. Nothing in `macos/` is secret, but before adding the Xcode project, move the site files (`index.html`, `style.css`, `script.js`, `editor.js`, favicons, `preview.jpg`, `robots.txt`) into `public/` and set `pages_build_output_dir = "public"`. `functions/` stays at the root. Update `AGENTS.md` and `README.md` with the new layout and a "macOS app" section.

## 8. Open decisions

1. **Shortcuts:** ⌃⌥C / ⌃⌥X (recommended) or another pair. ⇧⌥ alone is not possible without keylogging (section 1).
2. **Rich text in v1** or after (Phase 6). Recommended: after.
3. **Distribution:** personal build only, or notarized DMG for others.

## 9. Done so far

- Phase 1: `/api/rephrase` accepts `format: "plain"`; `/api/models` lists `formats`. Smoke test case added.
- Section 7: site files moved to `public/`, `pages_build_output_dir = "public"`, npm scripts updated.
- Phase 2: XcodeGen project (`project.yml`), menu bar app, Settings (server, sign in/out, defaults, shortcut recorders), token in the login Keychain, catalog from `/api/models`. The shortcut names are defined, but nothing handles them until Phase 3.
- Phase 3: ⌃⌥C reads the selection (`SelectionReader`: AX, `AXManualAccessibility` for Electron, ⌘C fallback with clipboard restore), opens a non-activating Liquid Glass popup next to it (`PopupPanel`, `PopupView`), streams the rewrite (`RephraseClient.rephrase`, `SSEParser`), re-runs when mode, style, tone, or language change, and replaces by pasting (`TextReplacer`). Without the Accessibility permission the shortcut opens the system prompt; the menu also offers it.
- Phase 4: ⌃⌥X sends a non-streaming request with the default settings, shows a glass badge ("Rewriting…", Esc, the shortcut again, or a click elsewhere cancels), and pastes the result. Before pasting it checks that the same app and the same focused element are still in front; otherwise it copies the result and says so. The selection's leading and trailing whitespace is kept, so a triple-clicked paragraph keeps its newline. If nothing changed it shows "Already looks good" and pastes nothing. The popup's Replace uses the same paste path and badge.
- Tests: decoding, error mapping, Keychain round trip, SSE parsing, output cleanup, popup state with a stubbed stream, and opt-in live sign-in and streaming tests.
- Not verified yet: the ⌃⌥C and ⌃⌥X flows in real apps (needs the Accessibility permission granted by hand) and the glass rendering on screen.
- Signing is still ad-hoc (`CODE_SIGN_IDENTITY: "-"`). Install an Apple Development certificate and set `DEVELOPMENT_TEAM` before Phase 3, or the Accessibility permission resets on every build.
