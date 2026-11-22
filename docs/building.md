# Building Rephrase

The repo has two parts that share one API:

- `public/` and `functions/`: the web app and its API, on Cloudflare Pages with Pages Functions.
- `macos/`: the native macOS app (Swift 6, SwiftUI, macOS 26). Design notes are in [macos/PLAN.md](../macos/PLAN.md).

## Web app and API

Needs Node and Wrangler (`npm install`).

```bash
ln -s local.env .env        # local.env holds anthropic_key=...; both files are git-ignored
cp .env.example .env.local  # set APP_PASSWORD for local use
npm run dev                 # http://localhost:8788
npm run dev:free            # same, plus the Workers AI binding (the free Gemma model)
APP_PASSWORD=dev-password npm run test:api   # smoke test: login, models, sample edits
```

Wrangler loads `.env` and `.env.local` as local variables. It ignores `--env-file` for this, which is why `.env` is a symlink.

### Deploying

Cloudflare Pages builds from GitHub with no build command; `wrangler.toml` sets the output folder to `public/`. Set these secrets in the Pages project (production and preview):

| Secret | Purpose |
| --- | --- |
| `APP_PASSWORD` | the sign-in password |
| `ANTHROPIC_API_KEY` | Claude; leave it out to use only Workers AI |
| `AUTH_SECRET` | optional, signs session tokens (defaults to `APP_PASSWORD`) |
| `ANTHROPIC_BASE_URL` | optional, routes Claude calls through Cloudflare AI Gateway |
| `GOOGLE_TRANSLATE_API_KEY` | optional, Google Cloud Translation (Basic v2) key; enables `/api/translate`, so the macOS app can translate with Google (without it, ⌃⌥Z uses Apple's on-device translation). Restrict it to the Cloud Translation API |

### Demo

Visitors without the password get a demo session (`POST /api/auth/demo`): the web app starts one on its own, and the macOS app offers **Try Demo**. Demo sessions can use only Gemma 4 26B on Workers AI, and all of them share one daily budget so the demo stays inside the Workers AI free allocation (10,000 neurons per day, reset at 00:00 UTC).

`functions/lib/demo.js` keeps the budget in the `rephrase-demo` D1 database (binding `DEMO_DB`, tables created on first use). Each request reserves its worst case in neurons before it runs (input estimate plus `max_tokens`) and gives back what it did not use, so concurrent requests cannot overshoot. Each visitor also has a daily request limit, counted by a salted, per-day hash of the IP address; the IP itself is not stored.

| Variable (`wrangler.toml`) | Default | Purpose |
| --- | --- | --- |
| `DEMO_ENABLED` | `true` | `false` turns the demo off; existing demo sessions stop working |
| `DEMO_NEURONS_PER_DAY` | `6000` | shared budget; the rest of the 10,000 is left for your own Gemma use and fallbacks |
| `DEMO_REQUESTS_PER_CLIENT` | `30` | rewrites per visitor per day |
| `DEMO_MAX_CHARS` | `2000` | longest demo text |
| `DEMO_MAX_OUTPUT_TOKENS` | `3072` | `max_tokens` for demo requests, which sets the reservation |

The demo is off when the `AI` or `DEMO_DB` binding is missing, so plain `npm run dev` has no demo; `npm run dev:free` has one, with a local D1 database. To check today's usage in production:

```bash
npx wrangler d1 execute rephrase-demo --remote --command "SELECT * FROM demo_usage ORDER BY day DESC LIMIT 3"
```

`npm run deploy` deploys from your machine instead.

The production site is `https://rephrase.aliaksei.xyz`, a custom domain on the `rephrase` Pages project (Workers & Pages > rephrase > Custom domains); `rephrase-eey.pages.dev` keeps working. The macOS app defaults to the custom domain.

### API

All routes live under `/api`. Everything except `/api/auth/*` needs a session: the `rephrase_session` cookie set by login, or `Authorization: Bearer <token>`.

| Route | Method | Body / result |
| --- | --- | --- |
| `/api/auth/login` | POST | `{ "password" }` → `{ ok, token, expires_at }` and sets the cookie |
| `/api/auth/demo` | POST | `{ ok, token, demo, expires_at }` and sets the cookie; 404 when the demo is off |
| `/api/auth/logout` | POST | clears the cookie |
| `/api/auth/me` | GET | `{ authenticated, configured, demo, demo_available, expires_at }`, plus `demo_status` for demo sessions |
| `/api/models` | GET | `{ models, default, modes, styles, tones, languages, formats, translate }`; demo sessions get only Gemma and `demo, max_chars` |
| `/api/rephrase` | POST | `{ text, mode, style, tone, language, format (markdown/plain), model, stream }` → SSE stream, or JSON with `stream: false`. Demo sessions get `demo: { left_for_you, budget_left }` in the result, or 429 with `code` `demo_limit` / `demo_client_limit` |
| `/api/translate` | GET | `{ languages: [{ code, name }] }` (Google Translate languages) |
| `/api/translate` | POST | `{ text, target, alternate? }` → `{ text, source, target }`; Google detects `source`, and `alternate` is used when the text is already in `target`. 503 `not_configured` without the key, 403 `demo_not_allowed` for demo sessions |

### Prompts

Prompts live in `functions/lib/prompts.js`. A shared base prompt pins language, meaning, formatting and voice; the mode, style and tone blocks are appended. Tune them against real messages and check every mode after a change.

## macOS app

Needs macOS 26, Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is generated from `macos/project.yml` and is git-ignored.

```bash
cd macos
xcodegen generate && open Rephrase.xcodeproj     # develop in Xcode
xcodebuild -scheme Rephrase -derivedDataPath build test   # unit tests
scripts/install.sh                               # Release build into ~/Applications, then launch
scripts/release.sh                               # DMG in macos/dist/
```

Add `TEST_RUNNER_REPHRASE_BASE_URL=http://localhost:8788 TEST_RUNNER_APP_PASSWORD=...` to the test command to also run the live sign-in and streaming tests.

### Signing

macOS ties the Accessibility permission to the app's signature. An ad-hoc build counts as a new app every time, so its permission has to be granted again after each install (`install.sh` resets the stale entry for you).

- `REPHRASE_TEAM_ID=<team id> scripts/install.sh` signs with your Apple Development certificate (Xcode › Settings › Apple Accounts; a free Apple ID works), so the permission survives reinstalls. Xcode stores the team id under `IDEProvisioningTeams` in `defaults read com.apple.dt.Xcode`.
- `CODESIGN_IDENTITY="Developer ID Application: …" scripts/release.sh` signs the DMG build for distribution; add `NOTARY_PROFILE=<profile>` to notarize it.

### Releasing

```bash
macos/scripts/release.sh
gh release create vX.Y.Z macos/dist/Rephrase-X.Y.Z.dmg --title "Rephrase X.Y.Z" --notes "..."
```

Bump `MARKETING_VERSION` in `macos/project.yml` first.

### Screenshots

Debug builds have a demo mode that renders the real popup with a live rewrite over a sample document, in a window behind everything else, and prints its window id for `screencapture -l`. See `macos/Rephrase/DemoMode.swift`.
