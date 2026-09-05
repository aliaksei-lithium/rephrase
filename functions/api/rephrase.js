import { error, json } from '../lib/http.js';
import { availableModels, DEFAULT_MODEL_ID, findModel } from '../lib/models.js';
import { buildSystemPrompt, cleanOutput, MODES, STYLES, TONES, wrapText } from '../lib/prompts.js';
import { streamFor, UpstreamError } from '../lib/providers.js';

const MAX_CHARS = 12_000;

function pick(value, allowed, fallback) {
    return allowed.includes(value) ? value : fallback;
}

/**
 * POST /api/rephrase
 * body: { text, mode, style, tone, model, stream }
 *   text   Markdown string (required)
 *   mode   "simple" | "default"
 *   style  "keep" | "casual" | "business" | "academic"
 *   tone   "keep" | "friendly" | "confident" | "diplomatic" | "enthusiastic"
 *   model  one of /api/models ids
 *   stream true (default) -> text/event-stream of {type:"delta"|"done"|"error"|"info"}
 *          false -> JSON { text, model, provider, usage }
 */
export async function onRequestPost(context) {
    const { request, env } = context;

    let body;
    try {
        body = await request.json();
    } catch {
        return error('Invalid JSON body');
    }

    const text = typeof body.text === 'string' ? body.text : '';
    if (!text.trim()) return error('Text is required');
    if (text.length > MAX_CHARS) return error(`Text is too long (max ${MAX_CHARS} characters)`, 413);

    const mode = pick(body.mode, MODES, 'default');
    const style = pick(body.style, STYLES, 'keep');
    const tone = pick(body.tone, TONES, 'keep');

    const available = availableModels(env);
    if (!available.length) return error('No AI provider is configured (set ANTHROPIC_API_KEY or the AI binding)', 500);
    const requestedId = body.model || env.ANTHROPIC_MODEL || DEFAULT_MODEL_ID;
    const model = available.some((m) => m.id === requestedId) ? findModel(requestedId) : findModel(available[0].id);

    const system = buildSystemPrompt({ mode, style, tone });
    const user = wrapText(text);
    const wantStream = body.stream !== false;

    const run = streamFor(model);
    const fallbackModel = model.provider === 'anthropic' && env.AI ? findModel('@cf/google/gemma-4-26b-a4b-it') : null;

    if (!wantStream) {
        try {
            const result = await collect(run, { env, model, system, user, signal: request.signal });
            return json({ text: cleanOutput(result.text), model: model.id, provider: model.provider, usage: result.usage });
        } catch (e) {
            return upstreamErrorResponse(e);
        }
    }

    const { readable, writable } = new TransformStream();
    const writer = writable.getWriter();
    const encoder = new TextEncoder();
    const send = (obj) => writer.write(encoder.encode(`data: ${JSON.stringify(obj)}\n\n`));

    context.waitUntil(
        (async () => {
            let usedModel = model;
            let emitted = false;
            try {
                try {
                    for await (const ev of run({ env, model, system, user, signal: request.signal })) {
                        if (ev.type === 'delta') {
                            emitted = true;
                            await send(ev);
                        } else if (ev.type === 'done') {
                            await send({ type: 'done', model: usedModel.id, provider: usedModel.provider, usage: ev.usage, stop_reason: ev.stop_reason });
                        }
                    }
                } catch (e) {
                    // Fall back to the free model only if nothing was streamed yet and the failure was upstream.
                    if (!emitted && fallbackModel && e instanceof UpstreamError && e.retryable) {
                        usedModel = fallbackModel;
                        await send({ type: 'info', message: `${model.label || model.id} unavailable, using ${fallbackModel.label}`, model: fallbackModel.id, provider: fallbackModel.provider });
                        for await (const ev of streamFor(fallbackModel)({ env, model: fallbackModel, system, user, signal: request.signal })) {
                            if (ev.type === 'delta') await send(ev);
                            else if (ev.type === 'done') await send({ type: 'done', model: usedModel.id, provider: usedModel.provider, usage: ev.usage, stop_reason: ev.stop_reason });
                        }
                    } else {
                        throw e;
                    }
                }
            } catch (e) {
                const payload = e instanceof UpstreamError
                    ? { type: 'error', message: e.message, status: e.status, details: e.details }
                    : { type: 'error', message: e?.message || 'Unexpected error', status: 500 };
                try {
                    await send(payload);
                } catch {
                    /* client gone */
                }
            } finally {
                try {
                    await writer.close();
                } catch {
                    /* already closed */
                }
            }
        })()
    );

    return new Response(readable, {
        headers: {
            'Content-Type': 'text/event-stream; charset=utf-8',
            'Cache-Control': 'no-cache, no-store',
            'X-Accel-Buffering': 'no',
        },
    });
}

async function collect(run, args) {
    let text = '';
    let usage = null;
    for await (const ev of run(args)) {
        if (ev.type === 'delta') text += ev.text;
        else if (ev.type === 'done') usage = ev.usage;
    }
    return { text, usage };
}

function upstreamErrorResponse(e) {
    if (e instanceof UpstreamError) {
        return json({ error: e.message, details: e.details }, e.status >= 400 && e.status < 600 ? e.status : 502);
    }
    return json({ error: 'Internal server error', message: e?.message }, 500);
}

export async function onRequest(context) {
    if (context.request.method === 'POST') return onRequestPost(context);
    return error('Method not allowed', 405);
}
