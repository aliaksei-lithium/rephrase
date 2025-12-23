# Agents Guide

## Project Overview

Rephrase tool built with Cloudflare Pages - static frontend with serverless functions.

## Structure

- `index.html`, `style.css`, `script.js` - Static frontend files
- `functions/api/` - Cloudflare Pages Functions (serverless API endpoints)
- `wrangler.toml` - Cloudflare Pages configuration

## Key Conventions

- Cloudflare Pages Functions use `onRequest()` export
- Functions in `functions/api/hello.js` map to `/api/hello` endpoint
- No build step required - static files served directly
- Test locally with `wrangler pages dev .`

## Tech Stack

- Frontend: Vanilla HTML/CSS/JS
- Backend: Cloudflare Pages Functions
- Deployment: Cloudflare Pages (GitHub integration)

