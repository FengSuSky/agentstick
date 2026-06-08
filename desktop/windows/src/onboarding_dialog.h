#pragma once

#include "app_config.h"
#include "l10n.h"

#include <Windows.h>

#include <functional>
#include <vector>

namespace agentstick {

class OnboardingDialog {
public:
    OnboardingDialog(HINSTANCE instance, HWND parent, AppConfig config);
    ~OnboardingDialog();

    bool Show();

    std::function<void()> on_pair_device_requested;
    std::function<void(AppConfig)> on_config_completed;

private:
    enum class Step {
        kLanguage,
        kDevice,
        kAsr,
        kLlm,
        kReady,
    };

    static INT_PTR CALLBACK DialogProc(HWND hwnd, UINT message, WPARAM w_param, LPARAM l_param);
    INT_PTR HandleMessage(UINT message, WPARAM w_param, LPARAM l_param);
    LPCDLGTEMPLATE BuildDialogTemplate();
    void RebuildUi();
    void DestroyControls();
    void BuildControls();
    void BuildLanguageStep(int content_x, int content_y, int content_w);
    void BuildDeviceStep(int content_x, int content_y, int content_w);
    void BuildAsrStep(int content_x, int content_y, int content_w);
    void BuildLlmStep(int content_x, int content_y, int content_w);
    void BuildReadyStep(int content_x, int content_y, int content_w);
    void LoadConfigIntoControls();
    void SaveControlsIntoConfig();
    void UpdateProviderVisibility();
    void ApplyTrialApiKey();
    void GoBack();
    void GoNext();
    void Finish();
    void SetStatus(const std::wstring& text);
    bool HasDevice() const;
    bool HasApiKey() const;
    std::wstring DeviceSummary() const;
    std::wstring Utf16(const std::string& text) const;
    std::string Utf8(const std::wstring& text) const;
    std::wstring GetText(HWND control) const;
    int Dp(int px) const;

    HINSTANCE instance_;
    HWND parent_;
    HWND hwnd_ = nullptr;
    AppConfig config_;
    Step step_ = Step::kDevice;
    UINT dpi_ = 96;
    HFONT ui_font_ = nullptr;
    std::vector<BYTE> dialog_template_;
    std::vector<HWND> controls_;
    HWND status_label_ = nullptr;
    HWND provider_combo_ = nullptr;
    HWND api_key_edit_ = nullptr;
    HWND apply_trial_button_ = nullptr;
    HWND resource_label_ = nullptr;
    HWND resource_combo_ = nullptr;
    HWND language_combo_ = nullptr;
    HWND llm_base_url_edit_ = nullptr;
    HWND llm_api_key_edit_ = nullptr;
    HWND llm_model_edit_ = nullptr;
    HWND back_button_ = nullptr;
    HWND next_button_ = nullptr;

    static constexpr int kClientWidth = 680;
    static constexpr int kClientHeight = 500;
    static constexpr UINT kIdPairDevice = 3001;
    static constexpr UINT kIdProviderCombo = 3002;
    static constexpr UINT kIdApiKeyEdit = 3003;
    static constexpr UINT kIdApplyTrial = 3004;
    static constexpr UINT kIdResourceCombo = 3005;
    static constexpr UINT kIdBack = 3006;
    static constexpr UINT kIdNext = 3007;
    static constexpr UINT kIdCancel = 3008;
    static constexpr UINT kIdLanguageCombo = 3009;
    static constexpr UINT kIdLlmBaseUrlEdit = 3010;
    static constexpr UINT kIdLlmApiKeyEdit = 3011;
    static constexpr UINT kIdLlmModelEdit = 3012;
};

bool NeedsOnboarding(const AppConfig& config);

} // namespace agentstick
