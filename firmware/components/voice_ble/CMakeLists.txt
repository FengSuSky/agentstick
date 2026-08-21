idf_component_register(
    SRCS "voice_ble.c"
    INCLUDE_DIRS "include"
    REQUIRES app_update bt nvs_flash stick_s3_board
)
