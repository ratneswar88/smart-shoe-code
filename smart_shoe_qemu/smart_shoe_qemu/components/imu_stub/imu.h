#pragma once
#include <stdint.h>
#include <stdbool.h>

/* ─────────────────────────────────────────────────────────────────────────────
 * imu.h  —  Common IMU interface for smart shoe firmware
 *
 * Both the real GY-86 driver (imu_gy86.c) and the QEMU stub (imu_stub.c)
 * implement this interface. Select via CONFIG_IMU_STUB in sdkconfig / prj.conf.
 * ───────────────────────────────────────────────────────────────────────────*/

/* Raw sensor data (straight from MPU-6050 ADC, 16-bit signed) */
typedef struct {
    int16_t ax, ay, az;   /* accelerometer: LSB/g, FS=±2g → 16384 LSB/g */
    int16_t gx, gy, gz;   /* gyroscope:     LSB/°/s, FS=±250°/s → 131 LSB/°/s */
    int16_t temp_raw;     /* temperature raw (optional) */
    uint32_t timestamp_us;/* microsecond timestamp */
} imu_raw_t;

/* Scaled / physical units (after applying sensitivity factors) */
typedef struct {
    float ax_g, ay_g, az_g;       /* acceleration in g */
    float gx_dps, gy_dps, gz_dps; /* angular rate in °/s */
    float temp_c;                  /* temperature in °C */
    uint32_t timestamp_us;
} imu_data_t;

/* Gait phase classification */
typedef enum {
    GAIT_UNKNOWN  = 0,
    GAIT_STANCE   = 1,   /* foot on ground — ZUPT update valid */
    GAIT_HEEL_STRIKE = 2,
    GAIT_PUSH_OFF = 3,
    GAIT_SWING    = 4,   /* foot in air */
} gait_phase_t;

/* Conversion constants */
#define IMU_ACCEL_SCALE   (1.0f / 16384.0f)   /* FS=±2g */
#define IMU_GYRO_SCALE    (1.0f / 131.0f)     /* FS=±250°/s */
#define IMU_SAMPLE_RATE_HZ  200

/* ── API ─────────────────────────────────────────────────────────────────── */

/**
 * @brief  Initialise the IMU (I2C bus + MPU-6050 config, or stub init).
 * @return 0 on success, negative errno on failure.
 */
int imu_init(void);

/**
 * @brief  Read one sample from the IMU.
 *         Blocks until a new sample is ready (DRQ or stub timer).
 * @param  out  Pointer to imu_data_t to fill.
 * @return 0 on success, negative errno on failure.
 */
int imu_read(imu_data_t *out);

/**
 * @brief  Read raw 16-bit counts (bypass scaling).
 */
int imu_read_raw(imu_raw_t *out);

/**
 * @brief  Return true if the IMU is in stub/simulation mode.
 */
bool imu_is_stub(void);
