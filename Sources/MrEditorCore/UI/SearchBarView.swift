import AppKit

/// 検索バー（ビューア右上に浮かぶ）。
///
/// custom draw() は持たない。背景・枠はレイヤで描く。
/// （custom draw を持つビューに子コントロールを同居させると、同一ウィンドウ内の
/// 別のカスタム描画ビューの合成が壊れる macOS の不具合を避けるため。[StatusBarView] 同様。）
final class SearchBarView: NSView, NSSearchFieldDelegate {
    static let height: CGFloat = 166   // 查找与替换两行
    private static let resultsHeight: CGFloat = 220

    private let field = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")

    private let caseToggle = NSButton()
    private let regexToggle = NSButton()
    private let filterToggle = NSButton()
    /// 前後 N 行（`grep -C`）。**アイコンでなく文字と数字**にしてある——
    /// 絞り込んだ画面に「±2」と出ていれば何が起きているか読めるが、記号だけだと気づかれない。
    private let contextLabel = NSTextField(labelWithString: "±")
    private let contextField = NSTextField()

    private let replaceField = NSTextField()
    private let replaceButton = NSButton()
    private let replaceAllButton = NSButton()
    private let preserveCaseToggle = NSButton()
    private let findAllButton = NSButton()
    private let resultSummary = NSTextField(labelWithString: "")
    private var replaceRowView: NSView?
    private let modeButton = NSButton()
    private let selectAll = NSButton()
    private let selectNone = NSButton()
    private let resultsScroll = NSScrollView()
    private let resultsTable = NSTableView()
    private var resultRows: [(line: Int, text: String)] = []

    var onQueryChange: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrev: (() -> Void)?
    var onClose: (() -> Void)?
    var onCaseToggle: ((Bool) -> Void)?
    var onRegexToggle: ((Bool) -> Void)?
    var onFilterToggle: ((Bool) -> Void)?
    /// 漏斗が**使えないペインに移ったせいで**降りたとき。本人が消したのとは別物で、
    /// 次に使えるペインへ戻ったら元に戻す（意図は消えていない）。
    var onFilterUnavailable: (() -> Void)?
    var onContextChange: ((Int) -> Void)?
    var onReplace: ((String) -> Void)?
    var onReplaceAll: ((String) -> Void)?
    var onPreserveCaseToggle: ((Bool) -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?
    var onFindAll: (() -> Void)?
    var onSelectResult: ((Int) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    let scopeSelector = NSPopUpButton()
    var onScopeChange: ((Int) -> Void)?
    var onSelectResultIndex: ((Int) -> Void)?
    var onSelectPreviewDetail: ((ReplacementDetail) -> Void)?
    var scope: Int { scopeSelector.indexOfSelectedItem }
    var caseSensitive: Bool { caseToggle.state == .on }
    var regexMode: Bool { regexToggle.state == .on }
    var preserveCase: Bool { preserveCaseToggle.state == .on }
    @objc private func scopeChanged() {
        collapseResults(); preview = nil; onScopeChange?(scope)
    }
    private let modeSelector = NSSegmentedControl()
    let resultsArea = NSView()
    var onResultsHeightChange: ((CGFloat) -> Void)?
    private let applyPreviewButton = NSButton()
    private let undoPreviewButton = NSButton()
    private var preview: ReplacementPreview?
    private var selectedPreview = Set<Int>()
    private var previewApplied = false
    private var expandedLines = Set<Int>()
    var onDirectReplaceAll: ((String) -> Void)?
    private var previewGroups: [[Int]] {
        guard let preview else { return [] }
        var groups: [[Int]] = []
        for i in preview.details.indices {
            if let last = groups.last?.first, preview.details[last].line == preview.details[i].line, preview.details[last].documentID == preview.details[i].documentID { groups[groups.count - 1].append(i) }
            else { groups.append([i]) }
        }
        return groups
    }
    private var headerHeight: CGFloat { modeSelector.selectedSegment == 0 ? 124 : 166 }

    private func setup() {
        wantsLayer = true
        applyColors()
        field.placeholderString = L("search.placeholder")
        field.delegate = self; field.target = self; field.action = #selector(enterPressed)
        field.sendsSearchStringImmediately = false
        field.recentsAutosaveName = "MrEditor.searchHistory"
        field.searchMenuTemplate = Self.makeSearchMenuTemplate(); field.maximumRecents = 10
        replaceField.placeholderString = L("search.replacePlaceholder")
        replaceField.delegate = self
        replaceField.target = self; replaceField.action = #selector(replaceTapped)
        modeSelector.segmentCount = 2
        modeSelector.setLabel(L("search.placeholder"), forSegment: 0)
        modeSelector.setLabel(L("search.findReplace"), forSegment: 1)
        modeSelector.selectedSegment = 1; modeSelector.target = self
        modeSelector.action = #selector(toggleReplaceRow)
        func configure(_ b: NSButton, _ title: String, _ action: Selector, toggle: Bool = false) {
            b.title = title; b.target = self; b.action = action; b.bezelStyle = .rounded
            if toggle { b.setButtonType(.pushOnPushOff) }
            b.setContentHuggingPriority(.required, for: .horizontal)
        }
        configure(caseToggle, "Aa", #selector(caseTapped), toggle: true)
        configure(regexToggle, ".*", #selector(regexTapped), toggle: true)
        configure(filterToggle, L("search.filterLines"), #selector(filterTapped), toggle: true)
        configure(preserveCaseToggle, "aA", #selector(preserveCaseTapped), toggle: true)
        configure(findAllButton, L("search.findAll"), #selector(findAllTapped))
        findAllButton.bezelColor = .controlAccentColor
        configure(replaceButton, L("search.replace"), #selector(replaceTapped))
        configure(replaceAllButton, L("search.preview"), #selector(replaceAllTapped))
        configure(applyPreviewButton, L("search.applySelected"), #selector(applyPreview))
        configure(undoPreviewButton, L("search.undoReplacement"), #selector(undoPreview))
        undoPreviewButton.isEnabled = false
        contextField.placeholderString = "0"; contextField.target = self; contextField.action = #selector(contextEdited)
        contextField.widthAnchor.constraint(equalToConstant: 32).isActive = true
        func row(_ views: [NSView]) -> NSStackView {
            let r = NSStackView(views: views); r.spacing = 8
            return r
        }
        func spacer() -> NSView { let v = NSView(); v.setContentHuggingPriority(.defaultLow, for: .horizontal); return v }
        scopeSelector.addItems(withTitles: [L("scope.current"), L("scope.selection"), L("scope.open")])
        scopeSelector.target = self; scopeSelector.action = #selector(scopeChanged)
        let title = row([modeSelector, spacer(), scopeSelector, iconButton("xmark", #selector(closeTapped))])
        let findLabel = NSTextField(labelWithString: L("search.placeholder"))
        let replaceLabel = NSTextField(labelWithString: L("search.replacePlaceholder"))
        for label in [findLabel, replaceLabel] { label.widthAnchor.constraint(equalToConstant: 54).isActive = true }
        let find = row([findLabel, field, caseToggle, regexToggle, findAllButton])
        let direct = NSButton(title: L("search.replaceAll"), target: self, action: #selector(directReplaceAll))
        direct.bezelStyle = .rounded
        let replace = row([replaceLabel, replaceField, preserveCaseToggle, replaceButton, direct, replaceAllButton])
        replaceRowView = replace
        let meta = row([countLabel, spacer(), filterToggle, contextLabel, contextField,
                        iconButton("chevron.up", #selector(prevTapped)), iconButton("chevron.down", #selector(nextTapped)), undoPreviewButton])
        let stack = NSStackView(views: [title, find, replace, meta])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
        ])
        for r in [title, find, replace, meta] {
            r.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            r.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        replaceField.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
        resultsTable.usesAlternatingRowBackgroundColors = true
        resultsTable.style = .plain
        resultsTable.addTableColumn(column); resultsTable.headerView = nil; resultsTable.rowHeight = 30
        resultsTable.delegate = self; resultsTable.dataSource = self
        resultsTable.target = self; resultsTable.action = #selector(resultDoubleClicked)
        resultsScroll.documentView = resultsTable; resultsScroll.hasVerticalScroller = true
        let collapse = NSButton(title: L("search.collapse"), target: self, action: #selector(collapseResults))
        selectAll.title = L("search.selectAll"); selectAll.target = self; selectAll.action = #selector(selectPreviewAll)
        selectNone.title = L("search.selectNone"); selectNone.target = self; selectNone.action = #selector(selectPreviewNone)
        let heading = row([resultSummary, spacer(), selectAll, selectNone, applyPreviewButton, collapse])
        for v in [heading, resultsScroll] { v.translatesAutoresizingMaskIntoConstraints = false; resultsArea.addSubview(v) }
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: resultsArea.topAnchor, constant: 8),
            heading.leadingAnchor.constraint(equalTo: resultsArea.leadingAnchor, constant: 18),
            heading.trailingAnchor.constraint(equalTo: resultsArea.trailingAnchor, constant: -18),
            heading.heightAnchor.constraint(equalToConstant: 28),
            resultsScroll.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            resultsScroll.leadingAnchor.constraint(equalTo: resultsArea.leadingAnchor),
            resultsScroll.trailingAnchor.constraint(equalTo: resultsArea.trailingAnchor),
            resultsScroll.bottomAnchor.constraint(equalTo: resultsArea.bottomAnchor),
        ])
        resultsArea.isHidden = true; applyPreviewButton.isHidden = true
    }

    func showPreview(_ value: ReplacementPreview) {
        selectAll.isHidden = false; selectNone.isHidden = false
        expandedLines.removeAll()
        preview = value; previewApplied = false; selectedPreview = Set(value.rows.indices)
        resultsVisible = true; resultsArea.isHidden = false
        resultSummary.isHidden = false; resultsScroll.isHidden = false
        applyPreviewButton.isHidden = false; applyPreviewButton.isEnabled = !selectedPreview.isEmpty
        resultSummary.stringValue = L("search.previewCount", selectedPreview.count, value.rows.count)
            + (value.limited ? " · " + L("search.previewLimit") : "")
        refreshPreviewSummary(); onResultsHeightChange?(300); resultsTable.reloadData()
    }
    @objc private func applyPreview() {
        guard let preview else { return }
        guard preview.apply(selectedPreview) else { resultSummary.stringValue = L("search.previewStale"); applyPreviewButton.isEnabled = false; return }
        previewApplied = true; applyPreviewButton.isEnabled = false; undoPreviewButton.isEnabled = true
        resultSummary.stringValue = L("search.applied", selectedPreview.count); resultsTable.reloadData()
    }
    @objc private func undoPreview() {
        guard let preview, preview.canUndo() else {
            resultSummary.stringValue = L("search.undoStale"); undoPreviewButton.isEnabled = false; return
        }
        preview.undo(); undoPreviewButton.isEnabled = false
        resultSummary.stringValue = L("search.undone")
    }
    @objc private func togglePreview(_ button: NSButton) {
        if button.state == .on { selectedPreview.insert(button.tag) } else { selectedPreview.remove(button.tag) }
        applyPreviewButton.isEnabled = !selectedPreview.isEmpty
        refreshPreviewSummary(); resultsTable.reloadData()
    }
    private func refreshPreviewSummary() {
        guard let preview else { return }
        let lines = Set(selectedPreview.map { preview.details[$0].documentID + ":" + String(preview.details[$0].line) }).count
        applyPreviewButton.title = L("search.applyCount", selectedPreview.count)
        let key = selectedPreview.allSatisfy({ preview.details[$0].replacement.isEmpty }) ? "search.deleteSummary" : "search.changeSummary"
        resultSummary.stringValue = L(key, selectedPreview.count, lines) + (preview.limited ? " · " + L("search.previewLimit") : "")
    }
    @objc private func selectPreviewAll() {
        guard let preview, !previewApplied else { return }
        selectedPreview = Set(preview.details.indices); refreshPreviewSummary(); resultsTable.reloadData(); applyPreviewButton.isEnabled = !selectedPreview.isEmpty
    }
    @objc private func selectPreviewNone() {
        guard preview != nil, !previewApplied else { return }
        selectedPreview = []; refreshPreviewSummary(); resultsTable.reloadData(); applyPreviewButton.isEnabled = false
    }
    @objc private func directReplaceAll() { onDirectReplaceAll?(replaceField.stringValue) }
    @objc private func toggleGroup(_ button: NSButton) {
        let group = previewGroups[button.tag]
        if group.allSatisfy({ selectedPreview.contains($0) }) { selectedPreview.subtract(group) } else { selectedPreview.formUnion(group) }
        refreshPreviewSummary(); resultsTable.reloadData()
        applyPreviewButton.isEnabled = !selectedPreview.isEmpty
    }
    @objc private func expandGroup(_ button: NSButton) {
        if !expandedLines.insert(button.tag).inserted { expandedLines.remove(button.tag) }
        resultsTable.reloadData()
        resultsTable.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<previewGroups.count))
    }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard preview != nil, previewGroups.indices.contains(row) else { return 30 }
        return 94 + (expandedLines.contains(row) ? CGFloat(previewGroups[row].count * 28) : 0)
    }
    private func previewCell(_ row: Int) -> NSView {
        let preview = preview!, group = previewGroups[row], first = preview.details[group[0]]
        let before = NSMutableAttributedString(string: first.source)
        let after = NSMutableAttributedString(attributedString: before)
        for i in group.reversed() where selectedPreview.contains(i) {
            let d = preview.details[i]
            guard NSMaxRange(d.range) <= before.length else { continue }
            before.addAttributes([.foregroundColor: NSColor.systemRed, .strikethroughStyle: 1], range: d.range)
            after.replaceCharacters(in: d.range, with: NSAttributedString(string: d.replacement, attributes: [.foregroundColor: NSColor.systemGreen]))
        }
        let check = NSButton(checkboxWithTitle: (first.documentName.isEmpty ? "" : first.documentName + " · ") + L("search.lineChanges", first.line, group.count), target: self, action: #selector(toggleGroup(_:)))
        check.tag = row; check.allowsMixedState = true
        let count = group.filter { selectedPreview.contains($0) }.count
        check.state = count == 0 ? .off : (count == group.count ? .on : .mixed); check.isEnabled = !previewApplied
        let expand = NSButton(title: L(expandedLines.contains(row) ? "search.collapse" : "search.expandMatches"), target: self, action: #selector(expandGroup(_:)))
        expand.tag = row
        let heading = NSStackView(views: group.count > 1 ? [check, expand] : [check]); heading.spacing = 16
        let stack = NSStackView(views: [heading]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 5
        for (label, value) in [(L("search.before"), before), (L("search.after"), after)] {
            let text = NSTextField(labelWithString: "")
            let content = NSMutableAttributedString(string: label + "   ", attributes: [.foregroundColor: NSColor.secondaryLabelColor])
            content.append(value); text.attributedStringValue = content
            text.lineBreakMode = .byTruncatingTail; text.toolTip = content.string
            stack.addArrangedSubview(text)
            text.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        if expandedLines.contains(row) {
            for i in group {
                let d = preview.details[i]
                let text = (d.source as NSString).substring(with: d.range)
                let button = NSButton(checkboxWithTitle: L("search.occurrence", d.range.location + 1) + "  " + text + " → " + (d.replacement.isEmpty ? L("search.deleteText") : d.replacement), target: self, action: #selector(togglePreview(_:)))
                button.tag = i; button.state = selectedPreview.contains(i) ? .on : .off; button.isEnabled = !previewApplied
                stack.addArrangedSubview(button)
            }
        }
        let cell = NSView(); stack.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10), stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10), stack.topAnchor.constraint(equalTo: cell.topAnchor, constant: 6)])
        return cell
    }
    @objc private func collapseResults() { resultsVisible = false; resultsArea.isHidden = true; onResultsHeightChange?(0) }

    /// 文字のトグル（Aa / .*）は縮めさせない。詰まると「…」に化けて何のボタンか読めなくなる
    /// （±N の欄を足したときに実際そうなった）。狭いときに縮むのは検索欄の側でよい。
    private func keepIntrinsicWidth(_ views: [NSView]) {
        for v in views {
            v.setContentCompressionResistancePriority(.required, for: .horizontal)
            v.setContentHuggingPriority(.required, for: .horizontal)
        }
    }

    /// 検索語の履歴メニューのひな形。**タグ付きの項目を並べるだけ**で中身は空でよい——
    /// `NSSearchField` が表示のたびに `recentsTitleMenuItemTag`/`recentsMenuItemTag` の位置に
    /// 見出しと実際の履歴を差し込み、`noRecentsMenuItemTag` は履歴が無いときだけ残す。
    private static func makeSearchMenuTemplate() -> NSMenu {
        let menu = NSMenu()

        let title = NSMenuItem(title: L("search.recentSearches"), action: nil, keyEquivalent: "")
        title.tag = NSSearchField.recentsTitleMenuItemTag
        menu.addItem(title)

        let recentsPlaceholder = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        recentsPlaceholder.tag = NSSearchField.recentsMenuItemTag
        menu.addItem(recentsPlaceholder)

        let noRecents = NSMenuItem(title: L("search.noRecentSearches"), action: nil, keyEquivalent: "")
        noRecents.tag = NSSearchField.noRecentsMenuItemTag
        menu.addItem(noRecents)

        menu.addItem(.separator())

        let clear = NSMenuItem(title: L("search.clearRecentSearches"), action: nil, keyEquivalent: "")
        clear.tag = NSSearchField.clearRecentsMenuItemTag
        menu.addItem(clear)

        return menu
    }

    private func iconButton(_ symbol: String, _ action: Selector) -> NSButton {
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        let b = NSButton(image: img ?? NSImage(), target: self, action: action)
        b.isBordered = false
        b.bezelStyle = .smallSquare
        b.imageScaling = .scaleProportionallyDown
        b.setContentHuggingPriority(.required, for: .horizontal)
        return b
    }

    private func applyColors() {
        let theme = EditorTheme.current()
        layer?.backgroundColor = EditorTheme.withBackgroundOpacity(theme.chromeBackground).cgColor
        layer?.borderColor = theme.separator.cgColor
        countLabel.textColor = theme.chromeSecondaryText
        syncContextEnabled()   // 「±」の色は使える／使えないで変わる
    }
    /// 配色（テーマ）を検索パネルへ適用する（内部の検索フィールド・ボタンは窓アピアランスに追従）。
    func applyTheme() { applyColors() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance { applyColors() }
    }

    // MARK: - 公開API

    var query: String { field.stringValue }

    /// 検索語の履歴（AppKit 標準機能）が有効になっているかのテスト用アクセサ。
    var _testSearchHistoryAutosaveName: String? { field.recentsAutosaveName }
    var _testSearchHistoryMenuEnabled: Bool { field.searchMenuTemplate != nil }
    var _testRecentSearches: [String] { field.recentSearches }
    /// 検索欄に文字を入れて Enter を押したのと同じ経路（履歴に積まれることの確認用）。
    func _testCommitSearch(_ text: String) {
        field.stringValue = text
        enterPressed()
    }
    /// `recentsAutosaveName` はユーザ既定に永続化されるため、`SearchBarView()` を
    /// 新しく作っても前のテストの履歴を引き継いでしまう。テストの `setUp` で呼んで消す。
    func _testResetHistory() { field.recentSearches = [] }

    /// フィルタ（一致行だけ表示）を使えないペインでは漏斗ボタンを隠す。
    func setFilterAvailable(_ available: Bool) {
        if !available, filterToggle.state == .on {
            filterToggle.state = .off
            onFilterUnavailable?()
        }
        filterToggle.isHidden = !available
        contextLabel.isHidden = !available
        contextField.isHidden = !available
        syncContextEnabled()
    }

    /// 前後 N 行の欄は**絞り込んでいる間だけ**触れる（絞っていないときは前後も何もない）。
    private func syncContextEnabled() {
        let on = !filterToggle.isHidden && filterToggle.state == .on
        contextField.isEnabled = on
        contextLabel.textColor = on ? EditorTheme.current().chromeText
                                    : EditorTheme.current().chromeSecondaryText
    }

    /// 前後 N 行を外から立てる（メニューの増減・ペインを切り替えたとき）。
    func setContextLines(_ n: Int) {
        contextField.stringValue = n > 0 ? String(n) : ""
        syncContextEnabled()
    }

    /// 置換できないペイン（構造化表示中・一致行だけ表示中）では置換の行を触れなくする。
    /// 隠さずに落とすのは、バーの高さが固定で行を消すと隙間が空くため。
    func setReplaceAvailable(_ available: Bool) {
        replaceField.isEnabled = available
        preserveCaseToggle.isEnabled = available
        replaceButton.isEnabled = available
        replaceAllButton.isEnabled = available
    }

    /// 漏斗ボタンの状態を外から立てる（ツールバーの「フィルタ」から開いたとき用）。
    /// 押下イベントを伴わないので、本文側の反映は呼び出し元が行う。
    func setFilterOn(_ on: Bool) {
        guard !filterToggle.isHidden else { return }
        filterToggle.state = on ? .on : .off
        syncContextEnabled()
    }

    func focusField() {
        onHeightChange?(headerHeight)
        window?.makeFirstResponder(field)
        field.selectText(nil)
    }

    /// 外から検索条件を丸ごと立てる（分析ペインの表から「この値で絞る」を押したとき）。
    /// **本文側の反映は呼び出し元が行う**（`setFilterOn` と同じ約束）。
    func setQuery(_ text: String, regex: Bool, caseSensitive: Bool, filter: Bool) {
        field.stringValue = text
        regexToggle.state = regex ? .on : .off
        caseToggle.state = caseSensitive ? .on : .off
        setFilterOn(filter)
    }

    /// `capped` が真なら総数は上限で打ち切った下限＝「N 件以上」と出す。
    /// 打ち切った数をそのまま「N 件」と言うと、実際より少ない数を断言してしまう。
    ///
    /// **走査中は、件数のうしろに進み具合を付ける。**（2026-09-05 に直した）
    /// 前は「検索中… N%」を `total == 0` のときだけ出していたので、1 件でも当たった
    /// 瞬間に「13 件」へ切り替わり、まだ走査中でも**確定したように見えていた**。
    /// 大きいファイルでは件数がそのあとも増え続けるのに、終わりの合図が無かった
    /// （「いつが終わりかわからない」）。件数と進み具合を同時に出せば、
    /// **進み具合が消えたときが終わり**になる。
    func setCount(current: Int, total: Int, searching: Bool, progress: Int,
                  invalid: Bool, capped: Bool = false) {
        countLabel.stringValue = Self.countText(query: query, current: current, total: total,
                                                searching: searching, progress: progress,
                                                invalid: invalid, capped: capped)
        if resultsVisible && preview == nil { onFindAll?() }
    }

    func setResults(_ rows: [(Int, String)], hasMore: Bool) {
        guard preview == nil else { return }
        resultRows = rows.map { ($0.0, $0.1) }
        selectAll.isHidden = true; selectNone.isHidden = true
        resultsTable.reloadData()
        resultSummary.isHidden = !resultsVisible
        resultsScroll.isHidden = !resultsVisible
        resultSummary.stringValue = rows.isEmpty ? L("search.none") : (hasMore ? L("search.resultsCapped", rows.count) : L("search.found", String(rows.count)))
        resultsTable.toolTip = hasMore ? L("search.resultsCapped", rows.count) : nil
    }

    private var resultsVisible = false

    /// 出す文言（UI から切り離してテストできるようにしてある）。
    static func countText(query: String, current: Int, total: Int, searching: Bool,
                          progress: Int, invalid: Bool, capped: Bool) -> String {
        let fmt = { (n: Int) in NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal) }
        if query.isEmpty { return "" }
        if invalid { return L("search.invalid") }
        if total == 0 {
            return searching ? L("search.searching", progress) : L("search.none")
        }
        // 走査中は「何件目か」を出さない。**バーの幅が足りず、末尾から切れる**
        // （「1,365,193 件中 2 件目（検索中 0%」のように閉じ括弧ごと消えた）。
        // 走っている最中に知りたいのは「いくつ見つかったか」と「あとどれくらいか」で、
        // 何件目かは動かしてから読めばよい。
        if searching {
            let found = capped ? L("search.foundCapped", fmt(total)) : L("search.found", fmt(total))
            return L("search.stillSearching", found, progress)
        }
        if current == 0 {
            return capped ? L("search.foundCapped", fmt(total)) : L("search.found", fmt(total))
        }
        return capped ? L("search.countCapped", fmt(current), fmt(total))
                      : L("search.count", fmt(current), fmt(total))
    }

    // MARK: - イベント

    private func invalidatePreview() {
        if preview != nil { collapseResults() }
        preview = nil; undoPreviewButton.isEnabled = false; applyPreviewButton.isHidden = true
        selectAll.isHidden = true; selectNone.isHidden = true
    }
    func controlTextDidChange(_ obj: Notification) {
        invalidatePreview()
        resultsTable.reloadData()
        onQueryChange?(field.stringValue)
    }

    @objc private func enterPressed() {
        // 「最近の検索」メニューから選んだときは stringValue だけが変わり、
        // controlTextDidChange（＝onQueryChange）は飛んでこない。ここで明示的に
        // 同期しないと、表示中の語と実際に検索窓が持っている語がズレる
        // （検索欄には選んだ語が出ているのに、ヒットは前の語のまま、という壊れ方をした）。
        onQueryChange?(field.stringValue)
        rememberRecentSearch()
        // Shift+Enter で前へ。
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { onPrev?() } else { onNext?() }
    }

    /// 確定した検索語を履歴の先頭へ積む（新しい順・重複なし・`maximumRecents` で頭打ち）。
    /// `recentSearches` へ代入すると、`recentsAutosaveName` 経由でユーザ既定への保存と
    /// 「最近の検索」メニューの更新は AppKit 側が面倒を見る。
    private func rememberRecentSearch() {
        let term = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        var recents = field.recentSearches.filter { $0 != term }
        recents.insert(term, at: 0)
        field.recentSearches = Array(recents.prefix(field.maximumRecents))
    }
    @objc private func nextTapped() { onNext?() }
    @objc private func prevTapped() { onPrev?() }
    @objc private func closeTapped() { onClose?() }
    @objc private func caseTapped() { invalidatePreview(); onCaseToggle?(caseToggle.state == .on) }
    @objc private func regexTapped() { invalidatePreview(); onRegexToggle?(regexToggle.state == .on) }
    @objc private func filterTapped() {
        syncContextEnabled()
        onFilterToggle?(filterToggle.state == .on)
    }
    @objc private func contextEdited() {
        let n = min(max(0, Int(contextField.stringValue) ?? 0), FilterContext.maxContext)
        contextField.stringValue = n > 0 ? String(n) : ""   // 入力を丸めた結果を見せる
        onContextChange?(n)
    }
    @objc private func preserveCaseTapped() { invalidatePreview(); onPreserveCaseToggle?(preserveCaseToggle.state == .on) }
    @objc private func replaceTapped() { onReplace?(replaceField.stringValue) }
    @objc private func replaceAllTapped() { onReplaceAll?(replaceField.stringValue) }
    @objc private func toggleReplaceRow() {
        if modeSelector.selectedSegment == 0 { collapseResults() }
        replaceRowView?.isHidden = modeSelector.selectedSegment == 0
        onHeightChange?(headerHeight)
    }
    @objc private func findAllTapped() {
        preview = nil; undoPreviewButton.isEnabled = false; applyPreviewButton.isHidden = true
        resultsVisible = true; resultsArea.isHidden = false
        resultSummary.isHidden = false; resultsScroll.isHidden = false
        onResultsHeightChange?(240)
        onFindAll?()
    }
    @objc private func resultDoubleClicked() {
        if let preview {
            let row = resultsTable.clickedRow
            if previewGroups.indices.contains(row) {
                let detail = preview.details[previewGroups[row][0]]
                if let onSelectPreviewDetail { onSelectPreviewDetail(detail) } else { onSelectResult?(detail.line) }
            }
            return
        }
        let row = resultsTable.clickedRow
        guard row >= 0, row < resultRows.count else { return }
        if let onSelectResultIndex { onSelectResultIndex(row) } else { onSelectResult?(resultRows[row].line + 1) }
    }

    /// バーを閉じる時に状態をリセット。
    func clear() {
        field.stringValue = ""
        replaceField.stringValue = ""
        caseToggle.state = .off
        regexToggle.state = .off
        filterToggle.state = .off
        preserveCaseToggle.state = .off
        countLabel.stringValue = ""
        collapseResults(); preview = nil; undoPreviewButton.isEnabled = false
        resultSummary.isHidden = true
        onHeightChange?(Self.height)
        resultsScroll.isHidden = true
        resultRows = []
        resultsTable.reloadData()
        // 前後 N 行は消さない（アプリの設定として覚えている値なので、閉じるたびに 0 へ戻さない）。
        syncContextEnabled()
    }

    /// Esc でバーを閉じる。
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            onClose?()
            return true
        }
        return false
    }
}

extension SearchBarView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { preview == nil ? resultRows.count : previewGroups.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if preview != nil { return previewCell(row) }
        guard resultRows.indices.contains(row) else { return nil }
        let item = resultRows[row]
        let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("resultCell"), owner: self) as? NSTableCellView ?? {
            let view = NSTableCellView()
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            view.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
            view.identifier = NSUserInterfaceItemIdentifier("resultCell")
            return view
        }()
        cell.textField?.stringValue = "\(item.line + 1)  ·  \(item.text)"
        return cell
    }
}
