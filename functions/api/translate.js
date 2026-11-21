import { error, json } from '../lib/http.js';
import { listLanguages, sameLanguage, translateEnabled, TranslateError, translateText } from '../lib/translate.js';

const MAX_CHARS = 12_000;
const CODE = /^[a-zA-Z]{2,3}(-[a-zA-Z0-9]{2,4})?$/;

function guard(context) {
    if (context.data?.session?.demo) {
        return error('Translation is not part of the demo. Sign in with the password.', 403, { code: 'demo_not_allowed' });
    }
    if (!translateEnabled(context.env)) {
        return error('Translation is not configured on the server (GOOGLE_TRANSLATE_API_KEY)', 503, { code: 'not_configured' });
    }
    return null;
}

function fail(err) {
    if (err instanceof TranslateError) return error(err.message, err.status, { code: 'upstream' });
    return error('Translation failed', 502, { code: 'upstream' });
}

/** GET /api/translate -> { languages: [{ code, name }] } */
export async function onRequestGet(context) {
    const blocked = guard(context);
    if (blocked) return blocked;
    try {
        return json({ languages: await listLanguages(context.env) });
    } catch (err) {
        return fail(err);
    }
}

/**
 * POST /api/translate
 * body: { text, target, alternate? }
 *   text       plain text (required)
 *   target     language code to translate into, e.g. "en", "de", "zh-CN" (required)
 *   alternate  optional code used instead when the text is already in the target language
 * -> { text, source, target }   source is the detected language
 */
export async function onRequestPost(context) {
    const blocked = guard(context);
    if (blocked) return blocked;

    let body;
    try {
        body = await context.request.json();
    } catch {
        return error('Invalid JSON body');
    }

    const text = typeof body.text === 'string' ? body.text : '';
    if (!text.trim()) return error('Text is required');
    if (text.length > MAX_CHARS) {
        return error(`Text is too long (max ${MAX_CHARS} characters)`, 413, { code: 'too_long', max_chars: MAX_CHARS });
    }
    const target = typeof body.target === 'string' && CODE.test(body.target) ? body.target : null;
    if (!target) return error('target must be a language code such as "en"');
    const alternate = typeof body.alternate === 'string' && CODE.test(body.alternate) && !sameLanguage(body.alternate, target)
        ? body.alternate
        : null;

    try {
        const first = await translateText(context.env, text, target);
        if (alternate && sameLanguage(first.source, target)) {
            const second = await translateText(context.env, text, alternate, first.source);
            return json({ text: second.text, source: first.source, target: alternate });
        }
        return json({ text: first.text, source: first.source, target });
    } catch (err) {
        return fail(err);
    }
}
