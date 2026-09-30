import hljs from './languages';
import { loadAll, JSON_SCHEMA } from 'js-yaml';
import DOMPurify from 'dompurify';

export function parseDelimited(source: string, delimiter: string, limit = 2000): {rows: string[][]; truncated: boolean} {
    const rows: string[][] = []; let row: string[] = [], field = '', quoted = false, closed = false;
    for (let i = 0; i < source.length; i++) {
        const c = source[i];
        if (quoted) { if (c === '"') { if (source[i + 1] === '"') { field += '"'; i++; } else { quoted = false; closed = true; } } else field += c; continue; }
        if (c === '"' && !field && !closed) { quoted = true; continue; }
        if (c === delimiter || c === '\n' || c === '\r') {
            row.push(field); field = ''; closed = false;
            if (c !== delimiter) { if (c === '\r' && source[i + 1] === '\n') i++; rows.push(row); row = []; if (rows.length >= limit + 1) return {rows, truncated: i < source.length - 1}; }
        } else { if (closed && c !== ' ' && c !== '\t') throw new Error('引号结束后存在无效字符 / Invalid character after quote'); field += c; }
    }
    if (quoted) throw new Error('未闭合的引号 / Unterminated quoted field');
    if (field || row.length || closed) { row.push(field); rows.push(row); }
    return { rows, truncated: false };
}
const make = <K extends keyof HTMLElementTagNameMap>(tag: K, text?: string) => { const e = document.createElement(tag); if (text !== undefined) e.textContent = text; return e; };
const button = (label: string, action: () => void) => { const b = make('button', label); b.type = 'button'; b.onclick = action; return b; };

export function structured(source: string, yaml: boolean): HTMLElement {
    const root = make('section');
    try {
        const docs = yaml ? loadAll(source, undefined, {schema: JSON_SCHEMA}) : [JSON.parse(source)];
        let budget = 10000; const seen = new WeakSet<object>();
        function node(key: string, value: unknown, depth: number): HTMLElement {
            if (--budget < 0 || depth > 40) return make('p', '… 达到树形展示上限 / Tree display limit');
            if (value !== null && typeof value === 'object') {
                if (seen.has(value)) return make('p', key + ': ↩ YAML alias'); seen.add(value);
                const d = make('details'); d.open = depth < 2;
                const entries = Object.entries(value); d.append(make('summary', `${key} ${Array.isArray(value) ? '[' : '{'}${entries.length}${Array.isArray(value) ? ']' : '}'}`));
                const children = make('div'); children.className = 'tree-children';
                for (const [k, v] of entries) { children.append(node(k, v, depth + 1)); if (budget < 0) break; }
                d.append(children); return d;
            }
            const p = make('div'); p.className = 'tree-value'; p.append(make('strong', key + ': '), make('code', JSON.stringify(value) ?? String(value))); return p;
        }
        root.append(button('展开全部 / Expand', () => root.querySelectorAll('details').forEach(d => d.open = true)), button('折叠全部 / Collapse', () => root.querySelectorAll('details').forEach(d => d.open = false)));
        docs.forEach((d, i) => root.append(node(docs.length > 1 ? `Document ${i + 1}` : '$', d, 0)));
    } catch (error) { const e = error as {message?: string; mark?: {line: number; column: number}}; root.append(make('h3', '格式错误 / Parse error'), make('pre', `${e.mark ? `行 / Line ${e.mark.line + 1}, 列 / Column ${e.mark.column + 1}\n` : ''}${e.message ?? error}`), codeView(source, yaml ? 'yaml' : 'json')); }
    return root;
}
export function tableView(source: string, delimiter: string): HTMLElement {
    const root = make('section');
    try {
        const {rows, truncated} = parseDelimited(source, delimiter); const header = rows.shift() ?? [];
        const columns = Math.min(200, Math.max(header.length, ...rows.map(r => r.length), 0));
        const originalRows = rows.length; const maxRows = Math.max(1, Math.floor(30000 / Math.max(1, columns))); rows.splice(maxRows);
        const note = make('p', `${rows.length} 行 / rows · ${columns} 列 / columns${truncated || originalRows > rows.length ? ' · 已截取 / Truncated preview' : ''}${header.length > 200 ? ' · 仅前 200 列 / First 200 columns' : ''}`);
        const filter = make('input'); filter.type = 'search'; filter.placeholder = '筛选表格 / Filter rows'; filter.setAttribute('aria-label', filter.placeholder);
        const scroll = make('div'); scroll.className = 'data-table-scroll'; const table = make('table'); const head = make('thead'), tr = make('tr'), body = make('tbody');
        let sorted = rows.slice(), sortColumn = -1, ascending = true;
        function refresh() { const q = filter.value.toLocaleLowerCase(); body.replaceChildren(); for (const row of sorted) { if (q && !row.some(v => v.toLocaleLowerCase().includes(q))) continue; const line = make('tr'); for (let i=0;i<columns;i++) { const td = make('td', row[i] ?? ''); line.append(td); } body.append(line); } if(root.isConnected) root.dispatchEvent(new Event('preview-content-changed', {bubbles:true})); }
        for (let i = 0; i < columns; i++) { const th = make('th'); th.style.resize = 'horizontal'; th.style.overflow = 'auto'; const b = button(header[i] || `Column ${i+1}`, () => { ascending = sortColumn === i ? !ascending : true; sortColumn = i; sorted = rows.slice().sort((a,b) => (a[i] ?? '').localeCompare(b[i] ?? '', undefined, {numeric:true}) * (ascending ? 1 : -1)); head.querySelectorAll('th').forEach(h => h.removeAttribute('aria-sort')); th.setAttribute('aria-sort', ascending ? 'ascending':'descending'); refresh(); }); th.append(b); tr.append(th); }
        filter.oninput = refresh; head.append(tr); table.append(head, body); scroll.append(table); root.append(note, filter, scroll); refresh();
    } catch (error) { root.append(make('h3', 'CSV / TSV 格式错误'), make('pre', String(error)), codeView(source, 'text')); }
    return root;
}
export function codeView(source: string, language: string): HTMLElement {
    const root = make('section'); const wrap = button('自动换行 / Wrap lines', () => pre.classList.toggle('wrap-lines'));
    const pre = make('pre'); pre.className = 'source-lines';
    const lines = source.slice(0, 500000).split('\n'); const truncated = lines.length > 10000 || source.length > 500000;
    // Highlight a bounded document once, then split into line spans without losing multiline token state.
    const bounded = lines.slice(0,10000).join('\n');
    const container = make('code');
    if (hljs.getLanguage(language)) container.innerHTML = DOMPurify.sanitize(hljs.highlight(bounded, {language, ignoreIllegals:true}).value);
    else container.textContent = bounded;
    if (language === 'log') {
        container.replaceChildren(); lines.slice(0,10000).forEach((line,i) => { const span = make('span', `${i ? '\n' : ''}${String(i+1).padStart(5)}  ${line}`); span.className = /\b(ERROR|FATAL|SEVERE)\b/i.test(line) ? 'log-error' : /\bWARN(?:ING)?\b/i.test(line) ? 'log-warning' : /\b(?:INFO|DEBUG|TRACE)\b/i.test(line) ? 'log-info' : ''; container.append(span); });
    } else {
        const gutter = make('span', lines.slice(0,10000).map((_,i)=>i+1).join('\n')); gutter.className = 'line-numbers'; gutter.setAttribute('aria-hidden','true'); pre.append(gutter);
    }
    pre.append(container); root.append(wrap); if(truncated) root.append(make('p','代码预览已截取（最多 10000 行 / 500000 字符） / Code preview truncated')); root.append(pre); return root;
}
export function safeMarkup(source: string, svg: boolean): HTMLElement {
    const root = make('section'); root.className = svg ? 'svg-preview' : 'html-preview';
    root.innerHTML = DOMPurify.sanitize(source, {
        USE_PROFILES: svg ? {svg:true, svgFilters:true} : {html:true, svg:true},
        FORBID_TAGS: ['script','style','link','meta','base','iframe','object','embed','form','input','button','textarea','select','foreignObject','animate','set'],
        FORBID_ATTR: ['style','srcset','autofocus'],
    });
    root.querySelectorAll('*').forEach(e => { for (const a of Array.from(e.attributes)) { if (['href','xlink:href','src'].includes(a.name) && !a.value.startsWith('#')) e.removeAttribute(a.name); if (/url\(/i.test(a.value) && !/^url\(\s*#[\w-]+\s*\)$/.test(a.value)) e.removeAttribute(a.name); } });
    return root;
}
