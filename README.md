# AgentStick

English | [简体中文](README.zh-CN.md)

AgentStick is a portable desktop-agent entry point built around an ESP32 device and a desktop app. The goal is to turn a small ESP32 board into a physical task trigger: pick it up, press the button, speak a task, and let the desktop app route that task to agents such as Codex, Claude Code, or other local desktop agents. When the agent finishes, the desktop app can notify you and reflect the status back to the device.

This project is currently based on and inspired by [VoiceStick](https://github.com/78/voicestick). VoiceStick already provides the foundation for ESP32 audio capture, BLE transport, desktop ASR, text input, and firmware updates. AgentStick builds on that foundation and moves toward a workflow for dispatching tasks to desktop agents from a handheld device.

## Goal

AgentStick is not meant to be only a voice input tool. It is meant to make desktop agents easier to invoke at any time:

1. Pick up the ESP32 device and speak a task.
2. The device sends audio and button state to the desktop app over BLE.
3. The desktop app performs speech recognition and extracts the task.
4. The desktop app routes the task to Codex, Claude Code, or another desktop agent.
5. When the agent finishes, the desktop app notifies the user through notifications, an overlay, or the device screen.

Example use cases:

- Send a quick coding task to Codex while away from the keyboard.
- Ask Claude Code to inspect, edit, or explain a project in the background.
- Create voice-driven development tasks and review the results later.
- Use the ESP32 device as a handheld controller for multiple desktop AI agents.

## Current Status

This repository is still in the migration and adaptation stage from VoiceStick. The current foundation includes:

- ESP32-S3 firmware that advertises over BLE and connects to the desktop app.
- Button-triggered recording with Opus-encoded microphone audio over BLE.
- A macOS desktop app that receives audio, calls ASR, and displays recognized text.
- Text insertion into the focused desktop app.
- Direct dispatch of recognized tasks to Claude Code or Codex CLI, with local result capture.
- Device status updates and sound alerts for running, completed, failed, and needs-input agent states.
- A working adaptation for the Lichuang ESP32-S3 development board.
- Verified Volcengine ASR configuration and local macOS packaging flow.

Planned AgentStick capabilities:

- Maintain a task queue with task status and completion reminders.
- Notify the user when background agent work finishes.
- Support multiple agent backends and configurable task templates.

### Using voice-driven agents on macOS

1. Install and sign in to the `claude` or `codex` CLI.
2. Open AgentStick Settings. In the Agent section, choose Claude Code or Codex and select the project folder the agent may work in.
3. Choose Agent Run from the menu bar's Output menu. Devices with a side button can also switch modes while idle.
4. Hold the recording button and speak a task. After you confirm the transcript, the desktop app runs the selected agent in that project folder.

Safe approval mode is the default. When Claude or Codex asks to run a privileged command or expand file access, AgentStick opens Task History with working Allow and Deny buttons. For unattended execution, enable “Bypass Agent approvals (high risk)” in the Agent settings; the agent will then stop asking for individual approvals.

Task History also handles agent-initiated confirmations (such as commit, push, or deploy), choice and free-text questions, secret fields, and MCP browser-login or form requests. After approval or an answer, AgentStick resumes the original Claude session or Codex thread instead of recording the waiting message as a completed task.

Within the same agent and project folder, Agent Run uses follow-up cues, recency, and task similarity to decide whether to create or resume a Claude session or Codex thread. Start with “new conversation” to force a new session or “continue conversation” to force the most recent one. Clearing history also removes the local continuation index.

With Long-term Memory enabled, AgentStick stores stable preferences and project context from explicit phrases such as “remember,” “from now on,” “I prefer,” or “for this project.” Relevant memories are supplied to later Claude/Codex tasks. Memory can be viewed or cleared in Settings; API keys, passwords, and complete transcripts are not stored automatically.

Results are saved under `~/Library/Application Support/AgentStick/Tasks/`. The app discovers common Homebrew, NVM, Volta, and Bun installations, plus the Codex CLI bundled with Codex.app or ChatGPT.app. Custom commands remain configurable through `[agents.*]` in `config.toml`.

## Architecture

```text
ESP32 device
  - Button
  - Microphone
  - Screen status
  - BLE audio / state transport
        |
        v
Desktop app
  - BLE pairing and connection
  - ASR speech recognition
  - Task parsing
  - Agent routing
  - Notifications and result display
        |
        v
Desktop agents
  - Codex
  - Claude Code
  - Other local automation / development assistants
```

## Repository Layout

```text
firmware/          ESP-IDF firmware, currently adapted for ESP32-S3
desktop/macos/    Swift / AppKit macOS menu bar app
desktop/windows/  C++20 / Win32 Windows desktop workspace
desktop/linux/    Linux desktop placeholder workspace
website/          Vue + Vite site, downloads, appcast, and browser flashing entry
docs/             BLE protocol, ASR, hardware adaptation, and release docs
scripts/          Firmware asset tooling, packaging, DMG/MSI, and appcast scripts
```

## Hardware Adaptation

The current hardware focus is the Lichuang ESP32-S3 development board:

- Module: ESP32-S3-WROOM-1-N16R8
- Memory: 8MB PSRAM, 16MB flash
- Primary button: GPIO0
- I2C: SDA GPIO1, SCL GPIO2
- Audio ADC: ES7210
- Audio DAC: ES8311
- LCD: ST7789, 320 x 240
- IO expander: PCA9557 at `0x19`

Adaptation notes:

- `docs/lichuang-esp32s3-xiaozhi-notes.md`
- `docs/lichuang-local-adaptation-summary.md`

## Firmware Build

The firmware uses ESP-IDF. The currently verified local environment is ESP-IDF 5.5.x.

The default firmware configuration targets the Lichuang ESP32-S3 development board:

```sh
cd firmware
. /Users/fengsu/esp/esp-idf/export.sh
idf.py set-target esp32s3
idf.py build
```

To build for M5Stack StickS3 without overwriting the Lichuang build output, use the M5Stack defaults in a separate build directory:

```sh
cd firmware
. /Users/fengsu/esp/esp-idf/export.sh
idf.py -B build-m5stack \
  -D SDKCONFIG=build-m5stack/sdkconfig \
  -D SDKCONFIG_DEFAULTS='sdkconfig.defaults;sdkconfig.defaults.m5stack' \
  build
```

Flash and open the serial monitor:

```sh
idf.py -p /dev/cu.usbmodemXXXX flash monitor
```

If automatic download mode is unreliable on the Lichuang board, use manual download mode:

1. Hold the BOOT / user button.
2. Press RESET.
3. Release BOOT after flashing starts.

## macOS Desktop App

The macOS app is a Swift / AppKit menu bar app.

```sh
cd desktop/macos
swift build
swift run AgentStickApp
```

The configuration path currently still follows VoiceStick:

```text
~/Library/Application Support/AgentStick/config.toml
```

Create it from the example:

```sh
mkdir -p "$HOME/Library/Application Support/AgentStick"
cp desktop/macos/Config/config.example.toml "$HOME/Library/Application Support/AgentStick/config.toml"
```

Common configuration:

```toml
asr_provider = "volcengine"
volcengine_api_key = "your_volcengine_access_key"
volcengine_app_key = "your_volcengine_app_key"
resource_id = "volc.seedasr.sauc.duration"
interaction_mode = "hold_to_talk"
paired_device_ids = ""
auto_enter = false

[output]
target = "focused_app"
transform = "original"
```

Do not commit API keys.

## Relationship To VoiceStick

AgentStick currently reuses and extends a large part of VoiceStick's foundation:

- BLE GATT protocol
- ESP32 audio capture and Opus encoding
- Desktop BLE connection
- ASR WebSocket integration
- Text insertion and overlay status display
- OTA and release script structure

Future development will gradually separate AgentStick's product positioning, configuration names, desktop UX, and agent-dispatch layer from the original VoiceStick voice-input workflow.

Original project:

- [78/voicestick](https://github.com/78/voicestick)

## Related Docs

- `docs/protocol.md`: BLE audio, state, control, and OTA protocol
- `docs/volcengine-asr.md`: Volcengine ASR integration notes
- `docs/lichuang-esp32s3-xiaozhi-notes.md`: Lichuang ESP32-S3 hardware and xiaozhi reference notes
- `docs/lichuang-local-adaptation-summary.md`: Local Lichuang board adaptation summary
- `docs/release.md`: macOS, Windows, firmware, and website release flow
- `desktop/windows/README.md`: Windows build notes
- `website/README.md`: Website and appcast notes

## Development Direction

Near-term priorities:

1. Add a persistent task queue and voice follow-up for needs-input states.
2. Add richer desktop notifications and a task history UI.
3. Improve session resumption for Codex and Claude Code.
4. Continue hardening the board-target abstraction for Lichuang ESP32-S3 and M5Stack StickS3.
5. Gradually migrate configuration paths, app names, and UI copy from VoiceStick to AgentStick.
