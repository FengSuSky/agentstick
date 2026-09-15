import AppKit

private enum SettingsWindowLayout {
    /// Row layout is: 24pt margin + 120pt label + 12pt spacing + control + 24pt margin.
    static let rowLeading: CGFloat = 132
    static let outerMargin: CGFloat = 24
    static let windowWidth: CGFloat = 640
    static let minWindowWidth: CGFloat = 560
    /// Keeps wrapping hint text from exceeding the window's usable width.
    static var hintMaxWidth: CGFloat {
        windowWidth - (rowLeading + outerMargin * 2)
    }
}

final class SettingsWindowController: NSWindowController {
    private let providerPopup = NSPopUpButton()
    private let apiKeyField = NSSecureTextField()
    private let volcengineAppKeyField = NSSecureTextField()
    private let applyTrialAPIKeyButton = NSButton(title: L10n.applyTrial, target: nil, action: nil)
    private let resourcePopup = NSPopUpButton()
    private let hotwordsTextView = NSTextView()
    private let hotwordsScrollView = NSScrollView()
    private let llmBaseURLField = NSTextField()
    private let llmAPIKeyField = NSSecureTextField()
    private let llmModelField = NSTextField()
    private let agentPopup = NSPopUpButton()
    private let agentWorkingDirectoryField = NSTextField()
    private let agentTimeoutField = NSTextField()
    private let iMessageRecipientField = NSTextField()
    private let workBuddyClientIDField = NSTextField()
    private let workBuddyClientSecretField = NSSecureTextField()
    private let workBuddyRedirectURIField = NSTextField()
    private let workBuddyConnectButton = NSButton(
        title: currentLanguage == .chinese ? "连接 WorkBuddy" : "Connect WorkBuddy",
        target: nil,
        action: nil
    )
    private let workBuddyStatusLabel = NSTextField(labelWithString: "")
    private let workBuddyPasteCodeButton = NSButton(
        title: currentLanguage == .chinese ? "粘贴授权码" : "Paste code",
        target: nil,
        action: nil
    )
    private var workBuddyAuthController: WorkBuddyAuthController?
    private let agentSoundAlertsButton = NSButton(
        checkboxWithTitle: currentLanguage == .chinese ? "任务结束时在设备播放提示音" : "Play task alerts on device",
        target: nil,
        action: nil
    )
    private let agentBypassApprovalsButton = NSButton(
        checkboxWithTitle: currentLanguage == .chinese ? "绕过 Agent 授权（高风险）" : "Bypass Agent approvals (high risk)",
        target: nil,
        action: nil
    )
    private let agentMemoryButton = NSButton(
        checkboxWithTitle: currentLanguage == .chinese ? "记住使用习惯和项目上下文" : "Remember preferences and project context",
        target: nil,
        action: nil
    )
    private let deviceSoundVolumeSlider = NSSlider()
    private let deviceSoundVolumeLabel = NSTextField(labelWithString: "70%")
    private let testDeviceSoundButton = NSButton(
        title: currentLanguage == .chinese ? "测试" : "Test",
        target: nil,
        action: nil
    )
    private let debugAudioButton = NSButton(checkboxWithTitle: L10n.saveDebugAudioFiles, target: nil, action: nil)
    private let debugAudioDirectoryField = NSTextField()
    private let languagePopup = NSPopUpButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private var currentDisplayedProvider: ASRProvider = .volcengine
    private var resourceRow: NSStackView?
    var onConfigChanged: ((AppConfig) -> Void)?
    var onTestDeviceSoundVolume: ((Int) -> Bool)?

    private var config: AppConfig

    init(config: AppConfig = AppConfig.load()) {
        self.config = config
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsWindowLayout.windowWidth, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.agentStickSettings
        window.minSize = NSSize(width: SettingsWindowLayout.minWindowWidth, height: 480)
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

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack

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

        stack.addArrangedSubview(sectionTitle("Agent"))
        stack.addArrangedSubview(row(
            label: currentLanguage == .chinese ? "默认 Agent" : "Default Agent",
            control: agentPopup
        ))
        let agentDirectoryRow = NSStackView()
        agentDirectoryRow.orientation = .horizontal
        agentDirectoryRow.alignment = .centerY
        agentDirectoryRow.spacing = 8
        agentWorkingDirectoryField.isEditable = false
        agentWorkingDirectoryField.lineBreakMode = .byTruncatingMiddle
        let chooseAgentDirectoryButton = NSButton(
            title: L10n.choose,
            target: self,
            action: #selector(chooseAgentWorkingDirectory)
        )
        agentDirectoryRow.addArrangedSubview(agentWorkingDirectoryField)
        agentDirectoryRow.addArrangedSubview(chooseAgentDirectoryButton)
        agentWorkingDirectoryField.widthAnchor.constraint(equalToConstant: 260).isActive = true
        stack.addArrangedSubview(row(
            label: currentLanguage == .chinese ? "工程目录" : "Project Folder",
            control: agentDirectoryRow
        ))
        agentTimeoutField.placeholderString = "600"
        stack.addArrangedSubview(row(
            label: currentLanguage == .chinese ? "超时（秒）" : "Timeout (sec)",
            control: agentTimeoutField
        ))
        iMessageRecipientField.placeholderString = currentLanguage == .chinese ? "邮箱或手机号" : "Email address or phone number"
        stack.addArrangedSubview(row(
            label: currentLanguage == .chinese ? "iMessage 联系人" : "iMessage Contact",
            control: iMessageRecipientField
        ))
        stack.addArrangedSubview(hintRow(
            currentLanguage == .chinese
                ? "选择 iMessage Remote Agent 后，任务会发送给此联系人；对方回复时需保留任务标记。"
                : "When iMessage Remote Agent is selected, tasks go to this contact; replies must retain the task tag."
        ))
        stack.addArrangedSubview(hintRow(
            currentLanguage == .chinese
                ? "会话会按 Agent、工程目录和语义自动延续。说“新会话”可强制新建，说“继续会话”可强制接续。"
                : "Sessions continue automatically by agent, project, and context. Say “new conversation” or “continue conversation” to override."
        ))
        stack.addArrangedSubview(sectionTitle("WorkBuddy"))
        workBuddyClientIDField.placeholderString = WorkBuddyAppCredentials.clientID
        workBuddyClientSecretField.placeholderString = currentLanguage == .chinese
            ? "已内置；自定义应用时填写"
            : "Built in; fill only for a custom application"
        stack.addArrangedSubview(row(
            label: currentLanguage == .chinese ? "Client ID" : "Client ID",
            control: workBuddyClientIDField
        ))
        stack.addArrangedSubview(row(
            label: currentLanguage == .chinese ? "Client Secret" : "Client Secret",
            control: workBuddyClientSecretField
        ))
        workBuddyRedirectURIField.placeholderString = WorkBuddyOAuthCallbackServer.defaultRedirectURI
        stack.addArrangedSubview(row(
            label: currentLanguage == .chinese ? "回调地址" : "Callback URL",
            control: workBuddyRedirectURIField
        ))
        workBuddyConnectButton.target = self
        workBuddyConnectButton.action = #selector(connectWorkBuddy)
        let workBuddyControls = NSStackView()
        workBuddyControls.orientation = .horizontal
        workBuddyControls.alignment = .centerY
        workBuddyControls.spacing = 8
        workBuddyPasteCodeButton.target = self
        workBuddyPasteCodeButton.action = #selector(pasteWorkBuddyCode)
        workBuddyControls.addArrangedSubview(workBuddyConnectButton)
        workBuddyControls.addArrangedSubview(workBuddyPasteCodeButton)
        workBuddyControls.addArrangedSubview(workBuddyStatusLabel)
        stack.addArrangedSubview(row(
            label: currentLanguage == .chinese ? "授权" : "Authorization",
            control: workBuddyControls
        ))
        stack.addArrangedSubview(hintRow(
            currentLanguage == .chinese
                ? "已内置开发者应用配置，无需申请或填写凭据，点击连接并授权即可。语音任务发给已登录的 WorkBuddy，授权或提问可在任务历史窗口应答。"
                : "Developer credentials are built in. Click Connect and authorize. Tasks go to your signed-in WorkBuddy; answer approvals and questions in task history."
        ))
        stack.addArrangedSubview(hintRow(
            currentLanguage == .chinese
                ? "回调地址需与开放平台登记值完全一致（默认 \(WorkBuddyOAuthCallbackServer.defaultRedirectURI)）；登记为 https 时无法自动接收跳转，完成授权后点“粘贴授权码”。"
                : "The callback URL must match the platform value exactly (default \(WorkBuddyOAuthCallbackServer.defaultRedirectURI)); an https address cannot be received automatically, so click “Paste code” after approving."
        ))
        let memoryControls = NSStackView()
        memoryControls.orientation = .horizontal
        memoryControls.spacing = 8
        let viewMemoryButton = NSButton(title: currentLanguage == .chinese ? "查看记忆" : "View Memory", target: self, action: #selector(openAgentMemory))
        let clearMemoryButton = NSButton(title: currentLanguage == .chinese ? "清除记忆" : "Clear Memory", target: self, action: #selector(clearAgentMemory))
        memoryControls.addArrangedSubview(agentMemoryButton)
        memoryControls.addArrangedSubview(viewMemoryButton)
        memoryControls.addArrangedSubview(clearMemoryButton)
        stack.addArrangedSubview(row(label: currentLanguage == .chinese ? "长期记忆" : "Memory", control: memoryControls))
        stack.addArrangedSubview(hintRow(currentLanguage == .chinese
            ? "自动识别“记住、以后、我偏好”等明确表达；不会保存 API Key、密码或全部对话原文。"
            : "Stores explicit preferences such as “remember” or “I prefer”; never stores keys, passwords, or complete transcripts."))
        stack.addArrangedSubview(row(
            label: currentLanguage == .chinese ? "授权模式" : "Approval Mode",
            control: agentBypassApprovalsButton
        ))
        stack.addArrangedSubview(hintRow(
            currentLanguage == .chinese
                ? "默认在任务历史中允许或拒绝。开启后 Agent 可不经确认执行命令和修改文件。"
                : "By default, approve or deny in Task History. When enabled, the Agent may run commands and edit files without confirmation."
        ))
        stack.addArrangedSubview(row(
            label: currentLanguage == .chinese ? "设备提示音" : "Device Sound",
            control: agentSoundAlertsButton
        ))
        configureDeviceSoundVolumeControl()
        let volumeControls = NSStackView()
        volumeControls.orientation = .horizontal
        volumeControls.alignment = .centerY
        volumeControls.spacing = 8
        volumeControls.addArrangedSubview(deviceSoundVolumeSlider)
        volumeControls.addArrangedSubview(deviceSoundVolumeLabel)
        volumeControls.addArrangedSubview(testDeviceSoundButton)
        deviceSoundVolumeSlider.widthAnchor.constraint(equalToConstant: 205).isActive = true
        deviceSoundVolumeLabel.widthAnchor.constraint(equalToConstant: 42).isActive = true
        stack.addArrangedSubview(row(
            label: currentLanguage == .chinese ? "提示音音量" : "Sound Volume",
            control: volumeControls
        ))

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

        let stackBottomConstraint = stack.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor, constant: -24)
        stackBottomConstraint.priority = .defaultLow

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor, constant: 24),
            stackBottomConstraint
        ])
    }

    private func configureResourcePopup() {
        resourcePopup.addItems(withTitles: AppConfig.supportedResourceIDs)
    }

    private func configureDeviceSoundVolumeControl() {
        deviceSoundVolumeSlider.minValue = 0
        deviceSoundVolumeSlider.maxValue = 100
        deviceSoundVolumeSlider.numberOfTickMarks = 11
        deviceSoundVolumeSlider.allowsTickMarkValuesOnly = false
        deviceSoundVolumeSlider.isContinuous = true
        deviceSoundVolumeSlider.target = self
        deviceSoundVolumeSlider.action = #selector(deviceSoundVolumeChanged)
        testDeviceSoundButton.target = self
        testDeviceSoundButton.action = #selector(testDeviceSound)
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

    private func configureAgentPopup() {
        agentPopup.removeAllItems()
        for name in config.agentConfig.agents.keys.sorted() {
            switch name {
            case "claude":
                agentPopup.addItem(withTitle: "Claude Code")
            case "codex":
                agentPopup.addItem(withTitle: "Codex")
            case "imessage":
                agentPopup.addItem(withTitle: "iMessage Remote Agent")
            case "workbuddy":
                agentPopup.addItem(withTitle: "WorkBuddy")
            default:
                agentPopup.addItem(withTitle: name)
            }
            agentPopup.lastItem?.representedObject = name
        }
    }


    private func updateWorkBuddyStatus() {
        if let error = WorkBuddyAuthStore.shared.storageError() {
            workBuddyStatusLabel.stringValue = currentLanguage == .chinese
                ? "存储异常：\(error)" : "Storage error: \(error)"
            workBuddyStatusLabel.textColor = .systemRed
        } else if WorkBuddyAuthStore.shared.loadToken() != nil {
            workBuddyStatusLabel.stringValue = currentLanguage == .chinese
                ? "已授权" : "Authorized"
            workBuddyStatusLabel.textColor = .systemGreen
        } else {
            workBuddyStatusLabel.stringValue = currentLanguage == .chinese
                ? "未授权" : "Not authorized"
            workBuddyStatusLabel.textColor = .secondaryLabelColor
        }
    }

    @objc private func connectWorkBuddy() {
        let clientID = WorkBuddyAppCredentials.effectiveClientID(workBuddyClientIDField.stringValue)
        let enteredSecret = workBuddyClientSecretField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = clientID == WorkBuddyAppCredentials.clientID || enteredSecret.isEmpty
            ? (WorkBuddyAuthStore.shared.clientSecret(clientID: clientID) ?? "") : enteredSecret
        guard !clientID.isEmpty else {
            workBuddyStatusLabel.stringValue = currentLanguage == .chinese ? "请先填写 Client ID" : "Enter the Client ID first"
            workBuddyStatusLabel.textColor = .systemRed
            return
        }
        guard !clientSecret.isEmpty else {
            workBuddyStatusLabel.stringValue = currentLanguage == .chinese
                ? "请先填写 Client Secret" : "Enter the Client Secret first"
            workBuddyStatusLabel.textColor = .systemRed
            return
        }

        if clientID != WorkBuddyAppCredentials.clientID {
            do {
                try WorkBuddyAuthStore.shared.saveClientSecret(clientSecret, forClientID: clientID)
            } catch {
                workBuddyStatusLabel.stringValue = currentLanguage == .chinese
                    ? "保存 Client Secret 失败：\(error.localizedDescription)"
                    : "Failed to save Client Secret: \(error.localizedDescription)"
                workBuddyStatusLabel.textColor = .systemRed
                return
            }
        }
        workBuddyClientSecretField.stringValue = ""
        workBuddyStatusLabel.stringValue = currentLanguage == .chinese
            ? "正在浏览器中授权…" : "Waiting for authorization…"
        workBuddyStatusLabel.textColor = .secondaryLabelColor
        workBuddyConnectButton.isEnabled = false

        let controller = WorkBuddyAuthController()
        workBuddyAuthController = controller
        let configured = workBuddyRedirectURIField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveRedirect = configured.isEmpty
            ? WorkBuddyOAuthCallbackServer.defaultRedirectURI
            : configured

        // An https loopback URL (or any address this app cannot listen on) still has to be
        // sent verbatim, because the platform compares it byte for byte. The browser will
        // land on a page that never opens, so the code is collected by hand instead.
        guard WorkBuddyAuthController.canServeRedirect(effectiveRedirect) else {
            guard let url = controller.makeAuthorizationURL(
                clientID: clientID,
                redirectURLOverride: effectiveRedirect
            ) else {
                workBuddyConnectButton.isEnabled = true
                workBuddyStatusLabel.stringValue = currentLanguage == .chinese
                    ? "无法生成授权链接，请检查 Client ID" : "Could not build the authorization URL. Check the Client ID."
                workBuddyStatusLabel.textColor = .systemRed
                return
            }
            NSWorkspace.shared.open(url)
            // The link also goes to the clipboard: if the default browser is sandboxed or
            // the open call is swallowed, the user can still paste it into any browser.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            workBuddyConnectButton.isEnabled = true
            workBuddyStatusLabel.stringValue = currentLanguage == .chinese
                ? "浏览器已打开：登录后同意，再点“粘贴授权码”（授权码约 2 分钟内有效）"
                : "Browser opened: sign in, approve, then click “Paste code” (the code lasts about 2 minutes)"
            workBuddyStatusLabel.textColor = .secondaryLabelColor
            return
        }

        controller.authorize(
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURLOverride: effectiveRedirect
        ) { [weak self] result in
            guard let self else { return }
            self.workBuddyConnectButton.isEnabled = true
            switch result {
            case .success:
                self.workBuddyStatusLabel.stringValue = currentLanguage == .chinese
                    ? "已授权" : "Authorized"
                self.workBuddyStatusLabel.textColor = .systemGreen
            case .failure(let error):
                self.workBuddyStatusLabel.stringValue = error.localizedDescription
                self.workBuddyStatusLabel.textColor = .systemRed
            }
            self.workBuddyAuthController = nil
        }
    }

    /// Finishes an authorization whose redirect the desktop app could not receive.
    @objc private func pasteWorkBuddyCode() {
        let clientID = WorkBuddyAppCredentials.effectiveClientID(workBuddyClientIDField.stringValue)
        guard !clientID.isEmpty else {
            workBuddyStatusLabel.stringValue = currentLanguage == .chinese ? "请先填写 Client ID" : "Enter the Client ID first"
            workBuddyStatusLabel.textColor = .systemRed
            return
        }
        guard let clientSecret = WorkBuddyAuthStore.shared.clientSecret(clientID: clientID), !clientSecret.isEmpty else {
            workBuddyStatusLabel.stringValue = currentLanguage == .chinese
                ? "请先填写 Client Secret" : "Enter the Client Secret first"
            workBuddyStatusLabel.textColor = .systemRed
            return
        }

        let alert = NSAlert()
        alert.messageText = currentLanguage == .chinese
            ? "粘贴浏览器地址栏里的链接" : "Paste the URL from the address bar"
        alert.informativeText = currentLanguage == .chinese
            ? "同意授权后浏览器会跳到一个打不开的页面，把地址栏的完整链接复制进来即可。授权码约 2 分钟内有效，请尽快粘贴。"
            : "After you approve, the browser lands on a page that cannot open. Copy the full URL from the address bar. The code lasts about 2 minutes."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 440, height: 24))
        field.placeholderString = "https://localhost:10009/oauth/callback?code=…&state=…"
        // Pre-fill whatever callback URL is already on the clipboard so the round trip stays
        // short. The consent link also lands on the clipboard, so require an actual `code`
        // query item and reject anything that still carries `response_type`.
        if let clip = NSPasteboard.general.string(forType: .string),
           let components = URLComponents(string: clip.trimmingCharacters(in: .whitespacesAndNewlines)),
           let items = components.queryItems,
           items.contains(where: { $0.name == "code" }),
           !items.contains(where: { $0.name == "response_type" }) {
            field.stringValue = clip.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        alert.accessoryView = field
        alert.addButton(withTitle: currentLanguage == .chinese ? "完成授权" : "Finish")
        alert.addButton(withTitle: currentLanguage == .chinese ? "取消" : "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let pasted = field.stringValue
        guard !pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let controller = workBuddyAuthController ?? WorkBuddyAuthController()
        workBuddyAuthController = controller
        let configured = workBuddyRedirectURIField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let redirectURI = configured.isEmpty
            ? WorkBuddyOAuthCallbackServer.defaultRedirectURI
            : configured

        workBuddyStatusLabel.stringValue = currentLanguage == .chinese ? "正在换取令牌…" : "Exchanging the code…"
        workBuddyStatusLabel.textColor = .secondaryLabelColor

        controller.completeWithPastedCode(
            pasted,
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.workBuddyStatusLabel.stringValue = currentLanguage == .chinese
                    ? "已授权" : "Authorized"
                self.workBuddyStatusLabel.textColor = .systemGreen
            case .failure(let error):
                self.workBuddyStatusLabel.stringValue = error.localizedDescription
                self.workBuddyStatusLabel.textColor = .systemRed
            }
            self.workBuddyAuthController = nil
        }
    }

    private func loadConfigIntoFields() {
        configureAgentPopup()
        currentDisplayedProvider = config.asrProvider
        providerPopup.selectItem(withTitle: config.asrProvider.displayName)
        apiKeyField.stringValue = apiKey(for: config.asrProvider)
        volcengineAppKeyField.stringValue = config.volcengineAppKey
        hotwordsTextView.string = config.asrHotwords.joined(separator: ",")
        llmBaseURLField.stringValue = config.llmBaseURL
        llmAPIKeyField.stringValue = config.llmAPIKey
        llmModelField.stringValue = config.llmModel
        if let item = agentPopup.itemArray.first(where: {
            ($0.representedObject as? String) == config.agentConfig.defaultAgent.lowercased()
        }) {
            agentPopup.select(item)
        }
        agentWorkingDirectoryField.stringValue = config.agentConfig.workingDirectory.path
        agentTimeoutField.stringValue = String(config.agentConfig.timeoutSeconds)
        iMessageRecipientField.stringValue = config.agentConfig.definition(for: "imessage")?.recipient ?? ""
        workBuddyClientIDField.stringValue = WorkBuddyAppCredentials.effectiveClientID(config.agentConfig.definition(for: "workbuddy")?.clientID)
        workBuddyRedirectURIField.stringValue = config.agentConfig.definition(for: "workbuddy")?.redirectURI ?? ""
        updateWorkBuddyStatus()
        agentSoundAlertsButton.state = config.agentSoundAlertsEnabled ? .on : .off
        agentBypassApprovalsButton.state = config.agentBypassApprovals ? .on : .off
        agentMemoryButton.state = config.agentMemoryEnabled ? .on : .off
        deviceSoundVolumeSlider.integerValue = config.deviceSoundVolume
        updateDeviceSoundVolumeLabel()
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

    @objc private func deviceSoundVolumeChanged() {
        updateDeviceSoundVolumeLabel()
    }

    @objc private func testDeviceSound() {
        let sent = onTestDeviceSoundVolume?(deviceSoundVolumeSlider.integerValue) ?? false
        statusLabel.stringValue = sent
            ? (currentLanguage == .chinese ? "已发送测试提示音" : "Test sound sent")
            : (currentLanguage == .chinese ? "设备未连接" : "Device not connected")
    }

    private func updateDeviceSoundVolumeLabel() {
        deviceSoundVolumeLabel.stringValue = "\(deviceSoundVolumeSlider.integerValue)%"
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

    @objc private func chooseAgentWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.choose
        panel.directoryURL = URL(fileURLWithPath: agentWorkingDirectoryField.stringValue, isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            agentWorkingDirectoryField.stringValue = url.path
        }
    }

    @objc private func saveSettings() {
        saveDisplayedAPIKey()
        let provider = selectedProvider()
        let resourceID = resourcePopup.titleOfSelectedItem ?? config.resourceID
        let agentName = (agentPopup.selectedItem?.representedObject as? String) ?? config.agentConfig.defaultAgent
        guard let timeoutSeconds = Int(agentTimeoutField.stringValue), timeoutSeconds >= 10 else {
            showErrorAlert(
                title: currentLanguage == .chinese ? "无法保存设置" : "Could Not Save Settings",
                message: currentLanguage == .chinese ? "Agent 超时时间不能少于 10 秒。" : "Agent timeout must be at least 10 seconds."
            )
            return
        }
        let agentDirectory = URL(
            fileURLWithPath: agentWorkingDirectoryField.stringValue,
            isDirectory: true
        )
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: agentDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            showErrorAlert(
                title: currentLanguage == .chinese ? "无法保存设置" : "Could Not Save Settings",
                message: currentLanguage == .chinese ? "请选择一个有效的工程目录。" : "Choose a valid project folder."
            )
            return
        }
        var agentDefinitions = config.agentConfig.agents
        var iMessageDefinition = agentDefinitions["imessage"] ?? AgentCLIDefinition(type: .iMessage)
        iMessageDefinition.recipient = iMessageRecipientField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        agentDefinitions["imessage"] = iMessageDefinition
        var workBuddyDefinition = agentDefinitions["workbuddy"] ?? AgentCLIDefinition(type: .workBuddyLocal)
        workBuddyDefinition.clientID = WorkBuddyAppCredentials.effectiveClientID(workBuddyClientIDField.stringValue)
        let workBuddyRedirectURI = workBuddyRedirectURIField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        workBuddyDefinition.redirectURI = workBuddyRedirectURI.isEmpty ? nil : workBuddyRedirectURI
        agentDefinitions["workbuddy"] = workBuddyDefinition
        let workBuddySecret = workBuddyClientSecretField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !workBuddySecret.isEmpty, workBuddyDefinition.clientID != WorkBuddyAppCredentials.clientID {
            let cid = WorkBuddyAppCredentials.effectiveClientID(workBuddyDefinition.clientID)
            do {
                try WorkBuddyAuthStore.shared.saveClientSecret(workBuddySecret, forClientID: cid)
            } catch {
                showErrorAlert(
                    title: currentLanguage == .chinese ? "保存失败" : "Save failed",
                    message: error.localizedDescription
                )
                return
            }
            workBuddyClientSecretField.stringValue = ""
        }
        let agentConfig = AgentCLIConfig(
            defaultAgent: agentName,
            workingDirectory: agentDirectory,
            timeoutSeconds: timeoutSeconds,
            agents: agentDefinitions
        )

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
            agentConfig: agentConfig,
            autoEnter: config.autoEnter,
            agentCaptureEnabled: config.agentCaptureEnabled,
            agentSoundAlertsEnabled: agentSoundAlertsButton.state == .on,
            agentBypassApprovals: agentBypassApprovalsButton.state == .on,
            agentMemoryEnabled: agentMemoryButton.state == .on,
            deviceSoundVolume: deviceSoundVolumeSlider.integerValue,
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

    @objc private func openAgentMemory() {
        AgentMemoryStore.openMemoryFile()
    }

    @objc private func clearAgentMemory() {
        let alert = NSAlert()
        alert.messageText = currentLanguage == .chinese ? "清除全部长期记忆？" : "Clear all long-term memory?"
        alert.informativeText = currentLanguage == .chinese ? "会话历史文件不会被删除。" : "Task history files will not be deleted."
        alert.addButton(withTitle: currentLanguage == .chinese ? "清除" : "Clear")
        alert.addButton(withTitle: currentLanguage == .chinese ? "取消" : "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            AgentMemoryStore().clear()
            statusLabel.stringValue = currentLanguage == .chinese ? "记忆已清除" : "Memory cleared"
        }
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
        // Hints must wrap. A single-line NSTextField reports the full text width as its
        // intrinsic size, which inflates the stack and drags the window wider than the screen.
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = SettingsWindowLayout.hintMaxWidth
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.widthAnchor.constraint(lessThanOrEqualToConstant: SettingsWindowLayout.hintMaxWidth).isActive = true

        row.addArrangedSubview(spacer)
        row.addArrangedSubview(label)
        return row
    }
}
