// SPDX-License-Identifier: MIT
import MarkdownIt from 'markdown-it';
import anchor from 'markdown-it-anchor';
import alerts from 'markdown-it-github-alerts';
import emoji from 'markdown-it-emoji';
import footnote from 'markdown-it-footnote';
import tasks from 'markdown-it-task-lists';
import mark from 'markdown-it-mark';
import sub from 'markdown-it-sub';
import sup from 'markdown-it-sup';
import highlighter from './languages';

/** Build the parser from independently licensed public plugin APIs. */
export function createParser(): MarkdownIt {
    const parser = new MarkdownIt({html: true, typographer: true});
    for (const extension of [emoji, footnote, tasks, mark, sub, sup, alerts]) parser.use(extension);
    // Use markdown-it-anchor's MIT-licensed default; no application slug copy.
    parser.use(anchor);
    // Add source positions before rendering instead of overriding renderToken.
    parser.core.ruler.push('editor-source-position', state => {
        for (const token of state.tokens) {
            if (token.map && token.nesting >= 0) {
                token.attrSet('data-source-line', `${token.map[0] + 1}`);
                token.attrSet('data-source-line-end', `${token.map[1]}`);
            }
        }
    });
    parser.renderer.rules.fence = (tokens, index) => {
        const token = tokens[index];
        const language = token.info.trim().split(/\s+/)[0].toLowerCase();
        let content = parser.utils.escapeHtml(token.content);
        if (highlighter.getLanguage(language)) {
            try { content = highlighter.highlight(token.content, {language, ignoreIllegals: true}).value; }
            catch { /* Unknown or malformed code remains readable. */ }
        }
        const css = parser.utils.escapeHtml(`language-${language}`);
        const lines = token.map ? ` data-source-line="${token.map[0] + 1}" data-source-line-end="${token.map[1]}"` : '';
        return `<pre class="hljs"${lines}><code class="${css}">${content}</code></pre>\n`;
    };
    return parser;
}

/** Only relative document images and raster data URLs are accepted. */
export function localImageURL(input: string): string {
    const source = input.trim();
    if (/^data:image\/(png|jpeg|gif|webp);base64,[a-z0-9+/=\s]+$/i.test(source)) return source;
    if (!source || /^[\/\\]/.test(source) || /^[a-z][a-z\d+.-]*:/i.test(source)) return '';
    try {
        const result = new URL(source, 'mdasset://document/');
        return result.protocol === 'mdasset:' && result.hostname === 'document' ? result.href : '';
    } catch { return ''; }
}
