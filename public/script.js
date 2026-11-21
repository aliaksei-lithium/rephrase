document.addEventListener('DOMContentLoaded', () => {
    const E = window.RephraseEditor;

    const inputText = document.getElementById('inputText');
    const outputText = document.getElementById('outputText');
    const modelSelect = document.getElementById('modelSelect');
    const styleSelect = document.getElementById('styleSelect');
    const toneSelect = document.getElementById('toneSelect');
    const languageSelect = document.getElementById('languageSelect');
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
    const signInBtn = document.getElementById('signInBtn');
    const demoBadge = document.getElementById('demoBadge');
    const demoChoice = document.getElementById('demoChoice');
    const demoBtn = document.getElementById('demoBtn');

    const PREFS_KEY = 'rephrase.prefs.v2';
    const AUTO_DEBOUNCE_MS = 3000;

    const state = {
        mode: 'default',
        style: 'keep',
        tone: 'keep',
        language: 'auto',
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
    // Public demo: Gemma only, shared daily limit. demo.active means the current session is a demo one.
    const demo = { available: false, active: false };

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
        languageSelect.value = state.language;
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
        signInBtn.hidden = true;
        demoChoice.hidden = !demo.available;
        demoBtn.textContent = demo.active ? 'Back to the demo' : 'Try the demo';
        setTimeout(() => passwordInput.focus(), 0);
    }
    function hideLogin() {
        loginOverlay.hidden = true;
        loginError.textContent = '';
        passwordInput.value = '';
        applySessionUi();
    }
    function applySessionUi() {
        logoutBtn.hidden = demo.active;
        signInBtn.hidden = !demo.active;
        demoBadge.hidden = !demo.active;
    }
    function demoStatusText(info) {
        if (!info) return '';
        const parts = [];
        if (typeof info.left_for_you === 'number') parts.push(`${info.left_for_you} demo rewrites left today`);
        if (typeof info.budget_left === 'number' && info.budget_left < 0.2) parts.push('shared demo quota almost used up');
        return parts.join(' · ');
    }
    async function startDemo() {
        const res = await fetch('/api/auth/demo', { method: 'POST', credentials: 'same-origin' });
        if (!res.ok) return false;
        demo.active = true;
        return true;
    }
    async function checkAuth() {
        try {
            const res = await fetch('/api/auth/me', { credentials: 'same-origin' });
            const data = await res.json();
            if (!data.configured) {
                setStatus('Server is missing APP_PASSWORD. See README.', 'warn');
                return false;
            }
            demo.available = Boolean(data.demo_available);
            demo.active = Boolean(data.authenticated && data.demo);
            // Anyone can try the app: without a session, start a demo one instead of asking for the password.
            if (!data.authenticated && !(demo.available && (await startDemo()))) {
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
            demo.active = false;
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
        demo.active = false;
        demoBadge.hidden = true;
        showLogin();
    });
    signInBtn.addEventListener('click', showLogin);
    demoBtn.addEventListener('click', async () => {
        demoBtn.disabled = true;
        loginError.textContent = '';
        try {
            if (demo.active || (await startDemo())) {
                hideLogin();
                await loadModels();
                inputText.focus();
            } else {
                loginError.textContent = 'The demo is not available right now.';
            }
        } catch (e) {
            loginError.textContent = e.message;
        } finally {
            demoBtn.disabled = false;
        }
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
            else if (data.demo) setStatus(`Demo: the free Gemma model, texts up to ${(data.max_chars || 2000).toLocaleString()} characters. <button type="button" class="inline-link" data-action="sign-in">Sign in</button> for Claude.`);
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
        setStatus(`${state.mode === 'rewrite' ? 'Rewriting' : 'Rephrasing'} with ${modelById.get(state.model)?.label || state.model}…`);
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
                body: JSON.stringify({ text: markdown, mode: state.mode, style: state.style, tone: state.tone, language: state.language, model: state.model, stream: true }),
                signal: controller.signal,
            });
            if (!res.ok) {
                const errorData = await res.json().catch(() => ({ status: res.status, statusText: res.statusText }));
                if (errorData.code?.startsWith('demo_') || (demo.active && errorData.code === 'too_long')) {
                    // Expected demo limits: say so plainly instead of opening the error details.
                    outputText.textContent = errorData.error;
                    outputText.classList.remove('loading');
                    setStatus(`${errorData.error} <button type="button" class="inline-link" data-action="sign-in">Sign in</button>`, 'warn');
                    return;
                }
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

            const finalMd = cleanModelOutput(streamed);
            if (!finalMd) {
                showError({ message: 'The model returned no text.', model: usedModel, usage: done?.usage || null });
                outputText.textContent = 'Error: the model returned no text. Try again or pick another model.';
                outputText.classList.remove('loading');
                setStatus('Failed.', 'warn');
                return;
            }
            setProgress(100);
            const html = renderOutput(finalMd, originalPlain);
            finished = true;
            setTimeout(() => setProgress(null), 250);
            lastResult = { markdown: finalMd, html, originalPlain, model: usedModel, usage: done?.usage || null };

            const cost = estimateCost(usedModel, done?.usage);
            sessionCost += cost;
            const m = modelById.get(usedModel);
            const parts = [`<strong>${m ? m.label : usedModel}</strong>`];
            if (done?.usage) parts.push(`${done.usage.input_tokens} in / ${done.usage.output_tokens} out`);
            if (done?.demo) parts.push(demoStatusText(done.demo));
            else parts.push(`${fmtCost(cost)} (session ${fmtCost(sessionCost)})`);
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
        return out.trim()
            .replace(/(\d)\s*[\u2013\u2014]\s*(\d)/g, '$1-$2')
            .replace(/[ \t]*[\u2013\u2014][ \t]*/g, ' - ');
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

    // ---------- formatting toolbar ----------
    const toolbar = document.getElementById('toolbar');
    function refreshToolbar() {
        const active = E.activeFormats(inputText);
        toolbar.querySelectorAll('button').forEach((b) => b.classList.toggle('active', !!active[b.dataset.cmd]));
    }
    // Keep the editor selection when a toolbar button is pressed.
    toolbar.addEventListener('mousedown', (ev) => ev.preventDefault());
    toolbar.addEventListener('click', (ev) => {
        const btn = ev.target.closest('button[data-cmd]');
        if (!btn) return;
        E.format(inputText, btn.dataset.cmd);
        refreshToolbar();
    });
    document.addEventListener('selectionchange', refreshToolbar);
    inputText.addEventListener('keydown', (ev) => {
        if ((ev.metaKey || ev.ctrlKey) && !ev.shiftKey && !ev.altKey && ev.key.toLowerCase() === 'k') {
            ev.preventDefault();
            E.format(inputText, 'link');
        }
    });

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
    languageSelect.addEventListener('change', () => {
        state.language = languageSelect.value;
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
    statusInfo.addEventListener('click', (ev) => {
        if (ev.target.closest('[data-action="sign-in"]')) showLogin();
    });

    // ---------- init ----------
    loadPrefs();
    applyPrefsToUi();
    checkAuth().then((ok) => {
        if (ok) loadModels();
    });
});
