import { authenticate } from '../../lib/auth.js';
import { demoEnabled, demoStatus } from '../../lib/demo.js';
import { json } from '../../lib/http.js';

// GET -> { authenticated, demo, demo_available, expires_at } ; never 401 so the UI can decide what to show.
// A demo session also gets demo_status: { left_for_you, budget_left, max_chars, model }.
export async function onRequest(context) {
    const { request, env } = context;
    const headers = { 'Cache-Control': 'no-store' };
    if (!env.APP_PASSWORD) {
        return json({ authenticated: false, configured: false, demo_available: false }, 200, headers);
    }
    const session = await authenticate(request, env);
    const body = {
        authenticated: Boolean(session),
        configured: true,
        demo: Boolean(session?.demo),
        demo_available: demoEnabled(env),
        expires_at: session ? new Date(session.exp * 1000).toISOString() : null,
    };
    if (session?.demo && body.demo_available) {
        try {
            body.demo_status = await demoStatus(request, env);
        } catch {
            /* the counter is optional for this response */
        }
    }
    return json(body, 200, headers);
}
