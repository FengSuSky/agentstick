#include "ui_status_icons.h"

#include <string.h>

#define CLAWD_ICON_TOP_Y 42
#define CLAWD_ICON_SIZE 112
#define CLAWD_ICON_STRIDE (CLAWD_ICON_SIZE * 4)
#define CLAWD_ICON_DATA_SIZE (CLAWD_ICON_SIZE * CLAWD_ICON_STRIDE)
#define CLAWD_FRAME_COUNT 3
#define CLAWD_FRAME_PERIOD_MS 300

/* Embedded ARGB8888 binary data for all enabled scenes × 3 frames. */
extern const uint8_t _binary_clawd_boot_0_argb8888_bin_start[] asm("_binary_clawd_boot_0_argb8888_bin_start");
extern const uint8_t _binary_clawd_boot_2_argb8888_bin_start[] asm("_binary_clawd_boot_2_argb8888_bin_start");
extern const uint8_t _binary_clawd_boot_4_argb8888_bin_start[] asm("_binary_clawd_boot_4_argb8888_bin_start");

extern const uint8_t _binary_clawd_pairing_0_argb8888_bin_start[] asm("_binary_clawd_pairing_0_argb8888_bin_start");
extern const uint8_t _binary_clawd_pairing_2_argb8888_bin_start[] asm("_binary_clawd_pairing_2_argb8888_bin_start");
extern const uint8_t _binary_clawd_pairing_4_argb8888_bin_start[] asm("_binary_clawd_pairing_4_argb8888_bin_start");

extern const uint8_t _binary_clawd_idle_0_argb8888_bin_start[] asm("_binary_clawd_idle_0_argb8888_bin_start");
extern const uint8_t _binary_clawd_idle_2_argb8888_bin_start[] asm("_binary_clawd_idle_2_argb8888_bin_start");
extern const uint8_t _binary_clawd_idle_4_argb8888_bin_start[] asm("_binary_clawd_idle_4_argb8888_bin_start");

extern const uint8_t _binary_clawd_resting_0_argb8888_bin_start[] asm("_binary_clawd_resting_0_argb8888_bin_start");
extern const uint8_t _binary_clawd_resting_2_argb8888_bin_start[] asm("_binary_clawd_resting_2_argb8888_bin_start");
extern const uint8_t _binary_clawd_resting_4_argb8888_bin_start[] asm("_binary_clawd_resting_4_argb8888_bin_start");

extern const uint8_t _binary_clawd_recording_0_argb8888_bin_start[] asm("_binary_clawd_recording_0_argb8888_bin_start");
extern const uint8_t _binary_clawd_recording_2_argb8888_bin_start[] asm("_binary_clawd_recording_2_argb8888_bin_start");
extern const uint8_t _binary_clawd_recording_4_argb8888_bin_start[] asm("_binary_clawd_recording_4_argb8888_bin_start");

extern const uint8_t _binary_clawd_transcribing_0_argb8888_bin_start[] asm("_binary_clawd_transcribing_0_argb8888_bin_start");
extern const uint8_t _binary_clawd_transcribing_2_argb8888_bin_start[] asm("_binary_clawd_transcribing_2_argb8888_bin_start");
extern const uint8_t _binary_clawd_transcribing_4_argb8888_bin_start[] asm("_binary_clawd_transcribing_4_argb8888_bin_start");

extern const uint8_t _binary_clawd_thinking_0_argb8888_bin_start[] asm("_binary_clawd_thinking_0_argb8888_bin_start");
extern const uint8_t _binary_clawd_thinking_2_argb8888_bin_start[] asm("_binary_clawd_thinking_2_argb8888_bin_start");
extern const uint8_t _binary_clawd_thinking_4_argb8888_bin_start[] asm("_binary_clawd_thinking_4_argb8888_bin_start");

extern const uint8_t _binary_clawd_notification_0_argb8888_bin_start[] asm("_binary_clawd_notification_0_argb8888_bin_start");
extern const uint8_t _binary_clawd_notification_2_argb8888_bin_start[] asm("_binary_clawd_notification_2_argb8888_bin_start");
extern const uint8_t _binary_clawd_notification_4_argb8888_bin_start[] asm("_binary_clawd_notification_4_argb8888_bin_start");

extern const uint8_t _binary_clawd_ota_0_argb8888_bin_start[] asm("_binary_clawd_ota_0_argb8888_bin_start");
extern const uint8_t _binary_clawd_ota_2_argb8888_bin_start[] asm("_binary_clawd_ota_2_argb8888_bin_start");
extern const uint8_t _binary_clawd_ota_4_argb8888_bin_start[] asm("_binary_clawd_ota_4_argb8888_bin_start");

extern const uint8_t _binary_clawd_error_0_argb8888_bin_start[] asm("_binary_clawd_error_0_argb8888_bin_start");
extern const uint8_t _binary_clawd_error_2_argb8888_bin_start[] asm("_binary_clawd_error_2_argb8888_bin_start");
extern const uint8_t _binary_clawd_error_4_argb8888_bin_start[] asm("_binary_clawd_error_4_argb8888_bin_start");

#define CLAWD_FRAME_DSC(name) \
    { \
        .header.magic = LV_IMAGE_HEADER_MAGIC, \
        .header.cf = LV_COLOR_FORMAT_ARGB8888, \
        .header.flags = 0, \
        .header.w = CLAWD_ICON_SIZE, \
        .header.h = CLAWD_ICON_SIZE, \
        .header.stride = CLAWD_ICON_STRIDE, \
        .data_size = CLAWD_ICON_DATA_SIZE, \
        .data = name##_start, \
    }

/* Frame arrays for each state */
static const lv_image_dsc_t s_frames_boot[CLAWD_FRAME_COUNT] = {
    CLAWD_FRAME_DSC(_binary_clawd_boot_0_argb8888_bin),
    CLAWD_FRAME_DSC(_binary_clawd_boot_2_argb8888_bin),
    CLAWD_FRAME_DSC(_binary_clawd_boot_4_argb8888_bin),
};
static const lv_image_dsc_t s_frames_pairing[CLAWD_FRAME_COUNT] = {
    CLAWD_FRAME_DSC(_binary_clawd_pairing_0_argb8888_bin),
    CLAWD_FRAME_DSC(_binary_clawd_pairing_2_argb8888_bin),
    CLAWD_FRAME_DSC(_binary_clawd_pairing_4_argb8888_bin),
};
static const lv_image_dsc_t s_frames_idle[CLAWD_FRAME_COUNT] = {
    CLAWD_FRAME_DSC(_binary_clawd_idle_0_argb8888_bin),
    CLAWD_FRAME_DSC(_binary_clawd_idle_2_argb8888_bin),
    CLAWD_FRAME_DSC(_binary_clawd_idle_4_argb8888_bin),
};
static const lv_image_dsc_t s_frames_resting[CLAWD_FRAME_COUNT] = {
    CLAWD_FRAME_DSC(_binary_clawd_resting_0_argb8888_bin),
    CLAWD_FRAME_DSC(_binary_clawd_resting_2_argb8888_bin),
    CLAWD_FRAME_DSC(_binary_clawd_resting_4_argb8888_bin),
};
static const lv_image_dsc_t s_frames_recording[CLAWD_FRAME_COUNT] = {
    CLAWD_FRAME_DSC(_binary_clawd_recording_0_argb8888_bin),
    CLAWD_FRAME_DSC(_binary_clawd_recording_2_argb8888_bin),
    CLAWD_FRAME_DSC(_binary_clawd_recording_4_argb8888_bin),
};
static const lv_image_dsc_t s_frames_transcribing[CLAWD_FRAME_COUNT] = {
    CLAWD_FRAME_DSC(_binary_clawd_transcribing_0_argb8888_bin),
    CLAWD_FRAME_DSC(_binary_clawd_transcribing_2_argb8888_bin),
    CLAWD_FRAME_DSC(_binary_clawd_transcribing_4_argb8888_bin),
};
static const lv_image_dsc_t s_frames_thinking[CLAWD_FRAME_COUNT] = {
    CLAWD_FRAME_DSC(_binary_clawd_thinking_0_argb8888_bin),
    CLAWD_FRAME_DSC(_binary_clawd_thinking_2_argb8888_bin),
    CLAWD_FRAME_DSC(_binary_clawd_thinking_4_argb8888_bin),
};
static const lv_image_dsc_t s_frames_notification[CLAWD_FRAME_COUNT] = {
    CLAWD_FRAME_DSC(_binary_clawd_notification_0_argb8888_bin),
    CLAWD_FRAME_DSC(_binary_clawd_notification_2_argb8888_bin),
    CLAWD_FRAME_DSC(_binary_clawd_notification_4_argb8888_bin),
};
static const lv_image_dsc_t s_frames_ota[CLAWD_FRAME_COUNT] = {
    CLAWD_FRAME_DSC(_binary_clawd_ota_0_argb8888_bin),
    CLAWD_FRAME_DSC(_binary_clawd_ota_2_argb8888_bin),
    CLAWD_FRAME_DSC(_binary_clawd_ota_4_argb8888_bin),
};
static const lv_image_dsc_t s_frames_error[CLAWD_FRAME_COUNT] = {
    CLAWD_FRAME_DSC(_binary_clawd_error_0_argb8888_bin),
    CLAWD_FRAME_DSC(_binary_clawd_error_2_argb8888_bin),
    CLAWD_FRAME_DSC(_binary_clawd_error_4_argb8888_bin),
};

/* Pointer arrays for lv_image_set_src */
static const lv_image_dsc_t *const s_src_boot[CLAWD_FRAME_COUNT] = {
    &s_frames_boot[0], &s_frames_boot[1], &s_frames_boot[2],
};
static const lv_image_dsc_t *const s_src_pairing[CLAWD_FRAME_COUNT] = {
    &s_frames_pairing[0], &s_frames_pairing[1], &s_frames_pairing[2],
};
static const lv_image_dsc_t *const s_src_idle[CLAWD_FRAME_COUNT] = {
    &s_frames_idle[0], &s_frames_idle[1], &s_frames_idle[2],
};
static const lv_image_dsc_t *const s_src_resting[CLAWD_FRAME_COUNT] = {
    &s_frames_resting[0], &s_frames_resting[1], &s_frames_resting[2],
};
static const lv_image_dsc_t *const s_src_recording[CLAWD_FRAME_COUNT] = {
    &s_frames_recording[0], &s_frames_recording[1], &s_frames_recording[2],
};
static const lv_image_dsc_t *const s_src_transcribing[CLAWD_FRAME_COUNT] = {
    &s_frames_transcribing[0], &s_frames_transcribing[1], &s_frames_transcribing[2],
};
static const lv_image_dsc_t *const s_src_thinking[CLAWD_FRAME_COUNT] = {
    &s_frames_thinking[0], &s_frames_thinking[1], &s_frames_thinking[2],
};
static const lv_image_dsc_t *const s_src_notification[CLAWD_FRAME_COUNT] = {
    &s_frames_notification[0], &s_frames_notification[1], &s_frames_notification[2],
};
static const lv_image_dsc_t *const s_src_ota[CLAWD_FRAME_COUNT] = {
    &s_frames_ota[0], &s_frames_ota[1], &s_frames_ota[2],
};
static const lv_image_dsc_t *const s_src_error[CLAWD_FRAME_COUNT] = {
    &s_frames_error[0], &s_frames_error[1], &s_frames_error[2],
};

static const lv_image_dsc_t *const *get_scene_frames(ui_status_icon_scene_t scene)
{
    switch (scene) {
    case UI_STATUS_ICON_BOOT:          return s_src_boot;
    case UI_STATUS_ICON_PAIRING:       return s_src_pairing;
    case UI_STATUS_ICON_IDLE:          return s_src_idle;
    case UI_STATUS_ICON_RESTING:       return s_src_resting;
    case UI_STATUS_ICON_RECORDING:     return s_src_recording;
    case UI_STATUS_ICON_TRANSCRIBING:  return s_src_transcribing;
    case UI_STATUS_ICON_THINKING:      return s_src_thinking;
    case UI_STATUS_ICON_NOTIFICATION:  return s_src_notification;
    case UI_STATUS_ICON_OTA:           return s_src_ota;
    case UI_STATUS_ICON_ERROR:         return s_src_error;
    }
    return s_src_idle;
}

static void frame_timer_cb(lv_timer_t *timer)
{
    ui_status_icons_t *icons = (ui_status_icons_t *)lv_timer_get_user_data(timer);
    if (!icons || !icons->root || !icons->frames || icons->frame_count == 0) return;
    icons->frame_index = (icons->frame_index + 1) % icons->frame_count;
    lv_image_set_src(icons->root, icons->frames[icons->frame_index]);
}

void ui_status_icons_create(ui_status_icons_t *icons, lv_obj_t *screen)
{
    memset(icons, 0, sizeof(*icons));
    icons->root = lv_image_create(screen);
    lv_obj_remove_style_all(icons->root);
    icons->frames = s_src_boot;
    icons->frame_count = CLAWD_FRAME_COUNT;
    lv_image_set_src(icons->root, icons->frames[0]);
    lv_obj_align(icons->root, LV_ALIGN_TOP_MID, 0, CLAWD_ICON_TOP_Y);
    icons->timer = lv_timer_create(frame_timer_cb, CLAWD_FRAME_PERIOD_MS, icons);
    lv_timer_pause(icons->timer);
}

void ui_status_icons_stop_anim(ui_status_icons_t *icons)
{
    if (!icons->timer) return;
    lv_timer_pause(icons->timer);
}

void ui_status_icons_apply(ui_status_icons_t *icons, ui_status_icon_scene_t scene)
{
    if (!icons->root) return;
    icons->frames = get_scene_frames(scene);
    icons->frame_count = CLAWD_FRAME_COUNT;
    icons->frame_index = 0;
    lv_image_set_src(icons->root, icons->frames[icons->frame_index]);
    lv_obj_set_style_opa(icons->root, LV_OPA_COVER, 0);
    lv_obj_align(icons->root, LV_ALIGN_TOP_MID, 0, CLAWD_ICON_TOP_Y);
    if (icons->timer) lv_timer_reset(icons->timer);
}

void ui_status_icons_start_anim(ui_status_icons_t *icons, ui_status_icon_scene_t scene)
{
    if (!icons->timer) return;
    (void)scene;
    lv_timer_resume(icons->timer);
}
