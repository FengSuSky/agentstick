#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

rg -q 'case agentCLI = "agent_cli"' "$root/desktop/macos/Sources/AgentStickApp/AppConfig.swift"
rg -q 'struct AgentCLITask' "$root/desktop/macos/Sources/AgentStickApp"
rg -q 'codexExec' "$root/desktop/macos/Sources/AgentStickApp"
rg -q 'claudePrint' "$root/desktop/macos/Sources/AgentStickApp"
rg -q 'normalized.contains\("就绪"\)' "$root/desktop/macos/Sources/AgentStickApp/StatusController.swift"
rg -q 'scanForPeripherals\(withServices: nil\)' "$root/desktop/macos/Sources/AgentStickApp/BleCentral.swift"
rg -q 'scanForPeripherals\(withServices: nil\)' "$root/desktop/macos/Sources/AgentStickApp/PairDeviceWindowController.swift"
rg -q 'volcengineAppKeyField.stringValue = config.volcengineAppKey' "$root/desktop/macos/Sources/AgentStickApp/SettingsWindowController.swift"
rg -q 'Text Paste -> Agent Run' "$root/desktop/macos/Config/config.example.toml"
rg -q 'STICK_S3_PIN_BUTTON_SIDE.*esp_sleep_enable_ext1_wakeup_io|wake_mask' "$root/firmware/main/main.c"
