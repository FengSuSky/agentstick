import AppKit

final class SettingsWindowController: NSWindowController {
    private let providerPopup = NSPopUpButton()
    private let apiKeyField = NSTextField()
    private let volcengineAppKeyField = NSTextField()
    private let applyTrialAPIKeyButton = NSButton(title: L10n.applyTrial, target: nil, action: nil)
    private let resourcePopup = NSPopUpButton()
    private let hotwordsTextView = NSTextView()
    private let hotwordsScrollView = NSScrollView()
    private let llmBaseURLField = NSTextField()
    private let llmAPIKeyField = NSTextField()
    private let llmModelField = NSTextField()
    private let debugAudioButton = NSButton(checkboxWithTitle: L10n.saveDebugAudioFiles, target: nil, action: nil)
    private let debugAudioDirectoryField = NSTextField()
    private let languagePopup = NSPopUpButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private var currentDisplayedProvider: ASRProvider = .volcengine
    private var resourceRow: NSStackView?
    var onConfigChanged: ((AppConfig) -> Void)?

    private var config: AppConfig

    init(config: AppConfig = AppConfig.load()) {
        self.config = config
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.agentStickSettings
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
        loadConfigIntoFields()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(apiKeyFieldDidChange),
            name: NSControl.textDidChangeNotification,
            object: apiKeyField
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show() {
        config = AppConfig.load()
        loadConfigIntoFields()
        showWindow(nil)
        window?.makeFirstResponder(providerPopup)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        stack.addArrangedSubview(sectionTitle("ASR"))
        configureProviderPopup()
        stack.addArrangedSubview(row(label: L10n.provider, control: providerPopup))
        configureApplyTrialAPIKeyButton()
        stack.addArrangedSubview(row(label: L10n.apiKey, control: apiKeyControl()))
        stack.addArrangedSubview(row(label: L10n.appKey, control: volcengineAppKeyField))
        configureResourcePopup()
        let resourceRow = row(label: L10n.resourceID, control: resourcePopup)
        self.resourceRow = resourceRow
        stack.addArrangedSubview(resourceRow)
        configureHotwordsTextView()
        stack.addArrangedSubview(row(label: L10n.hotwords, control: hotwordsScrollView))
        stack.addArrangedSubview(hintRow(L10n.hotwordsHint))

        stack.addArrangedSubview(sectionTitle("LLM"))
        stack.addArrangedSubview(row(label: L10n.baseURL, control: llmBaseURLField))
        stack.addArrangedSubview(row(label: L10n.apiKey, control: llmAPIKeyField))
        stack.addArrangedSubview(row(label: L10n.model, control: llmModelField))

        stack.addArrangedSubview(sectionTitle(L10n.language))
        configureLanguagePopup()
        stack.addArrangedSubview(row(label: L10n.language, control: languagePopup))

        stack.addArrangedSubview(sectionTitle(currentLanguage == .chinese ? "调试" : "Debug"))
        stack.addArrangedSubview(row(label: L10n.audioCache, control: debugAudioButton))
        let debugDirRow = NSStackView()
        debugDirRow.orientation = .horizontal
        debugDirRow.alignment = .centerY
        debugDirRow.spacing = 8
        debugAudioDirectoryField.isEditable = false
        debugAudioDirectoryField.lineBreakMode = .byTruncatingMiddle
        let chooseButton = NSButton(title: L10n.choose, target: self, action: #selector(chooseDebugDirectory))
        debugDirRow.addArrangedSubview(debugAudioDirectoryField)
        debugDirRow.addArrangedSubview(chooseButton)
        debugAudioDirectoryField.widthAnchor.constraint(equalToConstant: 260).isActive = true
        stack.addArrangedSubview(row(label: L10n.audioFolder, control: debugDirRow))

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 10
        let openFolderButton = NSButton(title: L10n.openConfigFolder, target: self, action: #selector(openConfigFolder))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let saveButton = NSButton(title: L10n.save, target: self, action: #selector(saveSettings))
        saveButton.keyEquivalent = "\r"
        buttonRow.addArrangedSubview(openFolderButton)
        buttonRow.addArrangedSubview(statusLabel)
        buttonRow.addArrangedSubview(spacer)
        buttonRow.addArrangedSubview(saveButton)
        stack.addArrangedSubview(buttonRow)
        buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        statusLabel.textColor = .secondaryLabelColor

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])
    }

    private func configureResourcePopup() {
        resourcePopup.addItems(withTitles: AppConfig.supportedResourceIDs)
    }

    private func configureProviderPopup() {
        providerPopup.addItems(withTitles: [
            ASRProvider.agentStickCloud.displayName,
            ASRProvider.volcengine.displayName
        ])
        providerPopup.target = self
        providerPopup.action = #selector(providerSelectionChanged)
    }

    private func configureApplyTrialAPIKeyButton() {
        applyTrialAPIKeyButton.target = self
        applyTrialAPIKeyButton.action = #selector(applyTrialAPIKey)
    }

    private func apiKeyControl() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        apiKeyField.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
        applyTrialAPIKeyButton.widthAnchor.constraint(equalToConstant: 102).isActive = true
        stack.addArrangedSubview(apiKeyField)
        stack.addArrangedSubview(applyTrialAPIKeyButton)
        return stack
    }

    private func configureHotwordsTextView() {
        hotwordsScrollView.hasVerticalScroller = true
        hotwordsScrollView.borderType = .bezelBorder
        hotwordsScrollView.heightAnchor.constraint(equalToConstant: 78).isActive = true
        hotwordsScrollView.translatesAutoresizingMaskIntoConstraints = false

        hotwordsTextView.isRichText = false
        hotwordsTextView.isEditable = true
        hotwordsTextView.isSelectable = true
        hotwordsTextView.font = .systemFont(ofSize: 13)
        hotwordsTextView.textColor = .textColor
        hotwordsTextView.backgroundColor = .textBackgroundColor
        hotwordsTextView.drawsBackground = true
        hotwordsTextView.textContainerInset = NSSize(width: 4, height: 4)
        hotwordsTextView.minSize = NSSize(width: 0, height: hotwordsScrollView.contentSize.height)
        hotwordsTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        hotwordsTextView.isVerticallyResizable = true
        hotwordsTextView.isHorizontallyResizable = false
        hotwordsTextView.autoresizingMask = [.width]
        hotwordsTextView.frame = NSRect(origin: .zero, size: NSSize(width: 300, height: 78))
        hotwordsTextView.textContainer?.containerSize = NSSize(
            width: hotwordsTextView.frame.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        hotwordsTextView.textContainer?.widthTracksTextView = true
        hotwordsScrollView.documentView = hotwordsTextView
    }
    private func configureLanguagePopup() {
        languagePopup.removeAllItems()
        for lang in AppLanguage.allCases {
            languagePopup.addItem(withTitle: lang.displayName)
            languagePopup.lastItem?.representedObject = lang.rawValue
        }
    }


    private func loadConfigIntoFields() {
        currentDisplayedProvider = config.asrProvider
        providerPopup.selectItem(withTitle: config.asrProvider.displayName)
        apiKeyField.stringValue = apiKey(for: config.asrProvider)
        volcengineAppKeyField.stringValue = config.volcengineAppKey
        hotwordsTextView.string = config.asrHotwords.joined(separator: ",")
        llmBaseURLField.stringValue = config.llmBaseURL
        llmAPIKeyField.stringValue = config.llmAPIKey
        llmModelField.stringValue = config.llmModel
        languagePopup.selectItem(withTitle: config.appLanguage.displayName)
        debugAudioButton.state = config.debugAudioCache ? .on : .off
        debugAudioDirectoryField.stringValue = config.debugAudioDirectory.path

        if resourcePopup.itemTitles.contains(config.resourceID) {
            resourcePopup.selectItem(withTitle: config.resourceID)
        }
        updateProviderRows()
        updateApplyTrialButton()
        statusLabel.stringValue = ""
    }

    @objc private func providerSelectionChanged() {
        saveDisplayedAPIKey()
        currentDisplayedProvider = selectedProvider()
        config.asrProvider = currentDisplayedProvider
        apiKeyField.stringValue = apiKey(for: currentDisplayedProvider)
        updateProviderRows()
        updateApplyTrialButton()
    }

    @objc private func apiKeyFieldDidChange() {
        updateApplyTrialButton()
    }

    @objc private func applyTrialAPIKey() {
        saveDisplayedAPIKey()
        guard currentDisplayedProvider == .agentStickCloud else { return }

        applyTrialAPIKeyButton.isEnabled = false
        statusLabel.stringValue = "Applying trial API key..."
        AgentStickCloudAPI.applyTrialAPIKey(
            cloudURL: config.agentStickCloudURL,
            deviceID: config.pairedDeviceIDs.first
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.applyTrialAPIKeyButton.isEnabled = true
                switch result {
                case .success(.apiKey(let apiKey)):
                    self.config.agentStickAPIKey = apiKey
                    self.apiKeyField.stringValue = apiKey
                    self.statusLabel.stringValue = "Trial API key applied."
                    self.updateApplyTrialButton()
                case .success(.url(let url)):
                    self.statusLabel.stringValue = "Opened trial application page."
                    if !NSWorkspace.shared.open(url) {
                        self.showErrorAlert(
                            title: "Could Not Open Trial Page",
                            message: url.absoluteString
                        )
                    }
                case .failure(let error):
                    self.statusLabel.stringValue = ""
                    self.showErrorAlert(
                        title: "Could Not Apply Trial API Key",
                        message: error.localizedDescription
                    )
                    self.updateApplyTrialButton()
                }
            }
        }
    }

    @objc private func chooseDebugDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: debugAudioDirectoryField.stringValue)
        if panel.runModal() == .OK, let url = panel.url {
            debugAudioDirectoryField.stringValue = url.path
        }
    }

    @objc private func saveSettings() {
        saveDisplayedAPIKey()
        let provider = selectedProvider()
        let resourceID = resourcePopup.titleOfSelectedItem ?? config.resourceID

        config = AppConfig(
            asrProvider: provider,
            agentStickAPIKey: config.agentStickAPIKey,
            agentStickCloudURL: config.agentStickCloudURL,
            volcengineAPIKey: config.volcengineAPIKey,
            volcengineAppKey: volcengineAppKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            llmBaseURL: llmBaseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            llmAPIKey: llmAPIKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            llmModel: llmModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            interactionMode: config.interactionMode,
            resourceID: resourceID,
            asrHotwords: AppConfig.hotwordList(hotwordsTextView.string),
            pairedDeviceIDs: config.pairedDeviceIDs,
            deviceThemeColors: config.deviceThemeColors,
            deviceOverlayPositions: config.deviceOverlayPositions,
            defaultOutputProfile: config.defaultOutputProfile,
            deviceOutputProfiles: config.deviceOutputProfiles,
            agentConfig: config.agentConfig,
            autoEnter: config.autoEnter,
            agentCaptureEnabled: config.agentCaptureEnabled,
            agentSoundAlertsEnabled: config.agentSoundAlertsEnabled,
            debugAudioCache: debugAudioButton.state == .on,
            debugAudioDirectory: URL(fileURLWithPath: debugAudioDirectoryField.stringValue, isDirectory: true),
            appLanguage: (languagePopup.selectedItem?.representedObject as? String).flatMap { AppLanguage(rawValue: $0) } ?? .system
        )

        do {
            try config.save()
            setAppLanguage(config.appLanguage)
            onConfigChanged?(config)
            statusLabel.stringValue = L10n.saved
            window?.close()
        } catch {
            statusLabel.stringValue = ""
            showErrorAlert(title: L10n.couldNotSaveSettings, message: error.localizedDescription)
        }
    }

    @objc private func openConfigFolder() {
        AppConfig.openConfigDirectory()
    }

    private func selectedProvider() -> ASRProvider {
        switch providerPopup.titleOfSelectedItem {
        case ASRProvider.agentStickCloud.displayName:
            return .agentStickCloud
        case ASRProvider.volcengine.displayName:
            return .volcengine
        default:
            return config.asrProvider
        }
    }

    private func apiKey(for provider: ASRProvider) -> String {
        switch provider {
        case .agentStickCloud:
            return config.agentStickAPIKey
        case .volcengine:
            return config.volcengineAPIKey
        }
    }

    private func saveDisplayedAPIKey() {
        let value = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch currentDisplayedProvider {
        case .agentStickCloud:
            config.agentStickAPIKey = value
        case .volcengine:
            config.volcengineAPIKey = value
        }
    }

    private func updateProviderRows() {
        let isVolcengine = currentDisplayedProvider == .volcengine
        resourceRow?.isHidden = !isVolcengine
        volcengineAppKeyField.superview?.superview?.isHidden = !isVolcengine
        updateApplyTrialButton()
    }

    private func updateApplyTrialButton() {
        let isCloud = currentDisplayedProvider == .agentStickCloud
        let isEmpty = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        applyTrialAPIKeyButton.isHidden = !(isCloud && isEmpty)
    }

    private func showErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func sectionTitle(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func row(label: String, control: NSView) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        let labelView = NSTextField(labelWithString: label)
        labelView.alignment = .right
        labelView.textColor = .secondaryLabelColor
        labelView.widthAnchor.constraint(equalToConstant: 120).isActive = true
        if control is NSTextField || control is NSPopUpButton || control is NSStackView || control is NSScrollView {
            control.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        }
        row.addArrangedSubview(labelView)
        row.addArrangedSubview(control)
        return row
    }

    private func hintRow(_ text: String) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        let spacer = NSView()
        spacer.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 11)
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true

        row.addArrangedSubview(spacer)
        row.addArrangedSubview(label)
        return row
    }
}
