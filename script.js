document.addEventListener('DOMContentLoaded', () => {
    const inputText = document.getElementById('inputText');
    const outputText = document.getElementById('outputText');
    const languageSelect = document.getElementById('languageSelect');
    const cleanupBtn = document.getElementById('cleanupBtn');
    const writingStyleSelect = document.getElementById('writingStyle');
    const toneSelect = document.getElementById('tone');
    const menuItems = document.querySelectorAll('.menu-item');
    const errorToolbox = document.getElementById('errorToolbox');
    const errorToolboxContent = document.getElementById('errorToolboxContent');
    const closeToolboxBtn = document.getElementById('closeToolboxBtn');

    let debounceTimer = null;
    const DEBOUNCE_DELAY = 400;

    const state = {
        language: 'en',
        writingStyle: 'prefer_casual',
        tone: 'default'
    };

    function debounce(func, delay) {
        return function(...args) {
            clearTimeout(debounceTimer);
            debounceTimer = setTimeout(() => func.apply(this, args), delay);
        };
    }

    function showError(errorData) {
        errorToolboxContent.textContent = JSON.stringify(errorData, null, 2);
        errorToolbox.classList.add('visible');
    }

    function hideError() {
        errorToolbox.classList.remove('visible');
        errorToolboxContent.textContent = '';
    }

    async function rephraseText() {
        const text = inputText.value.trim();
        
        if (!text) {
            outputText.textContent = '';
            outputText.classList.remove('loading');
            hideError();
            return;
        }

        outputText.textContent = 'Rephrasing...';
        outputText.classList.add('loading');
        hideError();

        try {
            const response = await fetch('/api/rephrase', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    text: text,
                    language: state.language,
                    writing_style: state.writingStyle,
                    tone: state.tone
                })
            });

            if (!response.ok) {
                let errorData;
                try {
                    errorData = await response.json();
                } catch {
                    errorData = {
                        status: response.status,
                        statusText: response.statusText,
                        message: `HTTP error! status: ${response.status}`
                    };
                }
                showError({
                    status: response.status,
                    statusText: response.statusText,
                    ...errorData
                });
                outputText.textContent = `Error: ${errorData.error || errorData.message || `HTTP ${response.status}`}`;
                outputText.classList.remove('loading');
                return;
            }

            const data = await response.json();
            outputText.textContent = data.rephrased_text || data.text || 'No rephrasing available.';
            outputText.classList.remove('loading');
        } catch (error) {
            showError({
                error: error.name,
                message: error.message,
                stack: error.stack
            });
            outputText.textContent = `Error: ${error.message}`;
            outputText.classList.remove('loading');
        }
    }

    const debouncedRephrase = debounce(rephraseText, DEBOUNCE_DELAY);

    inputText.addEventListener('input', () => {
        debouncedRephrase();
    });

    languageSelect.addEventListener('change', (e) => {
        state.language = e.target.value;
        if (inputText.value.trim()) {
            rephraseText();
        }
    });

    writingStyleSelect.addEventListener('change', (e) => {
        state.writingStyle = e.target.value;
        if (state.writingStyle !== 'default') {
            toneSelect.value = 'default';
            state.tone = 'default';
        }
        if (inputText.value.trim()) {
            rephraseText();
        }
    });

    toneSelect.addEventListener('change', (e) => {
        state.tone = e.target.value;
        if (state.tone !== 'default') {
            writingStyleSelect.value = 'default';
            state.writingStyle = 'default';
        }
        if (inputText.value.trim()) {
            rephraseText();
        }
    });

    cleanupBtn.addEventListener('click', () => {
        inputText.value = '';
        outputText.textContent = '';
        outputText.classList.remove('loading');
        hideError();
    });

    closeToolboxBtn.addEventListener('click', () => {
        hideError();
    });

    menuItems.forEach(item => {
        item.addEventListener('click', () => {
            menuItems.forEach(menuItem => menuItem.classList.remove('active'));
            item.classList.add('active');
            const mode = item.getAttribute('data-mode');
            // Mode switching logic can be added here
            console.log('Mode switched to:', mode);
        });
    });
});
