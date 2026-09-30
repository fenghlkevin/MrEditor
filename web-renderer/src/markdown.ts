// Adapted from FluxMarkdown, copyright (c) 2024-2026 xykong. GPL-3.0.
// Upstream: 733a664c57cbc5f23045e5f87d3ec7f3db17f947. See LICENSE and UPSTREAM.md.
import MarkdownIt from 'markdown-it';
import hljs from 'highlight.js/lib/core';
import * as jsyaml from 'js-yaml';

import langJavascript from 'highlight.js/lib/languages/javascript';
import langTypescript from 'highlight.js/lib/languages/typescript';
import langPython from 'highlight.js/lib/languages/python';
import langBash from 'highlight.js/lib/languages/bash';
import langShell from 'highlight.js/lib/languages/shell';
import langSql from 'highlight.js/lib/languages/sql';
import langJson from 'highlight.js/lib/languages/json';
import langYaml from 'highlight.js/lib/languages/yaml';
import langMarkdown from 'highlight.js/lib/languages/markdown';
import langCss from 'highlight.js/lib/languages/css';
import langXml from 'highlight.js/lib/languages/xml';
import langGo from 'highlight.js/lib/languages/go';
import langRust from 'highlight.js/lib/languages/rust';
import langJava from 'highlight.js/lib/languages/java';
import langC from 'highlight.js/lib/languages/c';
import langCpp from 'highlight.js/lib/languages/cpp';
import langSwift from 'highlight.js/lib/languages/swift';
import langKotlin from 'highlight.js/lib/languages/kotlin';
import langRuby from 'highlight.js/lib/languages/ruby';
import langPhp from 'highlight.js/lib/languages/php';
import langCsharp from 'highlight.js/lib/languages/csharp';
import langDiff from 'highlight.js/lib/languages/diff';
import langDockerfile from 'highlight.js/lib/languages/dockerfile';
import langNginx from 'highlight.js/lib/languages/nginx';
import langScala from 'highlight.js/lib/languages/scala';
import langPerl from 'highlight.js/lib/languages/perl';
import langR from 'highlight.js/lib/languages/r';
import langDart from 'highlight.js/lib/languages/dart';
import langLua from 'highlight.js/lib/languages/lua';
import langHaskell from 'highlight.js/lib/languages/haskell';
import langElixir from 'highlight.js/lib/languages/elixir';
import langGroovy from 'highlight.js/lib/languages/groovy';
import langVerilog from 'highlight.js/lib/languages/verilog';
import langVhdl from 'highlight.js/lib/languages/vhdl';
import langMakefile from 'highlight.js/lib/languages/makefile';
import langToml from 'highlight.js/lib/languages/ini';
import langProtobuf from 'highlight.js/lib/languages/protobuf';
import langGraphql from 'highlight.js/lib/languages/graphql';
import langPlaintext from 'highlight.js/lib/languages/plaintext';
import langPowershell from 'highlight.js/lib/languages/powershell';
import langObjectivec from 'highlight.js/lib/languages/objectivec';

hljs.registerLanguage('javascript', langJavascript);
hljs.registerLanguage('typescript', langTypescript);
hljs.registerLanguage('python', langPython);
hljs.registerLanguage('bash', langBash);
hljs.registerLanguage('shell', langShell);
hljs.registerLanguage('sql', langSql);
hljs.registerLanguage('json', langJson);
hljs.registerLanguage('yaml', langYaml);
hljs.registerLanguage('markdown', langMarkdown);
hljs.registerLanguage('css', langCss);
hljs.registerLanguage('xml', langXml);
hljs.registerLanguage('html', langXml);
hljs.registerLanguage('go', langGo);
hljs.registerLanguage('rust', langRust);
hljs.registerLanguage('java', langJava);
hljs.registerLanguage('c', langC);
hljs.registerLanguage('cpp', langCpp);
hljs.registerLanguage('swift', langSwift);
hljs.registerLanguage('kotlin', langKotlin);
hljs.registerLanguage('ruby', langRuby);
hljs.registerLanguage('php', langPhp);
hljs.registerLanguage('csharp', langCsharp);
hljs.registerLanguage('diff', langDiff);
hljs.registerLanguage('dockerfile', langDockerfile);
hljs.registerLanguage('nginx', langNginx);
hljs.registerLanguage('scala', langScala);
hljs.registerLanguage('perl', langPerl);
hljs.registerLanguage('r', langR);
hljs.registerLanguage('dart', langDart);
hljs.registerLanguage('lua', langLua);
hljs.registerLanguage('haskell', langHaskell);
hljs.registerLanguage('elixir', langElixir);
hljs.registerLanguage('groovy', langGroovy);
hljs.registerLanguage('verilog', langVerilog);
hljs.registerLanguage('vhdl', langVhdl);
hljs.registerLanguage('makefile', langMakefile);
hljs.registerLanguage('toml', langToml);
hljs.registerLanguage('ini', langToml);
hljs.registerLanguage('protobuf', langProtobuf);
hljs.registerLanguage('graphql', langGraphql);
hljs.registerLanguage('plaintext', langPlaintext);
hljs.registerLanguage('powershell', langPowershell);
hljs.registerLanguage('objectivec', langObjectivec);

const LANG_ALIASES: Record<string, string> = {
    'js': 'javascript',
    'ts': 'typescript',
    'py': 'python',
    'sh': 'bash',
    'rb': 'ruby',
    'kt': 'kotlin',
    'cs': 'csharp',
    'c++': 'cpp',
    'objc': 'objectivec',
    'ps1': 'powershell',
    'proto': 'protobuf',
    'gql': 'graphql',
    'mk': 'makefile',
    'text': 'plaintext',
    'hs': 'haskell',
    'ex': 'elixir',
    'exs': 'elixir',
};

function resolveLanguage(lang: string): string {
    const lower = lang.toLowerCase();
    return LANG_ALIASES[lower] ?? lower;
}

// @ts-ignore
import emoji from 'markdown-it-emoji';
// @ts-ignore
import footnote from 'markdown-it-footnote';
// @ts-ignore
import taskLists from 'markdown-it-task-lists';
// @ts-ignore
import mark from 'markdown-it-mark';
// @ts-ignore
import sub from 'markdown-it-sub';
// @ts-ignore
import sup from 'markdown-it-sup';
// @ts-ignore
import anchor from 'markdown-it-anchor';
import githubAlerts from 'markdown-it-github-alerts';


/**
 * Escapes colons inside Gantt task labels when the metadata delimiter is
 * written as a spaced colon. Mermaid's lexer always splits at the first raw
 * colon, while `#colon;` is decoded back to a visible colon after parsing.
 */
export function preprocessMermaidGanttTaskColons(code: string): string {
    let foundGanttHeader = false;
    const directivePattern = /^(?:%%|---|title\b|dateFormat\b|inclusiveEndDates\b|topAxis\b|axisFormat\b|tickInterval\b|includes\b|excludes\b|todayMarker\b|weekday\b|weekend\b|section\b|click\b|accTitle\b|accDescr(?:iption)?\b)/i;
    const taskTags = new Set(['active', 'done', 'crit', 'milestone', 'vert']);

    return code.replace(/[^\r\n]+/g, (line) => {
        const trimmedLine = line.trim();
        if (/^gantt$/i.test(trimmedLine)) {
            foundGanttHeader = true;
            return line;
        }
        if (!foundGanttHeader || !trimmedLine || directivePattern.test(trimmedLine)) {
            return line;
        }

        const delimiterPattern = /\s+:/g;
        let delimiterIndex = -1;
        let match: RegExpExecArray | null;
        while ((match = delimiterPattern.exec(line)) !== null) {
            const candidateIndex = match.index + match[0].length - 1;
            const fields = line.slice(candidateIndex + 1).split(',').map((field) => field.trim());
            while (fields.length > 0 && taskTags.has(fields[0].toLowerCase())) {
                fields.shift();
            }
            if (fields.length >= 1 && fields.length <= 3 && fields.every(Boolean)) {
                delimiterIndex = candidateIndex;
            }
        }

        const title = delimiterIndex >= 0 ? line.slice(0, delimiterIndex) : '';
        if (!title.includes(':')) {
            return line;
        }

        return title.replace(/:/g, '#colon;') + line.slice(delimiterIndex);
    });
}

/**
 * Pre-processes Mermaid diagram source code before handing it to mermaid.render().
 *
 * Mermaid v11 does NOT convert `\n` to `<br>` for unquoted node labels —
 * the `\n` passes through `marked` as literal text and is never line-broken.
 * Only double-quoted STR labels (`A["text\nline2"]`) get a `<br>` because they
 * go through a different internal path. Everything else needs pre-processing.
 *
 * Cases handled here:
 *   1. `participant/actor X as "label"` — quotes are preserved verbatim by
 *      Mermaid's parser; we strip them and convert any \n inside.
 *   2. Double-quoted labels `A["...\n..."]` — STR path; we convert \n.
 *   3. Unquoted bracket labels `A[...\n...]`, `A{...\n...}`, `A(...\n...)` —
 *      Mermaid passes \n as literal text; we convert to <br/>.
 *
 * The bracket passes use a character-class exclusion pattern so they never
 * touch content that starts with `"` (already handled by pass 2) and never
 * cross bracket boundaries.
 */
export function preprocessMermaidNewlines(code: string): string {
    // 1. Strip quotes from `participant/actor X as "label"` and convert \n.
    let result = code.replace(
        /((?:participant|actor)\s+\S+\s+as\s+)"((?:[^"\\]|\\.)*)"/g,
        (_match, prefix: string, inner: string) => prefix + inner.replace(/\\n/g, '<br/>')
    );

    // 2. Convert \n inside double-quoted node labels.
    result = result.replace(/"((?:[^"\\]|\\.)*)"/g, (_match, inner: string) => {
        return '"' + inner.replace(/\\n/g, '<br/>') + '"';
    });

    // 3a. Unquoted square-bracket labels: A[text\ntext]
    result = result.replace(/\[([^\]"]*?\\n[^\]"]*?)\]/g, (_match, inner: string) => {
        return '[' + inner.replace(/\\n/g, '<br/>') + ']';
    });

    // 3b. Unquoted round-bracket labels: A(text\ntext)
    result = result.replace(/\(([^)"]*?\\n[^)"]*?)\)/g, (_match, inner: string) => {
        return '(' + inner.replace(/\\n/g, '<br/>') + ')';
    });

    // 3c. Unquoted curly-bracket labels (diamond/hexagon nodes): A{text\ntext}
    result = result.replace(/\{([^}"]*?\\n[^}"]*?)\}/g, (_match, inner: string) => {
        return '{' + inner.replace(/\\n/g, '<br/>') + '}';
    });

    return result;
}

function escapeHtml(text: string): string {
    const map: Record<string, string> = {
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#039;'
    };
    return text.replace(/[&<>"']/g, (char) => map[char]);
}


function extractFrontMatter(text: string): { yaml: string | null; body: string } {
    if (!text.startsWith('---')) {
        return { yaml: null, body: text };
    }
    const normalized = text.replace(/\r\n/g, '\n');
    if (!normalized.startsWith('---\n')) return { yaml: null, body: text };
    text = normalized;
    const closing = /^---[ \t]*$/m.exec(text.slice(4));
    const endIndex = closing ? 3 + closing.index : -1;
    if (endIndex === -1) {
        return { yaml: null, body: text };
    }
    const yaml = text.slice(3, endIndex).trim();
    const body = text.slice(endIndex + 4).trimStart();
    return { yaml, body };
}

function yamlValueToHtml(value: unknown): string {
    if (value === null || value === undefined) return '';
    if (Array.isArray(value)) {
        return '<ul>' + value.map(v => `<li>${escapeHtml(String(v))}</li>`).join('') + '</ul>';
    }
    if (typeof value === 'object') {
        return yamlObjectToTable(value as Record<string, unknown>);
    }
    return escapeHtml(String(value));
}

function yamlObjectToTable(obj: Record<string, unknown>): string {
    const rows = Object.entries(obj).map(([k, v]) => {
        const isComplex = v !== null && typeof v === 'object';
        return `<tr><th>${escapeHtml(k)}</th><td>${isComplex ? yamlValueToHtml(v) : escapeHtml(String(v ?? ''))}</td></tr>`;
    }).join('');
    return `<table class="yaml-frontmatter"><tbody>${rows}</tbody></table>`;
}

function renderFrontMatterHtml(yamlStr: string): string {
    try {
        const parsed = jsyaml.load(yamlStr, { schema: jsyaml.JSON_SCHEMA });
        if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
            return `<pre class="hljs"><code class="language-yaml">${escapeHtml(yamlStr)}</code></pre>`;
        }
        return yamlObjectToTable(parsed as Record<string, unknown>);
    } catch {
        return `<pre class="hljs"><code class="language-yaml">${escapeHtml(yamlStr)}</code></pre>`;
    }
}

function buildMd(): MarkdownIt {
    const instance = new MarkdownIt({
        html: true,
        breaks: false,
        linkify: false,
        typographer: true,
        highlight: function (str: string, lang: string): string {
            const resolvedLang = resolveLanguage(lang);

            if (resolvedLang && hljs.getLanguage(resolvedLang)) {
                try {
                    return '<pre class="hljs"><code>' +
                        hljs.highlight(str, { language: resolvedLang, ignoreIllegals: true }).value +
                        '</code></pre>';
                } catch (__) { }
            }
            const codeClass = lang ? 'language-' + instance.utils.escapeHtml(lang) : '';
            return '<pre class="hljs"><code class="' + codeClass + '">' + instance.utils.escapeHtml(str) + '</code></pre>';
        }
    });

    const originalValidateLink = instance.validateLink.bind(instance);
    instance.validateLink = function(url: string): boolean {
        if (url.startsWith('mdasset://')) {
            return true;
        }
        return originalValidateLink(url);
    };

    instance.use(footnote);
    instance.use(taskLists);
    instance.use(mark);
    instance.use(sub);
    instance.use(sup);
    instance.use(anchor, {
        permalink: false,
        slugify: (s: string) => s.toLowerCase().replace(/[^\w\u4e00-\u9fa5]+/g, '-').replace(/^-+|-+$/g, '')
    });
    instance.use(githubAlerts);

    const defaultImageRender = instance.renderer.rules.image || function(tokens: any, idx: any, options: any, env: any, self: any) {
        return self.renderToken(tokens, idx, options);
    };

    instance.renderer.rules.image = function (tokens: any, idx: any, options: any, env: any, self: any) {
        const token = tokens[idx];
        const srcIndex = token.attrIndex('src');
        if (srcIndex >= 0) {
            const originalSrc = token.attrs[srcIndex][1];
            token.attrs[srcIndex][1] = resolveImageSource(originalSrc);
        }
        return defaultImageRender(tokens, idx, options, env, self);
    };

    const defaultRenderToken = instance.renderer.renderToken.bind(instance.renderer);
    instance.renderer.renderToken = function(tokens: any[], idx: number, options: any): string {
        const token = tokens[idx];
        if (token.map && token.map.length >= 2 && (token.nesting === 1 || token.nesting === 0)) {
            token.attrSet('data-source-line', String(token.map[0] + 1));
            token.attrSet('data-source-line-end', String(token.map[1]));
        }
        return defaultRenderToken(tokens, idx, options);
    };

    return instance;
}


export { buildMd, escapeHtml, extractFrontMatter, renderFrontMatterHtml };
export function resolveImageSource(source: string): string {
    if (!source.trim()) return '';
    if (/^data:image\/(?:png|jpeg|gif|webp);base64,/i.test(source)) return source;
    if (/^[a-z][a-z0-9+.-]*:/i.test(source) || source.startsWith('//') || source.startsWith('/')) return '';
    try { return new URL(source, 'mdasset://document/').href; } catch { return ''; }
}
export function createMarkdownParser() {
    return buildMd().use(emoji);
}
