import AppKit

/// Hosts the remote reader in the workspace without pretending the remote path is a local URL.
final class RemotePane: NSView, DocumentPane {
    let reader = RemoteWindowController()
    var onStateChange: ((ViewerState) -> Void)?
    var onSearchState: ((Int, Int, Bool, Int, Bool, Bool) -> Void)?
    var onDropFiles: (([URL]) -> Void)?
    var onDirtyChange: ((Bool) -> Void)?
    var onTitleChange: (() -> Void)?
    var onClose: (() -> Void)?
    var fileURL: URL? { nil }
    var selectedText: String? { reader.selectedText }
    var connection: SSHConnection? { reader.currentSession?.transport?.connection }
    var title: String { reader.fileTitle }
    var supportsSearch: Bool { false } // The reader owns the server-side filter controls.
    var supportsSearchFilter: Bool { false }
    var supportsReplace: Bool { false }
    var supportsFollow: Bool { false }

    init(session: RemoteSession, follow: Bool) {
        super.init(frame: .zero)
        let content = reader.detachContent()
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor), content.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        reader.onTitleChange = { [weak self] in self?.onTitleChange?() }
        reader.onDisconnect = { [weak self] in self?.onClose?() }
        reader.open(session: session, follow: follow)
    }
    required init?(coder: NSCoder) { fatalError() }
    func open(url: URL) -> Bool { false }
    func reEmitState() {}
    func focusContent() { reader.focusContent() }
    func applyCurrentFontSize() { reader.refreshAppearance() }
    func applyDisplaySettings() { reader.refreshAppearance() }
    func shutdown() { reader.shutdown() }
    deinit { reader.shutdown() }
}
