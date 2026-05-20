idf_component_register(
    SRCS     "imu_stub.c"
    INCLUDE_DIRS "."
)
target_compile_options(${COMPONENT_LIB} PRIVATE -lm)
