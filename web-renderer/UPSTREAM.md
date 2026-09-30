# FluxMarkdown integration

Source: https://github.com/xykong/flux-markdown
Revision: `733a664c57cbc5f23045e5f87d3ec7f3db17f947` (v1.34.475).
Copyright (c) 2024-2026 xykong.

This integration uses the upstream GPL-3.0 license. No commercial license is
claimed. `LICENSE` and `LICENSE.COMMERCIAL` are retained verbatim. MrEditor's
existing MIT notices remain applicable to its original code; this combined
build includes GPL-3.0 code and must not be described as an MIT-only product.
The upstream commercial license is an alternative that must be obtained from
the author before relying on it for proprietary distribution.

Adapted files:

- `src/markdown.ts`: parsing, language registration, frontmatter, extension
  plugins and Mermaid preprocessing from upstream `web-renderer/src/index.ts`.
- `src/outline.ts`, `src/table-of-contents.ts`, and the three stylesheets
  `highlight-adaptive.css`, `callouts.css`, `table-of-contents.css`.
- `../Sources/MrEditorCore/UI/MarkdownPreviewResources.swift`: native bundle
  resource serving adapted from `Sources/Shared/RendererBundleSchemeHandler.swift`.

MrEditor changes (2026-09-30): separate renderer shell, DOMPurify sanitization,
offline CSP, scoped images, atomic/coalesced updates, table-of-contents observer
refresh and visibility persistence, explicit theme handling, native preview
integration and fallback. Frontmatter delimiter handling and language attribute
escaping are hardened. No QuickLook, updater, file watcher or upstream app UI
is included. Typst, Vega and Graphviz are outside this first integration.

Rebuild with `sh scripts/build_markdown_renderer.sh` from the repository root.
The generated resources are checked into the project so Swift-only builds
work offline. The build also collects dependency license texts and a resource
hash manifest; do not edit generated assets directly.
