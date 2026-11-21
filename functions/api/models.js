import { DEMO_MODEL_ID, demoConfig } from '../lib/demo.js';
import { availableModels, DEFAULT_MODEL_ID } from '../lib/models.js';
import { FORMATS, LANGUAGES, MODES, STYLES, TONES } from '../lib/prompts.js';
import { json } from '../lib/http.js';

export async function onRequest(context) {
    const demo = Boolean(context.data.session?.demo);
    let models = availableModels(context.env);
    if (demo) {
        models = models.filter((m) => m.id === DEMO_MODEL_ID);
        return json({ models, default: models[0]?.id || null, modes: MODES, styles: STYLES, tones: TONES, languages: LANGUAGES, formats: FORMATS, demo: true, max_chars: demoConfig(context.env).maxChars });
    }
    const configured = context.env.ANTHROPIC_MODEL;
    const defaultId = models.some((m) => m.id === configured) ? configured : (models.some((m) => m.id === DEFAULT_MODEL_ID) ? DEFAULT_MODEL_ID : models[0]?.id || null);
    return json({ models, default: defaultId, modes: MODES, styles: STYLES, tones: TONES, languages: LANGUAGES, formats: FORMATS });
}
