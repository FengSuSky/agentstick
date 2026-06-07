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
- A working adaptation for the Lichuang ESP32-S3 development board.
- Verified Volcengine ASR configuration and local macOS packaging flow.

Planned AgentStick capabilities:

- Route recognized voice tasks to Codex CLI / Codex desktop workflows.
- Route tasks to Claude Code.
- Maintain a task queue with task status and completion reminders.
- Notify the user when background agent work finishes.
- Show agent execution status on the device screen.
- Support multiple agent backends and configurable task templates.

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

```sh
cd firmware
. /Users/fengsu/esp/esp-idf/export.sh
idf.py set-target esp32s3
idf.py build
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
swift run VoiceStickApp
```

The configuration path currently still follows VoiceStick:

```text
~/Library/Application Support/VoiceStick/config.toml
```

Create it from the example:

```sh
mkdir -p "$HOME/Library/Application Support/VoiceStick"
cp desktop/macos/Config/config.example.toml "$HOME/Library/Application Support/VoiceStick/config.toml"
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

1. Connect Codex / Claude Code task dispatch into the macOS desktop app.
2. Design an agent task state machine: queued, running, done, failed, needs input.
3. Add desktop notifications and device screen status updates.
4. Turn the Lichuang ESP32-S3 changes into an explicit board target.
5. Gradually migrate configuration paths, app names, and UI copy from VoiceStick to AgentStick.
