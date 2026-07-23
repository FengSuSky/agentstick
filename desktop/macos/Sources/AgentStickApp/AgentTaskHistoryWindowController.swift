import AppKit
import AgentStickCore
import Foundation

final class AgentTaskHistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    var onClearSessionHistory: (() -> Void)?
    private struct TaskEntry {
        let url: URL
        let date: Date
        let agent: String
        let prompt: String
        let exitCode: Int?
        let markdown: String

        var succeeded: Bool { exitCode == 0 }
    }

    private enum HistoryEntry {
        case approval(AgentApprovalRequest)
        case input(AgentInputRequest)
        case task(TaskEntry)
    }

    private let tableView = NSTableView()
    private let detailTextView = NSTextView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let metadataLabel = NSTextField(labelWithString: "")
    private let openButton = NSButton()
    private let revealButton = NSButton()
    private let allowButton = NSButton()
    private let denyButton = NSButton()
    private let answerButton = NSButton()
    private let cancelInputButton = NSButton()
    private let deleteButton = NSButton()
    private let approvalCenter: AgentApprovalCenter
    private var entries: [HistoryEntry] = []

    init(approvalCenter: AgentApprovalCenter) {
        self.approvalCenter = approvalCenter
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = currentLanguage == .chinese ? "Agent 任务历史" : "Agent Task History"
        window.minSize = NSSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
        approvalCenter.onChange = { [weak self] request in
            guard let self else { return }
            self.reloadEntries(selecting: nil, approvalID: request?.id)
            if request?.state == .pending { self.show(selectingApproval: request?.id) }
        }
        approvalCenter.onInputChange = { [weak self] request in
            guard let self else { return }
            self.reloadEntries(selecting: nil, inputID: request?.id)
            if request?.state == .pending { self.show(selectingInput: request?.id) }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(selecting resultURL: URL? = nil) {
        reloadEntries(selecting: resultURL, approvalID: nil)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func show(selectingApproval approvalID: UUID?) {
        reloadEntries(selecting: nil, approvalID: approvalID)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func show(selectingInput inputID: UUID?) {
        reloadEntries(selecting: nil, inputID: inputID)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(splitView)

        let sidebar = NSView()
        let tableScrollView = NSScrollView()
        tableScrollView.hasVerticalScroller = true
        tableScrollView.drawsBackground = false
        tableScrollView.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(tableScrollView)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("task"))
        column.title = currentLanguage == .chinese ? "任务" : "Tasks"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 58
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableScrollView.documentView = tableView

        NSLayoutConstraint.activate([
            tableScrollView.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            tableScrollView.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            tableScrollView.topAnchor.constraint(equalTo: sidebar.topAnchor),
            tableScrollView.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
            sidebar.widthAnchor.constraint(lessThanOrEqualToConstant: 360)
        ])

        let detail = NSView()
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(titleLabel)

        metadataLabel.font = .systemFont(ofSize: 12)
        metadataLabel.textColor = .secondaryLabelColor
        metadataLabel.lineBreakMode = .byTruncatingMiddle
        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(metadataLabel)

        let detailScrollView = NSScrollView()
        detailScrollView.hasVerticalScroller = true
        detailScrollView.borderType = .noBorder
        detailScrollView.drawsBackground = false
        detailScrollView.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(detailScrollView)

        detailTextView.isEditable = false
        detailTextView.isSelectable = true
        detailTextView.drawsBackground = false
        detailTextView.textContainerInset = NSSize(width: 18, height: 18)
        detailTextView.isRichText = true
        detailTextView.isVerticallyResizable = true
        detailTextView.isHorizontallyResizable = false
        detailTextView.autoresizingMask = [.width]
        detailTextView.minSize = NSSize(width: 0, height: detailScrollView.contentSize.height)
        detailTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        detailTextView.textContainer?.containerSize = NSSize(
            width: detailScrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        detailTextView.textContainer?.widthTracksTextView = true
        detailTextView.usesFindBar = true
        detailTextView.isAutomaticLinkDetectionEnabled = true
        detailScrollView.documentView = detailTextView

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 10
        footer.alignment = .centerY
        footer.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(footer)

        let refreshButton = NSButton(
            title: currentLanguage == .chinese ? "刷新" : "Refresh",
            target: self,
            action: #selector(refresh)
        )
        let clearHistoryButton = NSButton(
            title: currentLanguage == .chinese ? "清空历史" : "Clear History",
            target: self,
            action: #selector(clearHistory)
        )
        openButton.title = currentLanguage == .chinese ? "打开原始文件" : "Open Original"
        openButton.target = self
        openButton.action = #selector(openSelectedTask)
        revealButton.title = currentLanguage == .chinese ? "在 Finder 中显示" : "Show in Finder"
        revealButton.target = self
        revealButton.action = #selector(revealSelectedTask)
        allowButton.title = currentLanguage == .chinese ? "允许" : "Allow"
        allowButton.bezelStyle = .rounded
        allowButton.keyEquivalent = "\r"
        allowButton.target = self
        allowButton.action = #selector(allowSelectedRequest)
        denyButton.title = currentLanguage == .chinese ? "拒绝" : "Deny"
        denyButton.bezelStyle = .rounded
        denyButton.target = self
        denyButton.action = #selector(denySelectedRequest)
        answerButton.title = currentLanguage == .chinese ? "回答…" : "Answer…"
        answerButton.bezelStyle = .rounded
        answerButton.keyEquivalent = "\r"
        answerButton.target = self
        answerButton.action = #selector(answerSelectedInput)
        cancelInputButton.title = currentLanguage == .chinese ? "取消请求" : "Cancel Request"
        cancelInputButton.bezelStyle = .rounded
        cancelInputButton.target = self
        cancelInputButton.action = #selector(cancelSelectedInput)
        deleteButton.title = currentLanguage == .chinese ? "删除记录" : "Delete"
        deleteButton.bezelStyle = .rounded
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelectedEntry)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(refreshButton)
        footer.addArrangedSubview(clearHistoryButton)
        footer.addArrangedSubview(spacer)
        footer.addArrangedSubview(deleteButton)
        footer.addArrangedSubview(denyButton)
        footer.addArrangedSubview(allowButton)
        footer.addArrangedSubview(cancelInputButton)
        footer.addArrangedSubview(answerButton)
        footer.addArrangedSubview(revealButton)
        footer.addArrangedSubview(openButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -24),
            titleLabel.topAnchor.constraint(equalTo: detail.topAnchor, constant: 22),
            metadataLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metadataLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            metadataLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            detailScrollView.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            detailScrollView.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            detailScrollView.topAnchor.constraint(equalTo: metadataLabel.bottomAnchor, constant: 12),
            detailScrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -10),
            footer.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: 18),
            footer.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -18),
            footer.bottomAnchor.constraint(equalTo: detail.bottomAnchor, constant: -14)
        ])

        splitView.addArrangedSubview(sidebar)
        splitView.addArrangedSubview(detail)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: contentView.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func reloadEntries(selecting resultURL: URL?, approvalID: UUID? = nil, inputID: UUID? = nil) {
        let directory = AppConfig.configDirectory.appendingPathComponent("Tasks", isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let taskEntries = urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap(loadEntry)
            .sorted { $0.date > $1.date }
        let interactions: [HistoryEntry] = (
            approvalCenter.requests.map(HistoryEntry.approval) +
            approvalCenter.inputRequests.map(HistoryEntry.input)
        ).sorted { interactionDate($0) > interactionDate($1) }
        entries = interactions + taskEntries.map(HistoryEntry.task)
        tableView.reloadData()

        let targetPath = resultURL?.standardizedFileURL.path
        let selectedIndex = inputID.flatMap { id in
            entries.firstIndex { if case .input(let value) = $0 { return value.id == id }; return false }
        } ?? approvalID.flatMap { id in
            entries.firstIndex { if case .approval(let value) = $0 { return value.id == id }; return false }
        } ?? targetPath.flatMap { path in
            entries.firstIndex { if case .task(let value) = $0 { return value.url.standardizedFileURL.path == path }; return false }
        } ?? (entries.isEmpty ? nil : 0)
        if let selectedIndex {
            tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
            tableView.scrollRowToVisible(selectedIndex)
            display(entries[selectedIndex])
        } else {
            displayEmptyState()
        }
    }

    private func interactionDate(_ entry: HistoryEntry) -> Date {
        switch entry {
        case .approval(let request): return request.createdAt
        case .input(let request): return request.createdAt
        case .task(let task): return task.date
        }
    }

    private func loadEntry(_ url: URL) -> TaskEntry? {
        guard let markdown = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        let agent = value(after: "Agent:", in: markdown) ?? "Agent"
        let exitCode = value(after: "Exit code:", in: markdown).flatMap(Int.init)
        let promptSection = section(named: "Prompt", in: markdown)
        let rawPrompt = promptSection
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? url.deletingPathExtension().lastPathComponent
        let prompt = AgentDisplayTitle.from(
            rawPrompt,
            fallback: url.deletingPathExtension().lastPathComponent
        )
        return TaskEntry(
            url: url,
            date: values?.contentModificationDate ?? .distantPast,
            agent: agent,
            prompt: prompt,
            exitCode: exitCode,
            markdown: markdown
        )
    }

    private func value(after prefix: String, in text: String) -> String? {
        text.components(separatedBy: .newlines).first { $0.hasPrefix(prefix) }.map {
            String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func section(named name: String, in text: String) -> String {
        let marker = "## \(name)"
        guard let start = text.range(of: marker) else { return "" }
        let remainder = text[start.upperBound...]
        let end = remainder.range(of: "\n## ")?.lowerBound ?? remainder.endIndex
        return String(remainder[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func display(_ historyEntry: HistoryEntry) {
        if case .approval(let request) = historyEntry {
            display(request)
            return
        }
        if case .input(let request) = historyEntry {
            display(request)
            return
        }
        guard case .task(let entry) = historyEntry else { return }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let status = entry.succeeded
            ? (currentLanguage == .chinese ? "完成" : "Completed")
            : (currentLanguage == .chinese ? "失败" : "Failed")
        titleLabel.stringValue = entry.prompt
        metadataLabel.stringValue = "\(entry.agent.capitalized) · \(status) · \(formatter.string(from: entry.date)) · \(entry.url.path)"
        detailTextView.textStorage?.setAttributedString(MarkdownTextRenderer.render(entry.markdown))
        detailTextView.scrollToBeginningOfDocument(nil)
        openButton.isEnabled = true
        revealButton.isEnabled = true
        openButton.isHidden = false
        revealButton.isHidden = false
        allowButton.isHidden = true
        denyButton.isHidden = true
        answerButton.isHidden = true
        cancelInputButton.isHidden = true
        deleteButton.isHidden = false
        deleteButton.isEnabled = true
    }

    private func display(_ request: AgentApprovalRequest) {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let status: String
        switch request.state {
        case .pending: status = currentLanguage == .chinese ? "等待授权" : "Waiting for approval"
        case .continuing: status = currentLanguage == .chinese ? "已允许 · 继续执行中" : "Allowed · Continuing"
        case .allowed: status = currentLanguage == .chinese ? "已允许" : "Allowed"
        case .denied: status = currentLanguage == .chinese ? "已拒绝" : "Denied"
        }
        titleLabel.stringValue = request.summary
        metadataLabel.stringValue = "\(request.agent) · \(request.kind) · \(status) · \(formatter.string(from: request.createdAt))"
        detailTextView.textStorage?.setAttributedString(MarkdownTextRenderer.render(request.details))
        detailTextView.scrollToBeginningOfDocument(nil)
        let pending = request.state == .pending
        allowButton.isHidden = false
        denyButton.isHidden = false
        allowButton.isEnabled = pending
        denyButton.isEnabled = pending
        openButton.isHidden = true
        revealButton.isHidden = true
        answerButton.isHidden = true
        cancelInputButton.isHidden = true
        deleteButton.isHidden = false
        deleteButton.isEnabled = request.state != .pending
    }

    private func display(_ request: AgentInputRequest) {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let status: String
        switch request.state {
        case .pending: status = currentLanguage == .chinese ? "等待回答" : "Waiting for input"
        case .submitted: status = currentLanguage == .chinese ? "已回答" : "Answered"
        case .cancelled: status = currentLanguage == .chinese ? "已取消" : "Cancelled"
        }
        titleLabel.stringValue = request.summary
        metadataLabel.stringValue = "\(request.agent) · \(status) · \(formatter.string(from: request.createdAt))"
        detailTextView.textStorage?.setAttributedString(MarkdownTextRenderer.render(request.details))
        detailTextView.scrollToBeginningOfDocument(nil)
        let pending = request.state == .pending
        answerButton.isHidden = false
        cancelInputButton.isHidden = false
        answerButton.isEnabled = pending
        cancelInputButton.isEnabled = pending
        allowButton.isHidden = true
        denyButton.isHidden = true
        openButton.isHidden = true
        revealButton.isHidden = true
        deleteButton.isHidden = false
        deleteButton.isEnabled = request.state != .pending
    }

    private func displayEmptyState() {
        titleLabel.stringValue = currentLanguage == .chinese ? "暂无任务记录" : "No task history"
        metadataLabel.stringValue = ""
        detailTextView.string = currentLanguage == .chinese
            ? "完成一次 Agent Run 后，任务和结果会显示在这里。"
            : "Completed Agent Run tasks and results will appear here."
        openButton.isEnabled = false
        revealButton.isEnabled = false
        allowButton.isHidden = true
        denyButton.isHidden = true
        answerButton.isHidden = true
        cancelInputButton.isHidden = true
        deleteButton.isHidden = true
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("TaskHistoryCell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? {
            let value = NSTableCellView()
            value.identifier = identifier
            let label = NSTextField(wrappingLabelWithString: "")
            label.maximumNumberOfLines = 2
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            value.textField = label
            value.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: value.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(equalTo: value.trailingAnchor, constant: -10),
                label.centerYAnchor.constraint(equalTo: value.centerYAnchor)
            ])
            return value
        }()
        switch entries[row] {
        case .task(let entry):
            let symbol = entry.succeeded ? "✓" : "!"
            cell.textField?.stringValue = "\(symbol) \(entry.agent.capitalized)\n\(entry.prompt)"
        case .approval(let request):
            let symbol: String
            switch request.state { case .pending: symbol = "●"; case .continuing: symbol = "↻"; case .allowed: symbol = "✓"; case .denied: symbol = "×" }
            cell.textField?.stringValue = "\(symbol) \(request.agent) · \(request.kind)\n\(request.summary)"
        case .input(let request):
            let symbol: String
            switch request.state { case .pending: symbol = "?"; case .submitted: symbol = "✓"; case .cancelled: symbol = "×" }
            cell.textField?.stringValue = "\(symbol) \(request.agent) · \(currentLanguage == .chinese ? "需要回答" : "Input needed")\n\(request.summary)"
        }
        cell.textField?.textColor = .labelColor
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard entries.indices.contains(row) else { return }
        display(entries[row])
    }

    @objc private func refresh() {
        let selectedURL: URL? = entries.indices.contains(tableView.selectedRow) ? {
            if case .task(let entry) = entries[tableView.selectedRow] { return entry.url }
            return nil
        }() : nil
        reloadEntries(selecting: selectedURL)
    }

    @objc private func openSelectedTask() {
        guard entries.indices.contains(tableView.selectedRow), case .task(let entry) = entries[tableView.selectedRow] else { return }
        NSWorkspace.shared.open(entry.url)
    }

    @objc private func revealSelectedTask() {
        guard entries.indices.contains(tableView.selectedRow), case .task(let entry) = entries[tableView.selectedRow] else { return }
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    @objc private func allowSelectedRequest() { resolveSelectedRequest(allowed: true) }
    @objc private func denySelectedRequest() { resolveSelectedRequest(allowed: false) }

    private func resolveSelectedRequest(allowed: Bool) {
        guard entries.indices.contains(tableView.selectedRow), case .approval(let request) = entries[tableView.selectedRow] else { return }
        approvalCenter.resolve(request, allowed: allowed)
        display(request)
        tableView.reloadData(forRowIndexes: IndexSet(integer: tableView.selectedRow), columnIndexes: IndexSet(integer: 0))
    }

    @objc private func deleteSelectedEntry() {
        guard entries.indices.contains(tableView.selectedRow) else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = currentLanguage == .chinese ? "删除这条记录？" : "Delete this record?"
        alert.informativeText = currentLanguage == .chinese
            ? "任务文件会移到废纸篓；已处理的交互记录会从列表移除。"
            : "Task files move to Trash; completed interaction records are removed from the list."
        alert.addButton(withTitle: currentLanguage == .chinese ? "删除" : "Delete")
        alert.addButton(withTitle: currentLanguage == .chinese ? "取消" : "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        switch entries[tableView.selectedRow] {
        case .task(let task):
            NSWorkspace.shared.recycle([task.url]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.reloadEntries(selecting: nil) }
            }
        case .approval(let request):
            approvalCenter.remove(request)
        case .input(let request):
            approvalCenter.remove(request)
        }
    }

    @objc private func clearHistory() {
        let pendingCount = approvalCenter.requests.filter { $0.state == .pending }.count +
            approvalCenter.inputRequests.filter { $0.state == .pending }.count
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = currentLanguage == .chinese ? "清空 Agent 历史？" : "Clear Agent history?"
        alert.informativeText = currentLanguage == .chinese
            ? "所有任务文件将移到废纸篓，已处理的交互记录会被清除。\(pendingCount > 0 ? " 正在等待的 \(pendingCount) 个请求会保留。" : "")"
            : "All task files move to Trash and resolved interactions are cleared.\(pendingCount > 0 ? " \(pendingCount) pending request(s) will be kept." : "")"
        alert.addButton(withTitle: currentLanguage == .chinese ? "清空" : "Clear")
        alert.addButton(withTitle: currentLanguage == .chinese ? "取消" : "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let directory = AppConfig.configDirectory.appendingPathComponent("Tasks", isDirectory: true)
        let taskURLs = ((try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []).filter { $0.pathExtension.lowercased() == "md" }
        approvalCenter.removeResolvedInteractions()
        onClearSessionHistory?()
        guard !taskURLs.isEmpty else {
            reloadEntries(selecting: nil)
            return
        }
        NSWorkspace.shared.recycle(taskURLs) { [weak self] _, _ in
            DispatchQueue.main.async { self?.reloadEntries(selecting: nil) }
        }
    }

    @objc private func cancelSelectedInput() {
        guard entries.indices.contains(tableView.selectedRow), case .input(let request) = entries[tableView.selectedRow] else { return }
        approvalCenter.resolve(request, answers: nil)
        display(request)
        tableView.reloadData(forRowIndexes: IndexSet(integer: tableView.selectedRow), columnIndexes: IndexSet(integer: 0))
    }

    @objc private func answerSelectedInput() {
        guard entries.indices.contains(tableView.selectedRow), case .input(let request) = entries[tableView.selectedRow], request.state == .pending else { return }
        let form = NSStackView()
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 10
        form.translatesAutoresizingMaskIntoConstraints = false
        form.widthAnchor.constraint(equalToConstant: 460).isActive = true
        var controls: [(AgentInputQuestion, NSControl)] = []
        var firstTextControl: NSTextField?
        for question in request.questions {
            let label = NSTextField(wrappingLabelWithString: question.question)
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.maximumNumberOfLines = 2
            label.lineBreakMode = .byTruncatingTail
            label.widthAnchor.constraint(equalToConstant: 460).isActive = true
            form.addArrangedSubview(label)
            let control: NSControl
            if !question.options.isEmpty && question.allowsFreeText {
                let combo = NSComboBox()
                combo.addItems(withObjectValues: question.options)
                combo.placeholderString = currentLanguage == .chinese ? "选择或输入回答" : "Choose or type an answer"
                control = combo
            } else if !question.options.isEmpty {
                let popup = NSPopUpButton()
                popup.addItems(withTitles: question.options)
                control = popup
            } else if question.isSecret {
                let field = NSSecureTextField()
                field.placeholderString = currentLanguage == .chinese ? "输入回答" : "Type your answer"
                control = field
                firstTextControl = firstTextControl ?? field
            } else {
                let field = NSTextField()
                field.placeholderString = currentLanguage == .chinese ? "输入回答，也可使用 AgentStick 语音回答" : "Type an answer, or answer by voice with AgentStick"
                field.isEditable = true
                field.isSelectable = true
                control = field
                firstTextControl = firstTextControl ?? field
            }
            control.widthAnchor.constraint(equalToConstant: 460).isActive = true
            if control is NSTextField {
                control.heightAnchor.constraint(equalToConstant: 28).isActive = true
            }
            form.addArrangedSubview(control)
            controls.append((question, control))
        }
        let alert = NSAlert()
        alert.messageText = request.summary
        alert.informativeText = currentLanguage == .chinese ? "回答后 Agent 将继续当前任务。" : "The agent will continue the current task after you answer."
        alert.accessoryView = form
        alert.addButton(withTitle: currentLanguage == .chinese ? "提交回答" : "Submit")
        let supportsVoiceAnswer =
            request.questions.count == 1 &&
            request.questions[0].options.isEmpty &&
            request.questions[0].allowsFreeText &&
            !request.questions[0].isSecret
        if supportsVoiceAnswer {
            alert.addButton(withTitle: currentLanguage == .chinese ? "使用语音回答" : "Answer by Voice")
        }
        alert.addButton(withTitle: currentLanguage == .chinese ? "关闭" : "Close")
        if let firstTextControl {
            alert.window.initialFirstResponder = firstTextControl
        }
        let response = alert.runModal()
        if supportsVoiceAnswer, response == .alertSecondButtonReturn {
            return
        }
        guard response == .alertFirstButtonReturn else { return }
        var answers: [String: [String]] = [:]
        for (question, control) in controls {
            let value: String
            if let popup = control as? NSPopUpButton {
                value = popup.titleOfSelectedItem ?? ""
            } else {
                value = control.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            answers[question.id] = value.isEmpty ? [] : [value]
        }
        approvalCenter.resolve(request, answers: answers)
        display(request)
        tableView.reloadData(forRowIndexes: IndexSet(integer: tableView.selectedRow), columnIndexes: IndexSet(integer: 0))
    }
}

private enum MarkdownTextRenderer {
    private static let inlineIntentKey = NSAttributedString.Key("NSInlinePresentationIntent")

    static func render(_ markdown: String) -> NSAttributedString {
        let output = NSMutableAttributedString()
        var inCodeBlock = false

        for sourceLine in markdown.components(separatedBy: .newlines) {
            if sourceLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }
            if inCodeBlock {
                appendCodeLine(sourceLine, to: output)
                continue
            }

            let trimmed = sourceLine.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "***" {
                appendLine("────────────────────────", font: .systemFont(ofSize: 12), color: .separatorColor, spacing: 12, to: output)
                continue
            }

            if let heading = heading(from: sourceLine) {
                let size: CGFloat = heading.level == 1 ? 25 : (heading.level == 2 ? 20 : 16)
                appendInlineLine(
                    heading.text,
                    prefix: "",
                    font: .systemFont(ofSize: size, weight: .bold),
                    spacing: heading.level == 1 ? 14 : 10,
                    to: output
                )
            } else if let item = unorderedListItem(from: sourceLine) {
                appendInlineLine(item, prefix: "•  ", font: .systemFont(ofSize: 15), spacing: 5, indent: 18, to: output)
            } else if let item = orderedListItem(from: sourceLine) {
                appendInlineLine(item.text, prefix: "\(item.ordinal).  ", font: .systemFont(ofSize: 15), spacing: 5, indent: 22, to: output)
            } else if trimmed.hasPrefix(">") {
                let text = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                appendInlineLine(text, prefix: "│  ", font: .systemFont(ofSize: 15), color: .secondaryLabelColor, spacing: 8, indent: 12, to: output)
            } else if trimmed.isEmpty {
                output.append(NSAttributedString(string: "\n"))
            } else {
                appendInlineLine(sourceLine, prefix: "", font: .systemFont(ofSize: 15), spacing: 7, to: output)
            }
        }
        return output
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let count = trimmed.prefix { $0 == "#" }.count
        guard count > 0, count <= 6, trimmed.dropFirst(count).first == " " else { return nil }
        return (count, String(trimmed.dropFirst(count + 1)))
    }

    private static func unorderedListItem(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for prefix in ["- ", "* ", "+ "] where trimmed.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count))
        }
        return nil
    }

    private static func orderedListItem(from line: String) -> (ordinal: String, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dot = trimmed.firstIndex(of: ".") else { return nil }
        let ordinal = String(trimmed[..<dot])
        guard !ordinal.isEmpty, ordinal.allSatisfy(\.isNumber) else { return nil }
        let afterDot = trimmed.index(after: dot)
        guard afterDot < trimmed.endIndex, trimmed[afterDot] == " " else { return nil }
        return (ordinal, String(trimmed[trimmed.index(after: afterDot)...]))
    }

    private static func appendInlineLine(
        _ text: String,
        prefix: String,
        font: NSFont,
        color: NSColor = .labelColor,
        spacing: CGFloat,
        indent: CGFloat = 0,
        to output: NSMutableAttributedString
    ) {
        let line = NSMutableAttributedString(string: prefix, attributes: [.font: font, .foregroundColor: color])
        let parsed: NSMutableAttributedString
        if let value = try? NSAttributedString(
            markdown: Data(text.utf8),
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace),
            baseURL: nil
        ) {
            parsed = NSMutableAttributedString(attributedString: value)
        } else {
            parsed = NSMutableAttributedString(string: text)
        }
        let fullRange = NSRange(location: 0, length: parsed.length)
        parsed.addAttributes([.font: font, .foregroundColor: color], range: fullRange)
        parsed.enumerateAttribute(inlineIntentKey, in: fullRange) { value, range, _ in
            guard let number = value as? NSNumber else { return }
            let intent = InlinePresentationIntent(rawValue: number.uintValue)
            var runFont = font
            if intent.contains(.code) {
                runFont = .monospacedSystemFont(ofSize: max(12, font.pointSize - 1), weight: .regular)
                parsed.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: range)
            }
            if intent.contains(.stronglyEmphasized) {
                runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .boldFontMask)
            }
            if intent.contains(.emphasized) {
                runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .italicFontMask)
            }
            parsed.addAttribute(.font, value: runFont, range: range)
            if intent.contains(.strikethrough) {
                parsed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        }
        line.append(parsed)
        line.append(NSAttributedString(string: "\n"))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = spacing
        paragraph.firstLineHeadIndent = indent > 0 ? 0 : indent
        paragraph.headIndent = indent
        line.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: line.length))
        output.append(line)
    }

    private static func appendCodeLine(_ text: String, to output: NSMutableAttributedString) {
        let line = NSMutableAttributedString(string: "  \(text)\n")
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        line.addAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: NSColor.quaternaryLabelColor,
            .paragraphStyle: paragraph
        ], range: NSRange(location: 0, length: line.length))
        output.append(line)
    }

    private static func appendLine(
        _ text: String,
        font: NSFont,
        color: NSColor,
        spacing: CGFloat,
        to output: NSMutableAttributedString
    ) {
        appendInlineLine(text, prefix: "", font: font, color: color, spacing: spacing, to: output)
    }
}
