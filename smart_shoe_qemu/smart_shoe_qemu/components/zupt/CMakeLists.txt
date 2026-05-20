idf_component_register(
    SRCS     "zupt.c"
    INCLUDE_DIRS "."
    REQUIRES imu_stub
)
target_link_libraries(${COMPONENT_LIB} PRIVATE m)
