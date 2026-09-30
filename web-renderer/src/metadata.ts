// SPDX-License-Identifier: MIT
import {load, JSON_SCHEMA} from 'js-yaml';

export function splitMetadata(source: string): {yaml: string | null; body: string} {
    const lines = source.replace(/^\uFEFF/, '').split(/\r?\n/);
    if (lines[0] !== '---') return {yaml: null, body: source};
    const end = lines.findIndex((line, index) => index > 0 && /^---[ \t]*$/.test(line));
    if (end < 0) return {yaml: null, body: source};
    return {yaml: lines.slice(1, end).join('\n').trim(), body: lines.slice(end + 1).join('\n').trimStart()};
}

/** Construct metadata with DOM text nodes, with bounds for YAML alias graphs. */
export function metadataView(yaml: string): HTMLElement {
    const fallback = () => {
        const pre = document.createElement('pre');
        pre.className = 'yaml-frontmatter-error';
        pre.textContent = yaml;
        return pre;
    };
    try {
        const value = load(yaml, {schema: JSON_SCHEMA});
        if (!value || typeof value !== 'object' || Array.isArray(value)) return fallback();
        let remaining = 2000;
        const ancestors = new Set<object>();
        const cell = (value: unknown, depth: number): Node => {
            if (--remaining < 0 || depth > 12) return document.createTextNode('…');
            if (value === null || typeof value !== 'object') return document.createTextNode(String(value ?? ''));
            if (ancestors.has(value)) return document.createTextNode('[YAML alias]');
            ancestors.add(value);
            const element = document.createElement(Array.isArray(value) ? 'ul' : 'table');
            if (Array.isArray(value)) {
                for (const child of value) {
                    if (remaining < 0) break;
                    const li = document.createElement('li');
                    li.append(cell(child, depth + 1)); element.append(li);
                }
            } else {
                element.className = 'yaml-frontmatter';
                const body = document.createElement('tbody'); element.append(body);
                for (const [key, child] of Object.entries(value)) {
                    if (remaining < 0) break;
                    const tr = document.createElement('tr');
                    const th = document.createElement('th'); th.textContent = key;
                    const td = document.createElement('td'); td.append(cell(child, depth + 1));
                    tr.append(th, td); body.append(tr);
                }
            }
            ancestors.delete(value);
            return element;
        };
        return cell(value, 0) as HTMLElement;
    } catch { return fallback(); }
}
