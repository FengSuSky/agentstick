# 立创·实战派 ESP32-S3 与 xiaozhi-esp32 适配记录

本文档记录本次在立创·实战派 ESP32-S3 开发板上的调试结论，以及 `78/xiaozhi-esp32` 对该板子的适配方式。用途是给后续继续移植当前项目做参考。

## 1. 本次实测结论

- 板子型号：立创·实战派 ESP32-S3 开发板，模块为 ESP32-S3-WROOM-1-N16R8。
- 存储配置：8MB PSRAM、16MB Flash。
- macOS 识别串口：`/dev/cu.usbmodem11301`。
- 当前本地项目的 LCD 诊断固件可以正常启动、背光常亮、PCA9557 可读写、LCD_CS 可拉低，但屏幕像素无变化。
- 刷入 `xiaozhi-esp32 v2.1.0` 的 `lichuang-dev` 固件后，屏幕可以正常显示“配网模式”。
- 因此，屏幕硬件、排线、背光、电源和基础显示链路是好的；当前本地项目后续应继续对齐 xiaozhi 的 LCD/显示栈细节。

## 2. 板子硬件要点

来自立创资料、原理图和 xiaozhi 适配代码的关键信息如下。

| 模块 | 型号/说明 | 关键点 |
| --- | --- | --- |
| 主控 | ESP32-S3-WROOM-1-N16R8 | 8MB PSRAM、16MB Flash |
| LCD | ST7789 | SPI 接口，xiaozhi 使用 320x240、swap_xy=true |
| 触摸 | FT6336 / FT5x06 兼容 | I2C 接口 |
| 姿态传感器 | QMI8658 | I2C 接口，地址资料中标为 `0x6a` |
| 音频 DAC | ES8311 | I2C 控制 + I2S 音频 |
| 音频 ADC | ES7210 | I2C 控制 + TDM/I2S 麦克风输入 |
| IO 扩展 | PCA9557 | I2C 地址 `0x19`，控制 LCD_CS、PA_EN、摄像头电源等 |
| 背光 | GPIO42 | 低电平开背光，xiaozhi 配置为 output invert |
| BOOT/用户键 | GPIO0 | 烧录时按住进入下载模式 |

注意：外壳资源图里屏幕标注出现过 `204*320`，但立创 LCD 资料和 xiaozhi 适配实际使用 `320x240`，并且 xiaozhi 官方固件实测能显示。因此后续移植时以 `320x240 + swap_xy=true` 作为有效配置。

## 3. 烧录方式

这块板子有时自动下载不稳定，实测可靠方式是手动进下载模式：

1. USB-C 连接电脑。
2. 按住下面的“用户/自定义/BOOT”键。
3. 点按一下“复位/RESET”键。
4. BOOT 继续按住，开始烧录。
5. 看到写入百分比后松开 BOOT。

常用命令：

```bash
. /Users/fengsu/esp/esp-idf/export.sh
idf.py -p /dev/cu.usbmodem11301 flash
idf.py -p /dev/cu.usbmodem11301 monitor
```

如果 monitor 显示 `waiting for download`，说明还停在下载模式；松开 BOOT 后点按 RESET 即可启动应用。

## 4. xiaozhi-esp32 中的板型入口

仓库：`https://github.com/78/xiaozhi-esp32`

本次实测使用版本：`v2.1.0`。

选择 `v2.1.0` 的原因：

- 当前 main / v2.2.x 要求 ESP-IDF `>=5.5.2`。
- 本机 ESP-IDF 为 `5.5.1`。
- `v2.1.0` 要求 `>=5.4.0`，可以直接构建。

相关文件：

```text
main/Kconfig.projbuild
main/CMakeLists.txt
main/boards/lichuang-dev/config.json
main/boards/lichuang-dev/config.h
main/boards/lichuang-dev/lichuang_dev_board.cc
```

Kconfig 中板型为：

```text
CONFIG_BOARD_TYPE_LICHUANG_DEV_S3
```

CMake 中对应目录：

```text
BOARD_TYPE = lichuang-dev
```

`config.json` 中构建名：

```json
{
  "target": "esp32s3",
  "builds": [
    {
      "name": "lichuang-dev",
      "sdkconfig_append": [
        "CONFIG_USE_DEVICE_AEC=y",
        "CONFIG_CAMERA_GC0308=y",
        "CONFIG_CAMERA_GC0308_AUTO_DETECT_DVP_INTERFACE_SENSOR=y",
        "CONFIG_CAMERA_GC0308_DVP_YUV422_640X480_16FPS=y"
      ]
    }
  ]
}
```

## 5. xiaozhi 的关键引脚配置

来自 `main/boards/lichuang-dev/config.h`。

### I2C 与音频 Codec

```c
#define AUDIO_CODEC_I2C_SDA_PIN  GPIO_NUM_1
#define AUDIO_CODEC_I2C_SCL_PIN  GPIO_NUM_2
#define AUDIO_CODEC_ES8311_ADDR  ES8311_CODEC_DEFAULT_ADDR
#define AUDIO_CODEC_ES7210_ADDR  0x82
```

音频 I2S：

```c
#define AUDIO_I2S_GPIO_MCLK GPIO_NUM_38
#define AUDIO_I2S_GPIO_WS   GPIO_NUM_13
#define AUDIO_I2S_GPIO_BCLK GPIO_NUM_14
#define AUDIO_I2S_GPIO_DIN  GPIO_NUM_12
#define AUDIO_I2S_GPIO_DOUT GPIO_NUM_45
```

### LCD

```c
#define DISPLAY_WIDTH   320
#define DISPLAY_HEIGHT  240
#define DISPLAY_MIRROR_X true
#define DISPLAY_MIRROR_Y false
#define DISPLAY_SWAP_XY true
#define DISPLAY_OFFSET_X  0
#define DISPLAY_OFFSET_Y  0
#define DISPLAY_BACKLIGHT_PIN GPIO_NUM_42
#define DISPLAY_BACKLIGHT_OUTPUT_INVERT true
```

SPI 引脚在板级代码里配置：

```c
MOSI = GPIO40
SCLK = GPIO41
DC   = GPIO39
CS   = GPIO_NUM_NC // 实际由 PCA9557 控制
```

### 摄像头

xiaozhi v2.1.0 的 `lichuang-dev` 同时适配了 GC0308 摄像头：

```c
#define CAMERA_PIN_XCLK GPIO_NUM_5
#define CAMERA_PIN_SIOD GPIO_NUM_1
#define CAMERA_PIN_SIOC GPIO_NUM_2
#define CAMERA_PIN_D7 GPIO_NUM_9
#define CAMERA_PIN_D6 GPIO_NUM_4
#define CAMERA_PIN_D5 GPIO_NUM_6
#define CAMERA_PIN_D4 GPIO_NUM_15
#define CAMERA_PIN_D3 GPIO_NUM_17
#define CAMERA_PIN_D2 GPIO_NUM_8
#define CAMERA_PIN_D1 GPIO_NUM_18
#define CAMERA_PIN_D0 GPIO_NUM_16
#define CAMERA_PIN_VSYNC GPIO_NUM_3
#define CAMERA_PIN_HREF GPIO_NUM_46
#define CAMERA_PIN_PCLK GPIO_NUM_7
```

## 6. PCA9557 的作用

xiaozhi 在 `lichuang_dev_board.cc` 中定义了一个简单的 PCA9557 类：

```c
WriteReg(0x01, 0x03);
WriteReg(0x03, 0xf8);
```

含义：

- PCA9557 地址：`0x19`
- 输出寄存器：`0x01`
- 方向寄存器：`0x03`
- `0xf8` 表示 IO0、IO1、IO2 为输出，其余为输入

xiaozhi 使用的几个输出位：

| PCA9557 位 | 作用 | xiaozhi 行为 |
| --- | --- | --- |
| IO0 | LCD_CS | LCD reset 后拉低 |
| IO1 | PA_EN / 功放使能 | 音频输出 enable 时拉高 |
| IO2 | 摄像头电源/使能 | 初始化摄像头前拉低 |

LCD 初始化时最关键的一句：

```c
esp_lcd_panel_reset(panel);
pca9557_->SetOutputState(0, 0);
esp_lcd_panel_init(panel);
```

也就是：ST7789 reset 后、init 前，把 LCD_CS 拉低。

## 7. xiaozhi 的 LCD 初始化流程

核心流程来自 `InitializeSt7789Display()`：

1. 初始化 SPI3：

```c
buscfg.mosi_io_num = GPIO_NUM_40;
buscfg.miso_io_num = GPIO_NUM_NC;
buscfg.sclk_io_num = GPIO_NUM_41;
buscfg.max_transfer_sz = DISPLAY_WIDTH * DISPLAY_HEIGHT * sizeof(uint16_t);
spi_bus_initialize(SPI3_HOST, &buscfg, SPI_DMA_CH_AUTO);
```

2. 创建 SPI LCD IO：

```c
io_config.cs_gpio_num = GPIO_NUM_NC;
io_config.dc_gpio_num = GPIO_NUM_39;
io_config.spi_mode = 2;
io_config.pclk_hz = 80 * 1000 * 1000;
io_config.trans_queue_depth = 10;
io_config.lcd_cmd_bits = 8;
io_config.lcd_param_bits = 8;
```

3. 创建 ST7789 panel：

```c
panel_config.reset_gpio_num = GPIO_NUM_NC;
panel_config.rgb_ele_order = LCD_RGB_ELEMENT_ORDER_RGB;
panel_config.bits_per_pixel = 16;
esp_lcd_new_panel_st7789(panel_io, &panel_config, &panel);
```

4. 初始化显示方向与颜色：

```c
esp_lcd_panel_reset(panel);
pca9557_->SetOutputState(0, 0);
esp_lcd_panel_init(panel);
esp_lcd_panel_invert_color(panel, true);
esp_lcd_panel_swap_xy(panel, true);
esp_lcd_panel_mirror(panel, true, false);
esp_lcd_panel_disp_on_off(panel, true);
```

5. 交给显示抽象：

```c
display_ = new SpiLcdDisplay(panel_io, panel,
    320, 240, 0, 0, true, false, true);
```

## 8. xiaozhi 官方固件实测日志

刷入 `xiaozhi-esp32 v2.1.0 lichuang-dev` 后，启动日志中出现：

```text
Board: UUID=... SKU=lichuang-dev
LcdDisplay: Turning display on
LcdDisplay: Initialize LVGL library
LcdDisplay: Adding LCD display
gc0308: Detected Camera sensor PID=0x9b
Esp32Camera: Camera init success
Backlight: Set brightness to 75
WifiConfigurationAp: Access Point started with SSID Xiaozhi-CE01
Application: 配网模式: 手机连接热点 Xiaozhi-CE01，浏览器访问 http://192.168.4.1
```

实物现象：屏幕显示“配网模式”。

这个结果说明：

- 板型选择正确。
- LCD、触摸/显示栈、背光、电源基础链路可用。
- 摄像头也被识别到了 GC0308。
- 后续当前项目移植时，应优先逐项对齐 xiaozhi 的板级初始化。

## 9. 对当前项目后续移植的判断

当前项目之前的诊断已经确认：

- ESP32-S3 正常启动。
- 16MB Flash、8MB PSRAM 识别正常。
- I2C GPIO1/GPIO2 可访问 PCA9557。
- PCA9557 可配置为 `output=0x02 config=0xf8`。
- LCD_CS 可以读回为低电平状态。
- GPIO42 背光常亮正常。

但当前项目刷色无显示，而 xiaozhi 官方固件能显示。这说明后续重点不是硬件排查，而是迁移细节：

1. 完整复用 xiaozhi 的 ST7789 初始化顺序。
2. 复用 `SpiLcdDisplay`/LVGL port 的 flush 方式或对齐像素格式处理。
3. 确认当前项目的 LCD flush 是否与 xiaozhi 一样在 RGB565 字节序上处理。
4. 音频引脚也必须从原 M5Stick 风格改为立创板引脚：
   - MCLK 38
   - WS 13
   - BCLK 14
   - DIN 12
   - DOUT 45
5. 如果需要摄像头，后续应移植 GC0308 相关配置。

当前项目的 `firmware` 仍然以 M5Stick S3 为板级基础：`stick_s3_board` 里有 M5PM1 PMIC、旧音频引脚、旧按键/电源中断语义。立创实战派 ESP32-S3 能跑 xiaozhi 的 `lichuang-dev`，所以目标不是继续硬件排查，而是把 xiaozhi 已验证的板级初始化搬到当前项目的硬件抽象层里。

## 10. 当前项目适配计划

### 10.1 建立板型边界

目标：不要在业务代码里到处判断立创板，优先把差异收敛在板级组件里。

当前相关文件：

```text
firmware/components/stick_s3_board/include/stick_s3_board.h
firmware/components/stick_s3_board/stick_s3_board.c
firmware/components/ui_status/ui_status.c
firmware/components/audio_pipeline/audio_pipeline.c
firmware/main/main.c
```

建议把 `stick_s3_board` 组件逐步重命名或抽象成更通用的 `board` / `voice_board`。第一阶段可以先保留现有 API，让 `main.c`、`audio_pipeline.c`、`ui_status.c` 少动，只把内部实现切到立创板：

- I2C：SDA `GPIO1`，SCL `GPIO2`。
- PCA9557：地址 `0x19`。
- LCD CS：PCA9557 IO0，reset 后、init 前拉低。
- PA_EN：PCA9557 IO1，后续给扬声器/功放用。
- 摄像头电源：PCA9557 IO2，第一版可暂时不启用。

### 10.2 去掉 M5PM1 依赖

当前 `stick_s3_board.c` 里大量逻辑是 M5PM1：

- 电池电压。
- USB/VBUS 检测。
- 充电状态。
- PMIC IRQ。
- 深睡前关 LDO。

立创板笔记里没有 M5PM1，所以第一版适配应把这些能力降级为“不可用但不阻塞启动”：

- `battery_level` 返回固定值或 `ESP_ERR_NOT_SUPPORTED`。
- `battery_charging` / `usb_powered` 返回 false 或不可用。
- `clear_power_irqs` 返回 `ESP_ERR_NOT_SUPPORTED`。
- `prepare_deep_sleep` 只关闭背光/显示，不碰 PMIC。

对应 `main.c` 里也要调整：`init_pmic_irq()` 不应作为立创板必需步骤，否则会卡在不存在的 PMIC IRQ 语义上。

### 10.3 显示栈优先完全对齐 xiaozhi

当前 `ui_status.c` 的参数大体接近，但第一轮建议严格对齐 xiaozhi：

- `LCD_H_RES = 320`。
- `LCD_V_RES = 240`。
- `swap_xy = true`。
- `mirror_x = true`。
- `mirror_y = false`。
- `invert_color = true`。
- SPI host：`SPI3_HOST`。
- MOSI `GPIO40`。
- SCLK `GPIO41`。
- DC `GPIO39`。
- CS `GPIO_NUM_NC`，由 PCA9557 控制。
- Backlight `GPIO42`，低电平点亮，LEDC invert 保持 true。
- SPI mode `2`。
- `pclk_hz` 先改为 xiaozhi 的 `80MHz`。

当前 `ui_status.c` 里 `LCD_DIAGNOSTIC_ONLY true` 会直接进入诊断任务，不跑完整 LVGL UI。适配阶段可以先保留诊断，但显示打通后要关掉它，恢复正常 UI。

### 10.4 LCD 验证顺序

建议分三步，不要一上来调完整 UI：

1. 只初始化 I2C + PCA9557 + 背光，确认日志读回 `output=0x02 config=0xf8`。
2. ST7789 init 后刷纯色/色条，确认像素变化。
3. 关闭 `LCD_DIAGNOSTIC_ONLY`，验证 LVGL 图标、文字、BLE 状态显示。

如果第二步仍黑屏，优先对比这些点：

- CS 是否在 `esp_lcd_panel_reset(panel)` 后、`esp_lcd_panel_init(panel)` 前拉低。
- `spi_mode` 是否为 2。
- RGB565 是否还需要 `lv_draw_sw_rgb565_swap`。
- `pclk_hz` 20MHz vs 80MHz 的差异。
- `esp_lcd_panel_set_gap` 是否为 0,0。

### 10.5 音频改成 ES8311 + ES7210 架构

当前项目只按 ES8311 ADC 模式在读麦克风，而且引脚还是旧板：

- 当前 MCLK `18`，应改 `38`。
- 当前 BCLK `17`，应改 `14`。
- 当前 LRCK `15`，应改 `13`。
- 当前 DIN/DOUT `14/16`，应改为：
  - MCU DIN / 麦克风输入：`GPIO12`。
  - MCU DOUT / 播放输出：`GPIO45`。

但立创板的麦克风输入实际是 ES7210，ES8311 主要是 DAC/输出。第一版如果只需要录音，重点应验证 `esp_codec_dev` 是否已有 ES7210 支持；若没有，要么引入对应 codec 组件，要么参考 xiaozhi 的音频板级代码迁移 ES7210 初始化。

### 10.6 按钮策略重新确认

当前项目配置：

- front button `GPIO11`。
- side button `GPIO12`。
- PMIC IRQ `GPIO13`。

但立创笔记只明确 BOOT/用户键为 `GPIO0`。同时 `GPIO12/13/14/45` 已经在音频里使用，不能继续当按钮。

第一版建议：

- 主按钮先用 `GPIO0`。
- 次按钮先禁用，或等查原理图确认。
- 深睡唤醒也用 `GPIO0`。
- 删除或屏蔽 PMIC IRQ 逻辑。

### 10.7 摄像头、触摸、姿态传感器延后

xiaozhi 已证明 GC0308 可识别，但当前 VoiceStick 主功能是 BLE + 录音 + 小屏状态。建议不要第一轮引入摄像头和触摸，避免扩大变量。

后续阶段再加：

- GC0308 摄像头。
- FT6336 / FT5x06 触摸。
- QMI8658 姿态。

## 11. 阶段性里程碑

### M1：能稳定启动

- 不再依赖 M5PM1。
- I2C 能初始化。
- PCA9557 能读写。
- 背光可控。
- 不因电池/PMIC IRQ 报错中断。

### M2：屏幕有像素

- 复刻 xiaozhi ST7789 初始化。
- 色条/纯色可显示。
- 确认 CS、SPI mode、方向、颜色反转。

### M3：恢复当前 UI

- 关闭 `LCD_DIAGNOSTIC_ONLY`。
- LVGL UI 正常显示。
- BLE pairing / ready / recording 状态能刷新。

### M4：录音链路

- 改 I2S 引脚。
- 迁移 ES7210 输入。
- 按住 GPIO0 能录音。
- Mac/桌面端能收到 Opus 音频。

### M5：电源和体验收尾

- 电池/USB 状态降级或补真实检测。
- 深睡逻辑适配 GPIO0。
- 次按钮、功放 PA_EN、音频输出按需补齐。

## 12. 最高风险点

第一是音频：当前代码按 ES8311 ADC 读麦，立创板录音侧是 ES7210，这不是只改 GPIO 就能完整解决。

第二是电源：当前主程序默认有 PMIC IRQ 和电池逻辑，立创板没有同样的 M5PM1 语义，必须让这些功能可选或降级。

第三是显示：本次实测已经证明硬件没坏，所以显示黑屏最可能是 ST7789 初始化顺序、CS 时序、SPI mode、RGB565 字节序其中之一。

建议实际开工顺序：先板级/PCA9557，再 LCD，再按钮，再音频。这样每一步都有清晰肉眼或日志反馈，不会把四个硬件问题搅在一起。
