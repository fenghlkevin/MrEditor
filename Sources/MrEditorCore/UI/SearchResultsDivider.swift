import AppKit

/// Drag in window coordinates so resizing the result pane does not move the drag origin.
final class SearchResultsDivider: NSView {
    var onDrag: ((CGFloat) -> Void)?
    private var lastY: CGFloat = 0
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeUpDown) }
    override func mouseDown(with event: NSEvent) { lastY = event.locationInWindow.y }
    override func mouseDragged(with event: NSEvent) {
        let y = event.locationInWindow.y
        onDrag?(y - lastY)
        lastY = y
    }
    override func draw(_ dirtyRect: NSRect) {
        EditorTheme.current().separator.setFill()
        NSRect(x: 0, y: bounds.midY, width: bounds.width, height: 1).fill()
    }
}

/// Use the same material-free chrome fill as SidebarView.
final class SearchResultsGutter: NSView {
    override func draw(_ dirtyRect: NSRect) {
        EditorTheme.withBackgroundOpacity(EditorTheme.current().chromeBackground).setFill()
        dirtyRect.fill()
    }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}
