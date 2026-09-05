import { anthropicKey } from './models.js';

const ANTHROPIC_DEFAULT_BASE = 'https://api.anthropic.com';
const UPSTREAM_TIMEOUT_MS = 60_000;

export class UpstreamError extends Error {
    constructor(message, { status = 502, details = null, retryable = false } = {}) {
        super(message);
        this.name = 'UpstreamError';
        this.status = status;
        this.details = details;
        this.retryable = retryable;
    }
}

// Splits a byte stream into SSE events and yields { event, data } objects.
async function* sseEvents(body) {
    const reader = body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';
    while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        let idx;
        while ((idx = buffer.indexOf('\n\n')) !== -1) {
            const chunk = buffer.slice(0, idx);
            buffer = buffer.slice(idx + 2);
            let event = 'message';
            const dataLines = [];
            for (const line of chunk.split('\n')) {
                if (line.startsWith('event:')) event = line.slice(6).trim();
                else if (line.startsWith('data:')) dataLines.push(line.slice(5).trimStart());
            }
            if (dataLines.length) yield { event, data: dataLines.join('\n') };
        }
    }
}

function withTimeout(signal) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(new Error('Upstream timeout')), UPSTREAM_TIMEOUT_MS);
    if (signal) signal.addEventListener('abort', () => controller.abort(signal.reason), { once: true });
    return { signal: controller.signal, clear: () => clearTimeout(timer) };
}

/**
 * Streams text deltas from the Anthropic Messages API, optionally through
 * Cloudflare AI Gateway (set ANTHROPIC_BASE_URL to the gateway's anthropic endpoint).
 * Yields { type: 'delta', text } and finally { type: 'done', usage, stop_reason }.
 */
export async function* anthropicStream({ env, model, system, user, signal }) {
    const key = anthropicKey(env);
    const base = (env.ANTHROPIC_BASE_URL || ANTHROPIC_DEFAULT_BASE).replace(/\/+$/, '');

    const headers = {
        'Content-Type': 'application/json',
        'anthropic-version': '2023-06-01',
    };
    if (key) headers['x-api-key'] = key;
    // Organization-level keys (not scoped to a workspace) must name the workspace to bill.
    if (env.ANTHROPIC_WORKSPACE_ID) headers['anthropic-workspace-id'] = env.ANTHROPIC_WORKSPACE_ID;
    if (env.AI_GATEWAY_TOKEN) headers['cf-aig-authorization'] = `Bearer ${env.AI_GATEWAY_TOKEN}`;
    if (!key && !env.AI_GATEWAY_TOKEN) {
        throw new UpstreamError('No Anthropic credentials configured', { status: 500 });
    }

    const body = {
        model: model.id,
        max_tokens: 8192,
        stream: true,
        system,
        messages: [{ role: 'user', content: user }],
    };
    if (model.effort) body.output_config = { effort: model.effort };
    if (model.fallbacks) {
        body.fallbacks = 'default';
        headers['anthropic-beta'] = 'server-side-fallback-2026-07-01';
    }

    const t = withTimeout(signal);
    let res;
    try {
        res = await fetch(`${base}/v1/messages`, { method: 'POST', headers, body: JSON.stringify(body), signal: t.signal });
    } catch (e) {
        t.clear();
        throw new UpstreamError(`Could not reach Anthropic: ${e.message}`, { retryable: true });
    }

    if (!res.ok) {
        t.clear();
        const text = await res.text();
        let details = text;
        try {
            details = JSON.parse(text);
        } catch {
            /* keep text */
        }
        const retryable = res.status === 429 || res.status >= 500 || res.status === 529;
        const msg = details?.error?.message || `Anthropic API error ${res.status}`;
        throw new UpstreamError(msg, { status: res.status, details, retryable });
    }

    const usage = { input_tokens: 0, output_tokens: 0 };
    let stopReason = null;
    let stopDetails = null;
    try {
        for await (const { event, data } of sseEvents(res.body)) {
            if (data === '[DONE]') break;
            let msg;
            try {
                msg = JSON.parse(data);
            } catch {
                continue;
            }
            switch (event || msg.type) {
                case 'message_start':
                    if (msg.message?.usage) usage.input_tokens = msg.message.usage.input_tokens || 0;
                    break;
                case 'content_block_delta':
                    if (msg.delta?.type === 'text_delta' && msg.delta.text) yield { type: 'delta', text: msg.delta.text };
                    break;
                case 'message_delta':
                    if (msg.delta?.stop_reason) stopReason = msg.delta.stop_reason;
                    if (msg.delta?.stop_details) stopDetails = msg.delta.stop_details;
                    if (msg.usage?.output_tokens) usage.output_tokens = msg.usage.output_tokens;
                    break;
                case 'error':
                    throw new UpstreamError(msg.error?.message || 'Anthropic stream error', { details: msg.error });
                default:
                    break;
            }
        }
    } finally {
        t.clear();
    }

    if (stopReason === 'refusal') {
        throw new UpstreamError('The model declined to process this text', {
            status: 422,
            details: { stop_reason: stopReason, stop_details: stopDetails },
        });
    }
    if (stopReason === 'max_tokens') {
        throw new UpstreamError('The answer was cut off (max_tokens). Try a shorter text.', { status: 422 });
    }

    yield { type: 'done', usage, stop_reason: stopReason };
}

/**
 * Streams text from a Workers AI text-generation model via the AI binding.
 */
export async function* workersAiStream({ env, model, system, user, signal }) {
    if (!env.AI) throw new UpstreamError('Workers AI binding (AI) is not configured', { status: 500 });

    let stream;
    try {
        stream = await env.AI.run(model.id, {
            messages: [
                { role: 'system', content: system },
                { role: 'user', content: user },
            ],
            stream: true,
            // Reasoning models spend most of this on thinking before the answer.
            max_tokens: 8192,
        }, { signal });
    } catch (e) {
        throw new UpstreamError(`Workers AI error: ${e.message}`, { retryable: true });
    }

    // Workers AI streams either {response} chunks (older models) or OpenAI-style
    // chat.completion.chunk objects; reasoning deltas are skipped, usage is per chunk.
    const usage = { input_tokens: 0, output_tokens: 0 };
    for await (const { data } of sseEvents(stream)) {
        if (data === '[DONE]') break;
        let msg;
        try {
            msg = JSON.parse(data);
        } catch {
            continue;
        }
        const text = typeof msg.response === 'string' ? msg.response : msg.choices?.[0]?.delta?.content;
        if (text) yield { type: 'delta', text };
        if (msg.usage) {
            usage.input_tokens = Math.max(usage.input_tokens, msg.usage.prompt_tokens || 0);
            usage.output_tokens += msg.usage.completion_tokens || 0;
        }
    }
    yield { type: 'done', usage, stop_reason: 'end_turn' };
}

export function streamFor(model) {
    return model.provider === 'workersai' ? workersAiStream : anthropicStream;
}
