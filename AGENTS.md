# Agents Guide

## Project Overview

Rephrase tool on Cloudflare Pages: static frontend plus Pages Functions that call Claude (Anthropic Messages API, optionally through Cloudflare AI Gateway) or Workers AI.

## Structure

- `index.html`, `style.css`, `script.js`, `editor.js` - static frontend, no build step
  - `editor.js` - rich-text helpers: paste sanitising (DOMPurify), HTML to Markdown (Turndown), Markdown to HTML (marked), diff marks, rich copy
  - `script.js` - app state, login flow, model picker, streaming client
- `functions/api/` - Pages Functions (each file maps to `/api/<name>`)
  - `_middleware.js` - CORS and session check for every `/api/*` route except `/api/auth/*`
  - `auth/login.js`, `auth/logout.js`, `auth/me.js`
  - `models.js` - models available given the configured providers
  - `rephrase.js` - main endpoint, streams SSE
- `functions/lib/` - shared code
  - `auth.js` - HMAC session tokens (cookie or Bearer)
  - `prompts.js` - system prompt builder (base + mode + style + tone)
  - `providers.js` - Anthropic and Workers AI streaming clients
  - `models.js` - model allowlist and prices
  - `http.js` - JSON and CORS helpers
- `wrangler.toml` - Pages config, `[vars]`, and the `AI` binding for production and preview
- `test-rephrase.js` - API smoke test against a local server

## Key Conventions

- Functions use `onRequest()` or `onRequestPost()` exports. Return JSON via `functions/lib/http.js`.
- Never send `x-api-key` and a gateway BYOK key at the same time; `providers.js` sends the key only when `ANTHROPIC_API_KEY` is set.
- Model ids are the exact strings from `functions/lib/models.js`. `output_config.effort` is only sent for models that support it.
- The frontend sends Markdown and renders Markdown; the diff is computed on plain text and applied to the rendered DOM.
- Secrets never go in `wrangler.toml`. Local: `.env` (symlink to `local.env`) and `.env.local`. Both are git-ignored; so is `*.env`.
- Test locally with `npm run dev` (or `npm run dev:free` for the Workers AI binding) and `APP_PASSWORD=dev-password npm run test:api`.

## Tech Stack

- Frontend: vanilla HTML/CSS/JS, libraries from cdnjs (jsdiff 5, DOMPurify 3, Turndown 7, marked 15)
- Backend: Cloudflare Pages Functions, raw `fetch` to the Anthropic Messages API (no SDK, no bundler)
- Deployment: Cloudflare Pages via GitHub integration, no build command
