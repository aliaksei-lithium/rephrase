export async function onRequest(context) {
    if (context.request.method !== 'POST') {
        return new Response(
            JSON.stringify({ error: 'Method not allowed' }),
            {
                status: 405,
                headers: { 'Content-Type': 'application/json' },
            }
        );
    }

    try {
        const body = await context.request.json();
        const { text, source_lang, target_lang } = body;

        if (!text || typeof text !== 'string') {
            return new Response(
                JSON.stringify({ error: 'Text is required and must be a string' }),
                {
                    status: 400,
                    headers: { 'Content-Type': 'application/json' },
                }
            );
        }

        if (!target_lang) {
            return new Response(
                JSON.stringify({ error: 'Target language is required' }),
                {
                    status: 400,
                    headers: { 'Content-Type': 'application/json' },
                }
            );
        }

        const DEEPL_API_KEY = context.env['deepl-api-key'] || context.env.DEEPL_API_KEY;
        if (!DEEPL_API_KEY) {
            return new Response(
                JSON.stringify({ error: 'DeepL API key not configured. Please set deepl-api-key in .dev.vars for local development or in Cloudflare Pages environment variables.' }),
                {
                    status: 500,
                    headers: { 'Content-Type': 'application/json' },
                }
            );
        }

        const apiUrl = 'https://api.deepl.com/v2/translate';

        const requestBody = {
            text: [text],
            target_lang: target_lang,
        };

        if (source_lang) {
            requestBody.source_lang = source_lang;
        }

        const response = await fetch(apiUrl, {
            method: 'POST',
            headers: {
                'Authorization': `DeepL-Auth-Key ${DEEPL_API_KEY}`,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(requestBody),
        });

        if (!response.ok) {
            const errorText = await response.text();
            return new Response(
                JSON.stringify({
                    error: 'DeepL API error',
                    details: errorText,
                    status: response.status,
                }),
                {
                    status: response.status,
                    headers: { 'Content-Type': 'application/json' },
                }
            );
        }

        const data = await response.json();
        
        if (data.translations && data.translations.length > 0) {
            return new Response(
                JSON.stringify({
                    translated_text: data.translations[0].text,
                    detected_language: data.translations[0].detected_source_language,
                }),
                {
                    headers: { 'Content-Type': 'application/json' },
                }
            );
        }

        return new Response(
            JSON.stringify({ error: 'No translation returned from DeepL' }),
            {
                status: 500,
                headers: { 'Content-Type': 'application/json' },
            }
        );
    } catch (error) {
        return new Response(
            JSON.stringify({
                error: 'Internal server error',
                message: error.message,
            }),
            {
                status: 500,
                headers: { 'Content-Type': 'application/json' },
            }
        );
    }
}

