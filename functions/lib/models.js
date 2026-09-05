// Models the UI may pick from. Prices are USD per 1M tokens (input / output) and
// only feed the cost estimate shown in the UI.
export const MODELS = [
    {
        id: 'claude-sonnet-5',
        label: 'Claude Sonnet 5',
        hint: 'fast, good value',
        provider: 'anthropic',
        effort: 'low',
        price: { input: 2, output: 10 },
    },
    {
        id: 'claude-opus-5',
        label: 'Claude Opus 5',
        hint: 'best quality',
        provider: 'anthropic',
        effort: 'low',
        fallbacks: true,
        price: { input: 5, output: 25 },
    },
    {
        id: 'claude-haiku-4-5',
        label: 'Claude Haiku 4.5',
        hint: 'cheapest',
        provider: 'anthropic',
        price: { input: 1, output: 5 },
    },
    {
        id: '@cf/google/gemma-4-26b-a4b-it',
        label: 'Gemma 4 26B',
        hint: 'free, Workers AI',
        provider: 'workersai',
        price: { input: 0, output: 0 },
    },
];

export const DEFAULT_MODEL_ID = 'claude-sonnet-5';

export function findModel(id) {
    return MODELS.find((m) => m.id === id) || null;
}

export function availableModels(env) {
    const hasAnthropic = Boolean(anthropicKey(env) || env.AI_GATEWAY_TOKEN);
    const hasWorkersAi = Boolean(env.AI);
    return MODELS.filter((m) => (m.provider === 'anthropic' ? hasAnthropic : hasWorkersAi)).map(
        ({ id, label, hint, provider, price }) => ({ id, label, hint, provider, price })
    );
}

export function anthropicKey(env) {
    return env.ANTHROPIC_API_KEY || env.anthropic_key || env.ANTHROPIC_KEY || '';
}
