import AppKit

/// 開いているドキュメントの縦リスト。
///
/// このウィンドウでは custom-draw のサブツリーは最前面の1つしか画面合成されない
/// macOS の不具合がある（本文の DocumentView がその1つ）。そこでサイドバーは
/// custom-draw を使わず、layer 背景＋コントロール（NSTextField の行）で構成し、
/// contentView の最前面側に置く（StatusBar / SearchBar と同じ作り）。
final class SidebarView: NSView {
    var onSelect: ((Int) -> Void)?
    var onCompare: (([Int]) -> Void)?
    var localFileURL: ((Int) -> URL?)?
    private(set) var selectedIndices = Set<Int>()
    private var selectionAnchor: Int?
    var onClose: ((Int) -> Void)?
    var onConnection: ((SSHConnection) -> Void)?
    var onNewConnection: (() -> Void)?
    var onManageConnections: (() -> Void)?
    var onEditConnection: ((SSHConnection) -> Void)?
    var onOpenLocal: (() -> Void)?
    var onSectionChange: ((Bool) -> Void)?
    private let stack = NSStackView()
    private let tabs = NSSegmentedControl(labels: [L("workspace.local"), L("workspace.servers")], trackingMode: .selectOne, target: nil, action: nil)
    private lazy var create = NSButton(title: "", target: self, action: #selector(createItem))
    private lazy var secondary = NSButton(title: "", target: self, action: #selector(secondaryAction))
    private var rows: [SidebarRow] = []
    private var documents: [WorkspaceDocument] = []
    private var groups: [WorkspaceServer] = []
    var isRemoteSection: Bool { tabs.selectedSegment == 1 }
    private var active = -1
    private var collapsed = Set<UUID>()
    private var pending = Set<UUID>()
    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }
    private func setup() {
        wantsLayer = true
        tabs.selectedSegment = 0; tabs.target = self; tabs.action = #selector(changeTab)
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let document = SidebarFlippedView(); document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(stack)
        for button in [create, secondary] { button.isBordered = false; button.alignment = .left; button.contentTintColor = .secondaryLabelColor }
        let footer = NSStackView(views: [create, secondary]); footer.orientation = .vertical; footer.alignment = .leading; footer.spacing = 14
        for view in [tabs, scroll, footer] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: topAnchor, constant: 12), tabs.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), tabs.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 18), scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor), scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18), footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor), stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 10), stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -10)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(refreshConnections), name: .sshConnectionsChanged, object: nil)
        refreshConnections(); applyTheme()
    }
    private func add(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func heading(_ key: String) -> NSTextField {
        let label = NSTextField(labelWithString: L(key)); label.font = .systemFont(ofSize: 11, weight: .semibold); label.textColor = .secondaryLabelColor
        return label
    }
    @objc private func changeTab() { rebuild(); onSectionChange?(tabs.selectedSegment == 1) }
    @objc private func createItem() { if tabs.selectedSegment == 1 { onNewConnection?() } else { onOpenLocal?() } }
    @objc private func secondaryAction() { if tabs.selectedSegment == 1 { onManageConnections?() } }
    @objc private func connect(_ sender: NSButton) {
        guard groups.indices.contains(sender.tag) else { return }
        let connection = groups[sender.tag].connection
        guard !pending.contains(connection.id) else { return }
        onConnection?(connection)
    }
    @objc private func disclosure(_ sender: NSButton) {
        guard groups.indices.contains(sender.tag) else { return }
        let id = groups[sender.tag].connection.id
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
        rebuild()
    }
    @objc private func edit(_ sender: NSButton) {
        guard groups.indices.contains(sender.tag) else { return }
        onEditConnection?(groups[sender.tag].connection)
    }
    func setConnecting(_ id: UUID, _ value: Bool) {
        if value { pending.insert(id) } else { pending.remove(id) }
        rebuild()
    }
    @objc func refreshConnections() { groups = WorkspaceNavigation.servers(saved: SSHConnectionStore().load(), documents: documents); rebuild() }
    private func rebuild() {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        rows.removeAll()
        let servers = tabs.selectedSegment == 1
        create.title = L(servers ? "workspace.newServer" : "workspace.openLocal")
        secondary.title = L("workspace.manageServers")
        secondary.isHidden = !servers
        add(heading(servers ? "workspace.servers" : "workspace.opened"))
        if !servers {
            for document in WorkspaceNavigation.local(documents) { addDocument(document, indented: false) }
        } else {
            if groups.isEmpty { add(heading("workspace.noConnections")) }
            for (index, group) in groups.enumerated() {
                let connection = group.connection
                let arrow = NSButton(image: NSImage(systemSymbolName: collapsed.contains(connection.id) ? "chevron.right" : "chevron.down", accessibilityDescription: L("workspace.expandServer"))!, target: self, action: #selector(disclosure(_:)))
                arrow.isBordered = false; arrow.tag = index; arrow.widthAnchor.constraint(equalToConstant: 16).isActive = true
                let button = NSButton(title: connection.name.isEmpty ? connection.endpoint.host : connection.name, target: self, action: #selector(connect(_:)))
                button.image = NSImage(systemSymbolName: "server.rack", accessibilityDescription: nil); button.imagePosition = .imageLeading
                button.isBordered = false; button.alignment = .left; button.font = .systemFont(ofSize: 13, weight: .medium)
                button.lineBreakMode = .byTruncatingTail; button.tag = index; button.isEnabled = !pending.contains(connection.id)
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                button.toolTip = connection.endpoint.host + ":" + connection.path
                let more = NSButton(title: "…", target: self, action: #selector(edit(_:))); more.tag = index; more.bezelStyle = .rounded
                more.toolTip = L("workspace.manageServers"); more.widthAnchor.constraint(equalToConstant: 28).isActive = true; more.isHidden = !group.saved
                let header = NSStackView(views: [arrow, button, more]); header.spacing = 4
                let detail = NSTextField(labelWithString: pending.contains(connection.id) ? L("remote.connecting", connection.endpoint.host) : connection.endpoint.user + "@" + connection.endpoint.host)
                detail.font = .systemFont(ofSize: 11); detail.textColor = .secondaryLabelColor; detail.lineBreakMode = .byTruncatingMiddle
                let row = NSStackView(views: [header, detail]); row.orientation = .vertical; row.alignment = .leading; row.spacing = 3
                row.edgeInsets = NSEdgeInsets(top: 10, left: 4, bottom: 7, right: 4)
                add(row)
                header.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -8).isActive = true
                detail.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true
                if !collapsed.contains(connection.id) {
                    for document in group.documents { addDocument(document, indented: true) }
                }
            }
        }
    }
    @objc private func compareSelection() { onCompare?(selectedIndices.sorted()) }
    @objc private func openInFinder(_ sender: NSMenuItem) {
        guard let url = localFileURL?(sender.tag), url.isFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    private func documentMenu(for index: Int) -> NSMenu {
        // A context click on either selected row preserves the pair.
        if !selectedIndices.contains(index) { selectDocument(index, modifiers: []) }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let compare = NSMenuItem(title: L("diff.compare"), action: #selector(compareSelection), keyEquivalent: "")
        compare.target = self
        compare.isEnabled = selectedIndices.count == 2
        menu.addItem(compare)
        let reveal = NSMenuItem(title: L("sidebar.openInFinder"), action: #selector(openInFinder(_:)), keyEquivalent: "")
        reveal.target = self
        reveal.tag = index
        reveal.isEnabled = localFileURL?(index)?.isFileURL == true
        menu.addItem(reveal)
        return menu
    }
    private func selectDocument(_ index: Int, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selectedIndices.contains(index) { selectedIndices.remove(index) } else { selectedIndices.insert(index) }
        } else if modifiers.contains(.shift), let anchor = selectionAnchor {
            let visible = rows.map { $0.index }.sorted()
            selectedIndices = Set(visible.filter { $0 >= min(anchor, index) && $0 <= max(anchor, index) })
        } else { selectedIndices = [index] }
        if !modifiers.contains(.shift) { selectionAnchor = index }
        onSelect?(index)
        rebuild()
    }
    private func addDocument(_ document: WorkspaceDocument, indented: Bool) {
        let row = SidebarRow(); row.index = document.index; row.label.stringValue = document.name
        row.icon.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        row.onClick = { [weak self] in self?.selectDocument($0, modifiers: $1) }; row.onClose = { [weak self] in self?.onClose?($0) }
        row.onContextMenu = { [weak self] in self?.documentMenu(for: $0) }
        row.setActive(selectedIndices.contains(document.index)); row.setDirty(document.dirty)
        let container = NSView(); row.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: indented ? 18 : 0), row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.topAnchor.constraint(equalTo: container.topAnchor), row.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        add(container); rows.append(row)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); applyTheme() }
    func applyTheme() {
        let theme = EditorTheme.current()
        layer?.backgroundColor = EditorTheme.withBackgroundOpacity(theme.chromeBackground).cgColor
        rows.forEach { $0.applyTheme(theme) }
    }
    func reload(documents: [WorkspaceDocument], active: Int) {
        self.documents = documents; self.active = active; selectedIndices = [active]; selectionAnchor = active; refreshConnections()
    }
    func setActive(_ index: Int) {
        active = index
        if let document = documents.first(where: { $0.index == index }) {
            tabs.selectedSegment = document.connection == nil ? 0 : 1
            if let connection = document.connection { collapsed.remove(connection.id) }
        }
        rebuild()
    }
    func setDirty(_ index: Int, _ dirty: Bool) {
        documents = documents.map { $0.index == index ? WorkspaceDocument(index: $0.index, name: $0.name, dirty: dirty, connection: $0.connection) : $0 }
        groups = WorkspaceNavigation.servers(saved: SSHConnectionStore().load(), documents: documents)
        for row in rows where row.index == index { row.setDirty(dirty) }
    }
}
private final class SidebarFlippedView: NSView { override var isFlipped: Bool { true } }

/// サイドバーの 1 行（layer 背景＋未保存ドット＋ラベル＋閉じるボタン）。
final class SidebarRow: NSView {
    let label = NSTextField(labelWithString: "")
    let icon = NSImageView()
    private let closeButton = NSButton()
    /// 未保存インジケータ（左端の小さな●。保存済みでは非表示）。
    private let dirtyDot = NSView()
    var index = 0
    var onClick: ((Int, NSEvent.ModifierFlags) -> Void)?
    var onContextMenu: ((Int) -> NSMenu?)?
    /// × ボタンでこの行を閉じる要求。
    var onClose: ((Int) -> Void)?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7

        dirtyDot.wantsLayer = true
        dirtyDot.layer?.cornerRadius = 3
        dirtyDot.isHidden = true
        dirtyDot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dirtyDot)

        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        label.lineBreakMode = .byTruncatingMiddle
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.setButtonType(.momentaryChange)
        closeButton.toolTip = L("sidebar.close")
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            // 左端に未保存ドット用の固定コラム（保存済み/未で名前の左位置がズレないよう常に確保）。
            dirtyDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            dirtyDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dirtyDot.widthAnchor.constraint(equalToConstant: 6),
            dirtyDot.heightAnchor.constraint(equalToConstant: 6),
            icon.leadingAnchor.constraint(equalTo: dirtyDot.trailingAnchor, constant: 5),
            icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 34),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func menu(for event: NSEvent) -> NSMenu? { onContextMenu?(index) }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            if let menu = menu(for: event) { NSMenu.popUpContextMenu(menu, with: event, for: self) }
        } else { onClick?(index, event.modifierFlags) }
    }
    @objc private func closeTapped() { onClose?(index) }

    private var isActive = false
    private var isDirty = false
    private var theme = EditorTheme.current()

    func setActive(_ active: Bool) {
        isActive = active
        restyle()
    }

    /// 未保存状態を反映する（●表示＋×アイコンの塗り分け）。
    func setDirty(_ dirty: Bool) {
        isDirty = dirty
        restyle()
    }

    /// テーマ変更時に色を差し替える（選択・未保存状態は保持）。
    func applyTheme(_ theme: EditorColorTheme) {
        self.theme = theme
        restyle()
    }

    private func restyle() {
        layer?.backgroundColor = (isActive ? NSColor.controlAccentColor.withAlphaComponent(0.12) : .clear).cgColor
        // 名前は可読性優先で通常色のまま。未保存は●と×をアクセント色にして色分けする。
        label.textColor = isActive ? .controlAccentColor : theme.chromeText
        icon.contentTintColor = label.textColor
        dirtyDot.isHidden = !isDirty
        dirtyDot.layer?.backgroundColor = theme.dirtyIndicator.cgColor
        closeButton.image = NSImage(
            systemSymbolName: isDirty ? "xmark.circle.fill" : "xmark.circle",
            accessibilityDescription: L("sidebar.close"))
        closeButton.contentTintColor = isDirty ? theme.dirtyIndicator
                                               : (isActive ? .controlAccentColor : theme.chromeSecondaryText)
    }
}
