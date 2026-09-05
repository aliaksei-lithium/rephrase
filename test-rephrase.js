// Smoke test against a local `npm run dev` server.
// Usage: APP_PASSWORD=dev-password node test-rephrase.js [model]
const BASE = process.env.BASE_URL || 'http://localhost:8788';
const PASSWORD = process.env.APP_PASSWORD || 'dev-password';
const MODEL = process.argv[2];

const cases = [
    {
        name: 'Simple mode keeps structure, fixes errors',
        body: { mode: 'simple', text: 'hi team, i have send the report yesterday but the numbers was wrong, i will fix it until tomorrow. **important:** please dont merge PR-123 before.' },
    },
    {
        name: 'Default mode with formatting',
        body: {
            mode: 'default',
            text: 'Quick update:\n- the deploy is done\n- i seen some errors in logs, looks like `redis` timeout\n- eventually we need to increase the limit, what you think?\n\n> original alert: _connection reset_',
        },
    },
    {
        name: 'German stays German',
        body: { mode: 'simple', text: 'Ich habe gestern die Bericht geschickt aber die Zahlen war falsch.' },
    },
];

async function login() {
    const res = await fetch(`${BASE}/api/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password: PASSWORD }),
    });
    if (!res.ok) throw new Error(`login failed: ${res.status} ${await res.text()}`);
    return (await res.json()).token;
}

async function main() {
    const token = await login();
    const auth = { Authorization: `Bearer ${token}` };

    const models = await (await fetch(`${BASE}/api/models`, { headers: auth })).json();
    console.log('Models:', models.models.map((m) => m.id).join(', '), '| default:', models.default);
    const model = MODEL || models.default;

    for (const c of cases) {
        console.log(`\n=== ${c.name} (${model}) ===`);
        console.log('IN :', JSON.stringify(c.body.text));
        const res = await fetch(`${BASE}/api/rephrase`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', ...auth },
            body: JSON.stringify({ ...c.body, model, stream: false }),
        });
        const data = await res.json();
        if (!res.ok) {
            console.log('ERR:', res.status, JSON.stringify(data));
            continue;
        }
        console.log('OUT:', JSON.stringify(data.text));
        console.log('usage:', data.usage, 'provider:', data.provider);
    }
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
