idf_component_register(
    SRCS     "ble_stub.c"
    INCLUDE_DIRS "."
    REQUIRES zupt imu_stub
)
target_link_libraries(${COMPONENT_LIB} PRIVATE m)
