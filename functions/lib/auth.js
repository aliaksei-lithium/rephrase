// Stateless session tokens: base64url(payload) + "." + base64url(HMAC-SHA256(secret, payloadB64)).
// The same token is accepted either as an HttpOnly cookie (browser) or as
// "Authorization: Bearer <token>" (desktop app or scripts).

const COOKIE_NAME = 'rephrase_session';
const DEFAULT_SESSION_DAYS = 180;

const encoder = new TextEncoder();

function b64url(bytes) {
    let s = '';
    for (const b of bytes) s += String.fromCharCode(b);
    return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function b64urlDecode(str) {
    const pad = str.length % 4 === 0 ? '' : '='.repeat(4 - (str.length % 4));
    const s = str.replace(/-/g, '+').replace(/_/g, '/') + pad;
    const bin = atob(s);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
}

function secretOf(env) {
    return env.AUTH_SECRET || env.APP_PASSWORD || '';
}

async function hmacKey(secret) {
    return crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
}

async function sign(secret, data) {
    const key = await hmacKey(secret);
    const sig = await crypto.subtle.sign('HMAC', key, encoder.encode(data));
    return b64url(new Uint8Array(sig));
}

function constantTimeEqual(a, b) {
    if (a.length !== b.length) return false;
    let diff = 0;
    for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
    return diff === 0;
}

export function sessionDays(env) {
    const n = Number(env.SESSION_DAYS);
    return Number.isFinite(n) && n > 0 ? n : DEFAULT_SESSION_DAYS;
}

export async function verifyPassword(env, candidate) {
    const expected = env.APP_PASSWORD;
    if (!expected || typeof candidate !== 'string') return false;
    // Hash both sides so the comparison length does not leak the password length.
    const [a, b] = await Promise.all([
        crypto.subtle.digest('SHA-256', encoder.encode(candidate)),
        crypto.subtle.digest('SHA-256', encoder.encode(expected)),
    ]);
    return constantTimeEqual(b64url(new Uint8Array(a)), b64url(new Uint8Array(b)));
}

export async function issueToken(env) {
    const now = Math.floor(Date.now() / 1000);
    const payload = { v: 1, iat: now, exp: now + sessionDays(env) * 86400 };
    const payloadB64 = b64url(encoder.encode(JSON.stringify(payload)));
    const sig = await sign(secretOf(env), payloadB64);
    return { token: `${payloadB64}.${sig}`, payload };
}

export async function verifyToken(env, token) {
    if (typeof token !== 'string' || !token.includes('.')) return null;
    const [payloadB64, sig] = token.split('.');
    if (!payloadB64 || !sig) return null;
    const expected = await sign(secretOf(env), payloadB64);
    if (!constantTimeEqual(expected, sig)) return null;
    let payload;
    try {
        payload = JSON.parse(new TextDecoder().decode(b64urlDecode(payloadB64)));
    } catch {
        return null;
    }
    if (!payload || payload.v !== 1 || typeof payload.exp !== 'number') return null;
    if (payload.exp <= Math.floor(Date.now() / 1000)) return null;
    return payload;
}

export function readCookie(request, name = COOKIE_NAME) {
    const header = request.headers.get('Cookie') || '';
    for (const part of header.split(';')) {
        const [k, ...v] = part.trim().split('=');
        if (k === name) return decodeURIComponent(v.join('='));
    }
    return null;
}

export function tokenFromRequest(request) {
    const auth = request.headers.get('Authorization') || '';
    if (auth.toLowerCase().startsWith('bearer ')) return auth.slice(7).trim();
    return readCookie(request);
}

export async function authenticate(request, env) {
    const token = tokenFromRequest(request);
    if (!token) return null;
    return verifyToken(env, token);
}

export function sessionCookie(request, env, token) {
    const secure = new URL(request.url).protocol === 'https:' ? '; Secure' : '';
    const maxAge = sessionDays(env) * 86400;
    return `${COOKIE_NAME}=${encodeURIComponent(token)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAge}${secure}`;
}

export function clearCookie(request) {
    const secure = new URL(request.url).protocol === 'https:' ? '; Secure' : '';
    return `${COOKIE_NAME}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0${secure}`;
}
