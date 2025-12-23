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
        const { text, language, writing_style, tone } = body;

        if (!text || typeof text !== 'string') {
            return new Response(
                JSON.stringify({ error: 'Text is required and must be a string' }),
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

        const targetLang = language === 'de' ? 'de' : 'en';
        const apiUrl = 'https://api.deepl.com/v2/write/rephrase';

        const requestBody = {
            text: [text],
            target_lang: targetLang,
        };

        if (writing_style && writing_style !== 'default') {
            requestBody.writing_style = writing_style;
        } else if (tone && tone !== 'default') {
            requestBody.tone = tone;
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
        
        if (data.improvements && data.improvements.length > 0) {
            return new Response(
                JSON.stringify({
                    rephrased_text: data.improvements[0].text,
                    detected_language: data.improvements[0].detected_source_language,
                }),
                {
                    headers: { 'Content-Type': 'application/json' },
                }
            );
        }

        return new Response(
            JSON.stringify({ error: 'No improvements returned from DeepL' }),
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

