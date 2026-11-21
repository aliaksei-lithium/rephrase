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

`npm run deploy` deploys from your machine instead.

The production site is `https://rephrase.aliaksei.xyz`, a custom domain on the `rephrase` Pages project (Workers & Pages > rephrase > Custom domains); `rephrase-eey.pages.dev` keeps working. The macOS app defaults to the custom domain.

### API

All routes live under `/api`. Everything except `/api/auth/*` needs a session: the `rephrase_session` cookie set by login, or `Authorization: Bearer <token>`.

| Route | Method | Body / result |
| --- | --- | --- |
| `/api/auth/login` | POST | `{ "password" }` → `{ ok, token, expires_at }` and sets the cookie |
| `/api/auth/logout` | POST | clears the cookie |
| `/api/auth/me` | GET | `{ authenticated, configured, expires_at }` |
| `/api/models` | GET | `{ models, default, modes, styles, tones, languages, formats }` |
| `/api/rephrase` | POST | `{ text, mode, style, tone, language, format (markdown/plain), model, stream }` → SSE stream, or JSON with `stream: false` |

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
