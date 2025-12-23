document.addEventListener('DOMContentLoaded', () => {
    const testBtn = document.getElementById('testBtn');
    const result = document.getElementById('result');

    testBtn.addEventListener('click', async () => {
        result.textContent = 'Loading...';
        
        // #region agent log
        console.log('[DEBUG H1] Button clicked, starting fetch');
        // #endregion
        
        try {
            const response = await fetch('/api/hello');
            // #region agent log
            console.log('[DEBUG H1] Fetch completed', {status: response.status, ok: response.ok});
            // #endregion
            
            const data = await response.json();
            // #region agent log
            console.log('[DEBUG H3] JSON parsed', data);
            // #endregion
            
            result.textContent = data.message || 'Success!';
            // #region agent log
            console.log('[DEBUG H4] Result updated', result.textContent);
            // #endregion
        } catch (error) {
            // #region agent log
            console.log('[DEBUG H5] Error caught', error.message);
            // #endregion
            result.textContent = 'Error: ' + error.message;
        }
    });
});

