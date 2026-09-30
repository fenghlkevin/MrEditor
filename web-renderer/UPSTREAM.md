# MrEditor preview provenance

The current application integration is distributed under the repository's MIT
license. Original MrEditor copyright and permission notices are retained.
Dependencies retain their own licenses; DOMPurify's Apache-2.0 option is selected.
The build generates ThirdPartyNotices.txt and dependency-licenses.json, including
package versions, selected licenses and license-text hashes. This inventory is
conservative: it includes all non-development packages in the lockfile, even
when the bundler removes unused code.

## Replacement implementation (2026-09-30)

- parser.ts configures markdown-it's public plugins and adds source metadata in
  a core pass. languages.ts declares the supported highlight.js grammars.
- metadata.ts creates bounded DOM nodes from YAML, including cycle detection.
- navigation.ts derives a flat, visually indented contents list from sanitized
  headings and tracks scroll/resize events. There is no copied outline tree.
- diagrams.ts uses a label scanner and a Gantt field boundary rule.
- index.ts assembles documents off-screen and commits only the latest request.
- components.css implements application controls and metadata presentation.
  Syntax themes come directly from highlight.js; alert styling comes directly
  from markdown-it-github-alerts. Both retain their package license notices.
- MarkdownPreviewResources.swift catalogs contained files at initialization;
  requests look up an asset key instead of constructing a filesystem path.

The original app-specific formats/search, preview shell styling, native image
sandboxing and Quick Look controls remain. The editor and Quick Look receive
the same freshly built renderer resources.

## Historical context

The preceding implementation incorporated FluxMarkdown revision
733a664c57cbc5f23045e5f87d3ec7f3db17f947 under GPL-3.0. Its parser, outline,
contents controller, three stylesheet files and native resource-serving
implementation have been replaced, and generated assets are rebuilt from an
empty output directory. The previous files and their notices remain in Git
history; this change does not relicense those historical versions.

This is a source replacement, not a certified clean-room process: the developer
had access to the preceding implementation. Functional tests, visual references
and public dependency APIs informed the replacement. License metadata checks
verify declared inputs and packaged files, not legal independence. A commercial
release should review this provenance and any separately maintained Pro code.

Rebuild: `sh scripts/build_markdown_renderer.sh` from the repository root.

## Focused provenance remediation (2026-09-30)

The follow-up comparison against revision 733a664 found a near-identical custom
heading slug expression and short matching contents CSS fragments. Those have
now been removed, rather than renamed or reformatted:

- Heading IDs use markdown-it-anchor 9.2.0's MIT-licensed default implementation.
  Unicode IDs are URI encoded; punctuation is retained by that dependency.
  Local fragment navigation handles Unicode and encoded IDs. Old manually
  authored links based on punctuation removal may need their target updated;
  the legacy custom slug function is deliberately not retained as an alias.
  Source: node_modules/markdown-it-anchor/dist/markdownItAnchor.mjs and LICENSE.
- Contents controls use system Canvas/CanvasText/Highlight colors, uniformly
  sized wrapping rows and indentation as the hierarchy cue. The old per-level
  font/spacing rules and contents palette are no longer used by those controls.
  Metadata/alert palette values remain for the independently licensed document
  styles; they are not a claim of exclusive ownership of common color values.
- Gantt label handling remains the replacement character scanner, not the old
  upstream regexp/field-validation implementation. Its task separator and
  vocabulary are checked against https://mermaid.js.org/syntax/gantt.html#syntax
  and the installed MIT-licensed Mermaid 11.17.2 package's Gantt parser (the
  exact installed version is authoritative in dependency-licenses.json).
  MrEditor's additional policy is to treat the last whitespace-prefixed colon
  as the separator in legacy labels; this is an application compatibility
  extension, not a promise that Mermaid documents that extension. Explicit
  #colon; labels and time values are regression tested. Documentation of the
  public specification does not retroactively prove independent authorship.

The scan is evidence for this reviewed snapshot, not a legal certificate.
Historical access to FluxMarkdown and the earlier source-replacement caveat
remain recorded above. No license in Git history or old backups was changed.
