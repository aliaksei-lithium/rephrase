export async function onRequest() {
    // #region agent log
    console.log('[DEBUG H2] API handler called');
    // #endregion
    
    const responseBody = {
        message: 'Hello from Cloudflare Pages Functions! 🚀',
        timestamp: new Date().toISOString()
    };
    
    // #region agent log
    console.log('[DEBUG H2] API returning response', responseBody);
    // #endregion
    
    return new Response(
        JSON.stringify(responseBody),
        {
            headers: {
                'Content-Type': 'application/json',
            },
        }
    );
}

