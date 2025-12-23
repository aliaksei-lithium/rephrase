document.addEventListener('DOMContentLoaded', () => {
    const inputText = document.getElementById('inputText');
    const outputText = document.getElementById('outputText');
    const languageSelect = document.getElementById('languageSelect');
    const sourceLangSelect = document.getElementById('sourceLangSelect');
    const targetLangSelect = document.getElementById('targetLangSelect');
    const swapLangBtn = document.getElementById('swapLangBtn');
    const cleanupBtn = document.getElementById('cleanupBtn');
    const copyBtn = document.getElementById('copyBtn');
    const writingStyleSelect = document.getElementById('writingStyle');
    const toneSelect = document.getElementById('tone');
    const menuItems = document.querySelectorAll('.menu-item');
    const errorToolbox = document.getElementById('errorToolbox');
    const errorToolboxContent = document.getElementById('errorToolboxContent');
    const closeToolboxBtn = document.getElementById('closeToolboxBtn');
    const rephraseHeader = document.getElementById('rephraseHeader');
    const translateHeader = document.getElementById('translateHeader');
    const configSection = document.getElementById('configSection');
    const usageInfo = document.getElementById('usageInfo');

    let debounceTimer = null;
    const DEBOUNCE_DELAY = 400;

    let currentMode = 'rephrase';

    const state = {
        language: 'en',
        writingStyle: 'prefer_casual',
        tone: 'default',
        sourceLang: '',
        targetLang: 'RU'
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

    function highlightDiff(original, rephrased) {
        if (!window.Diff || original === rephrased) {
            return rephrased;
        }

        const diff = Diff.diffWords(original, rephrased, {
            ignoreWhitespace: false,
            ignoreCase: false
        });

        let html = '';
        diff.forEach(part => {
            if (part.added) {
                html += `<span class="diff-added">${escapeHtml(part.value)}</span>`;
            } else if (!part.removed) {
                html += escapeHtml(part.value);
            }
        });
        return html;
    }

    function escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    function switchMode(mode) {
        currentMode = mode;
        
        if (mode === 'rephrase') {
            rephraseHeader.style.display = 'flex';
            translateHeader.style.display = 'none';
            configSection.style.display = 'flex';
            inputText.placeholder = 'Enter text to rephrase...';
        } else {
            rephraseHeader.style.display = 'none';
            translateHeader.style.display = 'flex';
            configSection.style.display = 'none';
            inputText.placeholder = 'Type to translate.';
        }
        
        if (inputText.value.trim()) {
            if (mode === 'rephrase') {
                rephraseText();
            } else {
                translateText();
            }
        } else {
            outputText.textContent = '';
            hideError();
        }
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
            const rephrasedText = data.rephrased_text || data.text || 'No rephrasing available.';
            const originalText = inputText.value.trim();
            
            if (rephrasedText && originalText && window.Diff) {
                outputText.innerHTML = highlightDiff(originalText, rephrasedText);
            } else {
                outputText.textContent = rephrasedText;
            }
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

    async function translateText() {
        const text = inputText.value.trim();
        
        if (!text) {
            outputText.textContent = '';
            outputText.classList.remove('loading');
            hideError();
            return;
        }

        outputText.textContent = 'Translating...';
        outputText.classList.add('loading');
        hideError();

        try {
            const response = await fetch('/api/translate', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    text: text,
                    source_lang: state.sourceLang || undefined,
                    target_lang: state.targetLang
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
            const translatedText = data.translated_text || data.text || 'No translation available.';
            outputText.textContent = translatedText;
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
    const debouncedTranslate = debounce(translateText, DEBOUNCE_DELAY);

    inputText.addEventListener('input', () => {
        if (currentMode === 'rephrase') {
            debouncedRephrase();
        } else {
            debouncedTranslate();
        }
    });

    languageSelect.addEventListener('change', (e) => {
        state.language = e.target.value;
        if (inputText.value.trim()) {
            rephraseText();
        }
    });

    sourceLangSelect.addEventListener('change', (e) => {
        state.sourceLang = e.target.value;
        if (inputText.value.trim()) {
            translateText();
        }
    });

    targetLangSelect.addEventListener('change', (e) => {
        state.targetLang = e.target.value;
        if (inputText.value.trim()) {
            translateText();
        }
    });

    swapLangBtn.addEventListener('click', () => {
        const sourceLang = state.sourceLang;
        const targetLang = state.targetLang;
        
        state.sourceLang = targetLang;
        state.targetLang = sourceLang;
        
        sourceLangSelect.value = state.sourceLang;
        targetLangSelect.value = state.targetLang;
        
        if (inputText.value.trim()) {
            translateText();
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
        outputText.innerHTML = '';
        outputText.classList.remove('loading');
        hideError();
    });

    copyBtn.addEventListener('click', async () => {
        const textToCopy = outputText.textContent.trim();
        if (!textToCopy) {
            return;
        }
        
        try {
            await navigator.clipboard.writeText(textToCopy);
            const originalText = copyBtn.textContent;
            copyBtn.textContent = '✓';
            copyBtn.style.color = '#28a745';
            setTimeout(() => {
                copyBtn.textContent = originalText;
                copyBtn.style.color = '';
            }, 2000);
        } catch (error) {
            console.error('Failed to copy text:', error);
        }
    });

    closeToolboxBtn.addEventListener('click', () => {
        hideError();
    });

    menuItems.forEach(item => {
        item.addEventListener('click', () => {
            menuItems.forEach(menuItem => menuItem.classList.remove('active'));
            item.classList.add('active');
            const mode = item.getAttribute('data-mode');
            switchMode(mode);
        });
    });

    async function fetchUsage() {
        try {
            const response = await fetch('/api/usage');
            if (!response.ok) {
                usageInfo.innerHTML = '<div class="usage-loading">Unable to load usage</div>';
                return;
            }

            const data = await response.json();
            
            const writeProduct = data.products?.find(p => p.product_type === 'write') || {};
            const translateProduct = data.products?.find(p => p.product_type === 'translate') || {};
            
            const writeUsage = writeProduct.api_key_character_count || 0;
            const writeMax = data.api_key_character_limit || 0;
            const writePercentage = writeMax > 0 ? Math.round((writeUsage / writeMax) * 100) : 0;
            
            const translateUsage = translateProduct.api_key_character_count || 0;
            const translateMax = data.api_key_character_limit || 0;
            const translatePercentage = translateMax > 0 ? Math.round((translateUsage / translateMax) * 100) : 0;
            
            const startDate = data.start_time ? new Date(data.start_time).toLocaleDateString() : '';
            const endDate = data.end_time ? new Date(data.end_time).toLocaleDateString() : '';
            const billingPeriod = startDate && endDate ? `${startDate} - ${endDate}` : '';

            usageInfo.innerHTML = `
                <div class="usage-item"><strong>Write:</strong> ${writeUsage.toLocaleString()} (${writePercentage}%), max ${writeMax.toLocaleString()}</div>
                <div class="usage-item"><strong>Translate:</strong> ${translateUsage.toLocaleString()} (${translatePercentage}%), max ${translateMax.toLocaleString()}</div>
                ${billingPeriod ? `<div class="usage-item"><strong>Billing period:</strong> ${billingPeriod}</div>` : ''}
            `;
        } catch (error) {
            usageInfo.innerHTML = '<div class="usage-loading">Unable to load usage</div>';
        }
    }

    fetchUsage();
});
