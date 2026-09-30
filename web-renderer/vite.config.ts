import { defineConfig } from 'vite';

export default defineConfig({
  base: './',
  plugins: [{
    name: 'webkit-local-modules',
    transformIndexHtml: { order: 'post', handler: html => html.replace(/ crossorigin/g, '') },
  }],
  css: { postcss: { plugins: [{
    postcssPlugin: 'mreditor-explicit-theme',
    Rule(rule: any) {
      const file = rule.source?.input.file?.replaceAll('\\', '/') ?? '';
      const theme = file.endsWith('/highlight.js/styles/github-dark.css') ? 'dark' : file.endsWith('/highlight.js/styles/github.css') ? 'light' : null;
      if (theme) rule.selectors = rule.selectors.map((selector: string) => `[data-theme="${theme}"] ${selector}`);
    },
    AtRule(rule: any) {
      const match = rule.name === 'media' && rule.params.match(/^\(prefers-color-scheme: (dark|light)\)$/);
      if (!match) return;
      rule.walkRules((child: any) => {
        child.selectors = child.selectors.map((selector: string) => `[data-theme="${match[1]}"] ${selector}`);
      });
      rule.replaceWith(...rule.nodes);
    },
  }] } },
  build: {
    target: 'safari16',
    outDir: '../Sources/MrEditorCore/Resources/MarkdownPreview',
    emptyOutDir: true,
  },
});
