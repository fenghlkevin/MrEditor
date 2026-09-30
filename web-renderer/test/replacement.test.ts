// @vitest-environment jsdom
import {beforeAll, describe, expect, it, vi} from 'vitest';
import {createParser, localImageURL} from '../src/parser';
import {metadataView, splitMetadata} from '../src/metadata';
import {labelBreaks, ganttLabels} from '../src/diagrams';
import {HeadingNavigation} from '../src/navigation';
import highlighter from '../src/languages';

beforeAll(() => {
    vi.stubGlobal('requestAnimationFrame', (fn: FrameRequestCallback) => { fn(0); return 1; });
    HTMLElement.prototype.scrollIntoView = vi.fn();
});

describe('replacement parser and metadata', () => {
    it('preserves heading links, duplicate IDs and source line metadata', () => {
        const root = document.createElement('main');
        root.innerHTML = createParser().render('# 中文\n\n## **Same** `code`\n\n## **Same** `code`');
        expect(Array.from(root.querySelectorAll('h1,h2'), h => h.id)).toEqual([encodeURIComponent('中文'), 'same-code', 'same-code-1']);
        expect(root.querySelector('h2')?.getAttribute('data-source-line')).toBe('3');
    });
    it('uses dependency slug rules for Unicode, punctuation and repeated headings', () => {
        const root = document.createElement('main');
        root.innerHTML = createParser().render('# Hello, 世界!\n\n# Hello, 世界!');
        expect(Array.from(root.querySelectorAll('h1'), h => h.id)).toEqual([
            encodeURIComponent('hello,-世界!'), encodeURIComponent('hello,-世界!') + '-1',
        ]);
    });
    it('keeps all supported grammar aliases available to code previews', () => {
        for (const language of ['js', 'ts', 'py', 'sh', 'rb', 'kt', 'cs', 'c++', 'objc', 'ps1', 'proto', 'gql', 'mk', 'text', 'hs', 'ex', 'exs', 'toml', 'html']) {
            expect(highlighter.getLanguage(language), language).toBeTruthy();
        }
    });
    it('renders every alert type and escapes unknown language attributes', () => {
        const parser = createParser();
        for (const name of ['NOTE','TIP','IMPORTANT','WARNING','CAUTION']) expect(parser.render(`> [!${name}]\n> text`)).toContain(`markdown-alert-${name.toLowerCase()}`);
        const root = document.createElement('div'); root.innerHTML = parser.render('```bad" onclick="evil\n<script>evil</script>\n```');
        expect(root.querySelector('[onclick],script')).toBeNull();
        expect(root.textContent).toContain('<script>');
    });
    it('renders nested metadata without interpreting markup or cycles', () => {
        const root = metadataView('title: "<script>bad</script>"\nitems: [a, b]\nchild: {x: 2}\nloop: &a [*a]');
        expect(root.querySelector('script')).toBeNull();
        expect(root.textContent).toContain('<script>bad</script>');
        expect(root.textContent).toContain('[YAML alias]');
        expect(root.querySelector('ul')).not.toBeNull();
    });
    it('bounds repeated YAML alias expansion', () => {
        const source = 'a: &a [1, 2, 3]\nb: &b [*a, *a, *a]\nc: &c [*b, *b, *b]\nd: &d [*c, *c, *c]\ne: &e [*d, *d, *d]\nf: [*e, *e, *e]';
        expect(metadataView(source).querySelectorAll('*').length).toBeLessThan(5000);
    });
    it('preserves malformed YAML as readable text', () => {
        for (const source of ['a: [', '- a\n- b', 'plain']) expect(metadataView(source).textContent).toBe(source);
        expect(splitMetadata('\uFEFF---\r\nx: 1\r\n---\r\nbody')).toEqual({yaml:'x: 1',body:'body'});
        expect(splitMetadata('---\nx: 1').body).toBe('---\nx: 1');
    });
    it('rejects disguised schemes and keeps raster data URLs', () => {
        for (const url of [' https://x/a.png', '\\server\\a.png', 'javascript:x', 'mdasset://other/a', 'data:image/svg+xml;base64,aaaa']) expect(localImageURL(url)).toBe('');
        expect(localImageURL('data:image/png;base64,YQ==')).toBe('data:image/png;base64,YQ==');
    });
});

describe('diagram compatibility', () => {
    it('supports bracket shapes, quotes and sequence aliases', () => {
        for (const label of ['A[a\\nb]', 'A(a\\nb)', 'A{a\\nb}', 'A["a\\nb"]']) expect(labelBreaks(label)).toContain('a<br/>b');
        expect(labelBreaks('participant A as "a\\nb"')).toBe('participant A as a<br/>b');
        expect(labelBreaks('%% A[a\\nb]')).toBe('%% A[a\\nb]');
        expect(labelBreaks('A --> B\\nC')).toBe('A --> B\\nC');
    });
    it('does not alter explicit entities or timestamps in valid Gantt input', () => {
        const source = 'gantt\n dateFormat YYYY-MM-DD HH:mm\n Work#colon; phase :job, 2026-09-30 09:30, 2h';
        expect(ganttLabels(source)).toBe(source);
        expect(ganttLabels('gantt\n Task :job, after first, 1d')).toBe('gantt\n Task :job, after first, 1d');
    });
    it('keeps gantt directives and metadata intact', () => {
        const source = 'gantt\ntitle API: plan\ndateFormat YYYY-MM-DD\nsection Phase: 1\nAPI: endpoint :crit, task, 2026-09-30, 1d';
        const result = ganttLabels(source);
        expect(result).toContain('title API: plan');
        expect(result).toContain('section Phase: 1');
        expect(result).toContain('API#colon; endpoint :crit, task, 2026-09-30, 1d');
        expect(ganttLabels('sequenceDiagram\nA->>B: hi')).toBe('sequenceDiagram\nA->>B: hi');
    });
});

describe('DOM-based contents', () => {
    it('uses rendered text, supports keyboard closing and survives empty documents', () => {
        const host = document.createElement('aside'); const content = document.createElement('main');
        document.body.replaceChildren(host, content);
        content.innerHTML = createParser().render('# **Bold** `code`\n\n### 子标题\n\n### 子标题');
        const nav = new HeadingNavigation(host, content); nav.refresh('zh-Hans');
        const button = host.querySelector('button')!; button.click();
        expect(button.getAttribute('aria-expanded')).toBe('true');
        expect(host.querySelector('a')?.textContent).toBe('Bold code');
        expect(host.querySelectorAll('a')).toHaveLength(3);
        (host.querySelectorAll('a')[2] as HTMLElement).click();
        expect(HTMLElement.prototype.scrollIntoView).toHaveBeenCalled();
        nav.refresh('en', false); expect(host.hidden).toBe(true);
        nav.refresh('en'); expect(host.querySelector('nav')?.hidden).toBe(false);
        host.querySelector('nav')!.dispatchEvent(new KeyboardEvent('keydown', {key:'Escape',bubbles:true}));
        expect(button.getAttribute('aria-expanded')).toBe('false');
        expect(document.activeElement).toBe(button);
    });
    it('tracks scrolled headings after render instead of retaining old observers', () => {
        const host = document.createElement('aside'); const content = document.createElement('main');
        document.body.replaceChildren(host, content); content.innerHTML = '<h1 id="a">A</h1><h2 id="b">B</h2>';
        const nav = new HeadingNavigation(host, content);
        const headings = content.querySelectorAll('h1,h2');
        headings[0].getBoundingClientRect = () => ({top:-100} as DOMRect);
        headings[1].getBoundingClientRect = () => ({top:30} as DOMRect);
        nav.refresh('en'); window.dispatchEvent(new Event('scroll'));
        expect(host.querySelector('.active')?.textContent).toBe('B');
        content.innerHTML = '<h2>New</h2>'; nav.refresh('en');
        expect(host.querySelector('.active')?.textContent).toBe('New');
        expect(content.querySelector('h2')?.id).toBeTruthy();
    });
});
