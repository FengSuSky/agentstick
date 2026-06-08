# 立创 ESP32-S3 本地适配整理

本文档整理当前本地代码相对 `origin/main` 的主要差异，方便后续继续基于本项目开发。硬件考证和 xiaozhi-esp32 参考细节见 `docs/lichuang-esp32s3-xiaozhi-notes.md`。

## 1. 背景

上游 `origin/main` 的固件主要面向 M5Stack StickC / StickS3 一类硬件。本次本地适配目标是立创·实战派 ESP32-S3 开发板：

- 模组：ESP32-S3-WROOM-1-N16R8
- 存储：8MB PSRAM、16MB Flash
- 串口：`/dev/cu.usbmodem11301`
- 蓝牙设备名实测：`VS-CE00`

立创板的屏幕、音频 Codec、电源和按键拓扑与上游默认板型不同，所以这次不是单纯换 GPIO，而是同时调整了板级初始化、LCD、音频输入、休眠和桌面 ASR 配置。

## 2. 固件差异

### 2.1 板级初始化

相关文件：

- `firmware/components/stick_s3_board/Kconfig`
- `firmware/components/stick_s3_board/include/stick_s3_board.h`
- `firmware/components/stick_s3_board/stick_s3_board.c`

主要变化：

- 新增 `AGENTSTICK_BOARD_M5STACK_STICKS3` / `AGENTSTICK_BOARD_LICHUANG_ESP32S3` 板型选择。
- I2C 改为立创板连接：SDA `GPIO1`，SCL `GPIO2`。
- 主按键改为 BOOT / 用户键：`GPIO0`，低电平按下。
- 侧键当前未定义，`stick_s3_side_button_pressed()` 固定返回 `false`。
- I2S 引脚改为：
  - MCLK `GPIO38`
  - WS / LRCK `GPIO13`
  - BCLK `GPIO14`
  - DIN `GPIO12`
  - DOUT `GPIO45`
- 新增 PCA9557 IO 扩展器支持，地址 `0x19`。
- LCD 片选由 PCA9557 IO0 控制，而不是 ESP32 直连 GPIO。
- M5PM1 PMIC 在立创板上不存在，初始化失败时按无 PMIC 处理，不再中断启动。

需要注意：当前代码仍沿用 `stick_s3_board` 命名，但已经通过 Kconfig 保留 M5Stack StickS3 和立创 ESP32-S3 两个板型。后续可以继续把配置拆到更独立的 board source 文件里。

### 2.2 LCD 显示

相关文件：

- `firmware/components/ui_status/ui_status.c`
- `firmware/components/ui_status/include/ui_status.h`

主要变化：

- ST7789 分辨率使用 `320x240`。
- SPI 使用 `SPI3_HOST`，MOSI `GPIO40`，SCLK `GPIO41`，DC `GPIO39`。
- LCD CS 不走 `cs_gpio_num`，改为 PCA9557 IO0，在 reset 后、panel init 前拉低。
- SPI mode 使用 `2`，像素时钟使用 `80 MHz`。
- 显示方向对齐 xiaozhi 的立创板适配：
  - `swap_xy = true`
  - `mirror_x = true`
  - `mirror_y = false`
- 背光为 `GPIO42`，低电平点亮，所以 PWM 逻辑做了反相。
- 亮度接口重命名为 `ui_status_set_brightness_stop_fade()`，用于在需要时停止渐暗定时器并立即设置亮度。

### 2.3 音频输入

相关文件：

- `firmware/components/audio_pipeline/audio_pipeline.c`
- `firmware/components/stick_s3_board/include/stick_s3_board.h`

主要变化：

- 立创板的麦克风输入使用 ES7210 ADC，而不是 ES8311 ADC。
- ES7210 I2C 地址为 `0x82`。
- 麦克风选择为 `MIC1 | MIC2`，当前宏为 `STICK_S3_ES7210_MIC_SELECT 0x03`。
- ES8311 仍可作为播放侧 Codec 保留，但录音链路切换到 ES7210。
- BLE / Opus / 上层语音协议未做结构性改动。

这是本次“能看到识别文字”的关键修复点。如果后续出现桌面端一直 `Listening` 但没有 `Processing` 或无结果，优先检查设备是否真正发出了有效音频帧。

### 2.4 主循环、按键和休眠

相关文件：

- `firmware/main/main.c`

主要变化：

- 侧键逻辑使用 `#ifdef STICK_S3_PIN_BUTTON_SIDE` 保护。
- PMIC IRQ / 电池刷新逻辑使用 `#ifdef STICK_S3_PIN_PMIC_IRQ` 保护。
- 立创板当前关闭 light sleep，避免无 PMIC / 按键 / 唤醒链路不一致导致设备行为异常。

当前硬件只有前键可用，所以“最终文本等待确认”状态下没有独立侧键取消。后续可以考虑为立创板设计专门交互，例如前键短按发送、长按取消，或增加超时自动发送。

### 2.5 Flash 配置

相关文件：

- `firmware/sdkconfig.defaults`
- `firmware/sdkconfig.defaults.m5stack`

主要变化：

- 默认 `sdkconfig.defaults` 面向立创 ESP32-S3，Flash size 为 `16MB`。
- `sdkconfig.defaults.m5stack` 提供 M5Stack StickS3 覆盖配置，Flash size 为 `8MB`。

## 3. macOS 桌面端差异

### 3.1 火山 ASR App Key

相关文件：

- `desktop/macos/Sources/AgentStickApp/AppConfig.swift`
- `desktop/macos/Sources/AgentStickApp/ASRWebSocketClient.swift`
- `desktop/macos/Sources/AgentStickApp/SettingsWindowController.swift`
- `desktop/macos/Config/config.example.toml`

主要变化：

- 配置增加 `volcengine_app_key`。
- ASR WebSocket 在设置 App Key 时发送：
  - `X-Api-App-Key`
  - `X-Api-Access-Key`
  - `X-Api-Connect-Id`
- 这是为了匹配当前火山实时 ASR WebSocket 鉴权方式。实测缺少 `X-Api-App-Key` 时服务端会返回 `400 Bad Request`。

用户当前本机配置位于：

```text
/Users/fengsu/Library/Application Support/AgentStick/config.toml
```

关键配置：

```toml
asr_provider = "volcengine"
volcengine_api_key = "..."
volcengine_app_key = "..."
volcengine_resource_id = "volc.seedasr.sauc.duration"
interaction_mode = "hold_to_talk"
paired_device_ids = "CE00"

[output]
target = "focused_app"
transform = "original"
```

### 3.2 macOS 打包签名

相关文件：

- `scripts/build-macos.sh`
- `scripts/make-dmg.sh`

主要变化：

- 没有 Developer ID 证书、使用 ad-hoc 签名时，不再传 `--options runtime`。
- 原因是 ad-hoc + hardened runtime 会导致 Sparkle framework 在本地安装后被 dyld 拒绝加载。

已生成并验证过的本地包：

```text
/Users/fengsu/work/agentstick/build/AgentStick-0.3.4.app
/Users/fengsu/work/agentstick/build/AgentStick-0.3.4.dmg
```

## 4. 当前已验证

固件：

- 立创默认配置 `idf.py build` 构建通过。
- M5Stack 配置构建通过：

```sh
idf.py -B build-m5stack \
  -D SDKCONFIG=build-m5stack/sdkconfig \
  -D SDKCONFIG_DEFAULTS='sdkconfig.defaults;sdkconfig.defaults.m5stack' \
  build
```

- `idf.py -p /dev/cu.usbmodem11301 flash` 烧录成功。
- monitor 中看到：
  - I2C 使用 `sda=1`、`scl=2`
  - PCA9557 可读写
  - LCD CS 可拉低
  - display ready
  - BLE 设备 `VS-CE00` 初始化并连接
  - audio pipeline ready
- 实机确认语音可以被桌面端识别成文字。

桌面端：

- 火山 ASR 配置已验证可握手并返回会话事件。
- macOS app 可启动。
- 关闭 `Press Return After Paste` 后，不再自动发送聊天消息。
- 当前自动粘贴行为正常。

## 5. 当前行为说明

- AgentStick 的自动粘贴逻辑会临时写入剪贴板、发送 `Cmd+V`，然后恢复原剪贴板；它不是“把识别结果永久复制到剪贴板”。
- `Press Return After Paste` 会在粘贴后发送 Return，适合搜索框或命令框，但在聊天软件里会自动发送消息。
- 因为立创板没有独立侧键，涉及 `Front: Send / Side: Cancel` 的交互在这块板上需要重新设计。

## 6. 后续整理建议

建议按优先级继续做这些收尾：

1. 继续把 M5Stack StickS3 与 Lichuang ESP32-S3 的 GPIO、Codec、LCD、PMIC 差异拆成独立 board source 文件，减少 `#if` 分支。
2. 给 CI 增加两个固件构建矩阵：立创 ESP32-S3 和 M5Stack StickS3。
3. 为无侧键设备设计独立交互，尤其是最终文本确认、取消和误触处理。
4. 给 GPIO0 加更明确的消抖或状态机保护，避免释放录音时误进入 `showPausedFinal`。
5. 继续清理 LCD 调试期辅助代码，只保留必要初始化和日志。
6. 在 macOS app 中增加“粘贴失败诊断”，例如提示辅助功能权限、前台 app 是否可输入、是否启用自动回车。
7. README 后续建议分成“用户使用说明”和“开发/移植说明”，避免硬件适配细节挤进首页。
