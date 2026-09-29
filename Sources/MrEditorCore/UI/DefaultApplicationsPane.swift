import AppKit
import UniformTypeIdentifiers

/// Changes only explicitly selected content types; opening this pane is read-only.
final class DefaultApplicationsPane: NSViewController {
    private struct Entry {
        let type: UTType
        let extensions: String
        let check: NSButton
        let status: NSTextField
    }
    private var entries: [Entry] = []
    private let message = NSTextField(wrappingLabelWithString: "")
    private let applyButton = NSButton()
    private let restoreButton = NSButton()
    private let backupKey = "MrEditor.previousDefaultApplications"
    private var busy = false

    private let customField = NSTextField()
    private let list = NSStackView()
    private let customKey = "MrEditor.customTextExtensions"
    private let restoreAllButton = NSButton()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 540))
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        let hint = NSTextField(wrappingLabelWithString: L("defaults.hint"))
        stack.addArrangedSubview(hint)
        customField.placeholderString = L("defaults.customHint")
        let add = NSButton(title: L("defaults.add"), target: self, action: #selector(addCustom))
        let customRow = NSStackView(views: [customField, add]); customRow.spacing = 8
        stack.addArrangedSubview(customRow)
        list.orientation = .vertical; list.alignment = .leading; list.spacing = 8
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.documentView = list
        list.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(scroll)
        applyButton.title = L("defaults.apply"); applyButton.target = self; applyButton.action = #selector(applySelected)
        restoreButton.title = L("defaults.restore"); restoreButton.target = self; restoreButton.action = #selector(restoreSelected)
        restoreAllButton.title = L("defaults.restoreAll"); restoreAllButton.target = self; restoreAllButton.action = #selector(restoreAll)
        let refresh = NSButton(title: L("defaults.refresh"), target: self, action: #selector(refreshStatus))
        let actions = NSStackView(views: [applyButton, restoreButton, restoreAllButton, refresh]); actions.spacing = 8
        stack.addArrangedSubview(actions); stack.addArrangedSubview(message)
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18),
            hint.widthAnchor.constraint(equalTo: stack.widthAnchor), message.widthAnchor.constraint(equalTo: stack.widthAnchor),
            customRow.widthAnchor.constraint(equalTo: stack.widthAnchor), scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
            list.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            list.topAnchor.constraint(equalTo: scroll.contentView.topAnchor)
        ])
        preferredContentSize = NSSize(width: 620, height: 540)
        rebuildList()
    }
    private func rebuildList() {
        for row in list.arrangedSubviews { list.removeArrangedSubview(row); row.removeFromSuperview() }
        entries.removeAll()
        var seen = Set<String>()
        let custom = UserDefaults.standard.stringArray(forKey: customKey) ?? []
        let groups: [(String, [String])] = [("defaults.documents", ["txt", "log", "md"]),
            ("defaults.data", ["csv", "tsv", "json", "xml", "yaml", "yml", "ini", "conf"]),
            ("defaults.code", ["sh", "py", "js", "sql"]), ("defaults.custom", custom)]
        for (title, extensions) in groups where !extensions.isEmpty {
            let heading = NSTextField(labelWithString: L(title)); heading.font = .boldSystemFont(ofSize: 12)
            list.addArrangedSubview(heading)
            for ext in extensions {
                guard let type = UTType(filenameExtension: ext), seen.insert(type.identifier).inserted else { continue }
                let aliases = type.tags[.filenameExtension] ?? [ext]
                let check = NSButton(checkboxWithTitle: aliases.prefix(4).map { "." + $0 }.joined(separator: ", "), target: nil, action: nil)
                let status = NSTextField(labelWithString: ""); status.textColor = .secondaryLabelColor
                let row = NSStackView(views: [check, status]); row.spacing = 12
                check.widthAnchor.constraint(equalToConstant: 260).isActive = true
                entries.append(Entry(type: type, extensions: ext, check: check, status: status))
                list.addArrangedSubview(row)
            }
        }
        refreshStatus()
    }
    @objc private func addCustom() {
        guard !busy else { return }
        let extensions = customField.stringValue.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "，" }).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        guard !extensions.isEmpty, extensions.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" } }) else {
            message.stringValue = L("defaults.invalidExtension"); return
        }
        var saved = UserDefaults.standard.stringArray(forKey: customKey) ?? []
        for ext in extensions where !saved.contains(ext) { saved.append(ext) }
        UserDefaults.standard.set(saved, forKey: customKey); customField.stringValue = ""; rebuildList()
    }
    @objc private func restoreAll() {
        let backups = UserDefaults.standard.dictionary(forKey: backupKey) as? [String: String] ?? [:]
        // Include backed-up types even when their custom extension is no longer listed.
        for identifier in backups.keys where !entries.contains(where: { $0.type.identifier == identifier }) {
            if let type = UTType(identifier) { entries.append(Entry(type: type, extensions: type.preferredFilenameExtension ?? identifier, check: NSButton(), status: NSTextField())) }
        }
        for entry in entries { entry.check.state = backups[entry.type.identifier] == nil ? .off : .on }
        change(restore: true)
    }
    override func viewWillAppear() { super.viewWillAppear(); refreshStatus() }
    @objc private func refreshStatus() {
        for entry in entries {
            let url = NSWorkspace.shared.urlForApplication(toOpen: entry.type)
            let owned = url?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
            entry.status.stringValue = owned ? L("defaults.managed") : (url.map { FileManager.default.displayName(atPath: $0.path) } ?? L("defaults.none"))
            entry.status.textColor = owned ? .systemGreen : .secondaryLabelColor
            entry.status.toolTip = entry.type.identifier
        }
    }
    @objc private func applySelected() { change(restore: false) }
    @objc private func restoreSelected() { change(restore: true) }
    private func change(restore: Bool) {
        guard !busy else { return }
        let selected = entries.filter { $0.check.state == .on }
        guard !selected.isEmpty else { message.stringValue = L("defaults.select"); return }
        busy = true; applyButton.isEnabled = false; restoreButton.isEnabled = false; restoreAllButton.isEnabled = false
        message.stringValue = L("defaults.working")
        Task { @MainActor in
            var errors: [String] = []
            var completed = 0
            for entry in selected {
                var backups = UserDefaults.standard.dictionary(forKey: backupKey) as? [String: String] ?? [:]
                let current = NSWorkspace.shared.urlForApplication(toOpen: entry.type)
                let target: URL
                if restore {
                    guard let path = backups[entry.type.identifier], FileManager.default.fileExists(atPath: path) else {
                        errors.append(entry.extensions + ": " + L("defaults.noBackup")); continue
                    }
                    target = URL(fileURLWithPath: path)
                } else {
                    target = Bundle.main.bundleURL
                    if let current, current.standardizedFileURL != target.standardizedFileURL, backups[entry.type.identifier] == nil {
                        backups[entry.type.identifier] = current.path
                        UserDefaults.standard.set(backups, forKey: backupKey)
                    }
                }
                do {
                    try await NSWorkspace.shared.setDefaultApplication(at: target, toOpen: entry.type)
                    guard NSWorkspace.shared.urlForApplication(toOpen: entry.type)?.standardizedFileURL == target.standardizedFileURL else {
                        errors.append(entry.extensions + ": " + L("defaults.unconfirmed")); continue
                    }
                    completed += 1
                    if restore { backups.removeValue(forKey: entry.type.identifier); UserDefaults.standard.set(backups, forKey: backupKey) }
                } catch { errors.append(entry.extensions + ": " + error.localizedDescription) }
            }
            busy = false; applyButton.isEnabled = true; restoreButton.isEnabled = true; restoreAllButton.isEnabled = true
            refreshStatus()
            message.stringValue = L("defaults.done", completed) + (errors.isEmpty ? "" : "\n" + errors.joined(separator: "\n"))
        }
    }
}
