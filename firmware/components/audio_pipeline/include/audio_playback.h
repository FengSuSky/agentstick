#pragma once

#include <stdbool.h>
#include "esp_err.h"

typedef enum {
    AUDIO_PLAYBACK_SOUND_TASK_DONE,
    AUDIO_PLAYBACK_SOUND_TASK_FAILED,
    AUDIO_PLAYBACK_SOUND_NEEDS_INPUT,
} audio_playback_sound_t;

esp_err_t audio_playback_init(void);
esp_err_t audio_playback_play(audio_playback_sound_t sound);
bool audio_playback_is_busy(void);
