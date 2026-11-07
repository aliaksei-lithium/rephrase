// Rich-text helpers: sanitise pasted HTML, convert editor HTML <-> Markdown,
// mark diffs inside formatted output, and copy with formatting.
(function () {
    const ALLOWED_TAGS = ['b', 'strong', 'i', 'em', 's', 'del', 'strike', 'u', 'code', 'pre', 'a', 'ul', 'ol', 'li', 'blockquote', 'p', 'div', 'br', 'h1', 'h2', 'h3', 'h4'];
    const ALLOWED_ATTR = ['href'];

    function sanitizeHtml(html) {
        return DOMPurify.sanitize(html, {
            ALLOWED_TAGS,
            ALLOWED_ATTR,
            KEEP_CONTENT: true,
            ALLOW_DATA_ATTR: false,
        });
    }

    // Turndown: editor HTML -> Markdown for the model.
    const turndown = new TurndownService({
        headingStyle: 'atx',
        codeBlockStyle: 'fenced',
        bulletListMarker: '-',
        emDelimiter: '_',
        strongDelimiter: '**',
        br: '\n',
    });
    turndown.addRule('strikethrough', {
        filter: ['s', 'del', 'strike'],
        replacement: (content) => (content.trim() ? `~~${content}~~` : ''),
    });
    turndown.addRule('underline', {
        filter: ['u'],
        replacement: (content) => content,
    });
    // Contenteditable and Slack both use <div> per line; keep them as single line breaks.
    turndown.addRule('lineDiv', {
        filter: (node) => node.nodeName === 'DIV',
        replacement: (content) => `\n${content}\n`,
    });
    // Turndown pads list markers to 4 columns ("-   item"); use the compact "- item" form.
    turndown.addRule('compactListItem', {
        filter: 'li',
        replacement: (content, node, options) => {
            const body = content.replace(/^\n+/, '').replace(/\n+$/, '\n').replace(/\n/gm, '\n  ');
            let prefix = `${options.bulletListMarker} `;
            const parent = node.parentNode;
            if (parent.nodeName === 'OL') {
                const start = parent.getAttribute('start');
                const index = Array.prototype.indexOf.call(parent.children, node);
                prefix = `${start ? Number(start) + index : index + 1}. `;
            }
            return prefix + body + (node.nextSibling && !/\n$/.test(body) ? '\n' : '');
        },
    });
    // Slack copies code blocks as a bare <pre> (no <code> child); Turndown only fences <pre><code>.
    turndown.addRule('barePre', {
        filter: (node) => node.nodeName === 'PRE' && !(node.firstChild && node.firstChild.nodeName === 'CODE'),
        replacement: (content, node) => `\n\n\`\`\`\n${node.textContent.replace(/\n$/, '')}\n\`\`\`\n\n`,
    });

    function editorToMarkdown(el) {
        const clean = sanitizeHtml(el.innerHTML);
        let md = turndown.turndown(clean);
        md = md.replace(/ /g, ' ').replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n');
        return md.trim();
    }

    function editorPlainText(el) {
        return el.innerText.replace(/ /g, ' ');
    }

    marked.use({ gfm: true, breaks: true });

    function markdownToHtml(md) {
        return sanitizeHtml(marked.parse(md || '')).trim();
    }

    // Insert pasted content as sanitised HTML (or text) at the caret.
    function handlePaste(event) {
        const dt = event.clipboardData;
        if (!dt) return;
        event.preventDefault();
        const html = dt.getData('text/html');
        const text = dt.getData('text/plain');
        if (html && html.trim()) {
            const clean = sanitizeHtml(stripSlackNoise(html));
            document.execCommand('insertHTML', false, clean);
        } else if (text) {
            document.execCommand('insertText', false, text);
        }
    }

    // Slack wraps code blocks and lists in extra containers; remove things that only add nesting.
    function stripSlackNoise(html) {
        const doc = new DOMParser().parseFromString(html, 'text/html');
        doc.querySelectorAll('meta, style, script').forEach((n) => n.remove());
        // <span> inside <pre> becomes text; standalone spans are unwrapped by the sanitiser.
        return doc.body.innerHTML;
    }

    // Underline words that appear in `container` but not in `originalText`.
    function applyDiffMarks(container, originalText, className = 'diff-added') {
        const newText = container.textContent;
        if (!window.Diff || !originalText || originalText === newText) return 0;

        const parts = Diff.diffWords(originalText, newText);
        const ranges = [];
        let pos = 0;
        for (const part of parts) {
            if (part.removed) continue;
            if (part.added && part.value.trim()) ranges.push([pos, pos + part.value.length]);
            pos += part.value.length;
        }
        if (!ranges.length) return 0;

        const walker = document.createTreeWalker(container, NodeFilter.SHOW_TEXT);
        const nodes = [];
        let n;
        while ((n = walker.nextNode())) nodes.push(n);

        let offset = 0;
        let marked = 0;
        for (const node of nodes) {
            const start = offset;
            const end = offset + node.length;
            offset = end;
            const segs = [];
            for (const [a, b] of ranges) {
                if (b <= start || a >= end) continue;
                segs.push([Math.max(a, start) - start, Math.min(b, end) - start]);
            }
            // Split from the right so earlier offsets stay valid.
            for (let i = segs.length - 1; i >= 0; i--) {
                const [s, e] = segs[i];
                if (e <= s) continue;
                const mid = node.splitText(s);
                mid.splitText(e - s);
                const span = document.createElement('span');
                span.className = className;
                mid.parentNode.insertBefore(span, mid);
                span.appendChild(mid);
                marked++;
            }
        }
        return marked;
    }

    function stripDiffMarks(html) {
        const doc = new DOMParser().parseFromString(html, 'text/html');
        doc.querySelectorAll('span.diff-added').forEach((s) => s.replaceWith(...s.childNodes));
        return doc.body.innerHTML;
    }

    // innerText needs layout, so render into an attached but invisible node.
    function htmlToPlainText(html) {
        const holder = document.createElement('div');
        // Normal white-space so newlines between block tags collapse; <pre> keeps its own.
        holder.style.cssText = 'position:absolute;left:-99999px;top:0;width:800px;white-space:normal;';
        holder.innerHTML = html;
        // Keep list structure readable in the plain-text flavour.
        holder.querySelectorAll('li').forEach((li) => {
            const parent = li.parentNode;
            const marker = parent.nodeName === 'OL' ? `${Array.prototype.indexOf.call(parent.children, li) + 1}. ` : '• ';
            li.insertBefore(document.createTextNode(marker), li.firstChild);
        });
        document.body.appendChild(holder);
        const text = holder.innerText;
        holder.remove();
        return text.replace(/ /g, ' ').trim();
    }

    async function copyRich(html, plain) {
        if (navigator.clipboard && window.ClipboardItem) {
            const item = new ClipboardItem({
                'text/html': new Blob([html], { type: 'text/html' }),
                'text/plain': new Blob([plain], { type: 'text/plain' }),
            });
            await navigator.clipboard.write([item]);
            return;
        }
        await navigator.clipboard.writeText(plain);
    }

    function selectionInside(el) {
        const sel = window.getSelection();
        return sel.rangeCount > 0 && el.contains(sel.anchorNode);
    }

    function closestInEditor(el, selector) {
        const sel = window.getSelection();
        let node = sel.anchorNode;
        if (node && node.nodeType === 3) node = node.parentNode;
        const found = node && node.closest ? node.closest(selector) : null;
        return found && el.contains(found) ? found : null;
    }

    // Apply a toolbar command to the editor selection.
    function format(el, cmd) {
        el.focus();
        if (!selectionInside(el)) {
            const range = document.createRange();
            range.selectNodeContents(el);
            range.collapse(false);
            const sel = window.getSelection();
            sel.removeAllRanges();
            sel.addRange(range);
        }
        const sel = window.getSelection();
        switch (cmd) {
            case 'code': {
                const code = closestInEditor(el, 'code');
                if (code) {
                    code.replaceWith(...code.childNodes);
                } else if (!sel.isCollapsed) {
                    const text = sel.toString();
                    document.execCommand('insertHTML', false, '<code>' + text.replace(/&/g, '&amp;').replace(/</g, '&lt;') + '</code>');
                }
                break;
            }
            case 'link': {
                const a = closestInEditor(el, 'a');
                if (a) {
                    document.execCommand('unlink');
                    break;
                }
                if (sel.isCollapsed) break;
                const url = window.prompt('Link URL');
                if (url && url.trim()) document.execCommand('createLink', false, url.trim());
                break;
            }
            case 'quote':
                document.execCommand('formatBlock', false, closestInEditor(el, 'blockquote') ? 'div' : 'blockquote');
                break;
            case 'clear': {
                if (sel.isCollapsed) document.execCommand('selectAll');
                document.execCommand('removeFormat');
                document.execCommand('unlink');
                // removeFormat leaves <code>, lists and quotes; flatten them to plain lines.
                const range = sel.rangeCount ? sel.getRangeAt(0) : null;
                el.querySelectorAll('code, pre, h1, h2, h3, h4').forEach((n) => {
                    if (!range || range.intersectsNode(n)) n.replaceWith(...n.childNodes);
                });
                break;
            }
            default:
                document.execCommand(cmd);
        }
        el.dispatchEvent(new Event('input', { bubbles: true }));
    }

    function activeFormats(el) {
        if (!selectionInside(el)) return {};
        const q = (c) => {
            try {
                return document.queryCommandState(c);
            } catch {
                return false;
            }
        };
        return {
            bold: q('bold'),
            italic: q('italic'),
            strikeThrough: q('strikeThrough'),
            insertUnorderedList: q('insertUnorderedList'),
            insertOrderedList: q('insertOrderedList'),
            code: !!closestInEditor(el, 'code'),
            link: !!closestInEditor(el, 'a'),
            quote: !!closestInEditor(el, 'blockquote'),
        };
    }

    window.RephraseEditor = {
        format,
        activeFormats,
        sanitizeHtml,
        editorToMarkdown,
        editorPlainText,
        markdownToHtml,
        handlePaste,
        applyDiffMarks,
        stripDiffMarks,
        htmlToPlainText,
        copyRich,
    };
})();
