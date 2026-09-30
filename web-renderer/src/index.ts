// FluxMarkdown-derived preview integration. See ../UPSTREAM.md and ../LICENSE.
import 'github-markdown-css/github-markdown.css';
import 'katex/dist/katex.min.css';
import './styles/highlight-adaptive.css';
import './styles/callouts.css';
import './styles/table-of-contents.css';
import './styles/preview.css';
import DOMPurify from 'dompurify';
import {structured, tableView, codeView, safeMarkup} from './formats';
import {installSearch} from './search';
import {
    createMarkdownParser, extractFrontMatter, renderFrontMatterHtml, resolveImageSource,
    preprocessMermaidGanttTaskColons, preprocessMermaidNewlines,
} from './markdown';
import { extractHeadings, buildHeadingTree } from './outline';
import { TableOfContents } from './table-of-contents';

const md = createMarkdownParser();
const output = document.getElementById('markdown-preview')!;
const toc = new TableOfContents('toc-container');
const search = installSearch(output);
let latestSource = '';
let sourceMode = false;
const sourceToggle = document.createElement('button');
sourceToggle.textContent = '‹›';
sourceToggle.title = '查看源码';
sourceToggle.setAttribute('aria-label', '查看源码');
sourceToggle.className = 'preview-source-toggle';
search.bar.append(sourceToggle);
sourceToggle.onclick = () => { sourceMode = !sourceMode; sourceToggle.title = sourceMode ? '返回预览' : '查看源码'; sourceToggle.setAttribute('aria-label', sourceToggle.title); sourceToggle.setAttribute('aria-pressed', String(sourceMode)); if (latestOptions) window.mrPreview.render(latestSource, latestOptions); };
let latestOptions: {dark:boolean;revision:number;language:string;format?:string;syntax?:string} | undefined;
let generation = 0;
let pending: Promise<unknown> = Promise.resolve();
let katexLoaded = false;
let mermaid: typeof import('mermaid')['default'] | undefined;

// Sanitize before any document-provided HTML enters the live DOM. CSP also
// prevents document scripts, remote requests and embedded frames.
export function sanitizeDocument(html: string): string {
    return DOMPurify.sanitize(html, {
        ADD_URI_SAFE_ATTR: ['data-source-line', 'data-source-line-end'],
        ADD_ATTR: ['target'],
        ALLOWED_URI_REGEXP: /^(?:(?:https?|mailto|mdasset):|[^a-z]|[a-z+.-]+(?:[^a-z+.:\-]|$))/i,
        FORBID_TAGS: ['style', 'link', 'meta', 'base', 'iframe', 'object', 'embed', 'form', 'button', 'textarea', 'select'],
        FORBID_ATTR: ['srcset', 'autofocus'],
    });
}

async function render(source: string, options: { dark: boolean; revision: number; language: string; format?: string; syntax?: string }, request: number) {
    if (request !== generation) return false;
    latestSource = source; latestOptions = options;
    document.documentElement.dataset.theme = options.dark ? 'dark' : 'light';
    const format = options.format ?? 'markdown';
    if(sourceMode || !['markdown','mermaid'].includes(format)) {
        const root = sourceMode ? codeView(source, options.syntax ?? 'text') :
            format === 'json' || format === 'yaml' ? structured(source, format === 'yaml') :
            format === 'csv' || format === 'tsv' ? tableView(source, format === 'csv' ? ',' : '\t') :
            format === 'html' || format === 'svg' ? safeMarkup(source, format === 'svg') : codeView(source, options.syntax ?? 'text');
        if(request !== generation) return false;
        search.clear(); output.replaceChildren(root); output.dataset.revision=String(options.revision); toc.render([]); search.refresh(); return true;
    }
    const { yaml, body } = extractFrontMatter(format === 'mermaid' ? '````````mermaid\n' + source + '\n````````' : source);
    if (!katexLoaded && body.includes('$')) {
        const { default: katex } = await import('@iktakahiro/markdown-it-katex');
        md.use(katex, { throwOnError: false, trust: false, maxExpand: 1000 });
        katexLoaded = true;
    }
    if (request !== generation) return false;
    const tokens = md.parse(body, {});
    const headings = buildHeadingTree(extractHeadings(tokens));
    const root = document.createElement('div');
    root.innerHTML = sanitizeDocument((yaml ? renderFrontMatterHtml(yaml) : '') + md.renderer.render(tokens, md.options, {}));
    root.querySelectorAll('img').forEach(img => {
        const src = img.getAttribute('src') || '';
        // Markdown images have already been rewritten; raw HTML images have not.
        const resolved = src.startsWith('mdasset://document/') ? src : resolveImageSource(src);
        if (resolved) img.setAttribute('src', resolved.startsWith('mdasset:') ? resolved.split('?')[0] + `?revision=${options.revision}` : resolved);
        else img.removeAttribute('src');
        img.loading = 'lazy';
        img.addEventListener('error', () => img.classList.add('image-load-failed'));
    });

    const diagrams = root.querySelectorAll<HTMLElement>('pre code.language-mermaid');
    if (diagrams.length) {
        mermaid ??= (await import('mermaid')).default;
        if (request !== generation) return false;
        mermaid.initialize({
            startOnLoad: false, securityLevel: 'strict', suppressErrorRendering: true,
            theme: options.dark ? 'dark' : 'default', htmlLabels: false,
            flowchart: { htmlLabels: false }, maxTextSize: 50000, maxEdges: 500,
        });
        for (let index = 0; index < diagrams.length; index++) {
            if (request !== generation) return false;
            const block = diagrams[index];
            const diagram = document.createElement('div');
            diagram.className = 'mermaid-diagram';
            const code = block.textContent || '';
            try {
                const normalized = preprocessMermaidNewlines(preprocessMermaidGanttTaskColons(code));
                const { svg } = await mermaid.render(`mr-diagram-${request}-${index}`, normalized);
                diagram.innerHTML = DOMPurify.sanitize(svg, { USE_PROFILES: { svg: true, svgFilters: true } });
            } catch (error) {
                const details = document.createElement('details');
                details.open = true;
                const summary = document.createElement('summary');
                summary.textContent = options.language.startsWith('zh') ? 'Mermaid 图表语法错误' : 'Mermaid syntax error';
                const pre = document.createElement('pre');
                pre.textContent = `${String(error)}\n\n${code}`;
                details.append(summary, pre);
                diagram.append(details);
            }
            block.parentElement?.replaceWith(diagram);
        }
    }
    if (request !== generation) return false;
    document.documentElement.dataset.theme = options.dark ? 'dark' : 'light';
    document.documentElement.lang = options.language;
    search.clear();
    output.replaceChildren(...root.childNodes);
    search.refresh();
    output.dataset.revision = String(options.revision);
    toc.render(headings);
    toc.observeHeadings();
    const chinese = options.language.startsWith('zh');
    const toggle = document.querySelector('.toc-toggle');
    toggle?.setAttribute('aria-label', chinese ? '显示或隐藏目录' : 'Toggle contents');
    toggle?.setAttribute('title', chinese ? '目录' : 'Contents');
    const title = document.querySelector('.toc-title');
    if (title) title.textContent = chinese ? '目录' : 'Contents';
    await document.fonts.ready;
    return request === generation;
}

window.mrPreview = {
    render(source, options) {
        const request = ++generation;
        // Mermaid and markdown-it plugin state are shared. Serialize rendering,
        // skip superseded requests, and commit each document atomically.
        const result = pending.then(() => render(source, options, request));
        pending = result.catch(() => undefined);
        return result;
    },
    cancel() { generation++; },
};

document.addEventListener('click', event => {
    const target = event.target;
    if (!(target instanceof Element)) return;
    const anchor = target.closest('a');
    const href = anchor?.getAttribute('href');
    if (!href?.startsWith('#')) return;
    event.preventDefault();
    try {
        const id = decodeURIComponent(href.slice(1));
        // Scope lookup to document content, so raw HTML cannot target app UI.
        const element = Array.from(output.querySelectorAll('[id]')).find(node => node.id === id);
        element?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    } catch { /* Malformed document anchors are inert. */ }
});

window.webkit?.messageHandlers?.markdownRenderer?.postMessage('ready');
