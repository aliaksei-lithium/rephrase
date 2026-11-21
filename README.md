<p align="center">
  <img src="docs/images/icon.png" width="132" alt="">
</p>

<h1 align="center">Rephrase</h1>

<p align="center">
  Fix and rephrase your messages with Claude, in your own voice.<br>
  A native macOS app for any text field, and a web app for formatted text.
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

It needs only the Accessibility permission, to read the selection and paste the result. It never watches what you type.

### Install

Download **[Rephrase 0.1.0](https://github.com/aliaksei-lithium/rephrase/releases/download/v0.1.0/Rephrase-0.1.0.dmg)** (or any version from [Releases](https://github.com/aliaksei-lithium/rephrase/releases)) and drag Rephrase to Applications. The app is not notarized, so the first time either right-click it and choose **Open**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/Rephrase.app
```

The setup guide then asks you to sign in to your Rephrase server and to allow Accessibility access.

## Web app

![Rephrase web app](docs/images/web.png)

Paste formatted text from Slack, Gmail or Docs. The result keeps bold, lists, code and links, underlines what changed, and copies back with formatting or as Markdown.

## What it does

- **Fix** corrects typos, grammar and punctuation only. **Edit** also smooths awkward phrasing. **Rewrite** says it again in more natural words.
- Optional style (casual, business, academic) and tone (friendly, confident, diplomatic, enthusiastic).
- Keeps the language of the text, or writes in English or German.
- Claude Sonnet 5 by default; Opus 5, Haiku 4.5 or the free Gemma model on Workers AI are one click away.
- Runs on your own Cloudflare account behind a password, and keeps no copy of your text.

---

Apache 2.0 licence · [Building and deploying](docs/building.md)
