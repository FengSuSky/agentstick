#include "l10n.h"

#include <Windows.h>

#include <mutex>

namespace agentstick {

namespace {

AppLanguage g_language = AppLanguage::kSystem;
std::once_flag g_init_flag;

bool IsChinese() {
    return CurrentLanguage() == AppLanguage::kChinese;
}

} // namespace

AppLanguage CurrentLanguage() {
    std::call_once(g_init_flag, [] {
        try {
            auto cfg = AppConfig::Load();
            g_language = AppLanguageResolved(cfg.app_language);
        } catch (...) {
            g_language = AppLanguageResolved(AppLanguage::kSystem);
        }
    });
    return g_language;
}

void SetCurrentLanguage(AppLanguage lang) {
    g_language = AppLanguageResolved(lang);
}

namespace L10n {

// StatusController — tray states
std::wstring PairAgentStick() {
    return IsChinese() ? L"配对 AgentStick" : L"Pair AgentStick";
}
std::wstring Listening() {
    return IsChinese() ? L"正在聆听" : L"Listening";
}
std::wstring Processing() {
    return IsChinese() ? L"正在处理" : L"Processing";
}
std::wstring Ready() {
    return IsChinese() ? L"就绪" : L"Ready";
}
std::wstring Error() {
    return IsChinese() ? L"错误" : L"Error";
}
std::wstring NoSpeech() {
    return IsChinese() ? L"无语音" : L"No speech";
}
std::wstring Pair() {
    return IsChinese() ? L"配对" : L"Pair";
}

// Menu items
std::wstring RestoreLastInput() {
    return IsChinese() ? L"恢复上次输入" : L"Restore Last Input";
}
std::wstring PairDevice() {
    return IsChinese() ? L"配对设备…" : L"Pair Device...";
}
std::wstring Settings() {
    return IsChinese() ? L"设置…" : L"Settings...";
}
std::wstring Website() {
    return IsChinese() ? L"官网" : L"Website";
}
std::wstring CheckForAppUpdates() {
    return IsChinese() ? L"检查应用更新…" : L"Check for App Updates...";
}
std::wstring Quit() {
    return IsChinese() ? L"退出" : L"Quit";
}
std::wstring PressReturnAfterPaste() {
    return IsChinese() ? L"粘贴后按回车" : L"Press Return After Paste";
}
std::wstring Interaction() {
    return IsChinese() ? L"交互方式" : L"Interaction";
}
std::wstring HoldToTalk() {
    return IsChinese() ? L"按住说话" : L"Hold to Talk";
}
std::wstring ClickToTalk() {
    return IsChinese() ? L"点击说话" : L"Click to Talk";
}
std::wstring Output() {
    return IsChinese() ? L"输出" : L"Output";
}
std::wstring Scanning() {
    return IsChinese() ? L"正在扫描" : L"Scanning";
}
std::wstring Connected() {
    return IsChinese() ? L"已连接" : L"Connected";
}
std::wstring ForgetThisDevice() {
    return IsChinese() ? L"忘记此设备" : L"Forget This Device";
}
std::wstring ThemeColor() {
    return IsChinese() ? L"主题颜色" : L"Theme Color";
}
std::wstring OverlayPosition() {
    return IsChinese() ? L"浮窗位置" : L"Overlay Position";
}
std::wstring Translation() {
    return IsChinese() ? L"翻译" : L"Translation";
}
std::wstring Original() {
    return IsChinese() ? L"原文" : L"Original";
}
std::wstring TranslateTo(const std::wstring& name) {
    return IsChinese() ? L"翻译为" + name : L"Translate to " + name;
}

// Firmware
std::wstring FirmwareUnknown() {
    return IsChinese() ? L"固件版本未知" : L"Firmware Unknown";
}
std::wstring Firmware(const std::wstring& v) {
    return IsChinese() ? L"固件 " + v : L"Firmware " + v;
}
std::wstring CheckingForUpdates() {
    return IsChinese() ? L"正在检查更新" : L"Checking for Updates";
}
std::wstring UpdateCheckFailed() {
    return IsChinese() ? L"更新检查失败" : L"Update Check Failed";
}
std::wstring UpdateTo(const std::wstring& v) {
    return IsChinese() ? L"更新到 " + v + L"…" : L"Update to " + v + L"...";
}
std::wstring FirmwareUpToDate() {
    return IsChinese() ? L"固件已是最新" : L"Firmware Up to Date";
}
std::wstring AsrError() {
    return IsChinese() ? L"语音识别错误" : L"ASR error";
}

// Settings
std::wstring AgentStickSettings() {
    return IsChinese() ? L"AgentStick 设置" : L"AgentStick Settings";
}
std::wstring Provider() {
    return IsChinese() ? L"服务商" : L"Provider";
}
std::wstring ApiKey() {
    return IsChinese() ? L"API Key" : L"API Key";
}
std::wstring AppKey() {
    return IsChinese() ? L"App Key" : L"App Key";
}
std::wstring ResourceID() {
    return IsChinese() ? L"资源 ID" : L"Resource ID";
}
std::wstring Hotwords() {
    return IsChinese() ? L"热词" : L"Hotwords";
}
std::wstring HotwordsHint() {
    return IsChinese() ? L"每行一个，或用逗号分隔" : L"One per line, or comma-separated";
}
std::wstring BaseURL() {
    return IsChinese() ? L"基础 URL" : L"Base URL";
}
std::wstring Model() {
    return IsChinese() ? L"模型" : L"Model";
}
std::wstring Language() {
    return IsChinese() ? L"语言" : L"Language";
}
std::wstring SaveDebugAudioFiles() {
    return IsChinese() ? L"保存调试音频文件" : L"Save debug audio files";
}
std::wstring Choose() {
    return IsChinese() ? L"浏览…" : L"Choose...";
}
std::wstring Saved() {
    return IsChinese() ? L"已保存" : L"Saved";
}
std::wstring CouldNotSaveSettings() {
    return IsChinese() ? L"无法保存设置" : L"Could Not Save Settings";
}
std::wstring ApplyTrial() {
    return IsChinese() ? L"申请试用" : L"Apply Trial";
}
std::wstring Save() {
    return IsChinese() ? L"保存" : L"Save";
}
std::wstring OpenConfigFolder() {
    return IsChinese() ? L"打开配置目录" : L"Open Config Folder";
}

// Onboarding
std::wstring SetUpAgentStick() {
    return IsChinese() ? L"设置 AgentStick" : L"Set up AgentStick";
}
std::wstring Device() {
    return IsChinese() ? L"设备" : L"Device";
}
std::wstring VoiceRecognition() {
    return IsChinese() ? L"语音识别" : L"Voice Recognition";
}
std::wstring Continue() {
    return IsChinese() ? L"继续" : L"Continue";
}
std::wstring Back() {
    return IsChinese() ? L"返回" : L"Back";
}
std::wstring Next() {
    return IsChinese() ? L"下一步" : L"Next";
}
std::wstring Finish() {
    return IsChinese() ? L"完成" : L"Finish";
}
std::wstring ReadyToGo() {
    return IsChinese() ? L"准备就绪" : L"Ready to Go";
}
std::wstring PairYourDevice() {
    return IsChinese() ? L"配对你的 AgentStick 设备。" : L"Pair your AgentStick device.";
}
std::wstring SelectVoiceStickDeviceFirst() {
    return IsChinese() ? L"请先选择一台 AgentStick 设备。" : L"Select a AgentStick device first.";
}
std::wstring ChooseSpeechService() {
    return IsChinese() ? L"选择语音识别服务。" : L"Choose your speech recognition service.";
}
std::wstring AgentStickIsReady() {
    return IsChinese() ? L"AgentStick 已就绪。" : L"AgentStick is ready.";
}
std::wstring DictateInstructions() {
    return IsChinese() ? L"按下设备前面的按钮，在当前应用中输入语音。" : L"Press the front button on your device to dictate into the focused app.";
}
std::wstring Accessibility() {
    return IsChinese() ? L"辅助功能" : L"Accessibility";
}

// PairDevice
std::wstring PairNewDevice() {
    return IsChinese() ? L"配对新设备" : L"Pair New Device";
}
std::wstring Cancel() {
    return IsChinese() ? L"取消" : L"Cancel";
}
std::wstring Close() {
    return IsChinese() ? L"关闭" : L"Close";
}
std::wstring Done() {
    return IsChinese() ? L"完成" : L"Done";
}
std::wstring UpdateFailed() {
    return IsChinese() ? L"更新失败" : L"Update Failed";
}
std::wstring KeptCurrentFirmware() {
    return IsChinese() ? L"设备保留了当前固件。" : L"The device kept its current firmware.";
}
std::wstring FirmwareUpdateRecommended() {
    return IsChinese() ? L"建议更新固件" : L"Firmware update recommended";
}
std::wstring FirmwareUpdateAvailable() {
    return IsChinese() ? L"有可用固件更新" : L"Firmware update available";
}
std::wstring UpdateFirmware() {
    return IsChinese() ? L"更新固件" : L"Update Firmware";
}
std::wstring Later() {
    return IsChinese() ? L"稍后" : L"Later";
}

// BLE errors
std::wstring NoAgentStickConnected() {
    return IsChinese() ? L"没有已连接的 AgentStick。" : L"No AgentStick is connected.";
}
std::wstring FirmwareNoBLEOTA() {
    return IsChinese() ? L"已连接的固件不支持 BLE OTA。" : L"The connected firmware does not expose BLE OTA.";
}
std::wstring FirmwareImageTooLarge() {
    return IsChinese() ? L"固件镜像大于 OTA 分区。" : L"Firmware image is larger than the OTA partition.";
}
std::wstring FirmwareUpdateAlreadyRunning() {
    return IsChinese() ? L"固件更新已在进行中。" : L"A firmware update is already running.";
}
std::wstring FirmwareUpdateCancelled() {
    return IsChinese() ? L"固件更新已取消。" : L"Firmware update cancelled.";
}
std::wstring BleWriteFailed(const std::wstring& m) {
    return IsChinese() ? L"BLE 写入失败: " + m : L"BLE write failed: " + m;
}
std::wstring DeviceRejectedOTA(const std::wstring& c) {
    return IsChinese() ? L"设备拒绝了 OTA: " + c : L"Device rejected OTA: " + c;
}

// OutputProfile
std::wstring FocusedApp() {
    return IsChinese() ? L"当前应用" : L"Focused App";
}
std::wstring Subtitle() {
    return IsChinese() ? L"字幕" : L"Subtitle";
}

std::wstring AsrErrorWith(const std::wstring& t) {
    return IsChinese() ? L"语音识别错误: " + t : L"ASR error: " + t;
}
std::wstring Edit() {
    return IsChinese() ? L"编辑" : L"Edit";
}
std::wstring Undo() {
    return IsChinese() ? L"撤销" : L"Undo";
}
std::wstring Redo() {
    return IsChinese() ? L"重做" : L"Redo";
}
std::wstring Debug() {
    return IsChinese() ? L"调试" : L"Debug";
}

} // namespace L10n
} // namespace agentstick
