import { availableModels, DEFAULT_MODEL_ID } from '../lib/models.js';
import { LANGUAGES, MODES, STYLES, TONES } from '../lib/prompts.js';
import { json } from '../lib/http.js';

export async function onRequest(context) {
    const models = availableModels(context.env);
    const configured = context.env.ANTHROPIC_MODEL;
    const defaultId = models.some((m) => m.id === configured) ? configured : (models.some((m) => m.id === DEFAULT_MODEL_ID) ? DEFAULT_MODEL_ID : models[0]?.id || null);
    return json({ models, default: defaultId, modes: MODES, styles: STYLES, tones: TONES, languages: LANGUAGES });
}
