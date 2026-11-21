import { DEMO_MODEL_ID, DemoLimitError, demoConfig, reserveDemo } from '../lib/demo.js';
import { error, json } from '../lib/http.js';
import { availableModels, DEFAULT_MODEL_ID, findModel } from '../lib/models.js';
import { buildSystemPrompt, cleanOutput, FORMATS, LANGUAGES, MODES, STYLES, TONES, wrapText } from '../lib/prompts.js';
import { streamFor, UpstreamError } from '../lib/providers.js';

const MAX_CHARS = 12_000;

function pick(value, allowed, fallback) {
    return allowed.includes(value) ? value : fallback;
}

/**
 * POST /api/rephrase
 * body: { text, mode, style, tone, language, format, model, stream }
 *   text   Markdown string, or plain text with format "plain" (required)
 *   mode   "simple" | "default"
 *   style  "keep" | "casual" | "business" | "academic"
 *   tone   "keep" | "friendly" | "confident" | "diplomatic" | "enthusiastic"
 *   language "auto" | "en" | "de"   output language (auto keeps the input language)
 *   format "markdown" (default) | "plain"   plain: input and output are plain text, no Markdown
 *   model  one of /api/models ids
 *   stream true (default) -> text/event-stream of {type:"delta"|"done"|"error"|"info"}
 *          false -> JSON { text, model, provider, usage }
 *
 * Demo sessions always use the demo model, have a shorter text limit and draw on the shared
 * daily demo budget; over it they get 429 { code: "demo_limit" | "demo_client_limit" }.
 * Their "done" event and JSON response also carry demo: { left_for_you, budget_left }.
 */
export async function onRequestPost(context) {
    const { request, env } = context;
    const isDemo = Boolean(context.data?.session?.demo);
    const maxChars = isDemo ? demoConfig(env).maxChars : MAX_CHARS;

    let body;
    try {
        body = await request.json();
    } catch {
        return error('Invalid JSON body');
    }

    const text = typeof body.text === 'string' ? body.text : '';
    if (!text.trim()) return error('Text is required');
    if (text.length > maxChars) {
        const hint = isDemo ? ' in the demo. Sign in for longer texts.' : '';
        return error(`Text is too long (max ${maxChars} characters)${hint}`, 413, { code: 'too_long', max_chars: maxChars });
    }

    const mode = pick(body.mode, MODES, 'default');
    const style = pick(body.style, STYLES, 'keep');
    const tone = pick(body.tone, TONES, 'keep');
    const language = pick(body.language, LANGUAGES, 'auto');
    const format = pick(body.format, FORMATS, 'markdown');

    const available = availableModels(env);
    if (!available.length) return error('No AI provider is configured (set ANTHROPIC_API_KEY or the AI binding)', 500);
    const requestedId = isDemo ? DEMO_MODEL_ID : body.model || env.ANTHROPIC_MODEL || DEFAULT_MODEL_ID;
    if (isDemo && !available.some((m) => m.id === DEMO_MODEL_ID)) return error('The demo model is not available', 503);
    const model = available.some((m) => m.id === requestedId) ? findModel(requestedId) : findModel(available[0].id);

    const system = buildSystemPrompt({ mode, style, tone, language, format });
    const user = wrapText(text);
    const wantStream = body.stream !== false;

    const run = streamFor(model);
    const fallbackModel = !isDemo && model.provider === 'anthropic' && env.AI ? findModel(DEMO_MODEL_ID) : null;
    const runArgs = { env, model, system, user, signal: request.signal };

    let demo = null;
    if (isDemo) {
        runArgs.maxTokens = demoConfig(env).maxOutputTokens;
        try {
            demo = await reserveDemo(request, env, system.length + user.length);
        } catch (e) {
            if (e instanceof DemoLimitError) return error(e.message, 429, { code: e.code });
            return error('The demo is unavailable right now. Try again later.', 503, { code: 'demo_unavailable' });
        }
    }
    const settleDemo = (usage, produced) => (demo ? demo.settle(usage, { produced }).catch(() => {}) : Promise.resolve());
    const demoInfo = demo ? { demo: demo.status } : {};

    if (!wantStream) {
        let result = null;
        try {
            result = await collect(run, runArgs);
            const text = cleanOutput(result.text);
            if (!text) return json({ error: 'The model returned no text. Try again or pick another model.', usage: result.usage }, 502);
            return json({ text, model: model.id, provider: model.provider, usage: result.usage, ...demoInfo });
        } catch (e) {
            return upstreamErrorResponse(e);
        } finally {
            context.waitUntil(settleDemo(result?.usage, Boolean(result?.text)));
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
            let usage = null;
            try {
                try {
                    for await (const ev of run(runArgs)) {
                        if (ev.type === 'delta') {
                            emitted = true;
                            await send(ev);
                        } else if (ev.type === 'done') {
                            usage = ev.usage;
                            if (!emitted) throw new UpstreamError('The model returned no text. Try again or pick another model.', { status: 502, retryable: true });
                            await send({ type: 'done', model: usedModel.id, provider: usedModel.provider, usage: ev.usage, stop_reason: ev.stop_reason, ...demoInfo });
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
                // A model can bill for reasoning without emitting text, so only a run with no
                // usage and no output is treated as free.
                await settleDemo(usage, emitted || Boolean(usage));
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
