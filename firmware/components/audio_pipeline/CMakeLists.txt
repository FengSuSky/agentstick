idf_component_register(
    SRCS "audio_pipeline.c" "audio_playback.c"
    INCLUDE_DIRS "include"
    REQUIRES voice_ble stick_s3_board esp_driver_i2s esp_codec_dev nvs_flash
)
