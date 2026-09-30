// SPDX-License-Identifier: MIT
import 'github-markdown-css/github-markdown.css';
import 'katex/dist/katex.min.css';
import 'highlight.js/styles/github.css';
import 'highlight.js/styles/github-dark.css';
import 'markdown-it-github-alerts/styles/github-base.css';
import './styles/components.css';
import './styles/preview.css';
import DOMPurify from 'dompurify';
import {createParser, localImageURL} from './parser';
import {splitMetadata, metadataView} from './metadata';
import {labelBreaks, ganttLabels} from './diagrams';
import {HeadingNavigation} from './navigation';
import {structured, tableView, codeView, safeMarkup} from './formats';
import {installSearch} from './search';

type Options = Parameters<Window['mrPreview']['render']>[1];
const content = document.getElementById('markdown-preview')!;
const search = installSearch(content);
const navigation = new HeadingNavigation(document.getElementById('toc-container')!, content);
const parser = createParser();
let mathReady = false;
let diagramEngine: typeof import('mermaid')['default'] | undefined;
let serial: Promise<unknown> = Promise.resolve();
let version = 0;
let sourceView = false;
let current: {source: string; options: Options} | undefined;

const sourceButton = document.createElement('button');
sourceButton.className = 'preview-source-toggle';
sourceButton.textContent = '‹›';
sourceButton.type = 'button';
search.bar.append(sourceButton);
sourceButton.onclick = () => {
    sourceView = !sourceView;
    if (current) void window.mrPreview.render(current.source, current.options);
};

function updateControls(options: Options): void {
    const chinese = options.language.startsWith('zh');
    const japanese = options.language.startsWith('ja');
    const label = sourceView ? (chinese ? '返回预览' : japanese ? 'プレビュー' : 'Show preview') :
        (chinese ? '查看源码' : japanese ? 'ソースを表示' : 'Show source');
    sourceButton.title = label;
    sourceButton.setAttribute('aria-label', label);
    sourceButton.setAttribute('aria-pressed', String(sourceView));
    document.documentElement.lang = options.language;
    document.documentElement.dataset.theme = options.dark ? 'dark' : 'light';
}

function cleanHTML(html: string): string {
    return DOMPurify.sanitize(html, {
        FORBID_TAGS: ['style', 'link', 'meta', 'base', 'iframe', 'object', 'embed', 'form', 'button', 'textarea', 'select'],
        FORBID_ATTR: ['srcset', 'autofocus'],
    });
}

function rewriteImages(root: HTMLElement, revision: number): void {
    for (const image of root.querySelectorAll('img')) {
        const path = localImageURL(image.getAttribute('src') ?? '');
        image.removeAttribute('src');
        if (path) {
            if (path.startsWith('mdasset:')) {
                const url = new URL(path); url.searchParams.set('revision', String(revision));
                image.src = url.href;
            } else image.src = path;
        }
        image.loading = 'lazy';
        image.onerror = () => image.classList.add('image-load-failed');
    }
}

async function renderDiagrams(root: HTMLElement, options: Options, ticket: number): Promise<void> {
    const blocks = root.querySelectorAll<HTMLElement>('code.language-mermaid');
    if (!blocks.length) return;
    diagramEngine ??= (await import('mermaid')).default;
    if (ticket !== version) return;
    diagramEngine.initialize({startOnLoad: false, securityLevel: 'strict', suppressErrorRendering: true,
        theme: options.dark ? 'dark' : 'default', htmlLabels: false,
        flowchart: {htmlLabels: false}, maxTextSize: 50000, maxEdges: 500});
    let index = 0;
    for (const block of blocks) {
        if (ticket !== version) return;
        const view = document.createElement('div'); view.className = 'mermaid-diagram';
        const source = block.textContent ?? '';
        try {
            const rendered = await diagramEngine.render(`preview-${ticket}-${++index}`, labelBreaks(ganttLabels(source)));
            view.innerHTML = DOMPurify.sanitize(rendered.svg, {USE_PROFILES: {svg: true, svgFilters: true}});
        } catch (error) {
            const details = document.createElement('details'); details.open = true;
            const summary = document.createElement('summary');
            summary.textContent = options.language.startsWith('zh') ? 'Mermaid 图表语法错误' : 'Mermaid syntax error';
            const pre = document.createElement('pre'); pre.textContent = `${error}\n\n${source}`;
            details.append(summary, pre); view.append(details);
        }
        block.closest('pre')?.replaceWith(view);
    }
}

async function createDocument(source: string, options: Options, ticket: number): Promise<HTMLElement> {
    const format = options.format ?? 'markdown';
    if (sourceView) return codeView(source, options.syntax ?? 'text');
    switch (format) {
        case 'json': return structured(source, false);
        case 'yaml': return structured(source, true);
        case 'csv': return tableView(source, ',');
        case 'tsv': return tableView(source, '\t');
        case 'html': return safeMarkup(source, false);
        case 'svg': return safeMarkup(source, true);
        case 'markdown': case 'mermaid': break;
        default: return codeView(source, options.syntax ?? 'text');
    }
    const root = document.createElement('div');
    if (format === 'mermaid') {
        const pre = document.createElement('pre'); const code = document.createElement('code');
        code.className = 'language-mermaid'; code.textContent = source;
        pre.append(code); root.append(pre);
    } else {
        const {yaml, body} = splitMetadata(source);
        if (!mathReady && body.includes('$')) {
            const math = await import('@iktakahiro/markdown-it-katex');
            parser.use(math.default, {trust: false, throwOnError: false, maxExpand: 1000});
            mathReady = true;
        }
        if (ticket !== version) return root;
        root.innerHTML = cleanHTML(parser.render(body));
        if (yaml !== null && yaml !== '') root.prepend(metadataView(yaml));
        rewriteImages(root, options.revision);
    }
    await renderDiagrams(root, options, ticket);
    return root;
}

window.mrPreview = {
    render(source, options) {
        current = {source, options};
        const ticket = ++version;
        const task = serial.then(async () => {
            if (ticket !== version) return false;
            updateControls(options);
            const root = await createDocument(source, options, ticket);
            if (ticket !== version) return false;
            search.clear();
            // Keep interactive format wrappers, but preserve Markdown block layout.
            if (!sourceView && ['markdown', 'mermaid'].includes(options.format ?? 'markdown')) content.replaceChildren(...root.childNodes);
            else content.replaceChildren(root);
            navigation.refresh(options.language, !sourceView && (options.format ?? 'markdown') === 'markdown');
            search.refresh();
            await document.fonts.ready;
            if (ticket !== version) return false;
            content.dataset.revision = String(options.revision);
            return true;
        });
        serial = task.catch(() => undefined);
        return task;
    },
    cancel() { version++; },
};

content.addEventListener('click', event => {
    const anchor = (event.target as Element).closest('a');
    const target = anchor?.getAttribute('href');
    if (!target?.startsWith('#')) return;
    event.preventDefault();
    try {
        const id = decodeURIComponent(target.substring(1));
        Array.from(content.querySelectorAll<HTMLElement>('[id]')).find(node =>
            node.id === id || node.id === encodeURIComponent(id))
            ?.scrollIntoView({behavior: 'smooth', block: 'start'});
    } catch { /* Invalid percent escapes do not navigate out of the document. */ }
});
window.webkit?.messageHandlers?.markdownRenderer?.postMessage('ready');
