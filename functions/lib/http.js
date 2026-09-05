export function json(data, status = 200, extraHeaders = {}) {
    return new Response(JSON.stringify(data), {
        status,
        headers: { 'Content-Type': 'application/json; charset=utf-8', ...extraHeaders },
    });
}

export function error(message, status = 400, extra = {}) {
    return json({ error: message, ...extra }, status);
}

// CORS: any origin may call the API with a Bearer token (desktop app, scripts).
// Cookies are never shared cross-origin because credentials are not allowed.
export function withCors(response, request) {
    const origin = request.headers.get('Origin');
    if (!origin) return response;
    const res = new Response(response.body, response);
    res.headers.set('Access-Control-Allow-Origin', origin);
    res.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    res.headers.set('Access-Control-Max-Age', '86400');
    res.headers.append('Vary', 'Origin');
    return res;
}

export function preflight(request) {
    return withCors(new Response(null, { status: 204 }), request);
}
