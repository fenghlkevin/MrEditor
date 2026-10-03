import AppKit

/// Native two-sided merge editor. The left source is read-only; the right result is editable.
final class InlineMergeView: NSView, NSTextViewDelegate {
    let leftEditor = MergeCodeView()
    let rightEditor: NSTextView
    private let leftScroll = NSScrollView(), rightScroll = NSScrollView()
    private let bridge = MergeBridgeView()
    private var rulers: [LineNumberRulerView] = []
    private var observers: [NSObjectProtocol] = []
    private var pending: DispatchWorkItem?
    private var revision = 0
    private var syncing = false
    private let rightUndoManager = UndoManager()
    private let language: CodeSyntax.Language?
    private(set) var model: InlineMergeModel
    private(set) var selected = 0
    private(set) var updating = false
    var onChange: (() -> Void)?
    var onFocus: (() -> Void)?
    var onSummary: ((Int, Bool) -> Void)?

    init(left: String, rightEditor: NSTextView, fileName: String) {
        self.rightEditor = rightEditor
        language = CodeSyntax.Language.detect(extension: (fileName as NSString).pathExtension)
        model = InlineMergeModel(left: left, right: rightEditor.string)
        super.init(frame: .zero)
        for (editor, scroll, isLeft) in [(leftEditor as NSTextView, leftScroll, true), (rightEditor, rightScroll, false)] {
            scroll.documentView = editor; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
            scroll.autohidesScrollers = true; scroll.borderType = .noBorder
            editor.isRichText = false; editor.isEditable = !isLeft; editor.isSelectable = true
            editor.allowsUndo = !isLeft; editor.isVerticallyResizable = true; editor.isHorizontallyResizable = true
            editor.autoresizingMask = [.width]
            editor.minSize = .zero
            editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            editor.textContainer?.widthTracksTextView = false
            editor.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            editor.textContainerInset = NSSize(width: 10, height: 8)
            editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
            editor.isAutomaticTextReplacementEnabled = false; editor.isContinuousSpellCheckingEnabled = false
            addSubview(scroll)
            let ruler = LineNumberRulerView(textView: editor)
            ruler.lineIndexProvider = { [weak editor] in LineStartIndex(editor?.string ?? "") }
            scroll.verticalRulerView = ruler; scroll.hasVerticalRuler = true; scroll.rulersVisible = true
            rulers.append(ruler)
            scroll.contentView.postsBoundsChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in self?.didScroll(fromLeft: isLeft) })
        }
        leftEditor.setAccessibilityIdentifier("merge-left-source")
        rightEditor.setAccessibilityIdentifier("merge-right-result")
        leftEditor.setAccessibilityLabel("左侧原文，只读")
        rightEditor.setAccessibilityLabel("右侧合并结果，可编辑")
        leftEditor.string = left
        rightEditor.delegate = self
        addSubview(bridge)
        bridge.onApply = { [weak self] index in self?.adopt(index) }
        bridge.geometry = { [weak self] in self?.geometry() ?? [] }
        leftEditor.bands = { [weak self] in self?.bands(left: true) ?? [] }
        if let right = rightEditor as? MergeCodeView { right.bands = { [weak self] in self?.bands(left: false) ?? [] } }
        applyAppearance(); render()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { pending?.cancel(); observers.forEach(NotificationCenter.default.removeObserver) }
    override func layout() {
        super.layout()
        let middle: CGFloat = 64, width = max(0, (bounds.width - middle) / 2)
        leftScroll.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        bridge.frame = NSRect(x: width, y: 0, width: middle, height: bounds.height)
        rightScroll.frame = NSRect(x: width + middle, y: 0, width: width, height: bounds.height)
        for (editor, scroll) in [(leftEditor as NSTextView, leftScroll), (rightEditor, rightScroll)] {
            editor.minSize = NSSize(width: scroll.contentSize.width, height: scroll.contentSize.height)
            editor.setFrameSize(NSSize(width: max(editor.frame.width, scroll.contentSize.width), height: max(editor.frame.height, scroll.contentSize.height)))
        }
        bridge.needsDisplay = true
    }
    func applyAppearance() {
        let theme = EditorTheme.current()
        for editor in [leftEditor as NSTextView, rightEditor] {
            editor.font = EditorFont.current(); editor.textColor = theme.foreground
            editor.backgroundColor = theme.background; editor.insertionPointColor = theme.foreground
            editor.selectedTextAttributes = [.backgroundColor: theme.selection]
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 3
            paragraph.defaultTabInterval = ("    " as NSString).size(withAttributes: [.font: EditorFont.current()]).width
            paragraph.tabStops = []
            editor.defaultParagraphStyle = paragraph
            editor.typingAttributes = [.font: EditorFont.current(), .foregroundColor: theme.foreground, .paragraphStyle: paragraph]
        }
        rulers.forEach { $0.updateThickness(); $0.needsDisplay = true }
        render()
    }
    func undoManager(for view: NSTextView) -> UndoManager? { rightUndoManager }
    var activeEditor: NSTextView { rightEditor }
    var canUndo: Bool { activeEditor.undoManager?.canUndo ?? false }
    func textDidChange(_ notification: Notification) {
        revision += 1; pending?.cancel(); updating = true
        // Disable stale arrows immediately. A character edit may invalidate every following range.
        bridge.enabled = false; bridge.needsDisplay = true
        onChange?(); onSummary?(model.hunks.count, true)
        let ticket = revision, left = leftEditor.string, right = rightEditor.string
        let work = DispatchWorkItem { [weak self] in
            let model = InlineMergeModel(left: left, right: right)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.revision == ticket else { return }
                self.model = model; self.updating = false; self.bridge.enabled = true
                self.selected = min(self.selected, max(0, model.hunks.count - 1)); self.render()
            }
        }
        pending = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.18, execute: work)
    }
    func textViewDidChangeSelection(_ notification: Notification) {
        onFocus?()
        guard !updating else { return }
        let location = activeEditor.selectedRange().location
        if let index = model.hunks.firstIndex(where: { let range = $0.right; return location >= range.location && location <= NSMaxRange(range) }) {
            selected = index; bridge.needsDisplay = true
        }
    }
    func navigate(_ delta: Int) {
        guard !updating, !model.hunks.isEmpty else { NSSound.beep(); return }
        selected = (selected + delta + model.hunks.count) % model.hunks.count
        let hunk = model.hunks[selected]
        leftEditor.scrollRangeToVisible(hunk.left); rightEditor.scrollRangeToVisible(hunk.right)
        activeEditor.setSelectedRange(NSRange(location: hunk.right.location, length: 0))
        bridge.needsDisplay = true
    }
    func adoptSelected() { adopt(selected) }
    private func adopt(_ index: Int) {
        guard !updating, model.hunks.indices.contains(index) else { NSSound.beep(); return }
        selected = index
        let hunk = model.hunks[index]
        let value = model.left.text.substring(with: hunk.left)
        let editor: NSTextView = rightEditor
        editor.breakUndoCoalescing()
        editor.insertText(value, replacementRange: hunk.right)
        editor.undoManager?.setActionName("采纳左侧差异")
        editor.breakUndoCoalescing()
        window?.makeFirstResponder(editor)
        onFocus?()
    }
    func undoMerge() { activeEditor.undoManager?.undo() }
    func copySelected(left: Bool) {
        guard !updating, model.hunks.indices.contains(selected) else { return }
        let hunk = model.hunks[selected]
        let value = (left ? model.left.text : model.right.text).substring(with: left ? hunk.left : hunk.right)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
    }
    private func render() {
        for (editor, lines) in [(leftEditor as NSTextView, model.left), (rightEditor, model.right)] {
            guard let lm = editor.layoutManager else { continue }
            let whole = NSRange(location: 0, length: (editor.string as NSString).length)
            lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: whole)
            // Syntax highlighting uses temporary attributes, preserving undo and the original text.
            if let language, lines.text.length <= 1_048_576 {
                for span in CodeSyntax.spans(text: lines.text, language: language) {
                    let color: NSColor
                    switch span.role {
                    case .comment: color = .secondaryLabelColor
                    case .string: color = .systemGreen
                    case .keyword: color = .systemBlue
                    case .number: color = .systemOrange
                    case .definition: color = .systemPurple
                    }
                    lm.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: span.range)
                }
            }
        }
        // Highlight changed words independently of full-line bands.
        for hunk in model.hunks where hunk.leftLines.count <= 100 && hunk.rightLines.count <= 100 {
            for offset in 0..<min(hunk.leftLines.count, hunk.rightLines.count) {
                let lr = model.left.ranges[hunk.leftLines.lowerBound + offset]
                let rr = model.right.ranges[hunk.rightLines.lowerBound + offset]
                let l = model.left.text.substring(with: lr), r = model.right.text.substring(with: rr)
                let changed = CharDiff.ranges(left: l, right: r)
                for (editor, value, base, ranges) in [(leftEditor as NSTextView, l, lr.location, changed.left), (rightEditor, r, rr.location, changed.right)] {
                    let chars = Array(value)
                    for range in ranges {
                        let prefix = String(chars.prefix(range.lowerBound)).utf16.count
                        let length = String(chars[range]).utf16.count
                        editor.layoutManager?.addTemporaryAttribute(.backgroundColor, value: NSColor.systemBlue.withAlphaComponent(0.25), forCharacterRange: NSRange(location: base + prefix, length: length))
                    }
                }
            }
        }
        rulers.forEach { $0.updateThickness(); $0.needsDisplay = true }
        leftEditor.needsDisplay = true; rightEditor.needsDisplay = true; bridge.needsDisplay = true
        onSummary?(model.hunks.count, updating)
    }
    private func lineY(_ location: Int, editor: NSTextView) -> CGFloat {
        guard let lm = editor.layoutManager, let tc = editor.textContainer else { return 8 }
        lm.ensureLayout(for: tc)
        let length = (editor.string as NSString).length
        if location >= length { return editor.textContainerOrigin.y + (lm.extraLineFragmentRect.isEmpty ? lm.usedRect(for: tc).maxY : lm.extraLineFragmentRect.minY) }
        let glyph = lm.glyphIndexForCharacter(at: max(0, location))
        return editor.textContainerOrigin.y + lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
    }
    private func verticalRange(_ range: NSRange, editor: NSTextView) -> (CGFloat, CGFloat) {
        let top = lineY(range.location, editor: editor)
        let bottom = range.length == 0 ? top + 3 : max(top + EditorFont.current().pointSize + 6, lineY(NSMaxRange(range), editor: editor))
        return (top, bottom)
    }
    private func bands(left: Bool) -> [(NSRect, NSColor)] {
        guard !updating else { return [] }
        let editor = left ? leftEditor : rightEditor
        return model.hunks.map { hunk in
            let (top, bottom) = verticalRange(left ? hunk.left : hunk.right, editor: editor)
            return (NSRect(x: 0, y: top, width: editor.bounds.width, height: bottom - top), color(hunk))
        }
    }
    private func color(_ hunk: InlineMergeModel.Hunk) -> NSColor {
        if hunk.left.length == 0 { return .systemGreen }
        if hunk.right.length == 0 { return .systemRed }
        return .systemBlue
    }
    private func geometry() -> [MergeBridgeView.Band] {
        guard !updating else { return [] }
        return model.hunks.enumerated().compactMap { index, hunk in
            let (lt, lb) = verticalRange(hunk.left, editor: leftEditor)
            let (rt, rb) = verticalRange(hunk.right, editor: rightEditor)
            let a = bridge.convert(NSPoint(x: 0, y: lt), from: leftEditor).y
            let b = bridge.convert(NSPoint(x: 0, y: lb), from: leftEditor).y
            let c = bridge.convert(NSPoint(x: 0, y: rt), from: rightEditor).y
            let d = bridge.convert(NSPoint(x: 0, y: rb), from: rightEditor).y
            guard max(b, d) >= 0, min(a, c) <= bridge.bounds.height else { return nil }
            return MergeBridgeView.Band(index: index, lt: a, lb: b, rt: c, rb: d, color: color(hunk), selected: selected == index)
        }
    }
    private func didScroll(fromLeft: Bool) {
        bridge.needsDisplay = true
        guard !syncing, !updating else { return }
        syncing = true; defer { syncing = false }
        let source = fromLeft ? leftScroll : rightScroll, target = fromLeft ? rightScroll : leftScroll
        let editor = fromLeft ? leftEditor : rightEditor
        let other = fromLeft ? rightEditor : leftEditor
        guard let lm = editor.layoutManager, let tc = editor.textContainer, lm.numberOfGlyphs > 0 else { return }
        let point = NSPoint(x: editor.textContainerOrigin.x, y: max(0, source.contentView.bounds.minY - editor.textContainerOrigin.y))
        let glyph = lm.glyphIndex(for: point, in: tc)
        let char = lm.characterIndexForGlyph(at: min(glyph, max(0, lm.numberOfGlyphs - 1)))
        let sourceIndex = LineStartIndex(editor.string), targetIndex = LineStartIndex(other.string)
        let line = sourceIndex.lineIndex(at: char)
        let y = lineY(sourceIndex.start(ofLine: line), editor: editor)
        let mapped = model.correspondingLine(Double(line), fromLeft: fromLeft)
        let floorLine = Int(mapped.rounded(.down))
        let targetY = lineY(targetIndex.start(ofLine: floorLine), editor: other)
        let desired = targetY + (mapped - Double(floorLine)) * Double(EditorFont.current().pointSize + 6) + Double(source.contentView.bounds.minY - y)
        let maxY = max(0, other.bounds.height - target.contentView.bounds.height)
        target.contentView.scroll(to: NSPoint(x: source.contentView.bounds.minX, y: min(maxY, max(0, desired))))
        target.reflectScrolledClipView(target.contentView)
    }
}

final class MergeCodeView: NSTextView {
    var bands: (() -> [(NSRect, NSColor)])?
    var onFocus: (() -> Void)?
    override func mouseDown(with event: NSEvent) { super.mouseDown(with: event); onFocus?() }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for (rect, color) in bands?() ?? [] where rect.intersects(dirtyRect) {
            color.withAlphaComponent(0.12).setFill(); rect.fill(using: .sourceOver)
            color.withAlphaComponent(0.45).setFill()
            NSRect(x: 0, y: rect.minY, width: 3, height: rect.height).fill()
        }
    }
}

private final class MergeBridgeView: NSView {
    struct Band { let index: Int; let lt: CGFloat; let lb: CGFloat; let rt: CGFloat; let rb: CGFloat; let color: NSColor; let selected: Bool }
    var geometry: (() -> [Band])?
    var onApply: ((Int) -> Void)?
    var enabled = true
    private var buttons: [NSButton] = []
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        EditorTheme.current().chromeBackground.setFill(); bounds.fill()
        let bands = geometry?() ?? []
        for band in bands {
            let path = NSBezierPath(), w = bounds.width
            path.move(to: NSPoint(x: 0, y: band.lt))
            path.curve(to: NSPoint(x: w, y: band.rt), controlPoint1: NSPoint(x: w * 0.5, y: band.lt), controlPoint2: NSPoint(x: w * 0.5, y: band.rt))
            path.line(to: NSPoint(x: w, y: band.rb))
            path.curve(to: NSPoint(x: 0, y: band.lb), controlPoint1: NSPoint(x: w * 0.5, y: band.rb), controlPoint2: NSPoint(x: w * 0.5, y: band.lb))
            path.close()
            band.color.withAlphaComponent(band.selected ? 0.20 : 0.10).setFill(); path.fill()
            band.color.withAlphaComponent(0.40).setStroke(); path.lineWidth = 1; path.stroke()
        }
        // Reuse accessible native buttons, rather than drawing non-interactive arrow glyphs.
        while buttons.count < bands.count {
            let button = NSButton(title: "→", target: self, action: #selector(apply(_:)))
            button.bezelStyle = .inline; button.font = .systemFont(ofSize: 18, weight: .medium)
            button.toolTip = "采纳左侧差异（可用 ⌘Z 撤销）"
            addSubview(button); buttons.append(button)
        }
        for (i, button) in buttons.enumerated() {
            button.isHidden = i >= bands.count
            guard i < bands.count else { continue }
            let band = bands[i]
            button.title = "→"
            button.toolTip = "采纳左侧到右侧（⌘Z 撤销）"
            button.tag = band.index; button.isEnabled = enabled
            button.frame = NSRect(x: 17, y: max(0, min(bounds.height - 26, (band.lt + band.rt) / 2)), width: 30, height: 26)
            button.setAccessibilityLabel("采纳左侧第 \(band.index + 1) 处差异")
            button.setAccessibilityIdentifier("inline-merge-arrow-\(band.index)")
        }
    }
    @objc private func apply(_ sender: NSButton) { onApply?(sender.tag) }
}
