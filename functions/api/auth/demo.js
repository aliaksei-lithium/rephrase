import { issueToken, sessionCookie } from '../../lib/auth.js';
import { demoConfig, demoEnabled } from '../../lib/demo.js';
import { error, json } from '../../lib/http.js';

// POST -> a demo session (cookie + token), no password. Demo sessions only get the free
// Gemma model and share a daily budget; see functions/lib/demo.js.
export async function onRequestPost(context) {
    const { request, env } = context;
    if (!demoEnabled(env)) return error('The demo is not available on this server', 404, { code: 'demo_disabled' });

    const days = demoConfig(env).sessionDays;
    const { token, payload } = await issueToken(env, { demo: true, days });
    return json(
        { ok: true, token, demo: true, expires_at: new Date(payload.exp * 1000).toISOString() },
        200,
        { 'Set-Cookie': sessionCookie(request, env, token, days), 'Cache-Control': 'no-store' }
    );
}

export async function onRequest(context) {
    if (context.request.method === 'POST') return onRequestPost(context);
    return error('Method not allowed', 405);
}
