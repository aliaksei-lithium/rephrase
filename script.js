document.addEventListener('DOMContentLoaded', () => {
    const E = window.RephraseEditor;

    const inputText = document.getElementById('inputText');
    const outputText = document.getElementById('outputText');
    const modelSelect = document.getElementById('modelSelect');
    const styleSelect = document.getElementById('styleSelect');
    const toneSelect = document.getElementById('toneSelect');
    const modeGroup = document.getElementById('modeGroup');
    const rephraseBtn = document.getElementById('rephraseBtn');
    const cleanupBtn = document.getElementById('cleanupBtn');
    const copyBtn = document.getElementById('copyBtn');
    const copyMdBtn = document.getElementById('copyMdBtn');
    const showDiff = document.getElementById('showDiff');
    const autoRun = document.getElementById('autoRun');
    const statusInfo = document.getElementById('statusInfo');
    const progressBar = document.getElementById('progressBar');
    const progressFill = document.getElementById('progressFill');
    const logoutBtn = document.getElementById('logoutBtn');
    const errorToolbox = document.getElementById('errorToolbox');
    const errorToolboxContent = document.getElementById('errorToolboxContent');
    const closeToolboxBtn = document.getElementById('closeToolboxBtn');
    const loginOverlay = document.getElementById('loginOverlay');
    const loginForm = document.getElementById('loginForm');
    const passwordInput = document.getElementById('passwordInput');
    const loginError = document.getElementById('loginError');
    const loginBtn = document.getElementById('loginBtn');

    const PREFS_KEY = 'rephrase.prefs.v2';
    const AUTO_DEBOUNCE_MS = 3000;

    const state = {
        mode: 'default',
        style: 'keep',
        tone: 'keep',
        model: null,
        showDiff: true,
        autoRun: false,
    };
    let models = [];
    let modelById = new Map();
    let lastResult = null; // { markdown, html, originalPlain, model, usage }
    let sessionCost = 0;
    let inFlight = null;
    let debounceTimer = null;

    // ---------- prefs ----------
    function loadPrefs() {
        try {
            const saved = JSON.parse(localStorage.getItem(PREFS_KEY) || '{}');
            Object.assign(state, saved);
        } catch {
            /* ignore */
        }
    }
    function savePrefs() {
        try {
            localStorage.setItem(PREFS_KEY, JSON.stringify(state));
        } catch {
            /* ignore */
        }
    }
    function applyPrefsToUi() {
        styleSelect.value = state.style;
        toneSelect.value = state.tone;
        showDiff.checked = state.showDiff;
        autoRun.checked = state.autoRun;
        modeGroup.querySelectorAll('.seg-btn').forEach((b) => b.classList.toggle('active', b.dataset.mode === state.mode));
    }

    // ---------- errors ----------
    function showError(errorData) {
        errorToolboxContent.textContent = JSON.stringify(errorData, null, 2);
        errorToolbox.classList.add('visible');
    }
    function hideError() {
        errorToolbox.classList.remove('visible');
        errorToolboxContent.textContent = '';
    }
    function setStatus(html, cls = '') {
        statusInfo.innerHTML = html;
        statusInfo.className = `usage-info ${cls}`.trim();
    }

    // ---------- auth ----------
    async function api(path, options = {}) {
        const res = await fetch(path, { credentials: 'same-origin', ...options });
        if (res.status === 401) {
            showLogin();
            throw Object.assign(new Error('Sign in required'), { unauthorized: true });
        }
        return res;
    }
    function showLogin() {
        loginOverlay.hidden = false;
        logoutBtn.hidden = true;
        setTimeout(() => passwordInput.focus(), 0);
    }
    function hideLogin() {
        loginOverlay.hidden = true;
        logoutBtn.hidden = false;
        loginError.textContent = '';
        passwordInput.value = '';
    }
    async function checkAuth() {
        try {
            const res = await fetch('/api/auth/me', { credentials: 'same-origin' });
            const data = await res.json();
            if (!data.configured) {
                setStatus('Server is missing APP_PASSWORD. See README.', 'warn');
                return false;
            }
            if (!data.authenticated) {
                showLogin();
                return false;
            }
            hideLogin();
            return true;
        } catch (e) {
            setStatus(`Cannot reach the server: ${e.message}`, 'warn');
            return false;
        }
    }
    loginForm.addEventListener('submit', async (ev) => {
        ev.preventDefault();
        loginError.textContent = '';
        loginBtn.disabled = true;
        try {
            const res = await fetch('/api/auth/login', {
                method: 'POST',
                credentials: 'same-origin',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ password: passwordInput.value }),
            });
            const data = await res.json().catch(() => ({}));
            if (!res.ok) {
                loginError.textContent = data.error || `Login failed (${res.status})`;
                passwordInput.select();
                return;
            }
            hideLogin();
            await loadModels();
            inputText.focus();
        } catch (e) {
            loginError.textContent = e.message;
        } finally {
            loginBtn.disabled = false;
        }
    });
    logoutBtn.addEventListener('click', async () => {
        await fetch('/api/auth/logout', { method: 'POST', credentials: 'same-origin' }).catch(() => {});
        showLogin();
    });

    // ---------- models ----------
    async function loadModels() {
        try {
            const res = await api('/api/models');
            const data = await res.json();
            models = data.models || [];
            modelById = new Map(models.map((m) => [m.id, m]));
            modelSelect.innerHTML = '';
            for (const m of models) {
                const opt = document.createElement('option');
                opt.value = m.id;
                opt.textContent = m.hint ? `${m.label} · ${m.hint}` : m.label;
                modelSelect.appendChild(opt);
            }
            if (!modelById.has(state.model)) state.model = data.default || models[0]?.id || null;
            modelSelect.value = state.model || '';
            if (!models.length) setStatus('No AI provider configured on the server.', 'warn');
            else setStatus('Ready.');
        } catch (e) {
            if (!e.unauthorized) setStatus(`Could not load models: ${e.message}`, 'warn');
        }
    }

    // ---------- rephrase ----------
    function estimateCost(modelId, usage) {
        const m = modelById.get(modelId);
        if (!m || !usage) return 0;
        return (usage.input_tokens * m.price.input + usage.output_tokens * m.price.output) / 1e6;
    }
    function fmtCost(v) {
        if (v === 0) return '$0';
        if (v < 0.001) return '<$0.001';
        return `$${v.toFixed(3)}`;
    }

    // The answer length is unknown up front; assume it is about the input length.
    function setProgress(pct) {
        if (pct === null) {
            progressBar.hidden = true;
            progressFill.style.width = '0';
            return;
        }
        progressBar.hidden = false;
        progressFill.style.width = `${Math.max(3, Math.min(100, pct))}%`;
    }

    function renderOutput(markdown, originalPlain) {
        const html = E.markdownToHtml(markdown);
        outputText.innerHTML = html;
        outputText.classList.remove('loading');
        if (state.showDiff) E.applyDiffMarks(outputText, originalPlain);
        return html;
    }

    async function rephraseText() {
        const markdown = E.editorToMarkdown(inputText);
        const originalPlain = E.editorPlainText(inputText);
        if (!markdown.trim()) {
            outputText.textContent = '';
            outputText.classList.remove('loading');
            hideError();
            return;
        }
        if (inFlight) inFlight.abort();
        const controller = new AbortController();
        inFlight = controller;

        outputText.textContent = '';
        outputText.classList.add('loading');
        rephraseBtn.disabled = true;
        hideError();
        setStatus(`Rephrasing with ${modelById.get(state.model)?.label || state.model}…`);
        setProgress(3);
        const expectedChars = Math.max(markdown.length, 40);

        let streamed = '';
        let usedModel = state.model;
        let info = null;
        let finished = false;
        try {
            const res = await api('/api/rephrase', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ text: markdown, mode: state.mode, style: state.style, tone: state.tone, model: state.model, stream: true }),
                signal: controller.signal,
            });
            if (!res.ok) {
                const errorData = await res.json().catch(() => ({ status: res.status, statusText: res.statusText }));
                showError({ status: res.status, ...errorData });
                outputText.textContent = `Error: ${errorData.error || `HTTP ${res.status}`}`;
                outputText.classList.remove('loading');
                setStatus('Failed.', 'warn');
                return;
            }

            const reader = res.body.getReader();
            const decoder = new TextDecoder();
            let buffer = '';
            let done = null;
            outer: while (true) {
                const { value, done: finished } = await reader.read();
                if (finished) break;
                buffer += decoder.decode(value, { stream: true });
                let idx;
                while ((idx = buffer.indexOf('\n\n')) !== -1) {
                    const chunk = buffer.slice(0, idx);
                    buffer = buffer.slice(idx + 2);
                    const line = chunk.split('\n').find((l) => l.startsWith('data:'));
                    if (!line) continue;
                    let ev;
                    try {
                        ev = JSON.parse(line.slice(5).trim());
                    } catch {
                        continue;
                    }
                    if (ev.type === 'delta') {
                        streamed += ev.text;
                        setProgress(5 + (streamed.length / expectedChars) * 88);
                    } else if (ev.type === 'info') {
                        info = ev.message;
                        usedModel = ev.model;
                    } else if (ev.type === 'done') {
                        done = ev;
                        usedModel = ev.model || usedModel;
                        break outer;
                    } else if (ev.type === 'error') {
                        showError(ev);
                        outputText.textContent = `Error: ${ev.message}`;
                        outputText.classList.remove('loading');
                        setStatus('Failed.', 'warn');
                        return;
                    }
                }
            }

            setProgress(100);
            const finalMd = cleanModelOutput(streamed);
            const html = renderOutput(finalMd, originalPlain);
            finished = true;
            setTimeout(() => setProgress(null), 250);
            lastResult = { markdown: finalMd, html, originalPlain, model: usedModel, usage: done?.usage || null };

            const cost = estimateCost(usedModel, done?.usage);
            sessionCost += cost;
            const m = modelById.get(usedModel);
            const parts = [`<strong>${m ? m.label : usedModel}</strong>`];
            if (done?.usage) parts.push(`${done.usage.input_tokens} in / ${done.usage.output_tokens} out`);
            parts.push(`${fmtCost(cost)} (session ${fmtCost(sessionCost)})`);
            if (finalMd === markdown) parts.push('no changes');
            setStatus(`${info ? `<div class="usage-item warn-text">${info}</div>` : ''}<div class="usage-item">${parts.join(' · ')}</div>`);
        } catch (error) {
            if (error.name === 'AbortError') return;
            if (error.unauthorized) {
                outputText.textContent = '';
                outputText.classList.remove('loading');
                return;
            }
            showError({ error: error.name, message: error.message });
            outputText.textContent = `Error: ${error.message}`;
            outputText.classList.remove('loading');
            setStatus('Failed.', 'warn');
        } finally {
            if (inFlight === controller) inFlight = null;
            rephraseBtn.disabled = false;
            if (!finished) setProgress(null);
        }
    }

    function cleanModelOutput(raw) {
        let out = String(raw || '').trim();
        const fence = out.match(/^```[a-z]*\n([\s\S]*?)\n```$/i);
        if (fence) out = fence[1].trim();
        out = out.replace(/^<text>\s*/i, '').replace(/\s*<\/text>$/i, '');
        return out.trim();
    }

    // ---------- events ----------
    inputText.addEventListener('paste', E.handlePaste);
    inputText.addEventListener('keydown', (ev) => {
        if ((ev.metaKey || ev.ctrlKey) && ev.key === 'Enter') {
            ev.preventDefault();
            rephraseText();
        }
    });
    inputText.addEventListener('input', () => {
        if (!state.autoRun) return;
        clearTimeout(debounceTimer);
        debounceTimer = setTimeout(rephraseText, AUTO_DEBOUNCE_MS);
    });

    rephraseBtn.addEventListener('click', rephraseText);

    modeGroup.addEventListener('click', (ev) => {
        const btn = ev.target.closest('.seg-btn');
        if (!btn) return;
        state.mode = btn.dataset.mode;
        applyPrefsToUi();
        savePrefs();
    });
    styleSelect.addEventListener('change', () => {
        state.style = styleSelect.value;
        savePrefs();
    });
    toneSelect.addEventListener('change', () => {
        state.tone = toneSelect.value;
        savePrefs();
    });
    modelSelect.addEventListener('change', () => {
        state.model = modelSelect.value;
        savePrefs();
    });
    showDiff.addEventListener('change', () => {
        state.showDiff = showDiff.checked;
        savePrefs();
        if (lastResult) renderOutput(lastResult.markdown, lastResult.originalPlain);
    });
    autoRun.addEventListener('change', () => {
        state.autoRun = autoRun.checked;
        savePrefs();
    });

    cleanupBtn.addEventListener('click', () => {
        if (inFlight) inFlight.abort();
        inputText.innerHTML = '';
        outputText.innerHTML = '';
        outputText.classList.remove('loading');
        lastResult = null;
        hideError();
        setProgress(null);
        setStatus('Ready.');
        inputText.focus();
    });

    function flash(btn, ok = true) {
        const original = btn.textContent;
        btn.textContent = ok ? '✓' : '✗';
        btn.classList.add(ok ? 'ok' : 'fail');
        setTimeout(() => {
            btn.textContent = original;
            btn.classList.remove('ok', 'fail');
        }, 1500);
    }

    copyBtn.addEventListener('click', async () => {
        if (!lastResult) return;
        try {
            const html = E.stripDiffMarks(outputText.innerHTML);
            const plain = E.htmlToPlainText(html);
            await E.copyRich(html, plain);
            flash(copyBtn);
        } catch (error) {
            console.error('Copy failed:', error);
            flash(copyBtn, false);
        }
    });
    copyMdBtn.addEventListener('click', async () => {
        if (!lastResult) return;
        try {
            await navigator.clipboard.writeText(lastResult.markdown);
            flash(copyMdBtn);
        } catch (error) {
            console.error('Copy failed:', error);
            flash(copyMdBtn, false);
        }
    });

    closeToolboxBtn.addEventListener('click', hideError);

    // ---------- init ----------
    loadPrefs();
    applyPrefsToUi();
    checkAuth().then((ok) => {
        if (ok) loadModels();
    });
});
