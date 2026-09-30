import { defineConfig } from 'vite';

export default defineConfig({
  base: './',
  plugins: [{
    name: 'webkit-local-modules',
    transformIndexHtml: { order: 'post', handler: html => html.replace(/ crossorigin/g, '') },
  }],
  css: { postcss: { plugins: [{
    postcssPlugin: 'mreditor-explicit-theme',
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
