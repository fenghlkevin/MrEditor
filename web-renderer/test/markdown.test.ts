// @vitest-environment jsdom
import { beforeAll, describe, expect, it, vi } from 'vitest';
import {createParser as createMarkdownParser, localImageURL as resolveImageSource} from '../src/parser';
import {splitMetadata as extractFrontMatter} from '../src/metadata';
import {ganttLabels as preprocessMermaidGanttTaskColons, labelBreaks as preprocessMermaidNewlines} from '../src/diagrams';

beforeAll(async () => {
    vi.stubGlobal('IntersectionObserver', class { observe() {} disconnect() {} });
    Object.defineProperty(document, 'fonts', { value: { ready: Promise.resolve() } });
    document.body.innerHTML = '<div id="toc-container"></div><main id="markdown-preview"></main>';
    await import('../src/index');
});

describe('MrEditor document renderer', () => {
    it('renders GFM, language aliases, footnotes, alerts and inline extensions', () => {
        const html = createMarkdownParser().render('# 中文\n\n```js\nconst x = 42;\n```\n\n- [x] done\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n> [!NOTE]\n> hello\n\n==mark== H~2~O x^2^ ~~old~~ :smile: note[^1]\n\n[^1]: footnote');
        for (const value of ['hljs-keyword', 'checkbox', '<table ', 'markdown-alert', '<mark>', '<sub>', '<sup>', '<s>', 'footnote']) expect(html).toContain(value);
    });
    it('recognizes complete YAML delimiters and CRLF without eating horizontal rules', () => {
        expect(extractFrontMatter('---\r\na: 1\r\n---\r\n# Body')).toEqual({ yaml: 'a: 1', body: '# Body' });
        expect(extractFrontMatter('---no\na: 1\n---\n# Body').yaml).toBeNull();
        expect(extractFrontMatter('---\na: 1\n---suffix\n# Body').yaml).toBeNull();
    });
    it('scopes image URLs and rejects remote and absolute image paths', () => {
        expect(resolveImageSource('images/中文 图.png')).toBe('mdasset://document/images/%E4%B8%AD%E6%96%87%20%E5%9B%BE.png');
        for (const url of ['', 'https://example.com/a.png', '//example.com/a.png', 'file:///etc/a.png', '/tmp/a.png', 'javascript:alert(1)']) expect(resolveImageSource(url)).toBe('');
    });
    it('supports escaped Mermaid labels', () => {
        expect(preprocessMermaidNewlines('graph TD\nA[one\\ntwo]')).toContain('one<br/>two');
        expect(preprocessMermaidGanttTaskColons('gantt\nsection X\nAPI: endpoint :a, 2026-09-30, 1d')).toContain('API#colon; endpoint');
    });
    it('sanitizes document markup while preserving formatting and local images', async () => {
        await window.mrPreview.render('# Safe\n\n<img src="x.png" onerror="window.pwned=1"><script>window.pwned=1</script><iframe src="https://example.com"></iframe>\n\n<b>bold</b> [bad](javascript:alert)\n\n```unknown\" onclick=\"alert(1)\ncode\n```', { dark: false, revision: 1, language: 'zh-Hans' });
        const output = document.getElementById('markdown-preview')!;
        expect(output.querySelector('script,iframe,[onerror],[onclick]')).toBeNull();
        expect(output.querySelector('b')?.textContent).toBe('bold');
        expect(output.querySelector('img')?.getAttribute('src')).toBe('mdasset://document/x.png?revision=1');
    });
    it('navigates Unicode fragments using dependency-generated heading IDs', async () => {
        HTMLElement.prototype.scrollIntoView = vi.fn();
        await window.mrPreview.render('# 中文\n\n[跳转](#中文)', {dark:false, revision:20, language:'zh-Hans'});
        const heading = document.querySelector('h1')!;
        expect(heading.id).toBe(encodeURIComponent('中文'));
        (document.querySelector('#markdown-preview a') as HTMLElement).click();
        expect(heading.scrollIntoView).toHaveBeenCalled();
    });
    it('renders math, preserves an open TOC after edits, and gives the latest request priority', async () => {
        await window.mrPreview.render('# Before\n\n$E=mc^2$', { dark: false, revision: 2, language: 'en' });
        expect(document.querySelector('.katex')).not.toBeNull();
        (document.querySelector('.toc-toggle') as HTMLElement).click();
        const first = window.mrPreview.render('# Obsolete', { dark: false, revision: 3, language: 'en' });
        const last = window.mrPreview.render('# 最终版本\n\n## 子标题', { dark: true, revision: 4, language: 'zh-Hans' });
        expect(await first).toBe(false);
        expect(await last).toBe(true);
        expect(document.querySelector('h1')?.textContent).toBe('最终版本');
        expect(document.querySelectorAll('.toc-link')).toHaveLength(2);
        expect(document.querySelector('.toc-nav.visible')).not.toBeNull();
        expect(document.documentElement.dataset.theme).toBe('dark');
    });
    it('cancels queued rendering when the native preview is suspended', async () => {
        const result = window.mrPreview.render('# Cancelled', { dark: false, revision: 5, language: 'en' });
        window.mrPreview.cancel();
        expect(await result).toBe(false);
        expect(document.querySelector('h1')?.textContent).toBe('最终版本');
    });
});
