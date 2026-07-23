import Foundation

enum AppLanguage: String, CaseIterable {
    case system = "system"
    case english = "en"
    case chinese = "zh-Hans"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }
}

/// Current UI language. Updated when the user changes the setting.
private(set) var currentLanguage: AppLanguage = {
    let stored = UserDefaults.standard.string(forKey: "appLanguage").flatMap(AppLanguage.init) ?? .system
    return stored.resolved
}()

func setAppLanguage(_ lang: AppLanguage) {
    UserDefaults.standard.set(lang.rawValue, forKey: "appLanguage")
    currentLanguage = lang.resolved
}

extension AppLanguage {
    var resolved: AppLanguage {
        if self != .system { return self }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("zh") ? .chinese : .english
    }
}

// MARK: - Localization strings

enum L10n {

    // MARK: StatusController — tray states
    static var pairAgentStick: String {
        currentLanguage == .chinese ? "配对 AgentStick" : "Pair AgentStick"
    }
    static var listening: String {
        currentLanguage == .chinese ? "正在聆听" : "Listening"
    }
    static var processing: String {
        currentLanguage == .chinese ? "正在处理" : "Processing"
    }
    static var ready: String {
        currentLanguage == .chinese ? "就绪" : "Ready"
    }
    static var error: String {
        currentLanguage == .chinese ? "错误" : "Error"
    }
    static var noSpeech: String {
        currentLanguage == .chinese ? "无语音" : "No speech"
    }
    static var pair: String {
        currentLanguage == .chinese ? "配对" : "Pair"
    }

    // MARK: StatusController — menu items
    static var restoreLastInput: String {
        currentLanguage == .chinese ? "恢复上次输入" : "Restore Last Input"
    }
    static var pairDevice: String {
        currentLanguage == .chinese ? "配对设备…" : "Pair Device..."
    }
    static var settings: String {
        currentLanguage == .chinese ? "设置…" : "Settings..."
    }
    static var website: String {
        currentLanguage == .chinese ? "官网" : "Website"
    }
    static var taskHistory: String {
        currentLanguage == .chinese ? "任务历史…" : "Task History..."
    }
    static var testDeviceSound: String {
        currentLanguage == .chinese ? "测试设备提示音" : "Test Device Sound"
    }
    static var quit: String {
        currentLanguage == .chinese ? "退出" : "Quit"
    }
    static var pressReturnAfterPaste: String {
        currentLanguage == .chinese ? "粘贴后按回车" : "Press Return After Paste"
    }
    static var interaction: String {
        currentLanguage == .chinese ? "交互方式" : "Interaction"
    }
    static var holdToTalk: String {
        currentLanguage == .chinese ? "按住说话" : "Hold to Talk"
    }
    static var clickToTalk: String {
        currentLanguage == .chinese ? "点击说话" : "Click to Talk"
    }
    static var output: String {
        currentLanguage == .chinese ? "输出" : "Output"
    }
    static var scanning: String {
        currentLanguage == .chinese ? "正在扫描" : "Scanning"
    }
    static var connected: String {
        currentLanguage == .chinese ? "已连接" : "Connected"
    }
    static var forgetThisDevice: String {
        currentLanguage == .chinese ? "忘记此设备" : "Forget This Device"
    }
    static var themeColor: String {
        currentLanguage == .chinese ? "主题颜色" : "Theme Color"
    }
    static var overlayPosition: String {
        currentLanguage == .chinese ? "浮窗位置" : "Overlay Position"
    }
    static var translation: String {
        currentLanguage == .chinese ? "翻译" : "Translation"
    }
    static var original: String {
        currentLanguage == .chinese ? "原文" : "Original"
    }
    static func translateTo(_ name: String) -> String {
        currentLanguage == .chinese ? "翻译为\(name)" : "Translate to \(name)"
    }
    static var firmwareUnknown: String {
        currentLanguage == .chinese ? "固件版本未知" : "Firmware Unknown"
    }
    static func firmware(_ version: String) -> String {
        currentLanguage == .chinese ? "固件 \(version)" : "Firmware \(version)"
    }
    static var checkingForUpdates: String {
        currentLanguage == .chinese ? "正在检查更新" : "Checking for Updates"
    }
    static var updateCheckFailed: String {
        currentLanguage == .chinese ? "更新检查失败" : "Update Check Failed"
    }
    static func updateTo(_ version: String) -> String {
        currentLanguage == .chinese ? "更新到 \(version)…" : "Update to \(version)..."
    }
    static var firmwareUpToDate: String {
        currentLanguage == .chinese ? "固件已是最新" : "Firmware Up to Date"
    }
    static var asrError: String {
        currentLanguage == .chinese ? "语音识别错误" : "ASR error"
    }

    // MARK: SettingsWindowController
    static var agentStickSettings: String {
        currentLanguage == .chinese ? "AgentStick 设置" : "AgentStick Settings"
    }
    static var provider: String {
        currentLanguage == .chinese ? "服务商" : "Provider"
    }
    static var apiKey: String {
        currentLanguage == .chinese ? "API Key" : "API Key"
    }
    static var appKey: String {
        currentLanguage == .chinese ? "App Key" : "App Key"
    }
    static var applyTrial: String {
        currentLanguage == .chinese ? "申请试用" : "Apply Trial"
    }
    static var resourceID: String {
        currentLanguage == .chinese ? "资源 ID" : "Resource ID"
    }
    static var hotwords: String {
        currentLanguage == .chinese ? "热词" : "Hotwords"
    }
    static var hotwordsHint: String {
        currentLanguage == .chinese ? "用逗号或换行分隔热词。" : "Separate hotwords with commas or new lines."
    }
    static var baseURL: String {
        currentLanguage == .chinese ? "Base URL" : "Base URL"
    }
    static var model: String {
        currentLanguage == .chinese ? "模型" : "Model"
    }
    static var audioCache: String {
        currentLanguage == .chinese ? "音频缓存" : "Audio Cache"
    }
    static var saveDebugAudioFiles: String {
        currentLanguage == .chinese ? "保存调试音频文件" : "Save debug audio files"
    }
    static var audioFolder: String {
        currentLanguage == .chinese ? "音频文件夹" : "Audio Folder"
    }
    static var choose: String {
        currentLanguage == .chinese ? "选择…" : "Choose..."
    }
    static var openConfigFolder: String {
        currentLanguage == .chinese ? "打开配置文件夹" : "Open Config Folder"
    }
    static var save: String {
        currentLanguage == .chinese ? "保存" : "Save"
    }
    static var saved: String {
        currentLanguage == .chinese ? "已保存。" : "Saved."
    }
    static var couldNotSaveSettings: String {
        currentLanguage == .chinese ? "无法保存设置" : "Could Not Save Settings"
    }
    static var language: String {
        currentLanguage == .chinese ? "界面语言" : "Language"
    }

    // MARK: OnboardingWindowController
    static var setUpAgentStick: String {
        currentLanguage == .chinese ? "设置 AgentStick" : "Set Up AgentStick"
    }
    static var pairYourAgentStick: String {
        currentLanguage == .chinese ? "配对你的 AgentStick" : "Pair your AgentStick"
    }
    static var pairDeviceDetail: String {
        currentLanguage == .chinese
            ? "选择附近的 VS-XXXX 设备。AgentStick 需要先配对设备才能开始收音。"
            : "Choose a nearby VS-XXXX device. AgentStick needs a paired device before the app can listen."
    }
    static var chooseSpeechProvider: String {
        currentLanguage == .chinese ? "选择语音服务商" : "Choose your speech provider"
    }
    static var allowTextInsertion: String {
        currentLanguage == .chinese ? "允许文本输入" : "Allow text insertion"
    }
    static var accessibilityDetail: String {
        currentLanguage == .chinese
            ? "AgentStick 会在光标位置粘贴识别到的文字，因此需要 macOS 辅助功能权限。"
            : "AgentStick pastes recognized text at your cursor, so macOS Accessibility permission is required."
    }
    static var agentStickIsReady: String {
        currentLanguage == .chinese ? "AgentStick 已就绪" : "AgentStick is ready"
    }
    static var readyDetail: String {
        currentLanguage == .chinese
            ? "设备和语音识别已配置完成。点击完成开始扫描和连接。"
            : "The device and ASR settings are configured. Finish setup to start scanning and connecting."
    }
    static var `continue`: String {
        currentLanguage == .chinese ? "继续" : "Continue"
    }
    static var finish: String {
        currentLanguage == .chinese ? "完成" : "Finish"
    }
    static var back: String {
        currentLanguage == .chinese ? "返回" : "Back"
    }
    static var openAccessibilitySettings: String {
        currentLanguage == .chinese ? "打开辅助功能设置" : "Open Accessibility Settings"
    }
    static var device: String {
        currentLanguage == .chinese ? "设备" : "Device"
    }
    static var notPaired: String {
        currentLanguage == .chinese ? "未配对" : "Not paired"
    }
    static var allowed: String {
        currentLanguage == .chinese ? "已允许" : "Allowed"
    }
    static var notAllowedYet: String {
        currentLanguage == .chinese ? "尚未允许" : "Not allowed yet"
    }
    static var bluetoothUnavailable: String {
        currentLanguage == .chinese ? "蓝牙不可用" : "Bluetooth unavailable"
    }
    static var selectADevice: String {
        currentLanguage == .chinese ? "请选择一台设备" : "Select a device"
    }
    static func selectedDevice(_ id: String) -> String {
        currentLanguage == .chinese ? "已选择 VS-\(id)" : "Selected VS-\(id)"
    }
    static func found(_ count: Int) -> String {
        currentLanguage == .chinese ? "已发现 \(count) 台" : "\(count) found"
    }
    static var openedTrialPage: String {
        currentLanguage == .chinese ? "已打开试用申请页面。" : "Opened trial application page."
    }

    // MARK: PairDeviceWindowController
    static var pairAgentStickTitle: String {
        currentLanguage == .chinese ? "配对 AgentStick" : "Pair AgentStick"
    }

    // MARK: FirmwareUpdateWindowController
    static var firmwareUpdate: String {
        currentLanguage == .chinese ? "固件更新" : "Firmware Update"
    }
    static var updatingFirmware: String {
        currentLanguage == .chinese ? "正在更新固件" : "Updating Firmware"
    }
    static var preparingUpdate: String {
        currentLanguage == .chinese ? "正在准备更新…" : "Preparing update..."
    }
    static func speed(_ value: String) -> String {
        currentLanguage == .chinese ? "速度 \(value)" : "Speed \(value)"
    }
    static var estimatingTimeRemaining: String {
        currentLanguage == .chinese ? "正在估算剩余时间" : "Estimating time remaining"
    }
    static var finishingOnDevice: String {
        currentLanguage == .chinese ? "设备端正在完成" : "Finishing on device"
    }
    static var firmwareUpdated: String {
        currentLanguage == .chinese ? "固件已更新" : "Firmware Updated"
    }
    static var deviceRebooting: String {
        currentLanguage == .chinese ? "设备正在重启进入新固件。" : "The device is rebooting into the new firmware."
    }
    static var done: String {
        currentLanguage == .chinese ? "完成" : "Done"
    }
    static var updateFailed: String {
        currentLanguage == .chinese ? "更新失败" : "Update Failed"
    }
    static var keptCurrentFirmware: String {
        currentLanguage == .chinese ? "设备保留了当前固件。" : "The device kept its current firmware."
    }
    static var cancellingFirmwareUpdate: String {
        currentLanguage == .chinese ? "正在取消固件更新" : "Cancelling Firmware Update"
    }
    static var stoppingTransfer: String {
        currentLanguage == .chinese ? "正在停止传输并请求设备中止。" : "Stopping transfer and asking the device to abort."
    }
    static var cancelling: String {
        currentLanguage == .chinese ? "正在取消" : "Cancelling"
    }
    static var close: String {
        currentLanguage == .chinese ? "关闭" : "Close"
    }
    static var cancel: String {
        currentLanguage == .chinese ? "取消" : "Cancel"
    }

    // MARK: AppDelegate
    static var quitAgentStick: String {
        currentLanguage == .chinese ? "退出 AgentStick" : "Quit AgentStick"
    }
    static var inputSaveFailed: String {
        currentLanguage == .chinese ? "输入保存失败" : "Input save failed"
    }
    static var themeSaveFailed: String {
        currentLanguage == .chinese ? "主题保存失败" : "Theme save failed"
    }
    static var outputSaveFailed: String {
        currentLanguage == .chinese ? "输出保存失败" : "Output save failed"
    }
    static var positionSaveFailed: String {
        currentLanguage == .chinese ? "位置保存失败" : "Position save failed"
    }
    static var pairSaveFailed: String {
        currentLanguage == .chinese ? "配对保存失败" : "Pair save failed"
    }
    static var forgetDeviceFailed: String {
        currentLanguage == .chinese ? "忘记设备失败" : "Forget device failed"
    }
    static var firmwareUpdateRecommended: String {
        currentLanguage == .chinese ? "建议更新固件" : "Firmware update recommended"
    }
    static var firmwareUpdateAvailable: String {
        currentLanguage == .chinese ? "有可用固件更新" : "Firmware update available"
    }
    static func firmwareUpdateDetail(deviceID: String, current: String, latest: String) -> String {
        currentLanguage == .chinese
            ? "VS-\(deviceID) 当前固件版本为 \(current)，最新版本为 \(latest)。"
            : "VS-\(deviceID) is running firmware \(current). The latest firmware is \(latest)."
    }
    static var updateFirmware: String {
        currentLanguage == .chinese ? "更新固件" : "Update Firmware"
    }
    static var later: String {
        currentLanguage == .chinese ? "稍后" : "Later"
    }
    static var cloudNeedsAttention: String {
        currentLanguage == .chinese ? "Cloud 需要注意" : "AgentStick Cloud needs attention"
    }
    static var selectVoiceStickDeviceFirst: String {
        currentLanguage == .chinese ? "请先选择一台 AgentStick 设备。" : "Select a AgentStick device first."
    }

    // MARK: BleCentral errors
    static var noAgentStickConnected: String {
        currentLanguage == .chinese ? "没有已连接的 AgentStick。" : "No AgentStick is connected."
    }
    static var firmwareNoBLEOTA: String {
        currentLanguage == .chinese ? "已连接的固件不支持 BLE OTA。" : "The connected firmware does not expose BLE OTA."
    }
    static var firmwareImageTooLarge: String {
        currentLanguage == .chinese ? "固件镜像大于 OTA 分区。" : "Firmware image is larger than the OTA partition."
    }
    static var firmwareUpdateAlreadyRunning: String {
        currentLanguage == .chinese ? "固件更新已在进行中。" : "A firmware update is already running."
    }
    static var firmwareUpdateCancelled: String {
        currentLanguage == .chinese ? "固件更新已取消。" : "Firmware update cancelled."
    }
    static func bleWriteFailed(_ message: String) -> String {
        currentLanguage == .chinese ? "BLE 写入失败: \(message)" : "BLE write failed: \(message)"
    }
    static func deviceRejectedOTA(_ code: String) -> String {
        currentLanguage == .chinese ? "设备拒绝了 OTA: \(code)" : "Device rejected OTA: \(code)"
    }

    // MARK: OutputProfile
    static var focusedApp: String {
        currentLanguage == .chinese ? "当前应用" : "Focused App"
    }
    static var subtitle: String {
        currentLanguage == .chinese ? "字幕" : "Subtitle"
    }

    // MARK: Misc
    static func asrErrorWith(_ text: String) -> String {
        currentLanguage == .chinese ? "语音识别错误: \(text)" : "ASR error: \(text)"
    }
    static var edit: String {
        currentLanguage == .chinese ? "编辑" : "Edit"
    }
    static var undo: String {
        currentLanguage == .chinese ? "撤销" : "Undo"
    }
    static var redo: String {
        currentLanguage == .chinese ? "重做" : "Redo"
    }
}
