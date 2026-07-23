# AgentStick

[English](README.md) | 简体中文

AgentStick 是一个基于 ESP32 设备和桌面 App 的随身桌面 Agent 入口。目标是把一块小型 ESP32 设备做成可以随时拿起、按下、说话的任务入口，通过蓝牙连接到电脑上的桌面 App，再把语音任务下发给 Codex、Claude Code 等本地或桌面 Agent。Agent 完成任务后，桌面端再把状态和结果提示回用户。

这个项目当前参考并基于 [VoiceStick](https://github.com/78/voicestick) 开发。VoiceStick 已经实现了 ESP32 语音采集、BLE 传输、桌面端 ASR、文本输入和固件更新等基础能力；AgentStick 会在这个基础上继续扩展为“随身给桌面 Agent 派任务”的工作流入口。

## 项目目标

AgentStick 想解决的问题不是单纯语音输入，而是让桌面 Agent 更容易被随时调用：

1. 拿起 ESP32 设备，按住按钮说出任务。
2. 设备通过 BLE 把音频和按键状态发送给桌面 App。
3. 桌面 App 完成语音识别，理解用户要下发的任务。
4. 桌面 App 把任务交给 Codex、Claude Code 或其他桌面 Agent。
5. Agent 执行完成后，桌面 App 通过通知、悬浮窗或设备屏幕提示用户。

理想使用场景包括：

- 离开键盘时快速给 Codex 下发一个代码任务。
- 让 Claude Code 在后台修改、检查或解释一个工程。
- 用语音创建待办式开发任务，稍后回到电脑查看结果。
- 把 ESP32 设备作为“随身遥控器”，控制桌面上的多个 AI Agent。

## 当前状态

当前仓库仍处于从 VoiceStick 迁移和适配阶段，已经具备的基础能力包括：

- ESP32-S3 固件通过 BLE 广播和连接桌面端。
- 设备按键触发录音，麦克风音频经 Opus 编码后通过 BLE 发送。
- macOS 桌面端可以接收音频、调用 ASR，并显示识别结果。
- macOS 桌面端可以把文本粘贴到当前应用。
- macOS 桌面端可以把识别出的任务直接交给 Claude Code 或 Codex CLI，并把执行结果保存到本地。
- Agent 运行中、完成、失败和等待确认状态可以回写到设备屏幕，并支持声音提醒。
- 已适配立创·实战派 ESP32-S3 开发板。
- 已验证火山引擎 ASR 配置和 macOS 本地打包流程。

尚在规划和开发中的 AgentStick 能力：

- 维护任务队列、任务状态和完成提醒。
- 支持“后台执行完成后提醒我”的桌面通知。
- 支持多个 Agent 后端和可配置任务模板。

### 在 macOS 上使用语音 Agent

1. 先安装并登录 `claude` 或 `codex` CLI。
2. 打开 AgentStick 设置，在 Agent 区域选择 Claude Code 或 Codex，并选择要操作的工程目录。
3. 在菜单栏的 Output 菜单选择 Agent Run；有侧键的设备也可以在空闲时用侧键切换。
4. 按住设备录音键说出任务，确认识别文本后，桌面 App 会在所选工程目录中运行 Agent。

默认使用安全授权模式：Claude/Codex 请求执行高权限命令或扩大文件访问范围时，App 会打开“Agent 任务历史”，可直接点击“允许”或“拒绝”。如需完全无人值守，可在设置的 Agent 区域勾选“绕过 Agent 授权（高风险）”；开启后 Agent 不再逐项询问。

任务中心同时处理 Agent 主动确认（例如提交、推送或部署）、选项与自由文本问题、敏感字段输入，以及 MCP 网页登录和表单请求。允许或回答后会继续原 Claude session / Codex thread，不会把等待用户的文字误记为已完成任务。

Agent Run 会在同一 Agent 和工程目录下自动识别承接语句与任务相似度，决定新建或恢复 Claude session / Codex thread。语音以“新会话”开头可强制新建，以“继续会话”开头可强制接续最近会话；“清空历史”也会清除本地会话续接索引。

开启“长期记忆”后，AgentStick 会从“记住、以后、我偏好、这个项目默认”等明确表达中保存稳定习惯和项目上下文，并在后续 Claude/Codex 任务中提供相关记忆。设置页可查看或清除记忆；API Key、密码等敏感内容和完整对话原文不会被自动保存。

执行结果保存在 `~/Library/Application Support/AgentStick/Tasks/`。App 会自动搜索 Homebrew、NVM、Volta、Bun 等常见安装位置，也会识别 Codex.app 或 ChatGPT.app 内置的 Codex CLI。自定义 CLI 命令仍可通过 `config.toml` 的 `[agents.*]` 配置。

## 架构草图

```text
ESP32 设备
  - 按键
  - 麦克风
  - 屏幕状态
  - BLE 音频 / 状态传输
        |
        v
桌面 App
  - BLE 配对与连接
  - ASR 语音识别
  - 任务解析
  - Agent 路由
  - 通知与结果展示
        |
        v
桌面 Agent
  - Codex
  - Claude Code
  - 其他本地自动化/开发助手
```

## 项目结构

```text
firmware/          ESP-IDF 固件，当前适配 ESP32-S3
desktop/macos/    Swift / AppKit macOS 菜单栏应用
desktop/windows/  C++20 / Win32 Windows 桌面端工作区
desktop/linux/    Linux 桌面端占位工作区
website/          Vue + Vite 网站、下载页、appcast 和浏览器刷机入口
docs/             BLE 协议、ASR、硬件适配和发布文档
scripts/          固件资源处理、打包、DMG/MSI、appcast 更新脚本
```

## 硬件适配

当前重点适配的是立创·实战派 ESP32-S3 开发板：

- 模组：ESP32-S3-WROOM-1-N16R8
- 存储：8MB PSRAM、16MB Flash
- 主按键：GPIO0
- I2C：SDA GPIO1，SCL GPIO2
- 音频 ADC：ES7210
- 音频 DAC：ES8311
- LCD：ST7789，320 x 240
- IO 扩展：PCA9557，地址 `0x19`

适配记录见：

- `docs/lichuang-esp32s3-xiaozhi-notes.md`
- `docs/lichuang-local-adaptation-summary.md`

## 固件构建

固件使用 ESP-IDF。当前本地验证环境为 ESP-IDF 5.5.x。

默认固件配置面向立创·实战派 ESP32-S3 开发板：

```sh
cd firmware
. /Users/fengsu/esp/esp-idf/export.sh
idf.py set-target esp32s3
idf.py build
```

如果要构建 M5Stack StickS3 固件，建议使用独立 build 目录和 M5Stack defaults，避免覆盖立创板构建产物：

```sh
cd firmware
. /Users/fengsu/esp/esp-idf/export.sh
idf.py -B build-m5stack \
  -D SDKCONFIG=build-m5stack/sdkconfig \
  -D SDKCONFIG_DEFAULTS='sdkconfig.defaults;sdkconfig.defaults.m5stack' \
  build
```

烧录并打开串口监视：

```sh
idf.py -p /dev/cu.usbmodemXXXX flash monitor
```

立创板如果自动下载不稳定，可以手动进入下载模式：

1. 按住 BOOT / 用户键。
2. 点按 RESET。
3. 开始烧录后松开 BOOT。

## macOS 桌面端

macOS 应用是 Swift / AppKit 菜单栏程序。

```sh
cd desktop/macos
swift build
swift run AgentStickApp
```

当前配置文件路径仍沿用 VoiceStick：

```text
~/Library/Application Support/AgentStick/config.toml
```

可从示例创建：

```sh
mkdir -p "$HOME/Library/Application Support/AgentStick"
cp desktop/macos/Config/config.example.toml "$HOME/Library/Application Support/AgentStick/config.toml"
```

常用配置：

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

不要提交任何 API Key。

## 与 VoiceStick 的关系

AgentStick 目前直接参考并继承 VoiceStick 的工程结构和大量基础能力：

- BLE GATT 协议
- ESP32 音频采集与 Opus 编码
- 桌面端 BLE 连接
- ASR WebSocket 调用
- 文本粘贴和悬浮状态显示
- OTA / 发布脚本基础结构

后续开发会逐步把产品定位、配置命名、桌面端交互和 Agent 调度能力从 VoiceStick 语音输入场景中拆出来，形成 AgentStick 自己的任务入口体验。

原项目地址：

- [78/voicestick](https://github.com/78/voicestick)

## 相关文档

- `docs/protocol.md`：BLE 音频、状态、控制和 OTA 协议
- `docs/volcengine-asr.md`：火山引擎 ASR 对接笔记
- `docs/lichuang-esp32s3-xiaozhi-notes.md`：立创 ESP32-S3 硬件和 xiaozhi 参考记录
- `docs/lichuang-local-adaptation-summary.md`：本地立创板适配整理
- `docs/release.md`：macOS、Windows、固件和网站发布流程
- `desktop/windows/README.md`：Windows 端构建说明
- `website/README.md`：网站和 appcast 说明

## 开发方向

近期优先级：

1. 增加可持久化的任务队列，以及 needs input 后的语音续答。
2. 增加更完整的桌面通知和任务历史界面。
3. 完善 Codex / Claude Code 的会话续接能力。
4. 继续完善立创 ESP32-S3 和 M5Stack StickS3 的板型抽象。
5. 逐步把配置路径、App 名称和 UI 文案从 VoiceStick 迁移到 AgentStick。
