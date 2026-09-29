import AppKit

/// One configuration form with two explicit actions, plus a separate saved-connections list.
final class SSHConnectionWindowController: NSWindowController, NSWindowDelegate {
    var direct = false
    var onBusy: ((Bool) -> Void)?
    var onDirectFinished: (() -> Void)?
    var onOpenFile: ((RemoteSession, Bool) -> Void)?
    private let editOnly: Bool
    private let store = SSHConnectionStore()
    private let tabs = NSSegmentedControl(labels: [L("ssh.quick"), L("ssh.saved")], trackingMode: .selectOne, target: nil, action: nil)
    private let content = NSStackView()
    private let form = NSStackView()
    private let saved = NSStackView()
    private let name = NSTextField()
    private let host = NSTextField()
    private let port = NSTextField(string: "22")
    private let user = NSTextField()
    private let auth = NSPopUpButton()
    private let secret = NSSecureTextField()
    private let key = NSTextField()
    private let path = NSTextField(string: "/var/log")
    private let follow = NSButton(checkboxWithTitle: L("ssh.follow"), target: nil, action: nil)
    private let advanced = NSButton(checkboxWithTitle: L("ssh.advanced"), target: nil, action: nil)
    private let jumpEnabled = NSButton(checkboxWithTitle: L("ssh.jump"), target: nil, action: nil)
    private let jumpHost = NSTextField()
    private let jumpPort = NSTextField(string: "22")
    private let jumpUser = NSTextField()
    private let jumpAuth = NSPopUpButton()
    private let jumpKey = NSTextField()
    private let jumpSecret = NSSecureTextField()
    private let remember = NSButton(checkboxWithTitle: L("ssh.remember"), target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let newActions = NSStackView()
    private let editActions = NSStackView()
    private var nameRow: NSView!
    private var keyRow: NSView!
    private var secretRow: NSView!
    private let advancedFields = NSStackView()
    private let jumpFields = NSStackView()
    private var jumpKeyRow: NSView!
    private var jumpSecretRow: NSView!
    private var editing: SSHConnection?
    private var pickers: [RemoteFilePickerController] = []
    private var viewers: [RemoteWindowController] = []
    private var connecting = false
    private var closed = false
    private var transport: SSHTransport?
    private var authentication: SSHAuthentication?

    init(editingConnection: SSHConnection? = nil) {
        editOnly = editingConnection != nil
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = L("remote.title")
        window.minSize = NSSize(width: 600, height: 520)
        super.init(window: window)
        window.delegate = self
        window.center()
        build()
        if let editingConnection {
            window.title = L("ssh.editServerTitle", editingConnection.name)
            fill(editingConnection, edit: true)
            window.initialFirstResponder = name
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func windowWillClose(_ notification: Notification) {
        closed = true; authentication?.cancelled = true; authentication = nil; transport = nil
        secret.stringValue = ""; jumpSecret.stringValue = ""
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: L(title), target: self, action: action)
        b.bezelStyle = .rounded
        return b
    }
    private func vertical(_ stack: NSStackView) {
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
    }
    private func row(_ label: String, _ field: NSView) -> NSView {
        let title = NSTextField(labelWithString: L(label))
        title.widthAnchor.constraint(equalToConstant: 115).isActive = true
        let stack = NSStackView(views: [title, field]); stack.spacing = 10
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return stack
    }
    private func append(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func build() {
        guard let root = window?.contentView else { return }
        vertical(content); content.spacing = 18
        tabs.selectedSegment = store.load().isEmpty ? 0 : 1; tabs.target = self; tabs.action = #selector(changeTab)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let document = SSHFlippedView(); document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        content.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor), scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: document.topAnchor, constant: 22),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -22)
        ])
        if !editOnly { append(tabs, to: content) }
        vertical(form); vertical(saved)
        append(form, to: content)
        if !editOnly { append(saved, to: content) }
        nameRow = row("ssh.name", name); append(nameRow, to: form)
        append(row("ssh.host", host), to: form)
        append(row("ssh.port", port), to: form)
        append(row("ssh.user", user), to: form)
        auth.addItems(withTitles: [L("ssh.password"), L("ssh.key"), "SSH Agent"])
        auth.target = self; auth.action = #selector(updateFields)
        append(row("ssh.auth", auth), to: form)
        let keyGroup = NSStackView(views: [key, button("ssh.choose", #selector(chooseKey))])
        keyRow = row("ssh.key", keyGroup); append(keyRow, to: form)
        secretRow = row("ssh.password", secret); append(secretRow, to: form)
        append(row("ssh.startDirectory", path), to: form)
        let directoryHint = NSTextField(wrappingLabelWithString: L("ssh.directoryHint"))
        directoryHint.textColor = .secondaryLabelColor
        append(directoryHint, to: form)
        follow.state = .on; append(follow, to: form)
        advanced.target = self; advanced.action = #selector(updateFields); append(advanced, to: form)
        vertical(advancedFields); vertical(jumpFields)
        jumpEnabled.target = self; jumpEnabled.action = #selector(updateFields)
        append(jumpEnabled, to: advancedFields)
        append(row("ssh.host", jumpHost), to: jumpFields)
        append(row("ssh.port", jumpPort), to: jumpFields)
        append(row("ssh.user", jumpUser), to: jumpFields)
        jumpAuth.addItems(withTitles: [L("ssh.password"), L("ssh.key"), "SSH Agent"])
        jumpAuth.target = self; jumpAuth.action = #selector(updateFields)
        append(row("ssh.auth", jumpAuth), to: jumpFields)
        jumpSecretRow = row("ssh.secret", jumpSecret); append(jumpSecretRow, to: jumpFields)
        jumpKeyRow = row("ssh.key", NSStackView(views: [jumpKey, button("ssh.choose", #selector(chooseJumpKey))]))
        append(jumpKeyRow, to: jumpFields)
        append(jumpFields, to: advancedFields); append(advancedFields, to: form)
        append(remember, to: form)
        let test = button("ssh.test", #selector(testConnection))
        if !editOnly {
            newActions.addArrangedSubview(button("ssh.connectOnce", #selector(connectOnce)))
            let save = button("ssh.saveConnect", #selector(saveAndConnect)); save.keyEquivalent = "\r"
            newActions.addArrangedSubview(save)
        }
        let cancel = button("ssh.cancel", #selector(cancelEdit))
        if editOnly { cancel.keyEquivalent = "\u{1b}" }
        editActions.addArrangedSubview(cancel)
        let saveChangesButton = button("ssh.saveChanges", #selector(saveChanges))
        if editOnly { saveChangesButton.keyEquivalent = "\r" }
        editActions.addArrangedSubview(saveChangesButton)
        if !editOnly { editActions.addArrangedSubview(button("ssh.saveConnect", #selector(saveEditedAndConnect))) }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: editOnly ? [spacer, editActions] : [test, spacer, newActions, editActions])
        actions.spacing = 8
        append(actions, to: form)
        status.textColor = .secondaryLabelColor; append(status, to: content)
        host.placeholderString = "192.0.2.24 / server.example.com"
        user.placeholderString = "deploy"
        updateFields(); reloadSaved(); changeTab()
    }
    @objc private func changeTab() {
        if editOnly { form.isHidden = false; saved.isHidden = true; return }
        form.isHidden = tabs.selectedSegment != 0; saved.isHidden = tabs.selectedSegment != 1
        if tabs.selectedSegment == 1 { reloadSaved() }
        status.stringValue = ""
    }
    @objc private func updateFields() {
        nameRow.isHidden = editing == nil; remember.isHidden = editing == nil
        newActions.isHidden = editing != nil; editActions.isHidden = editing == nil
        (secretRow as? NSStackView)?.arrangedSubviews.compactMap { $0 as? NSTextField }.first?.stringValue = L(auth.indexOfSelectedItem == 1 ? "ssh.passphrase" : "ssh.password")
        (jumpSecretRow as? NSStackView)?.arrangedSubviews.compactMap { $0 as? NSTextField }.first?.stringValue = L(jumpAuth.indexOfSelectedItem == 1 ? "ssh.passphrase" : "ssh.password")
        keyRow.isHidden = auth.indexOfSelectedItem != 1
        secretRow.isHidden = auth.indexOfSelectedItem == 2
        advancedFields.isHidden = advanced.state != .on
        jumpFields.isHidden = jumpEnabled.state != .on
        jumpKeyRow.isHidden = jumpAuth.indexOfSelectedItem != 1
        jumpSecretRow.isHidden = jumpAuth.indexOfSelectedItem == 2
    }
    private func selectKey(into field: NSTextField) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard let window else { return }
        panel.beginSheetModal(for: window) { result in if result == .OK { field.stringValue = panel.url?.path ?? "" } }
    }
    @objc private func chooseKey() { selectKey(into: key) }
    @objc private func chooseJumpKey() { selectKey(into: jumpKey) }
    private func read() throws -> SSHConnection {
        func endpoint(_ h: NSTextField, _ p: NSTextField, _ u: NSTextField, _ a: NSPopUpButton, _ k: NSTextField) -> SSHConnection.Endpoint {
            .init(host: h.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), port: Int(p.stringValue) ?? 0,
                  user: u.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                  authentication: SSHConnection.Authentication.allCases[a.indexOfSelectedItem], privateKey: k.stringValue)
        }
        var c = editing ?? SSHConnection()
        c.name = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        c.endpoint = endpoint(host, port, user, auth, key)
        if c.path != path.stringValue { c.pathKind = .directory }
        c.path = path.stringValue; c.follow = follow.state == .on
        c.jump = jumpEnabled.state == .on ? endpoint(jumpHost, jumpPort, jumpUser, jumpAuth, jumpKey) : nil
        c.rememberCredentials = remember.state == .on
        try c.validate()
        return c
    }
    private func report(_ error: Error) {
        status.stringValue = RemoteWindowController.describe(error)
        if direct {
            onBusy?(false)
            let alert = NSAlert(); alert.messageText = L("workspace.connectionFailed"); alert.informativeText = status.stringValue
            alert.runModal()
            onDirectFinished?()
        }
    }
    @objc private func testConnection() { launchForm(testOnly: true) }
    @objc private func connectOnce() { launchForm(testOnly: false) }
    private func launchForm(testOnly: Bool) {
        do { let c = try read(); connect(c, credentials: .init(target: secret.stringValue, jump: jumpSecret.stringValue), testOnly: testOnly) }
        catch { report(error) }
    }
    @objc private func saveAndConnect() {
        do {
            var c = try read()
            let alert = NSAlert(); alert.messageText = L("ssh.saveConnect")
            alert.informativeText = "\(c.endpoint.user)@\(c.endpoint.host):\(c.endpoint.port)"
            let field = NSTextField(string: ""); field.placeholderString = L("ssh.name")
            let check = NSButton(checkboxWithTitle: L("ssh.remember"), target: nil, action: nil)
            let fields = NSStackView(views: [field, check]); vertical(fields)
            fields.frame = NSRect(x: 0, y: 0, width: 380, height: 65)
            field.widthAnchor.constraint(equalToConstant: 380).isActive = true
            alert.accessoryView = fields
            alert.addButton(withTitle: L("ssh.saveConnect")); alert.addButton(withTitle: L("ssh.cancel"))
            alert.window.initialFirstResponder = field
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            c.name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !c.name.isEmpty else { status.stringValue = L("ssh.nameRequired"); return }
            c.rememberCredentials = check.state == .on
            let credentials = SSHCredentials(target: secret.stringValue, jump: jumpSecret.stringValue)
            try persist(c, credentials: credentials)
            connect(c, credentials: credentials, testOnly: false)
        } catch { report(error) }
    }
    private func persist(_ c: SSHConnection, credentials: SSHCredentials) throws {
        if c.rememberCredentials { try credentials.save(c.id) } else { try SSHCredentials.delete(c.id) }
        try store.save(c); reloadSaved()
    }
    @objc private func saveChanges() { saveEdit(connectAfter: false) }
    @objc private func saveEditedAndConnect() { saveEdit(connectAfter: true) }
    private func saveEdit(connectAfter: Bool) {
        do {
            let c = try read()
            guard !c.name.isEmpty else { status.stringValue = L("ssh.nameRequired"); return }
            let credentials = SSHCredentials(target: secret.stringValue, jump: jumpSecret.stringValue)
            try persist(c, credentials: credentials)
            if editOnly { close(); return }
            editing = nil; updateFields(); tabs.selectedSegment = 1; changeTab()
            if connectAfter { connect(c, credentials: credentials, testOnly: false) }
        } catch { report(error) }
    }
    @objc private func cancelEdit() { if editOnly { close(); return }; editing = nil; secret.stringValue = ""; jumpSecret.stringValue = ""; updateFields(); tabs.selectedSegment = 1; changeTab() }
    private func reloadSaved() {
        guard !editOnly else { return }
        saved.arrangedSubviews.forEach { saved.removeArrangedSubview($0); $0.removeFromSuperview() }
        let records = store.load()
        if records.isEmpty { append(NSTextField(wrappingLabelWithString: L("ssh.empty")), to: saved) }
        for (index, c) in records.enumerated() {
            let title = NSTextField(labelWithString: c.name); title.font = .boldSystemFont(ofSize: 14)
            append(title, to: saved)
            let detail = NSTextField(wrappingLabelWithString: "\(c.endpoint.user)@\(c.endpoint.host):\(c.endpoint.port)\n\(c.path)")
            detail.textColor = .secondaryLabelColor; append(detail, to: saved)
            let state = NSTextField(labelWithString: L(c.rememberCredentials ? "ssh.credentialsSaved" : "ssh.credentialsAsk"))
            state.textColor = .secondaryLabelColor; append(state, to: saved)
            let actions = NSStackView()
            for (label, selector) in [("ssh.connect", #selector(connectSaved(_:))), ("ssh.edit", #selector(editSaved(_:))),
                                      ("ssh.duplicate", #selector(duplicateSaved(_:))), ("ssh.delete", #selector(deleteSaved(_:)))] {
                let b = button(label, selector); b.tag = index; actions.addArrangedSubview(b)
            }
            append(actions, to: saved)
            let separator = NSBox(); separator.boxType = .separator; append(separator, to: saved)
        }
        append(button("ssh.new", #selector(newConnection)), to: saved)
    }
    @objc private func newConnection() {
        editing = nil; name.stringValue = ""; host.stringValue = ""; port.stringValue = "22"; user.stringValue = ""
        auth.selectItem(at: 0); key.stringValue = ""; secret.stringValue = ""; jumpSecret.stringValue = ""
        path.stringValue = "/var/log"; follow.state = .on; jumpEnabled.state = .off; advanced.state = .off
        remember.state = .off; updateFields(); tabs.selectedSegment = 0; changeTab()
    }
    private func record(_ sender: NSButton) -> SSHConnection? {
        let list = store.load(); return list.indices.contains(sender.tag) ? list[sender.tag] : nil
    }
    func startConnection(_ c: SSHConnection) {
        connect(c, credentials: c.rememberCredentials ? SSHCredentials.load(c.id) : SSHCredentials(), testOnly: false)
    }
    func showNewConnection() { newConnection() }
    @objc private func connectSaved(_ sender: NSButton) {
        guard let c = record(sender) else { return }
        connect(c, credentials: c.rememberCredentials ? SSHCredentials.load(c.id) : SSHCredentials(), testOnly: false)
    }
    @objc private func editSaved(_ sender: NSButton) {
        guard let c = record(sender) else { return }; fill(c, edit: true)
    }
    @objc private func duplicateSaved(_ sender: NSButton) {
        guard var c = record(sender) else { return }; c.id = UUID(); c.rememberCredentials = false; fill(c, edit: false)
    }
    private func fill(_ c: SSHConnection, edit: Bool) {
        editing = edit ? c : nil; name.stringValue = c.name; host.stringValue = c.endpoint.host
        port.stringValue = String(c.endpoint.port); user.stringValue = c.endpoint.user; key.stringValue = c.endpoint.privateKey
        auth.selectItem(at: SSHConnection.Authentication.allCases.firstIndex(of: c.endpoint.authentication)!)
        path.stringValue = c.path; follow.state = c.follow ? .on : .off; remember.state = c.rememberCredentials ? .on : .off
        let credentials = edit && c.rememberCredentials ? SSHCredentials.load(c.id) : SSHCredentials()
        secret.stringValue = credentials.target; jumpSecret.stringValue = credentials.jump
        jumpEnabled.state = c.jump == nil ? .off : .on; advanced.state = jumpEnabled.state
        let j = c.jump ?? SSHConnection.Endpoint()
        jumpHost.stringValue = j.host; jumpPort.stringValue = String(j.port); jumpUser.stringValue = j.user; jumpKey.stringValue = j.privateKey
        jumpAuth.selectItem(at: SSHConnection.Authentication.allCases.firstIndex(of: j.authentication)!)
        updateFields(); tabs.selectedSegment = 0; changeTab()
    }
    @objc private func deleteSaved(_ sender: NSButton) {
        guard let c = record(sender) else { return }
        let alert = NSAlert(); alert.messageText = L("ssh.deleteTitle", c.name); alert.informativeText = L("ssh.deleteHint")
        alert.addButton(withTitle: L("ssh.delete")); alert.addButton(withTitle: L("ssh.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try store.delete(c.id); reloadSaved() } catch { report(error) }
    }

    private func setBusy(_ busy: Bool) {
        connecting = busy
        onBusy?(busy)
        func enable(_ view: NSView) {
            if let control = view as? NSControl { control.isEnabled = !busy }
            view.subviews.forEach(enable)
        }
        enable(content)
    }
    private func connect(_ c: SSHConnection, credentials: SSHCredentials, testOnly: Bool) {
        guard !connecting else { return }
        do {
            try c.validate()
            closed = false
            let authentication = SSHAuthentication(connection: c, credentials: credentials)
            self.authentication = authentication
            let transport = try SSHTransport(connection: c) { prompt in
                var response: String?
                DispatchQueue.main.sync { response = authentication.answer(prompt) }
                return response
            }
            authentication.transport = transport
            self.transport = transport
            setBusy(true); status.stringValue = L("remote.connecting", c.endpoint.host)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    let session = try RemoteSession.connect(using: transport, requireFile: false)
                    if testOnly {
                        let location = try session.browserLocation(path: c.path, legacy: c.pathKind == nil)
                        _ = try session.listDirectory(location.directory)
                    }
                    DispatchQueue.main.async {
                        guard let self, !self.closed else { return }
                        self.setBusy(false)
                        if !testOnly, c.rememberCredentials, self.store.load().contains(where: { $0.id == c.id }) {
                            do { try authentication.credentials.save(c.id) } catch { self.report(error); return }
                        }
                        self.secret.stringValue = ""; self.jumpSecret.stringValue = ""
                        if testOnly { self.status.stringValue = L("ssh.testSuccess"); self.transport = nil; self.authentication = nil }
                        else {
                            let picker = RemoteFilePickerController(session: session, path: c.path, legacy: c.pathKind == nil, follow: c.follow)
                            picker.onOpen = { [weak self] file, follow in
                                guard let self else { return }
                                if let onOpenFile = self.onOpenFile {
                                    onOpenFile(file, follow)
                                    self.close()
                                    return
                                }
                                let viewer = RemoteWindowController()
                                self.viewers.append(viewer)
                                viewer.showWindow(nil); viewer.window?.makeKeyAndOrderFront(nil)
                                viewer.open(session: file, follow: follow)
                            }
                            picker.onInitialDirectory = { [weak self] directory in
                                guard let self else { return }
                                // Update only this unchanged profile; never overwrite edits in another window.
                                if var stored = self.store.load().first(where: { $0.id == c.id }), stored == c {
                                    stored.path = directory; stored.pathKind = .directory
                                    do { try self.store.save(stored); self.reloadSaved() } catch { self.report(error) }
                                }
                                if self.path.stringValue == c.path { self.path.stringValue = directory }
                            }
                            picker.onClose = { [weak self, weak picker] in
                                self?.pickers.removeAll { $0 === picker }
                                if self?.direct == true { self?.onDirectFinished?() }
                            }
                            self.pickers.append(picker)
                            picker.showWindow(nil); picker.window?.makeKeyAndOrderFront(nil); picker.start()
                            self.status.stringValue = L("ssh.chooseRemoteFile")
                            self.transport = nil; self.authentication = nil
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        guard let self, !self.closed else { return }
                        self.setBusy(false); self.transport = nil; self.authentication = nil
                        self.report(error)
                    }
                }
            }
        } catch { report(error) }
    }
}

private final class SSHFlippedView: NSView {
    override var isFlipped: Bool { true }
}
