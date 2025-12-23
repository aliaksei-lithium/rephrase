export async function onRequest(context) {
    if (context.request.method !== 'GET') {
        return new Response(
            JSON.stringify({ error: 'Method not allowed' }),
            {
                status: 405,
                headers: { 'Content-Type': 'application/json' },
            }
        );
    }

    try {
        const DEEPL_API_KEY = context.env['deepl-api-key'] || context.env.DEEPL_API_KEY;
        if (!DEEPL_API_KEY) {
            return new Response(
                JSON.stringify({ error: 'DeepL API key not configured' }),
                {
                    status: 500,
                    headers: { 'Content-Type': 'application/json' },
                }
            );
        }

        const apiUrl = 'https://api.deepl.com/v2/usage';

        const response = await fetch(apiUrl, {
            method: 'GET',
            headers: {
                'Authorization': `DeepL-Auth-Key ${DEEPL_API_KEY}`,
            },
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
        return new Response(
            JSON.stringify(data),
            {
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

