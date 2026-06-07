# VoiceStick

VoiceStick 是一个把 M5Stack StickS3 变成蓝牙按键语音输入器的项目。按住设备正面按钮说话，松开后桌面端会接收设备通过 BLE 传来的 Opus 音频，把音频转发给语音识别服务，并在短暂确认倒计时后把识别结果粘贴到当前光标所在的输入框中。默认会在粘贴后自动按下 Return，也可以在设置里关闭。

这个仓库同时包含 StickS3 固件、macOS / Windows 桌面端、官网与更新源，以及发布脚本。

## 它是做什么的

VoiceStick 的目标是做一个独立的“按键说话 -> 自动输入文字”的小硬件：

1. StickS3 负责蓝牙广播、按钮事件、麦克风采集、Opus 编码、屏幕状态显示和 BLE OTA。
2. 桌面端负责配对设备、接收音频、封装 Ogg Opus、连接 ASR、显示识别状态、确认/取消最终文本，并把文本输入到当前应用。
3. 网站负责产品首页、下载入口、浏览器 USB 刷固件，以及 Sparkle / WinSparkle appcast 更新源。

当前音频链路：

```text
StickS3 麦克风 -> ES8311/I2S PCM -> Opus -> BLE -> 桌面端 -> Ogg Opus -> ASR -> 粘贴文本
```

桌面端不会把 Opus 解码回 PCM，而是直接封装为 Ogg Opus 后发送给语音识别服务。

## 项目结构

```text
firmware/          ESP-IDF 固件，面向 M5Stack StickS3 / ESP32-S3
desktop/macos/    Swift / AppKit macOS 菜单栏应用
desktop/windows/  C++20 / Win32 Windows 桌面端工作区
desktop/linux/    Linux 桌面端占位工作区
website/          Vue + Vite 官网、下载页、appcast 和浏览器刷机入口
docs/             BLE 协议、ASR、发布流程等文档
scripts/          固件资源处理、打包、DMG/MSI、appcast 更新脚本
```

## 主要功能

- StickS3 蓝牙广播名为 `VS-XXXX`，其中 `XXXX` 来自设备 eFuse MAC 的最后两个字节。
- 桌面端只连接已配对的 `VS-XXXX` 设备，支持同时维护多个已配对设备。
- 正面按钮是协议里的 `primary`：默认按住录音、松开结束；也支持 `click_to_talk` 点击开始/停止。
- 侧边按钮是协议里的 `secondary`：可取消识别/确认中的文本，空闲时可恢复上一次可恢复的输入确认。
- 固件从 ES8311 麦克风采集 16 kHz / 16 bit / mono PCM，编码为 Opus 后通过 BLE notification 发送。
- 桌面端支持直连火山引擎 ASR，或通过 VoiceStick Cloud relay 转发。
- 识别过程中桌面端显示悬浮状态与菜单栏状态，固件屏幕显示 pairing、ready、listening、thinking、pending confirmation、error、电量等状态。
- 最终文本进入约 1.2 秒确认倒计时；倒计时内可暂停、确认或取消自动粘贴。
- 支持调试音频缓存，把有效识别会话保存为可播放的 Ogg Opus 文件。
- 支持固件更新检查和 BLE OTA：应用启动、设备连接/重连、手动刷新时可发现新固件。
- 固件屏幕 30 秒无操作后变暗；电池供电时 5 分钟后深度睡眠，USB 或充电时保持暗屏待机。

## 硬件目标

- 开发板：M5Stack StickS3 / ESP32-S3-PICO-1-N8R8
- 正面按钮：GPIO11，协议角色 `primary`，用于 push-to-talk 和深度睡眠唤醒
- 侧边按钮：GPIO12，协议角色 `secondary`
- PMIC IRQ：GPIO13
- 音频 Codec：ES8311 over I2S，16 kHz / 16 bit / mono
- 屏幕：135 x 240 ST7789P3 竖屏
- LCD 背光：GPIO38 PWM

主要引脚定义在 `firmware/components/stick_s3_board/include/stick_s3_board.h`。

## 交互模型

| 状态 | 正面按钮 | 侧边按钮 |
| --- | --- | --- |
| 未配对 / 未连接 | 不录音，屏幕显示 `VS-XXXX` | 无有效动作 |
| 已连接空闲 | 按住录音，或点击开始录音 | 恢复上一次输入确认 |
| 录音中 | 松开结束录音，或再次点击结束 | 不取消当前录音 |
| 识别 / 收尾中 | 新录音会被忽略 | 取消正在进行的识别 |
| 自动确认倒计时 | 暂停自动粘贴，保留待确认文本 | 取消待确认文本 |
| 手动待确认 | 确认并粘贴 | 取消待确认文本 |

固件只上报按钮事实，例如 `button_down` / `button_up` 和按钮角色。业务含义由桌面端状态机决定，然后桌面端通过 `ui_state` 把权威显示状态写回固件。

## BLE 协议概览

GATT Service UUID：

```text
8f2f0b84-6e6f-4b23-88f7-3a3ceafc5100
```

| 名称 | UUID | 方向 | 属性 |
| --- | --- | --- | --- |
| `audio_tx` | `8f2f0b84-6e6f-4b23-88f7-3a3ceafc5101` | StickS3 -> 桌面端 | notify |
| `state_tx` | `8f2f0b84-6e6f-4b23-88f7-3a3ceafc5102` | StickS3 -> 桌面端 | notify |
| `control_rx` | `8f2f0b84-6e6f-4b23-88f7-3a3ceafc5103` | 桌面端 -> StickS3 | write without response |
| `ota_rx` | `8f2f0b84-6e6f-4b23-88f7-3a3ceafc5104` | 桌面端 -> StickS3 | write / write without response |
| `ota_tx` | `8f2f0b84-6e6f-4b23-88f7-3a3ceafc5105` | StickS3 -> 桌面端 | notify |

完整帧格式见 `docs/protocol.md`。

## 固件构建

固件使用 ESP-IDF。下面命令假设 ESP-IDF 位于 `~/esp/v5.5.1/esp-idf`，如果你的路径不同请自行替换。

```sh
cd firmware
. "$HOME/esp/v5.5.1/esp-idf/export.sh"
idf.py set-target esp32s3
idf.py build
```

如果 `export.sh` 提示缺少 ESP-IDF Python 虚拟环境，先执行一次安装：

```sh
"$HOME/esp/v5.5.1/esp-idf/install.sh" esp32s3
```

烧录并打开串口监视：

```sh
idf.py -p /dev/cu.usbmodemXXXX flash monitor
```

当前固件使用 OTA 分区表，包含两个 3 MB app slot 和一个保留的 1984 KB `storage` 分区。老版本单 app 分区表的设备需要先通过 USB 完整擦写一次，之后才能使用 BLE OTA：

```sh
idf.py -p /dev/cu.usbmodemXXXX erase-flash flash monitor
```

固件依赖通过 ESP-IDF component manager 声明，主要包括：

- `espressif/button`
- `espressif/esp_codec_dev`
- `78/esp-opus`
- `lvgl/lvgl`

## macOS 桌面端

macOS 应用是一个 Swift Package，目标系统为 macOS 12 或更新版本。

```sh
cd desktop/macos
swift build
swift run VoiceStickApp
```

应用是菜单栏程序，会请求蓝牙权限。文本输入通过剪贴板和模拟 `Command-V` 完成，并可选自动按 Return。如果键盘事件被系统拦截，需要在“系统设置”里给运行终端或应用授予辅助功能权限。

本地配置文件路径：

```text
~/Library/Application Support/VoiceStick/config.toml
```

可从示例创建：

```sh
mkdir -p "$HOME/Library/Application Support/VoiceStick"
cp desktop/macos/Config/config.example.toml "$HOME/Library/Application Support/VoiceStick/config.toml"
```

配置示例：

```toml
asr_provider = "volcengine"
voicestick_api_key = ""
voicestick_cloud_url = "wss://api.xiaozhi.me/voicestick/asr/"
volcengine_api_key = "your_volcengine_access_key"
volcengine_app_key = ""  # set for old-style auth
llm_base_url = "https://api.openai.com/v1"
llm_api_key = "your_openai_compatible_llm_api_key"
llm_model = "gpt-5.5"
interaction_mode = "hold_to_talk"
resource_id = "volc.seedasr.sauc.duration"
asr_hotwords = "小智,VoiceStick"
paired_device_ids = ""
device_theme_colors = ""
device_overlay_positions = ""
auto_enter = true
debug_audio_cache = false

[output]
target = "focused_app"
transform = "original"
translation_target = "en"
```

常用字段：

| 字段 | 说明 |
| --- | --- |
| `asr_provider` | `volcengine` 或 `voicestick_cloud` |
| `volcengine_api_key` | 火山引擎 ASR Access Key，通过 `X-Api-Key`（新版）或 `X-Api-Access-Key`（旧版）发送 |
| `volcengine_app_key` | 火山引擎旧版 App Key。设置后使用旧版认证头 `X-Api-App-Key` + `X-Api-Access-Key`，留空则使用新版 `X-Api-Key` |
| `voicestick_api_key` | VoiceStick Cloud relay API Key，通过 `X-Api-Key` 发送 |
| `voicestick_cloud_url` | Cloud relay WebSocket 地址 |
| `llm_base_url` | OpenAI-compatible LLM API base URL |
| `llm_api_key` | LLM 服务 API Key |
| `llm_model` | LLM 模型名 |
| `interaction_mode` | `hold_to_talk` 或 `click_to_talk` |
| `resource_id` | 火山引擎 ASR resource ID |
| `asr_hotwords` | 逗号分隔的热词，也会作为翻译术语提示传给 LLM |
| `paired_device_ids` | 已配对设备 ID，例如 `C3D8,09AF` |
| `auto_enter` | 粘贴后是否自动按 Return |
| `debug_audio_cache` | 是否保存调试 Ogg Opus 音频 |
| `[output].target` | `focused_app` 或 `subtitle` |
| `[output].transform` | `original` 或 `translate` |
| `[output].translation_target` | 翻译目标语言，例如 `en` 或 `zh-Hans` |

不要提交任何 API Key。

## Windows 桌面端

Windows 端是原生 C++20 / Win32 实现，支持 64 位 Windows 10 1903 / 1909 及更新版本。

当前范围：

- Win32 托盘应用和悬浮窗
- `%APPDATA%\VoiceStick\config.toml` 配置
- `%LOCALAPPDATA%\VoiceStick\DebugAudio` 调试音频缓存
- C++/WinRT BLE 广播扫描
- VoiceStick 协议解析、Ogg Opus 封装、ASR 二进制帧和协调器状态机
- 通过剪贴板和 `SendInput` 输入文本
- 使用 WinSparkle 读取与 macOS 共用的 appcast 更新源

完整 BLE GATT 特征读写仍预留给后续硬件验证。

构建方式见 `desktop/windows/README.md`。

## 网站

`website/` 是 Vue + Vite 项目，提供 VoiceStick 首页、下载入口、appcast 和浏览器刷固件入口。网站使用 `vue-i18n` 支持简体中文和英文，浏览器语言以 `zh` 开头时自动使用中文。

开发：

```sh
cd website
npm install
npm run dev
```

构建：

```sh
cd website
npm run build
```

生成的 `dist/` 部署到 GitHub Pages。根路径 appcast 用于 macOS Sparkle 和 Windows WinSparkle 更新：

```text
https://78.github.io/voicestick/appcast.xml
```

## 配对流程

1. 烧录并启动 StickS3，屏幕会显示 `VS-XXXX`。
2. 启动 macOS 或 Windows 桌面端。
3. 在菜单栏 / 托盘菜单中打开 `Pair Device...`。
4. 从扫描列表里选择对应的 `VS-XXXX` 并点击 `Pair`。
5. 保存后，桌面端会扫描并连接该设备。重复这个流程可以配对多个设备。

也可以手动编辑 `paired_device_ids`。保存多个 ID 时，桌面端会忽略附近未配对的 VoiceStick 设备。

## 调试音频

在配置中启用：

```toml
debug_audio_cache = true
```

macOS 默认输出目录：

```text
~/Library/Application Support/VoiceStick/DebugAudio
```

每个有效识别会话会保存为可播放的 Ogg Opus 文件。短于 0.5 秒的录音会被桌面端丢弃，不会发送给 ASR。

## 发布

VoiceStick 发布包含三个部分：

- macOS 应用：由 GitHub Actions 构建、签名、公证并上传。
- StickS3 固件：由 GitHub Actions 构建，上传到 GitHub Releases 和 Aliyun OSS。
- Windows 应用：在本地 Windows 签名机器上构建和签名 MSI，再上传到对应 GitHub Release。

发布前需要同步更新：

```text
VERSION
firmware/version.txt
```

发布 tag 必须是 `v<VERSION>`，例如 `VERSION=0.2.4` 时 tag 为 `v0.2.4`。

发布流程详见 `docs/release.md`。

## 相关文档

- `docs/protocol.md`：BLE 音频、状态、控制和 OTA 协议
- `docs/volcengine-asr.md`：火山引擎 ASR 对接笔记
- `docs/release.md`：macOS、Windows、固件和网站发布流程
- `desktop/windows/README.md`：Windows 端构建说明
- `website/README.md`：网站和 appcast 说明
