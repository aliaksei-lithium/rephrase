# Rephrase Tool

A small web app that fixes or lightly rephrases messages with Claude while keeping your own voice and your formatting (bold, lists, code, links pasted from Slack). Runs on Cloudflare Pages with Pages Functions.
Live at https://rephrase-eey.pages.dev/.

<img width="1457" height="672" alt="image" src="https://github.com/user-attachments/assets/9ff6af32-7860-4bdf-88a1-94afdca480bc" />

## Features

- **Simple** mode: fixes typos, grammar, tense, articles, word order and clearly wrong words. Nothing else.
- **Default** mode: light, idiomatic rephrase that keeps sentence order, length and personality.
- Optional style (casual, business, academic) and tone (friendly, confident, diplomatic, enthusiastic).
- Language: Auto keeps the input language; English or German forces the output language (and translates if the input is in the other one) with language-specific writing rules.
- Rich-text input: paste from Slack, Gmail, Docs. Output keeps the formatting; changed words are underlined.
- Copy back with formatting (HTML + plain text) or as Markdown.
- Model picker: Claude Sonnet 5 (default), Opus 5, Haiku 4.5, or the free Gemma model on Workers AI.
- Password login with a long-lived session cookie. The same token works as a Bearer header for scripts or a desktop app.
- Streams the answer as it is generated. Shows tokens and an estimated cost per request.

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
| `/api/rephrase` | POST | `{ text (Markdown), mode, style, tone, language (auto/en/de), model, stream }` |

## Prompts

Prompts live in `functions/lib/prompts.js`. A shared base prompt pins language, meaning, formatting and voice; the mode, style and tone blocks are appended. Tune them against real messages and check both modes after every change.
