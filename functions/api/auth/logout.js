import { clearCookie } from '../../lib/auth.js';
import { json } from '../../lib/http.js';

export async function onRequest(context) {
    return json({ ok: true }, 200, { 'Set-Cookie': clearCookie(context.request), 'Cache-Control': 'no-store' });
}
