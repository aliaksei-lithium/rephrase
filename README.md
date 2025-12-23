# Rephrase Tool

A web application for rephrasing text using DeepL API, deployed on Cloudflare Pages.

## Cloudflare Pages Deployment

1. Push this repository to GitHub
2. Connect your GitHub repository to Cloudflare Pages
3. Configure build settings:
   - **Build command**: (leave EMPTY - do not set any command)
   - **Build output directory**: `/` (root)
   - **Root directory**: `/` (root)
4. Deploy!

**Important**: Do NOT set a build command. Cloudflare Pages will automatically serve your static files and functions.

## Local Development

Test locally using Wrangler:

```bash
npm install -g wrangler
wrangler pages dev .
```
