<p align="center">
  <img src="docs/images/icon.png" width="132" alt="">
</p>

<h1 align="center">Rephrase</h1>

<p align="center">
  Fix and rephrase your messages with Claude, in your own voice.<br>
  A native macOS app for any text field, and a web app for formatted text.
</p>

<p align="center">
  <a href="https://rephrase.aliaksei.xyz"><strong>Try it in your browser →</strong></a>
</p>

<p align="center">
  <a href="https://github.com/aliaksei-lithium/rephrase/releases/latest"><img src="https://img.shields.io/github/v/release/aliaksei-lithium/rephrase?color=0066cc&label=download" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-26-0066cc" alt="macOS 26">
  <img src="https://img.shields.io/badge/licence-Apache%202.0-0066cc" alt="Apache 2.0 licence">
</p>

![Rephrase for macOS](docs/images/macos.png)

## macOS app

Select text in any app and press:

- **⌃⌥C** to see the rewrite in a popup next to it. Change the mode, style, tone or language there, then press Enter to replace the text.
- **⌃⌥X** to replace it straight away with your default settings. ⌘Z undoes it.
- **⌃⌥Z** to translate it into your default language (the source language is detected) in a popup. Enter replaces, ⌘C copies. It remembers the last language you picked in the popup; you can also set it in Settings › General › Translate. Needs a Google Translate key on the server and a password sign-in.

Opening Rephrase shows its window with your setup status, the shortcuts and the version. Settings (⌘,), Sign Out and Quit are there too, and also in the menu bar menu. Every shortcut can be changed in Settings.

It needs only the Accessibility permission, to read the selection and paste the result. It never watches what you type.

### Install

**[Download Rephrase](https://github.com/aliaksei-lithium/rephrase/releases/latest)**. The app is not notarized, so the first time either right-click it and choose **Open**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/Rephrase.app
```

The Rephrase window then asks you to sign in to your Rephrase server, or to try the demo without a password, and to allow Accessibility access.

## Web app

**[rephrase.aliaksei.xyz](https://rephrase.aliaksei.xyz)**

![Rephrase web app](docs/images/web.png)

Paste formatted text from Slack, Gmail or Docs. The result keeps bold, lists, code and links, underlines what changed, and copies back with formatting or as Markdown.

## What it does

- **Fix** corrects typos, grammar and punctuation only. **Edit** also smooths awkward phrasing. **Rewrite** says it again in more natural words.
- Optional style (casual, business, academic) and tone (friendly, confident, diplomatic, enthusiastic).
- Keeps the language of the text, or writes in English or German.
- Claude Sonnet 5 by default; Opus 5, Haiku 4.5 or the free Gemma model on Workers AI are one click away.
- Runs on your own Cloudflare account behind a password, and keeps no copy of your text.

## Demo

Anyone can try the [web app](https://rephrase.aliaksei.xyz) or the macOS app without a password. The demo uses only the free Gemma model, takes texts up to 2,000 characters, and has a daily limit shared by everyone, so it may run out before the day ends (it resets at 00:00 UTC).

---

Apache 2.0 licence · [Building and deploying](docs/building.md)
