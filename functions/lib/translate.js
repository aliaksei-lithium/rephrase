// Google Cloud Translation (Basic, v2) with an API key: GOOGLE_TRANSLATE_API_KEY.
// The key goes in the X-Goog-Api-Key header, never in the URL.

const API = 'https://translation.googleapis.com/language/translate/v2';

export class TranslateError extends Error {
    constructor(message, status = 502) {
        super(message);
        this.status = status;
    }
}

export function translateEnabled(env) {
    return Boolean(env.GOOGLE_TRANSLATE_API_KEY);
}

async function call(env, path, init = {}) {
    const res = await fetch(`${API}${path}`, {
        ...init,
        headers: { 'Content-Type': 'application/json', 'X-Goog-Api-Key': env.GOOGLE_TRANSLATE_API_KEY },
    });
    const data = await res.json().catch(() => null);
    if (!res.ok) {
        const message = data?.error?.message || `Google Translate returned ${res.status}`;
        // 400 from Google is a bad language code or text; anything else is an upstream problem.
        throw new TranslateError(message, res.status === 400 ? 400 : 502);
    }
    return data?.data;
}

/** One translation. source omitted: Google detects it. Returns { text, source }. */
export async function translateText(env, text, target, source) {
    const body = { q: text, target, format: 'text' };
    if (source) body.source = source;
    const data = await call(env, '', { method: 'POST', body: JSON.stringify(body) });
    const item = data?.translations?.[0];
    if (!item) throw new TranslateError('Google Translate returned no text');
    return { text: item.translatedText, source: item.detectedSourceLanguage || source || null };
}

let languageCache = null;

/** Supported languages with English names, cached per isolate. */
export async function listLanguages(env) {
    if (languageCache) return languageCache;
    const data = await call(env, '/languages?target=en');
    languageCache = (data?.languages || [])
        .map((l) => ({ code: l.language, name: l.name || l.language }))
        .sort((a, b) => a.name.localeCompare(b.name));
    return languageCache;
}

/** "en-US" and "en" are the same language for the "already in the target" check; "zh-CN" and "zh-TW" are not. */
export function sameLanguage(a, b) {
    if (!a || !b) return false;
    const norm = (code) => {
        const lower = code.toLowerCase();
        return lower.startsWith('zh') ? lower : lower.split('-')[0];
    };
    return norm(a) === norm(b);
}
