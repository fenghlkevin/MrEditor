// SPDX-License-Identifier: MIT
/** Normalize escaped label line breaks without changing statement boundaries. */
export function labelBreaks(source: string): string {
    return source.split('\n').map(line => {
        if (line.trimStart().startsWith('%%')) return line;
        const actor = /^(\s*(?:participant|actor)\s+\S+\s+as\s+)(.*)$/.exec(line);
        if (actor) {
            let label = actor[2];
            if (label.startsWith('"') && label.endsWith('"')) label = label.slice(1, -1);
            return actor[1] + label.replaceAll('\\n', '<br/>');
        }
        const stack: string[] = [];
        let quoted = false;
        let result = '';
        for (let i = 0; i < line.length; i++) {
            const ch = line[i];
            if (ch === '\\' && i + 1 < line.length) {
                const next = line[++i];
                result += next === 'n' && (quoted || stack.length) ? '<br/>' : ch + next;
                continue;
            }
            if (ch === '"') quoted = !quoted;
            if (!quoted) {
                const closer = ({'[': ']', '(': ')', '{': '}'} as Record<string, string>)[ch];
                if (closer) stack.push(closer);
                else if (stack.at(-1) === ch) stack.pop();
            }
            result += ch;
        }
        return result;
    }).join('\n');
}

/** MrEditor compatibility policy for legacy task labels, not Mermaid syntax.
 * Specification basis: https://mermaid.js.org/syntax/gantt.html#syntax
 * Mermaid reserves ':' as the title/metadata separator. Our extension chooses
 * the last whitespace-prefixed colon; ambiguous input can use #colon; explicitly.
 * The scanner is application code; the directive names and entity notation are
 * Mermaid language vocabulary. See UPSTREAM.md for provenance and limitations.
 */
export function ganttLabels(source: string): string {
    if (!/^\s*gantt\s*$/mi.test(source)) return source;
    let inTasks = false;
    return source.split('\n').map(line => {
        const text = line.trim();
        if (text === 'gantt') { inTasks = true; return line; }
        if (!inTasks || /^(%%|---|title\b|section\b|dateFormat\b|axisFormat\b|tickInterval\b|excludes\b|includes\b|todayMarker\b|weekday\b|weekend\b|click\b|acc\w*\b|topAxis\b|inclusiveEndDates\b)/i.test(text)) return line;
        let delimiter = -1;
        for (let i = 1; i < line.length; i++) if (line[i] === ':' && /\s/.test(line[i - 1])) delimiter = i;
        if (delimiter < 0 || !line.slice(delimiter + 1).trim()) return line;
        return line.slice(0, delimiter).replaceAll(':', '#colon;') + line.slice(delimiter);
    }).join('\n');
}
