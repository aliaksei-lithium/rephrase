import { authenticate } from '../lib/auth.js';
import { error, preflight, withCors } from '../lib/http.js';

// Applies to every /api/* route. Login/logout/me are public; everything else needs a session.
export async function onRequest(context) {
    const { request, env, next } = context;
    const { pathname } = new URL(request.url);

    if (request.method === 'OPTIONS') return preflight(request);

    if (pathname.startsWith('/api/auth/')) {
        return withCors(await next(), request);
    }

    if (!env.APP_PASSWORD) {
        return withCors(error('APP_PASSWORD is not configured on the server', 500, { code: 'not_configured' }), request);
    }

    const session = await authenticate(request, env);
    if (!session) {
        return withCors(error('Sign in required', 401, { code: 'unauthorized' }), request);
    }

    context.data.session = session;
    return withCors(await next(), request);
}
