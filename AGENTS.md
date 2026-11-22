# Agents Guide

## Project Overview

Rephrase tool on Cloudflare Pages: static frontend plus Pages Functions that call Claude (Anthropic Messages API, optionally through Cloudflare AI Gateway) or Workers AI. A native macOS app in `macos/` (a window that opens with the app, a menu bar icon, global shortcuts) uses the same API.

## Structure

- `public/` - static frontend served by Pages (`pages_build_output_dir`), no build step
  - `index.html`, `style.css`, favicons, `robots.txt`
  - `editor.js` - rich-text helpers: paste sanitising (DOMPurify), HTML to Markdown (Turndown), Markdown to HTML (marked), diff marks, rich copy
  - `script.js` - app state, login flow, model picker, streaming client
- `functions/api/` - Pages Functions (each file maps to `/api/<name>`)
  - `_middleware.js` - CORS and session check for every `/api/*` route except `/api/auth/*`
  - `auth/login.js`, `auth/logout.js`, `auth/me.js`, `auth/demo.js` (passwordless demo session)
  - `models.js` - models available given the configured providers
  - `rephrase.js` - main endpoint, streams SSE
  - `translate.js` - Google Translate for the macOS ⌃⌥Z shortcut (password sessions only)
- `functions/lib/` - shared code
  - `auth.js` - HMAC session tokens (cookie or Bearer); demo tokens carry `demo: true`
  - `demo.js` - public demo: Gemma only, shared daily neuron budget and per-visitor limit in D1 (`DEMO_DB`)
  - `prompts.js` - system prompt builder (base + mode + style + tone)
  - `providers.js` - Anthropic and Workers AI streaming clients
  - `models.js` - model allowlist and prices
  - `http.js` - JSON and CORS helpers
  - `translate.js` - Google Cloud Translation v2 client (`GOOGLE_TRANSLATE_API_KEY`, sent as `X-Goog-Api-Key`)
- `macos/` - native macOS app (Swift 6, SwiftUI), see `macos/PLAN.md`
  - `project.yml` - XcodeGen spec; the `.xcodeproj` is generated and git-ignored
  - `Rephrase/` - app sources; `RephraseTests/` - Swift Testing tests
  - `scripts/release.sh` - Release archive and DMG in `macos/dist/` (ad-hoc unless `CODESIGN_IDENTITY`; notarizes with `NOTARY_PROFILE`)
  - `Rephrase/DemoMode.swift` - Debug-only staged popup for README screenshots (window behind everything, captured with `screencapture -l`)
  - `scripts/install.sh` - Release build into `~/Applications` (separate from the Debug build that tests replace); `REPHRASE_TEAM_ID` signs with a team so Accessibility access survives reinstalls
- `docs/building.md` - build, deploy, API and release notes; `docs/images/` - README images
- `wrangler.toml` - Pages config, `[vars]`, the `AI` binding for production and preview, and the `DEMO_DB` D1 binding (top level and per environment)
- `test-rephrase.js` - API smoke test against a local server

## Key Conventions

- Functions use `onRequest()` or `onRequestPost()` exports. Return JSON via `functions/lib/http.js`.
- Never send `x-api-key` and a gateway BYOK key at the same time; `providers.js` sends the key only when `ANTHROPIC_API_KEY` is set.
- Model ids are the exact strings from `functions/lib/models.js`. `output_config.effort` is only sent for models that support it.
- `/api/rephrase` takes `format: "markdown"` (default, web app) or `"plain"` (macOS app, selections from other apps).
- The frontend sends Markdown and renders Markdown; the diff is computed on plain text and applied to the rendered DOM.
- Translation is secondary and macOS-only: `/api/models` advertises `translate`, demo sessions are refused, and the web app has no translate UI.
- Demo sessions must never reach Anthropic or exceed the Workers AI free tier: `rephrase.js` forces `DEMO_MODEL_ID`, skips the fallback and reserves budget via `reserveDemo` before calling the model.
- Secrets never go in `wrangler.toml`. Local: `.env` (symlink to `local.env`) and `.env.local`. Both are git-ignored; so is `*.env`.
- macOS app: `cd macos && xcodegen generate`, then build in Xcode or `xcodebuild -scheme Rephrase -derivedDataPath build test`. Add `TEST_RUNNER_REPHRASE_BASE_URL=http://localhost:8788 TEST_RUNNER_APP_PASSWORD=...` to also run the live sign-in test.
- Test locally with `npm run dev` (or `npm run dev:free` for the Workers AI binding) and `APP_PASSWORD=dev-password npm run test:api`.

## Tech Stack

- Frontend: vanilla HTML/CSS/JS, libraries from cdnjs (jsdiff 5, DOMPurify 3, Turndown 7, marked 15)
- macOS: Swift 6 (default MainActor isolation), SwiftUI, macOS 26+, KeyboardShortcuts package, XcodeGen
- Backend: Cloudflare Pages Functions, raw `fetch` to the Anthropic Messages API (no SDK, no bundler)
- Deployment: Cloudflare Pages via GitHub integration, no build command
