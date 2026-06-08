#pragma once

#include "app_config.h"

#include <string>

namespace agentstick {

AppLanguage CurrentLanguage();
void SetCurrentLanguage(AppLanguage lang);

namespace L10n {

// StatusController — tray states
std::wstring PairAgentStick();
std::wstring Listening();
std::wstring Processing();
std::wstring Ready();
std::wstring Error();
std::wstring NoSpeech();
std::wstring Pair();

// Menu items
std::wstring RestoreLastInput();
std::wstring PairDevice();
std::wstring Settings();
std::wstring Website();
std::wstring CheckForAppUpdates();
std::wstring Quit();
std::wstring PressReturnAfterPaste();
std::wstring Interaction();
std::wstring HoldToTalk();
std::wstring ClickToTalk();
std::wstring Output();
std::wstring Scanning();
std::wstring Connected();
std::wstring ForgetThisDevice();
std::wstring ThemeColor();
std::wstring OverlayPosition();
std::wstring Translation();
std::wstring Original();
std::wstring TranslateTo(const std::wstring& name);

// Firmware
std::wstring FirmwareUnknown();
std::wstring Firmware(const std::wstring& version);
std::wstring CheckingForUpdates();
std::wstring UpdateCheckFailed();
std::wstring UpdateTo(const std::wstring& version);
std::wstring FirmwareUpToDate();
std::wstring AsrError();

// Settings
std::wstring AgentStickSettings();
std::wstring Provider();
std::wstring ApiKey();
std::wstring AppKey();
std::wstring ResourceID();
std::wstring Hotwords();
std::wstring HotwordsHint();
std::wstring BaseURL();
std::wstring Model();
std::wstring Language();
std::wstring SaveDebugAudioFiles();
std::wstring Choose();
std::wstring Saved();
std::wstring CouldNotSaveSettings();
std::wstring ApplyTrial();
std::wstring Save();
std::wstring OpenConfigFolder();

// Onboarding
std::wstring SetUpAgentStick();
std::wstring Device();
std::wstring VoiceRecognition();
std::wstring Continue();
std::wstring Back();
std::wstring Next();
std::wstring Finish();
std::wstring ReadyToGo();
std::wstring PairYourDevice();
std::wstring SelectVoiceStickDeviceFirst();
std::wstring ChooseSpeechService();
std::wstring AgentStickIsReady();
std::wstring DictateInstructions();
std::wstring Accessibility();

// PairDevice
std::wstring PairNewDevice();
std::wstring Cancel();
std::wstring Close();
std::wstring Done();
std::wstring UpdateFailed();
std::wstring KeptCurrentFirmware();
std::wstring FirmwareUpdateRecommended();
std::wstring FirmwareUpdateAvailable();
std::wstring UpdateFirmware();
std::wstring Later();

// BLE errors
std::wstring NoAgentStickConnected();
std::wstring FirmwareNoBLEOTA();
std::wstring FirmwareImageTooLarge();
std::wstring FirmwareUpdateAlreadyRunning();
std::wstring FirmwareUpdateCancelled();
std::wstring BleWriteFailed(const std::wstring& message);
std::wstring DeviceRejectedOTA(const std::wstring& code);

// OutputProfile
std::wstring FocusedApp();
std::wstring Subtitle();

// Misc
std::wstring AsrErrorWith(const std::wstring& text);
std::wstring Edit();
std::wstring Undo();
std::wstring Redo();
std::wstring Debug();

} // namespace L10n
} // namespace agentstick
