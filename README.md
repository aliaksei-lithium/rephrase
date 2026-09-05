# Rephrase Tool

A small web app that fixes or lightly rephrases messages with Claude while keeping your own voice and your formatting (bold, lists, code, links pasted from Slack). Runs on Cloudflare Pages with Pages Functions. Live at https://rephrase-eey.pages.dev/.

## Features

- **Simple** mode: fixes typos, grammar, tense, articles, word order and clearly wrong words. Nothing else.
- **Default** mode: light, idiomatic rephrase that keeps sentence order, length and personality.
- Optional style (casual, business, academic) and tone (friendly, confident, diplomatic, enthusiastic).
- Rich-text input: paste from Slack, Gmail, Docs. Output keeps the formatting; changed words are underlined.
- Copy back with formatting (HTML + plain text) or as Markdown.
- Model picker: Claude Sonnet 5 (default), Opus 5, Haiku 4.5, or the free Gemma model on Workers AI.
- Password login with a long-lived session cookie. The same token works as a Bearer header for scripts or a desktop app.
- Streams the answer as it is generated. Shows tokens and an estimated cost per request.

## Configuration

Secrets and variables, set in the Pages project (Settings > Variables and secrets) or with `wrangler pages secret put NAME --project-name calm-hat-f6c5`:

| Name | Required | Purpose |
| --- | --- | --- |
| `APP_PASSWORD` | yes | Login password. Changing it signs everyone out unless `AUTH_SECRET` is set. |
| `ANTHROPIC_API_KEY` | yes for Claude | Anthropic Console API key (`anthropic_key` is accepted too). |
| `ANTHROPIC_WORKSPACE_ID` | sometimes | Needed when the key is an organization-level key and the API answers "not scoped to a workspace". |
| `AUTH_SECRET` | no | Separate signing secret for session tokens. |
| `SESSION_DAYS` | no | Session length, default 180. |
| `ANTHROPIC_MODEL` | no | Default model id, default `claude-sonnet-5`. |
| `ANTHROPIC_BASE_URL` | no | Set to `https://gateway.ai.cloudflare.com/v1/<ACCOUNT_ID>/<GATEWAY>/anthropic` to route through Cloudflare AI Gateway (logs, caching, rate limits, spend caps). |
| `AI_GATEWAY_TOKEN` | no | Token for an authenticated gateway. With a gateway BYOK key stored under the `default` alias you can omit `ANTHROPIC_API_KEY`. |

The Workers AI binding `AI` is declared in `wrangler.toml` for the production and preview environments. It powers the free Gemma model and is the fallback when Anthropic returns a retryable error.

## Local development

```bash
npm install
ln -s local.env .env      # local.env holds anthropic_key=...; both files are git-ignored
cp .env.example .env.local # set APP_PASSWORD for local use
npm run dev                # http://localhost:8788
npm run dev:free           # same, plus the Workers AI binding (uses your account's free daily allocation)
```

Smoke test the API (logs in, lists models, runs three sample edits):

```bash
APP_PASSWORD=dev-password npm run test:api
```

Wrangler loads `.env` and `.env.local` as local variables. It ignores the `--env-file` flag for this purpose, which is why `.env` is a symlink.

## API

All routes live under `/api`. Everything except `/api/auth/*` needs a session: either the `rephrase_session` cookie set by login, or `Authorization: Bearer <token>`. Cross-origin calls are allowed with the Bearer header, so a desktop app can use the same endpoints.

| Route | Method | Body / result |
| --- | --- | --- |
| `/api/auth/login` | POST | `{ "password" }` → `{ ok, token, expires_at }` and sets the cookie |
| `/api/auth/logout` | POST | clears the cookie |
| `/api/auth/me` | GET | `{ authenticated, configured, expires_at }` |
| `/api/models` | GET | `{ models: [{ id, label, hint, provider, price }], default, modes, styles, tones }` |
| `/api/rephrase` | POST | `{ text (Markdown), mode, style, tone, model, stream }` |

With `stream: true` (default) the response is `text/event-stream` with `data:` JSON lines of type `delta`, `info`, `done` (carries `model`, `usage`) or `error`. With `stream: false` it returns `{ text, model, provider, usage }`.

## Deployment

The GitHub integration deploys every push to `main`. Do not set a build command; Pages serves the static files and bundles `functions/` itself. `wrangler.toml` is the source of truth for bindings and variables.

## Prompts

Prompts live in `functions/lib/prompts.js`. A shared base prompt pins language, meaning, formatting and voice; the mode, style and tone blocks are appended. Tune them against real messages and check both modes after every change.
