import { authenticate } from '../../lib/auth.js';
import { json } from '../../lib/http.js';

// GET -> { authenticated, expires_at } ; never 401 so the UI can decide what to show.
export async function onRequest(context) {
    const { request, env } = context;
    if (!env.APP_PASSWORD) {
        return json({ authenticated: false, configured: false }, 200, { 'Cache-Control': 'no-store' });
    }
    const session = await authenticate(request, env);
    return json(
        {
            authenticated: Boolean(session),
            configured: true,
            expires_at: session ? new Date(session.exp * 1000).toISOString() : null,
        },
        200,
        { 'Cache-Control': 'no-store' }
    );
}
