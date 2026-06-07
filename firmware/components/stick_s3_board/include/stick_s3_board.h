#pragma once

#include <stdbool.h>
#include "esp_err.h"
#include "driver/i2c_master.h"

/* ── Lichuang ESP32-S3 board pin mapping ──
 * Main button: BOOT/USER key = GPIO0 (active-low)
 * Side button: not available on this board (GPIO12 reused for I2S)
 * No M5PM1 PMIC on this board
 */
#define STICK_S3_PIN_BUTTON_FRONT 0
/* Side button not wired; leave STICK_S3_PIN_BUTTON_SIDE undefined */

#define STICK_S3_PIN_I2C_SCL 2
#define STICK_S3_PIN_I2C_SDA 1

/* I2S audio pins (Lichuang ES8311 DAC + ES7210 ADC wiring) */
#define STICK_S3_PIN_ES8311_MCLK 38
#define STICK_S3_PIN_ES8311_BCLK 14
#define STICK_S3_PIN_ES8311_LRCK 13
/* MCU data-out to codec (speaker path) */
#define STICK_S3_PIN_ES8311_DIN  45
/* Codec data-out to MCU (mic path) */
#define STICK_S3_PIN_ES8311_DOUT 12

/* Lichuang records through ES7210. esp_codec_dev uses 8-bit codec addresses. */
#define STICK_S3_ES7210_ADDR 0x82
#define STICK_S3_ES7210_MIC_SELECT 0x03 /* MIC1 | MIC2, ordinary I2S mode */

/* LCD SPI – unchanged, already matches Lichuang board */
#define STICK_S3_PIN_LCD_MOSI 40
#define STICK_S3_PIN_LCD_SCK  41
#define STICK_S3_PIN_LCD_DC   39
#define STICK_S3_PIN_LCD_CS   -1    /* PCA9557-controlled */
#define STICK_S3_PIN_LCD_RST  -1
#define STICK_S3_PIN_LCD_BL   42

esp_err_t stick_s3_board_init(void);
i2c_master_bus_handle_t stick_s3_board_i2c_bus(void);
esp_err_t stick_s3_board_lcd_select(bool selected);
esp_err_t stick_s3_board_battery_voltage_mv(int *voltage_mv);
esp_err_t stick_s3_board_vbus_voltage_mv(int *voltage_mv);
esp_err_t stick_s3_board_battery_level(int *level_percent);
esp_err_t stick_s3_board_battery_charging(bool *charging);
esp_err_t stick_s3_board_usb_powered(bool *usb_powered);
esp_err_t stick_s3_board_clear_power_irqs(uint8_t *sys_status);
void stick_s3_board_prepare_deep_sleep(void);
bool stick_s3_front_button_pressed(void);
bool stick_s3_side_button_pressed(void);
