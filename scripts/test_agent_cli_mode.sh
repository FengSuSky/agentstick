#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

rg -q 'case agentCLI = "agent_cli"' "$root/desktop/macos/Sources/AgentStickApp/AppConfig.swift"
rg -q 'struct AgentCLITask' "$root/desktop/macos/Sources/AgentStickApp"
rg -q 'codexExec' "$root/desktop/macos/Sources/AgentStickApp"
rg -q 'claudePrint' "$root/desktop/macos/Sources/AgentStickApp"
rg -q 'configureAgentPopup' "$root/desktop/macos/Sources/AgentStickApp/SettingsWindowController.swift"
rg -q 'chooseAgentWorkingDirectory' "$root/desktop/macos/Sources/AgentStickApp/SettingsWindowController.swift"
rg -q '/Applications/Codex.app/Contents/Resources/codex' "$root/desktop/macos/Sources/AgentStickApp/AgentCLIRunner.swift"
rg -Fq 'playAgentSoundIfEnabled("task_done", to: peripheralID)' "$root/desktop/macos/Sources/AgentStickApp/VoiceStickCoordinator.swift"
rg -Fq 'playAgentSoundIfEnabled("task_failed", to: peripheralID)' "$root/desktop/macos/Sources/AgentStickApp/VoiceStickCoordinator.swift"
rg -Fq 'sendUIState("task_running"' "$root/desktop/macos/Sources/AgentStickApp/VoiceStickCoordinator.swift"
rg -Fq 'sendUIState("needs_attention"' "$root/desktop/macos/Sources/AgentStickApp/VoiceStickCoordinator.swift"
rg -Fq 'sendUIState("notification"' "$root/desktop/macos/Sources/AgentStickApp/VoiceStickCoordinator.swift"
rg -Fq 'sendUIStateForActiveDevice("transcribing"' "$root/desktop/macos/Sources/AgentStickApp/VoiceStickCoordinator.swift"
rg -Fq 'UI_STATUS_ICON_THINKING' "$root/firmware/components/ui_status/ui_status_icons.h"
rg -Fq 'UI_STATUS_ICON_NOTIFICATION' "$root/firmware/components/ui_status/ui_status_icons.h"
rg -Fq 'app_ui_prevents_power_idle()' "$root/firmware/main/main.c"
rg -q 'final class AgentTaskHistoryWindowController' "$root/desktop/macos/Sources/AgentStickApp/AgentTaskHistoryWindowController.swift"
rg -q 'agent_bypass_approvals' "$root/desktop/macos/Sources/AgentStickApp/AppConfig.swift"
rg -q 'dangerously-skip-permissions' "$root/desktop/macos/Sources/AgentStickApp/AgentCLIRunner.swift"
rg -q 'dangerously-bypass-approvals-and-sandbox' "$root/desktop/macos/Sources/AgentStickApp/AgentCLIRunner.swift"
rg -q 'allowSelectedRequest' "$root/desktop/macos/Sources/AgentStickApp/AgentTaskHistoryWindowController.swift"
rg -q 'completeFocusedAppPaste' "$root/desktop/macos/Sources/AgentStickApp/VoiceStickCoordinator.swift"
rg -q 'NSSecureTextField' "$root/desktop/macos/Sources/AgentStickApp/SettingsWindowController.swift"
rg -q 'AXIsProcessTrustedWithOptions' "$root/desktop/macos/Sources/AgentStickApp/InputInjector.swift"
rg -q 'AGENTSTICK_APPROVAL_REQUIRED' "$root/desktop/macos/Sources/AgentStickApp/AgentCLIRunner.swift"
rg -q '\-\-resume' "$root/desktop/macos/Sources/AgentStickApp/AgentCLIRunner.swift"
rg -q 'AGENTSTICK_INPUT_REQUIRED' "$root/desktop/macos/Sources/AgentStickApp/AgentCLIRunner.swift"
rg -q 'item/tool/requestUserInput' "$root/desktop/macos/Sources/AgentStickApp/CodexInteractiveRunner.swift"
rg -q 'mcpServer/elicitation/request' "$root/desktop/macos/Sources/AgentStickApp/CodexInteractiveRunner.swift"
rg -q 'answerSelectedInput' "$root/desktop/macos/Sources/AgentStickApp/AgentTaskHistoryWindowController.swift"
if rg -q 'lazy var agentTaskHistoryController' "$root/desktop/macos/Sources/AgentStickApp/VoiceStickCoordinator.swift"; then
    echo "Agent task history must initialize eagerly so first approval auto-opens" >&2
    exit 1
fi
rg -q 'deleteSelectedEntry' "$root/desktop/macos/Sources/AgentStickApp/AgentTaskHistoryWindowController.swift"
rg -q 'clearHistory' "$root/desktop/macos/Sources/AgentStickApp/AgentTaskHistoryWindowController.swift"
rg -q 'NSWorkspace.shared.recycle' "$root/desktop/macos/Sources/AgentStickApp/AgentTaskHistoryWindowController.swift"
rg -q 'final class AgentSessionStore' "$root/desktop/macos/Sources/AgentStickApp/AgentSessionStore.swift"
rg -q 'thread/resume' "$root/desktop/macos/Sources/AgentStickApp/CodexInteractiveRunner.swift"
rg -q '\-\-resume' "$root/desktop/macos/Sources/AgentStickApp/AgentCLIRunner.swift"
rg -Fq 'NSAttributedString(' "$root/desktop/macos/Sources/AgentStickApp/AgentTaskHistoryWindowController.swift"
rg -Fq 'ble.playSound("task_done", for: deviceID)' "$root/desktop/macos/Sources/AgentStickApp/VoiceStickCoordinator.swift"
if rg -q '/Users/fengsu' "$root/desktop/macos/Sources/AgentStickApp/AgentCLIRunner.swift"; then
    echo "AgentCLIRunner must not contain a developer-specific home path" >&2
    exit 1
fi
rg -q 'normalized.contains\("就绪"\)' "$root/desktop/macos/Sources/AgentStickApp/StatusController.swift"
rg -q 'scanForPeripherals\(withServices: nil\)' "$root/desktop/macos/Sources/AgentStickApp/BleCentral.swift"
rg -q 'scanForPeripherals\(withServices: nil\)' "$root/desktop/macos/Sources/AgentStickApp/PairDeviceWindowController.swift"
rg -q 'volcengineAppKeyField.stringValue = config.volcengineAppKey' "$root/desktop/macos/Sources/AgentStickApp/SettingsWindowController.swift"
rg -q 'Text Paste -> Agent Run' "$root/desktop/macos/Config/config.example.toml"
rg -q 'STICK_S3_PIN_BUTTON_SIDE.*esp_sleep_enable_ext1_wakeup_io|wake_mask' "$root/firmware/main/main.c"
