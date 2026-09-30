# MrEditor

[简体中文](README.md) | **English** | [日本語 (historical version)](README.ja.md)

**A native macOS editor for logs, structured data, and Markdown.**

Open large files, filter logs, inspect JSON and tables, compare text, and edit Markdown alongside rendered math and diagrams. MrEditor brings local documents and SSH logs into one workspace, with Simplified Chinese, English, and Japanese interfaces.

## Screenshots and video

![Logs, CSV, JSON, and side-by-side comparison](docs/img/four-kinds-of-text.jpg)

*Four workflows: reading logs, aligning CSV columns, formatting JSON, and comparing character-level changes. This existing project screenshot shows an earlier interface; the current build may look different.*

[![Opening a 10 GB log in real time; click for the full video](docs/img/10gb-open.gif)](docs/media/mreditor-10gb.mp4)

**[▶ Play or download the full demo (MP4, approximately 27 seconds)](docs/media/mreditor-10gb.mp4)** · Open a 10 GB log, scroll, and jump to the last line. The GIF shows the first 10 seconds. Recorded with the original project's 1.14.0 release; this is not a benchmark of the current build.

## Recent additions

- **Split previews for multiple formats**: Markdown, JSON, YAML, CSV, TSV, code, logs, Mermaid, HTML, and SVG, with search inside the preview.
- **Enhanced Markdown**: highlighted code, KaTeX math, Mermaid diagrams, clickable outline, tables, task lists, footnotes, GitHub Alerts, and YAML frontmatter.
- **Finder Quick Look**: a bundled extension with source/preview switching, search, zoom, themes, and reload.
- **Data inspectors**: JSON trees and formatted copies, native CSV/TSV tables, and NDJSON record browsing and export.
- **Editing and search**: multiple cursors, rectangular column selections, Find All, and selectable replacement previews.
- **Remote workspace**: independent SSH profiles, remote file browsing, jump hosts, Keychain credentials, and separate Local/Servers sidebar sections.
- **Chinese localization**: Simplified Chinese UI, improved language matching, and clearer actions on the empty home screen.

## Features

### Markdown and document previews

![Markdown preview with highlighted code, math, Mermaid, callouts, and tables](docs/img/markdown-preview.png)

*Actual WebKit integration-test snapshot of the current renderer (2026-09-30), showing the preview content area.*

Choose **Display → Preview** in the toolbar to open a split view; Markdown files can open with live preview automatically. Source and preview synchronize scrolling proportionally in both directions and support light/dark appearance. Renderer scripts, fonts, and styles are bundled for offline viewing.

| Format | Preview capabilities |
| --- | --- |
| Markdown | CommonMark/GFM, highlighted code, math, diagrams, outline, task lists, and footnotes |
| JSON / YAML | Collapsible trees, expand/collapse all, parser diagnostics, and source view |
| CSV / TSV | Sticky headers, resizable columns, click-to-sort, text filtering, quoted and multiline fields |
| Code / configuration / logs | Registered language highlighting, line numbers, wrapping, search, and ERROR/FATAL/WARN colors |
| Mermaid | Direct rendering of `.mmd` / `.mermaid` diagrams |
| HTML / SVG | Sanitized document structure and vector previews |

HTML/SVG previews remove scripts, styles, and external resources; they do not reproduce full browser pages. Remote images are blocked, and local images are confined to the document directory. Editor split previews target files up to **8 MiB**; larger files retain the large-file editor. Table and text previews also have row, column, and character limits with visible notices. Preview search covers rendered content only and highlights up to 2,000 matches.

Try the [Markdown demo](docs/markdown-preview-demo.md) and [format samples](docs/preview-samples/). See [preview documentation](docs/markdown-preview.md) for exact scope and limits.

### Finder Quick Look

After installing and launching the app, enable MrEditor in **System Settings → General → Login Items & Extensions → Extensions → Quick Look** (labels vary by macOS version), select a file, and press Space.

The extension offers reload, 50%–250% zoom, source/preview switching, and System/Light/Dark themes. Its gear menu includes “Double-click preview to open file,” off by default.

Finder chooses the actual provider. In existing tests, Markdown, JSON, and logs used MrEditor, while CSV and SVG could still use system providers. Those formats support the new preview inside the app. Quick Look reads up to **4 MiB**, showing a truncation notice for larger files. It supports UTF-8 and BOM-marked UTF-16; local images also depend on the host's sandbox permissions.

### JSON, CSV, TSV, and NDJSON inspectors

Choose the corresponding data view from the toolbar display menu to inspect structure beside the source. These native inspectors are separate from the general web preview.

- **JSON**: background parsing, collapsible trees, and 500 children per page; selecting a node locates its source. Formatting creates a new document while preserving key order, duplicate keys, and numeric spelling. Large UTF-8 inputs use memory mapping and streaming formatting; save pending large-file edits before parsing.
- **CSV / TSV**: first-row-as-header toggle, resizable/reorderable columns, record filtering, and cell detail. Quoted delimiters, escaped quotes, and multiline fields are supported; columns are paged in groups of 100.
- **NDJSON**: browse records as JSON trees. Format All exports a new JSON array file. Invalid records report their number; export stops on errors and removes partial output.

### Large files and logs

MrEditor uses `mmap`, a sparse line index, and drawing restricted to visible lines. A piece table stores large-file edits without loading the whole file into a text control. The project includes a 10 GB log demo; actual performance depends on hardware, content, and operation.

- Background full-file search, case sensitivity, regular expressions, and multi-term AND queries.
- **Live grep**: show matching lines with original line numbers; add surrounding context with `±`.
- **Follow tail**: incrementally track appended content. Local following pauses during unsaved edits and resumes after saving.
- UTF-8, Shift-JIS, and EUC-JP detection and save conversion; atomic save, Save As, and revert.
- Bookmarks, go-to-line, ANSI log colors, soft wrapping, fonts, and themes.
- gzip/zip detection and extraction; standard input opens after the stream reaches EOF.

![Full-file search and highlighted matches in a large log](docs/img/search-10gb-dark.png)

*Large-file search in an earlier build. Filtered views are read-only; saving still writes the complete document.*

### Multiple cursors, column mode, and replacement preview

In the small-file editing pane, add cursors with `⌘`-click or `⌥⌘↑ / ↓`, and select the next occurrence with `⌘D`. Enable **Edit → Column Mode** (`⇧⌥⌘C`) and drag a rectangle to edit multiple lines. Short lines stop at their end; `Esc` exits column mode.

The search bar supports searching the selection, Find All, Replace, and Replace All. **Preview Changes** lists up to 500 replacements and lets you select which to apply. Regenerate the preview if the document changes. Replacement is restricted in formatted or read-only views.

### SSH remote logs

Connect through **File → Open Remote…** (`⌃⌘O`), the home screen, or the Servers sidebar.

- Quick connections or saved profiles; passwords, private keys, encrypted keys, SSH Agent, and independently authenticated jump hosts.
- Browse remote directories, filter filenames, sort by modification time, refresh, and reuse connections to choose another file.
- Read log segments on demand, filter on the server, and follow appended content with `tail -f`.
- Credentials enter macOS Keychain only when explicitly remembered. First connections require checking the actual host fingerprint; changed host keys are rejected.
- New connections use application-generated SSH configuration rather than `~/.ssh/config`.

Remote panes support reading, filtering, copying, and following logs, rather than every local editing feature. Missing remote commands produce capability notices. See [SSH connections](docs/SSH_CONNECTIONS.md).

### Compare and merge

Compare two files, open documents, clipboard contents, or an HTTPS URL with side-by-side line and character differences. Adopt changes from the left into the right-hand result and save it separately; the original files remain untouched. Format comparison checks data shapes and disables merging while active.

![Side-by-side differences](docs/img/diff_vew.png)

*Comparison screenshot from an earlier build.*

### Workspace and appearance

Switch and close documents in the sidebar, separate local files from servers, and restore sessions and unsaved new drafts. Finder Open With, default application settings, printing/PDF output, monospaced fonts, line spacing, caret styles, themes, and background opacity are supported.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| New / Open / Save | `⌘N` / `⌘O` / `⌘S` |
| Save As | `⇧⌘S` |
| Find / Next / Previous | `⌘F` / `⌘G` / `⇧⌘G` |
| Go to line / Toggle bookmark | `⌘L` / `⌘B` |
| Follow tail | `⌥⌘F` |
| Open remote file | `⌃⌘O` |
| Compare two files | `⇧⌘D` |
| Previous / Next difference | `⇧⌘[` / `⇧⌘]` |
| Column mode | `⇧⌥⌘C` |
| Add cursor above / below | `⌥⌘↑` / `⌥⌘↓` |
| Select next occurrence | `⌘D` |

## Build and run

Requires **macOS 13+**, a Swift 5.9 or newer toolchain (Xcode 15+), and Python 3 for packaging. Upstream release packages may not include this branch's preview enhancements and other changes; build from source to try this branch.

```sh
swift build -c release
sh scripts/make_app.sh release
codesign --verify --deep --strict .build/MrEditor.app
open .build/MrEditor.app
```

Packaging embeds localization resources and the Quick Look extension, validates the preview resource manifest, and signs the bundle. The default is local ad-hoc signing, which does not imply Developer ID signing or Apple notarization.

Before replacing `/Applications/MrEditor.app`, quit normally and resolve unsaved-document prompts. Back up the existing app in a separate directory under `.build/backups/`, then install and launch the new bundle.

Generated renderer resources are checked in, so ordinary Swift builds do not require Node.js. When changing `web-renderer/`, first rebuild it in an environment with Node.js/npm:

```sh
sh scripts/build_markdown_renderer.sh
swift test --filter 'Markdown(PreviewIntegration|Renderer|Syntax)Tests|EditableViewerMarkdownHighlightTests'
```

Install the optional command-line entry point to open files or completed pipe output:

```sh
sh scripts/install-cli.sh
mreditor /path/to/app.log
cat /path/to/app.log | mreditor
```

## Documentation and contributing

- [Preview features, limits, and verification](docs/markdown-preview.md)
- [SSH connections and integration tests](docs/SSH_CONNECTIONS.md)
- [Original large-file architecture](docs/ARCHITECTURE_v0.1.md)
- [Contributing guide](CONTRIBUTING.md)

## License and acknowledgments

Original MrEditor code: [MIT](LICENSE), © 2026 TABATA Hitoshi.

The enhanced preview uses MrEditor's own integration with permissively licensed dependencies. Original MIT notices and dependency license texts are bundled as `ThirdPartyNotices.txt`; DOMPurify is used under Apache-2.0. See [implementation provenance](web-renderer/UPSTREAM.md).
