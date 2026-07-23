#include "audio_playback.h"

#include <math.h>
#include <stdbool.h>
#include <string.h>

#include "driver/i2s_std.h"
#include "esp_check.h"
#include "esp_codec_dev.h"
#include "esp_codec_dev_defaults.h"
#include "esp_log.h"
#include "nvs.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "audio_pipeline.h"
#include "stick_s3_board.h"

static const char *TAG = "audio_playback";

#define PLAYBACK_SAMPLE_RATE 16000
#define TONE_BUF_FRAMES     320   /* 20 ms at 16 kHz */
#define PLAY_TASK_STACK      4096
#define PLAY_TASK_PRIO       4
#define TONE_AMPLITUDE       12000 /* ~-3 dBFS for 16-bit PCM */
#define PLAYBACK_VOLUME_DEFAULT 70
#define PLAYBACK_VOLUME_MIN     0
#define PLAYBACK_VOLUME_MAX     100
#define PLAYBACK_NVS_NAMESPACE  "agentstick"
#define PLAYBACK_NVS_VOLUME_KEY "sound_vol"

static bool s_initialized;
static volatile bool s_busy;
static int s_volume = PLAYBACK_VOLUME_DEFAULT;
static TaskHandle_t s_play_task;

/* --- tone definitions --------------------------------------------------- */

typedef struct {
    int freq_hz;     /* 0 = silence */
    int duration_ms;
} tone_segment_t;

static const tone_segment_t s_task_done_segs[] = {
    { 880,  120 },
    {   0,   40 },
    { 1100, 180 },
};

static const tone_segment_t s_task_failed_segs[] = {
    { 440, 180 },
    {   0,  40 },
    { 330, 250 },
};

static const tone_segment_t s_needs_input_segs[] = {
    { 660, 120 },
    {   0,  80 },
    { 660, 120 },
    {   0,  80 },
    { 660, 120 },
};

typedef struct {
    const tone_segment_t *segments;
    int count;
} sound_def_t;

static const sound_def_t s_sounds[] = {
    [AUDIO_PLAYBACK_SOUND_TASK_DONE]    = { s_task_done_segs,    3 },
    [AUDIO_PLAYBACK_SOUND_TASK_FAILED]  = { s_task_failed_segs,  3 },
    [AUDIO_PLAYBACK_SOUND_NEEDS_INPUT]  = { s_needs_input_segs,  5 },
};

/* --- play task ---------------------------------------------------------- */

static void play_task(void *arg)
{
    const audio_playback_sound_t sound = (audio_playback_sound_t)(uintptr_t)arg;
    const sound_def_t *def = &s_sounds[sound];
    bool speaker_enabled = false;

    /* Wait for any active recording session to finish. */
    int wait_ms = 0;
    while (audio_pipeline_is_running() && wait_ms < 3000) {
        vTaskDelay(pdMS_TO_TICKS(50));
        wait_ms += 50;
    }
    if (audio_pipeline_is_running()) {
        ESP_LOGW(TAG, "audio pipeline still running after %d ms, skip playback", wait_ms);
        s_busy = false;
        s_play_task = NULL;
        vTaskDelete(NULL);
        return;
    }

    /* Create I2S TX channel. */
    i2s_chan_handle_t tx_handle = NULL;
    i2s_chan_config_t chan_cfg = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_1, I2S_ROLE_MASTER);
    chan_cfg.auto_clear = true;

    esp_err_t err = i2s_new_channel(&chan_cfg, &tx_handle, NULL);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "create i2s tx channel: %s", esp_err_to_name(err));
        s_busy = false;
        s_play_task = NULL;
        vTaskDelete(NULL);
        return;
    }

    i2s_std_config_t std_cfg = {
        .clk_cfg  = I2S_STD_CLK_DEFAULT_CONFIG(PLAYBACK_SAMPLE_RATE),
        .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(
                        I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_MONO),
        .gpio_cfg = {
            .mclk = STICK_S3_PIN_ES8311_MCLK,
            .bclk = STICK_S3_PIN_ES8311_BCLK,
            .ws   = STICK_S3_PIN_ES8311_LRCK,
            .dout = STICK_S3_PIN_ES8311_DIN,
            .din  = -1,
            .invert_flags = {
                .mclk_inv = false,
                .bclk_inv = false,
                .ws_inv   = false,
            },
        },
    };
    std_cfg.clk_cfg.mclk_multiple = I2S_MCLK_MULTIPLE_256;

    err = i2s_channel_init_std_mode(tx_handle, &std_cfg);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "init i2s tx std mode: %s", esp_err_to_name(err));
        i2s_del_channel(tx_handle);
        s_busy = false;
        s_play_task = NULL;
        vTaskDelete(NULL);
        return;
    }
    err = i2s_channel_enable(tx_handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "enable i2s tx: %s", esp_err_to_name(err));
        i2s_del_channel(tx_handle);
        s_busy = false;
        s_play_task = NULL;
        vTaskDelete(NULL);
        return;
    }

    /* Init ES8311 codec in DAC mode for playback. */
    i2c_master_bus_handle_t i2c_bus = stick_s3_board_i2c_bus();
    if (!i2c_bus) {
        ESP_LOGE(TAG, "i2c bus unavailable");
        i2s_channel_disable(tx_handle);
        i2s_del_channel(tx_handle);
        s_busy = false;
        s_play_task = NULL;
        vTaskDelete(NULL);
        return;
    }

#if STICK_S3_AUDIO_INPUT_ES7210
    /* Lichuang: ES8311 is on I2C_NUM_0 alongside ES7210. */
    const i2c_port_t codec_i2c_port = I2C_NUM_0;
#else
    /* M5Stack: ES8311 on I2C_NUM_1. */
    const i2c_port_t codec_i2c_port = I2C_NUM_1;
#endif

    audio_codec_i2c_cfg_t i2c_cfg = {
        .port       = codec_i2c_port,
        .addr       = ES8311_CODEC_DEFAULT_ADDR,
        .bus_handle = i2c_bus,
    };
    const audio_codec_ctrl_if_t *ctrl_if = audio_codec_new_i2c_ctrl(&i2c_cfg);
    if (!ctrl_if) {
        ESP_LOGE(TAG, "create codec i2c ctrl");
        goto cleanup_i2s;
    }

    audio_codec_i2s_cfg_t i2s_data_cfg = {
        .port      = I2S_NUM_1,
        .rx_handle = NULL,
        .tx_handle = tx_handle,
    };
    const audio_codec_data_if_t *data_if = audio_codec_new_i2s_data(&i2s_data_cfg);
    if (!data_if) {
        ESP_LOGE(TAG, "create codec i2s data");
        goto cleanup_ctrl;
    }

    const audio_codec_gpio_if_t *gpio_if = audio_codec_new_gpio();
    if (!gpio_if) {
        ESP_LOGE(TAG, "create codec gpio");
        goto cleanup_data;
    }

    es8311_codec_cfg_t es8311_cfg = {
        .ctrl_if      = ctrl_if,
        .gpio_if      = gpio_if,
        .codec_mode   = ESP_CODEC_DEV_WORK_MODE_DAC,
        .pa_pin       = -1,
        .pa_reverted  = false,
        .master_mode  = false,
        .use_mclk     = true,
        .digital_mic  = false,
        .invert_mclk  = false,
        .invert_sclk  = false,
        .hw_gain      = {
            .pa_voltage          = 5.0,
            .codec_dac_voltage   = 3.3,
        },
    };
    const audio_codec_if_t *codec_if = es8311_codec_new(&es8311_cfg);
    if (!codec_if) {
        ESP_LOGE(TAG, "create es8311 codec");
        goto cleanup_gpio;
    }

    esp_codec_dev_cfg_t dev_cfg = {
        .dev_type  = ESP_CODEC_DEV_TYPE_OUT,
        .codec_if  = codec_if,
        .data_if   = data_if,
    };
    esp_codec_dev_handle_t codec = esp_codec_dev_new(&dev_cfg);
    if (!codec) {
        ESP_LOGE(TAG, "create codec dev");
        goto cleanup_codec_if;
    }

    esp_err_t speaker_err = stick_s3_board_speaker_enable(true);
    if (speaker_err != ESP_OK) {
        ESP_LOGE(TAG, "enable speaker amplifier: %s", esp_err_to_name(speaker_err));
        goto cleanup_codec_dev;
    }
    speaker_enabled = true;

    esp_codec_dev_sample_info_t sample_info = {
        .bits_per_sample = 16,
        .channel         = 1,
        .channel_mask    = I2S_STD_SLOT_LEFT,
        .sample_rate     = PLAYBACK_SAMPLE_RATE,
        .mclk_multiple   = 0,
    };
    if (esp_codec_dev_open(codec, &sample_info) != ESP_CODEC_DEV_OK) {
        ESP_LOGE(TAG, "open playback codec");
        goto cleanup_codec_dev;
    }

    const int volume = s_volume;
    int codec_err = esp_codec_dev_set_out_vol(codec, volume);
    if (codec_err != ESP_CODEC_DEV_OK) {
        ESP_LOGE(TAG, "set playback volume=%d err=%d", volume, codec_err);
        goto cleanup_open_codec;
    }
    codec_err = esp_codec_dev_set_out_mute(codec, false);
    if (codec_err != ESP_CODEC_DEV_OK) {
        ESP_LOGE(TAG, "unmute playback codec err=%d", codec_err);
        goto cleanup_open_codec;
    }
    vTaskDelay(pdMS_TO_TICKS(20));

    /* --- generate and play tone segments --- */
    int16_t buf[TONE_BUF_FRAMES];
    ESP_LOGI(TAG, "play sound=%d", (int)sound);

    for (int seg = 0; seg < def->count; seg++) {
        const tone_segment_t *s = &def->segments[seg];
        const int total_samples = (PLAYBACK_SAMPLE_RATE * s->duration_ms) / 1000;
        int written = 0;
        double phase = 0.0;
        const double phase_inc = (s->freq_hz > 0)
            ? (2.0 * M_PI * s->freq_hz / PLAYBACK_SAMPLE_RATE)
            : 0.0;

        while (written < total_samples) {
            const int chunk = (total_samples - written > TONE_BUF_FRAMES)
                            ? TONE_BUF_FRAMES
                            : (total_samples - written);
            for (int i = 0; i < chunk; i++) {
                buf[i] = (s->freq_hz > 0)
                    ? (int16_t)(TONE_AMPLITUDE * sin(phase))
                    : 0;
                phase += phase_inc;
            }
            /* Wrap phase to avoid loss of floating-point precision. */
            if (phase > 2.0 * M_PI * 1000.0) {
                phase -= 2.0 * M_PI * 1000.0;
            }

            esp_err_t werr = esp_codec_dev_write(codec, buf,
                                                  chunk * sizeof(int16_t));
            if (werr != ESP_CODEC_DEV_OK) {
                ESP_LOGW(TAG, "codec write err=%s seg=%d",
                         esp_err_to_name(werr), seg);
                break;
            }
            written += chunk;
        }
    }

    ESP_LOGI(TAG, "playback done sound=%d", (int)sound);

    /* --- cleanup --- */
cleanup_open_codec:
    (void)esp_codec_dev_set_out_mute(codec, true);
    esp_codec_dev_close(codec);
cleanup_codec_dev:
    esp_codec_dev_delete(codec);
cleanup_codec_if:
    audio_codec_delete_codec_if(codec_if);
cleanup_gpio:
    audio_codec_delete_gpio_if(gpio_if);
cleanup_data:
    audio_codec_delete_data_if(data_if);
cleanup_ctrl:
    audio_codec_delete_ctrl_if(ctrl_if);
cleanup_i2s:
    i2s_channel_disable(tx_handle);
    i2s_del_channel(tx_handle);

    if (speaker_enabled) {
        (void)stick_s3_board_speaker_enable(false);
    }

    s_busy = false;
    s_play_task = NULL;
    vTaskDelete(NULL);
}

/* --- public API --------------------------------------------------------- */

esp_err_t audio_playback_init(void)
{
    if (s_initialized) {
        return ESP_OK;
    }
    nvs_handle_t nvs;
    esp_err_t nvs_err = nvs_open(PLAYBACK_NVS_NAMESPACE, NVS_READONLY, &nvs);
    if (nvs_err == ESP_OK) {
        uint8_t stored_volume = PLAYBACK_VOLUME_DEFAULT;
        nvs_err = nvs_get_u8(nvs, PLAYBACK_NVS_VOLUME_KEY, &stored_volume);
        if (nvs_err == ESP_OK && stored_volume <= PLAYBACK_VOLUME_MAX) {
            s_volume = stored_volume;
        }
        nvs_close(nvs);
    }
    s_initialized = true;
    ESP_LOGI(TAG, "audio playback ready volume=%d", s_volume);
    return ESP_OK;
}

esp_err_t audio_playback_set_volume(int volume)
{
    if (volume < PLAYBACK_VOLUME_MIN || volume > PLAYBACK_VOLUME_MAX) {
        return ESP_ERR_INVALID_ARG;
    }

    nvs_handle_t nvs;
    esp_err_t err = nvs_open(PLAYBACK_NVS_NAMESPACE, NVS_READWRITE, &nvs);
    if (err != ESP_OK) {
        return err;
    }
    err = nvs_set_u8(nvs, PLAYBACK_NVS_VOLUME_KEY, (uint8_t)volume);
    if (err == ESP_OK) {
        err = nvs_commit(nvs);
    }
    nvs_close(nvs);
    if (err == ESP_OK) {
        s_volume = volume;
        ESP_LOGI(TAG, "playback volume saved=%d", volume);
    }
    return err;
}

int audio_playback_get_volume(void)
{
    return s_volume;
}

bool audio_playback_is_busy(void)
{
    return s_busy;
}

esp_err_t audio_playback_play(audio_playback_sound_t sound)
{
    if (!s_initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    if (s_busy) {
        ESP_LOGW(TAG, "playback busy, skip sound=%d", (int)sound);
        return ESP_ERR_INVALID_STATE;
    }
    if (sound < 0 || sound > AUDIO_PLAYBACK_SOUND_NEEDS_INPUT) {
        return ESP_ERR_INVALID_ARG;
    }

    s_busy = true;
    BaseType_t ok = xTaskCreatePinnedToCore(
        play_task, "audio_playback", PLAY_TASK_STACK,
        (void *)(uintptr_t)sound, PLAY_TASK_PRIO, &s_play_task, 0);
    if (ok != pdPASS) {
        ESP_LOGE(TAG, "create play task failed");
        s_busy = false;
        return ESP_ERR_NO_MEM;
    }
    return ESP_OK;
}
