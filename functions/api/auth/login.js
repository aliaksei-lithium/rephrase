import { issueToken, sessionCookie, verifyPassword } from '../../lib/auth.js';
import { error, json } from '../../lib/http.js';

// POST { password } -> sets the session cookie and also returns the token
// so non-browser clients can send it as "Authorization: Bearer <token>".
export async function onRequestPost(context) {
    const { request, env } = context;

    if (!env.APP_PASSWORD) {
        return error('APP_PASSWORD is not configured on the server', 500, { code: 'not_configured' });
    }

    let body;
    try {
        body = await request.json();
    } catch {
        return error('Invalid JSON body');
    }

    const ok = await verifyPassword(env, body?.password);
    if (!ok) {
        return error('Wrong password', 401, { code: 'bad_password' });
    }

    const { token, payload } = await issueToken(env);
    return json(
        { ok: true, token, expires_at: new Date(payload.exp * 1000).toISOString() },
        200,
        { 'Set-Cookie': sessionCookie(request, env, token), 'Cache-Control': 'no-store' }
    );
}

export async function onRequest(context) {
    if (context.request.method === 'POST') return onRequestPost(context);
    return error('Method not allowed', 405);
}
