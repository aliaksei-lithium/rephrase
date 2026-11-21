// Public demo: anyone can get a demo session without the password. Demo sessions may only
// use the free Gemma model on Workers AI, and a shared daily budget in D1 keeps all demo
// traffic together inside the Workers AI free allocation (10,000 neurons per day, reset at
// 00:00 UTC).
//
// Each request reserves its worst case (input estimate + max output) before it runs, and the
// unused part is given back once the real token usage is known, so concurrent requests can
// never push the day over the budget.

export const DEMO_MODEL_ID = '@cf/google/gemma-4-26b-a4b-it';

// Workers AI price for Gemma 4 26B A4B, neurons per token.
const NEURONS_PER_INPUT_TOKEN = 9091 / 1e6;
const NEURONS_PER_OUTPUT_TOKEN = 27273 / 1e6;

const DEFAULTS = {
    // Leaves room under the 10,000 free neurons for the owner's own Gemma use and fallbacks.
    neuronsPerDay: 6000,
    requestsPerClient: 30,
    maxChars: 2000,
    maxOutputTokens: 3072,
    sessionDays: 30,
};

function num(value, fallback) {
    const n = Number(value);
    return Number.isFinite(n) && n > 0 ? n : fallback;
}

export function demoConfig(env) {
    return {
        neuronsPerDay: num(env.DEMO_NEURONS_PER_DAY, DEFAULTS.neuronsPerDay),
        requestsPerClient: num(env.DEMO_REQUESTS_PER_CLIENT, DEFAULTS.requestsPerClient),
        maxChars: num(env.DEMO_MAX_CHARS, DEFAULTS.maxChars),
        maxOutputTokens: num(env.DEMO_MAX_OUTPUT_TOKENS, DEFAULTS.maxOutputTokens),
        sessionDays: num(env.DEMO_SESSION_DAYS, DEFAULTS.sessionDays),
    };
}

/** The demo needs the Workers AI binding and the D1 counter; DEMO_ENABLED = "false" turns it off. */
export function demoEnabled(env) {
    return Boolean(env.AI && env.DEMO_DB && env.APP_PASSWORD) && String(env.DEMO_ENABLED ?? 'true') !== 'false';
}

export function neuronsFor(usage) {
    if (!usage) return null;
    const input = Number(usage.input_tokens) || 0;
    const output = Number(usage.output_tokens) || 0;
    if (!input && !output) return null;
    return input * NEURONS_PER_INPUT_TOKEN + output * NEURONS_PER_OUTPUT_TOKEN;
}

/** Worst case for one request. Characters / 3 overestimates tokens for English and German. */
export function worstCaseNeurons(promptChars, env) {
    const { maxOutputTokens } = demoConfig(env);
    return Math.ceil(promptChars / 3) * NEURONS_PER_INPUT_TOKEN + maxOutputTokens * NEURONS_PER_OUTPUT_TOKEN;
}

function today() {
    return new Date().toISOString().slice(0, 10);
}

let schemaReady = false;
async function ensureSchema(db) {
    if (schemaReady) return;
    await db.batch([
        db.prepare('CREATE TABLE IF NOT EXISTS demo_usage (day TEXT PRIMARY KEY, neurons REAL NOT NULL DEFAULT 0, requests INTEGER NOT NULL DEFAULT 0)'),
        db.prepare('CREATE TABLE IF NOT EXISTS demo_clients (day TEXT NOT NULL, client TEXT NOT NULL, requests INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (day, client))'),
    ]);
    schemaReady = true;
}

/** A per-day, non-reversible id for the caller's IP; the IP itself is never stored. */
async function clientId(request, env, day) {
    const ip = request.headers.get('CF-Connecting-IP') || request.headers.get('X-Forwarded-For') || 'local';
    const secret = env.AUTH_SECRET || env.APP_PASSWORD || '';
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`${secret}|${day}|${ip}`));
    return [...new Uint8Array(digest).slice(0, 12)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export class DemoLimitError extends Error {
    constructor(message, code) {
        super(message);
        this.code = code;
    }
}

/**
 * Reserves budget for one demo request. Returns { settle(usage), status } or throws DemoLimitError.
 * settle() must be called once the request ends (with null usage on failure before any output).
 */
export async function reserveDemo(request, env, promptChars) {
    const db = env.DEMO_DB;
    const config = demoConfig(env);
    await ensureSchema(db);
    const day = today();
    const client = await clientId(request, env, day);
    const reserve = worstCaseNeurons(promptChars, env);

    const perClient = await db
        .prepare(
            `INSERT INTO demo_clients (day, client, requests) VALUES (?1, ?2, 1)
             ON CONFLICT (day, client) DO UPDATE SET requests = requests + 1 WHERE requests < ?3
             RETURNING requests`
        )
        .bind(day, client, config.requestsPerClient)
        .first();
    if (!perClient) {
        throw new DemoLimitError(
            `You have used today's ${config.requestsPerClient} demo rewrites. Come back after 00:00 UTC, or sign in.`,
            'demo_client_limit'
        );
    }

    const global = await db
        .prepare(
            `INSERT INTO demo_usage (day, neurons, requests) SELECT ?1, ?2, 1 WHERE ?2 <= ?3
             ON CONFLICT (day) DO UPDATE SET neurons = neurons + ?2, requests = requests + 1 WHERE neurons + ?2 <= ?3
             RETURNING neurons`
        )
        .bind(day, reserve, config.neuronsPerDay)
        .first();
    if (!global) {
        await db.prepare('UPDATE demo_clients SET requests = requests - 1 WHERE day = ?1 AND client = ?2').bind(day, client).run();
        throw new DemoLimitError('The free demo has used up today\'s quota. Come back after 00:00 UTC, or sign in.', 'demo_limit');
    }

    // Old rows are only useful for today; drop them now and then.
    if (Math.random() < 0.02) {
        await db.batch([
            db.prepare('DELETE FROM demo_usage WHERE day < ?1').bind(day),
            db.prepare('DELETE FROM demo_clients WHERE day < ?1').bind(day),
        ]);
    }

    let settled = false;
    return {
        status: {
            left_for_you: Math.max(0, config.requestsPerClient - perClient.requests),
            budget_left: Math.max(0, 1 - global.neurons / config.neuronsPerDay),
        },
        /** Gives back what the request did not use. Without usage, a request that produced
         * nothing is refunded fully and one that produced text keeps its whole reservation. */
        async settle(usage, { produced = true } = {}) {
            if (settled) return;
            settled = true;
            const used = neuronsFor(usage);
            const refund = used !== null ? Math.max(0, reserve - used) : produced ? 0 : reserve;
            const stmts = [];
            if (refund > 0) {
                stmts.push(db.prepare('UPDATE demo_usage SET neurons = MAX(0, neurons - ?2) WHERE day = ?1').bind(day, refund));
            }
            if (!produced) {
                stmts.push(db.prepare('UPDATE demo_clients SET requests = requests - 1 WHERE day = ?1 AND client = ?2').bind(day, client));
            }
            if (stmts.length) await db.batch(stmts);
        },
    };
}

/** Today's numbers for the caller, for the UI. */
export async function demoStatus(request, env) {
    const db = env.DEMO_DB;
    const config = demoConfig(env);
    await ensureSchema(db);
    const day = today();
    const client = await clientId(request, env, day);
    const [usage, mine] = await Promise.all([
        db.prepare('SELECT neurons FROM demo_usage WHERE day = ?1').bind(day).first(),
        db.prepare('SELECT requests FROM demo_clients WHERE day = ?1 AND client = ?2').bind(day, client).first(),
    ]);
    return {
        left_for_you: Math.max(0, config.requestsPerClient - (mine?.requests || 0)),
        budget_left: Math.max(0, 1 - (usage?.neurons || 0) / config.neuronsPerDay),
        max_chars: config.maxChars,
        model: DEMO_MODEL_ID,
    };
}
