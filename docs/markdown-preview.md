# Markdown preview integration

The first preview upgrade directly adapts FluxMarkdown code into MrEditor's
existing split editor. It supports CommonMark/GFM, highlighted fenced code,
KaTeX inline/display math, Mermaid diagrams, task lists, tables, footnotes,
GitHub Alerts, YAML frontmatter, emoji, marked text, subscript/superscript and
a clickable heading outline. The outline tracks headings and stays open when
the document changes. Pinch zoom is handled by WKWebView.

Open a local `.md` or `.markdown` file of up to 8 MiB. Preview opens beside the
editable source. Use the display menu's Preview item to reopen it,
or the close button to hide it. Source/preview scroll synchronization remains
proportional, not exact line mapping. Larger documents keep the existing large
file editor. Typst, Vega, Graphviz and PDF/HTML export are not included.

## Finder Quick Look

The app also bundles `MrEditorQuickLook.appex`. Select a `.md` or `.markdown`
file in Finder and press Space. Enable MrEditor under System Settings →
General → Login Items & Extensions → Extensions → Quick Look. If another
Markdown preview extension is installed, disable its Quick Look entry to avoid
competing providers. This does not change the default editor for double-click.

The top toolbar provides Reload file, Zoom out, Reset zoom, Zoom in, Help,
read-only Source/Preview, and System/Light/Dark theme controls. Zoom ranges
from 50% to 250%; switching source mode keeps the rendered view and its scroll
position. Reload reads the current contents from disk. These controls apply to
the Quick Look session and do not modify the document.

WebKit requires the extension’s `com.apple.security.network.client` entitlement
even for this local renderer. Page CSP still blocks remote assets and requests.
The extension uses the same bundled renderer, with a bounded 4 MiB read and
a visible truncation notice for larger files. UTF-8 and BOM-marked UTF-16 are
supported. Local image access is additionally subject to the Quick Look host’s
sandbox grant; images outside the granted directory may be unavailable.

`scripts/make_app.sh` compiles the extension for every architecture in the
main executable, embeds it, validates its resources, and signs it with its own
entitlements before signing the outer app. Launch the installed app once to
allow macOS to discover its extension. Reopen System Settings if its extension
list was already open during installation.

## Implementation

- `web-renderer/src/markdown.ts` contains the adapted upstream parser.
- `web-renderer/src/index.ts` sanitizes and renders each document, loads math
  and diagrams on demand and discards superseded requests.
- `MarkdownPreviewView.swift` retains one WKWebView shell, debounces editing,
  passes text as structured JavaScript arguments, restores scroll position,
  and falls back to the existing cmark renderer on initialization/render failure.
- `MarkdownPreviewResources.swift` serves only contained bundle resources.
- The existing `mdasset` image handler confines images to the current document
  directory, resolves symlinks, restricts file types and limits image size.
- DOMPurify removes executable markup. CSP blocks document scripts, frames,
  forms and network requests. Remote images remain disabled. All JS/CSS/fonts
  are bundled; ordinary viewing requires no Node.js or network access.

## Build and test

When changing the web renderer, rebuild checked-in assets first:

```sh
sh scripts/build_markdown_renderer.sh
swift test --filter 'Markdown(PreviewIntegration|Renderer|Syntax)Tests|EditableViewerMarkdownHighlightTests'
swift build -c release
sh scripts/make_app.sh release
```

The renderer build uses the pinned npm lockfile, runs parser/security tests and
TypeScript checking, compiles resources, collects third-party notices and
creates a SHA-256 resource manifest. The packaging script checks every manifest
entry in the actual application bundle before signing.

The WebKit integration tests exercise real KaTeX fonts, Mermaid SVG output,
theme switching, fast edits, reopening, Chinese local-image filenames, blocked
network requests and HTML sanitization. They write a preview snapshot to
`/private/tmp/mreditor-markdown-preview.png` for visual inspection.

## Provenance

See [upstream revision, license and adaptations](../web-renderer/UPSTREAM.md).
The original MIT license remains attached to original MrEditor code; this
combined variant additionally contains GPL-3.0 components. Bundled dependency
notices are in `MarkdownPreview/ThirdPartyNotices.txt` inside the resource bundle.

## Additional document formats and search

The editor split preview and the MrEditor Finder extension select a renderer by
file extension. The display menu's Preview item reopens the split preview.
Finder chooses the actual preview provider: on the tested macOS installation,
Markdown, JSON and logs used MrEditor, while CSV and SVG continued to use the
built-in system provider after registration/cache refresh. Those files have the
new interactive preview when opened inside MrEditor. System-wide replacement
for these built-in formats remains unresolved; declaring support alone does not
guarantee that Finder selects this extension.

- Markdown: literal, case-insensitive text search, match count, previous/next
  (Enter / Shift-Enter), clear. The visible search bar also works for other formats.
- JSON / YAML: collapsible tree, expand/collapse all, parser diagnostics, source
  view. YAML aliases and deep/large structures are bounded rather than expanded
  indefinitely. YAML uses JSON schema (no custom executable tags).
- CSV / TSV: quoted delimiters and multiline fields, sticky headers, resizable
  columns, click-to-sort headers, text filter. First row is the header. At most
  2000 data rows, 200 columns and roughly 30000 cells are shown with a notice.
- Code / configuration / logs: language highlighting when registered, line
  numbers, line wrapping, source search, ERROR/FATAL and WARN coloring. Text
  preview is bounded to 10000 lines / 500000 characters with a notice.
- Mermaid: `.mmd` and `.mermaid` render directly with the bundled Mermaid engine.
- HTML / SVG: sanitized structural/vector preview. Scripts, embedded pages,
  forms, animation, stylesheets, inline CSS and external resource references are
  removed. This is an offline document preview, not a full browser; presentation
  that depends on CSS/JavaScript or linked assets is intentionally unavailable.

Search highlights at most 2000 matches in currently rendered content. Search
expands tree nodes; table filtering limits the searched rows. The native Quick
Look source toggle opens a plain read-only text view; the web toolbar's Source
button retains the search bar. Other encodings beyond UTF-8 / BOM UTF-16 are
not currently supported by the Finder reader. Binary property lists are not text.

Samples for every added format are in `docs/preview-samples/`.

## Quick Look double-click preference

Use the native toolbar gear menu to toggle “双击预览打开文件” (Double-click
preview to open file). It is off by default and persists in the extension’s
preferences. When off, repeated mouse clicks in the preview content are consumed
before Quick Look can open the document; this also suppresses double-click text
selection there. Single-click controls and the system Open With button remain
available. This preference applies to MrEditor-provided previews only.
