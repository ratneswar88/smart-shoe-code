/* ─────────────────────────────────────────────────────────────────────────────
 * zupt.h / zupt.c  —  Zero Velocity Update dead reckoning
 *
 * Works identically in QEMU (stub IMU) and on real hardware (GY-86).
 * This is the core algorithm you want to unit-test in QEMU.
 * ───────────────────────────────────────────────────────────────────────────*/
#pragma once
#include "imu.h"

/* 3D vector */
typedef struct { float x, y, z; } vec3_t;

/* Dead reckoning state */
typedef struct {
    vec3_t velocity;      /* m/s  — zeroed on ZUPT update */
    vec3_t position;      /* m    — accumulated displacement */
    vec3_t accel_bias;    /* g    — estimated accelerometer bias */
    float  heading_rad;   /* rad  — yaw angle from gyro integration */
    bool   zupt_active;   /* true during stance phase */
    uint32_t step_count;
    float  stride_length_m;
    float  total_distance_m;
} zupt_state_t;

/* ZUPT detector thresholds — tune these for your shoe */
#define ZUPT_ACCEL_THRESH_G    0.05f   /* max accel variance during stance */
#define ZUPT_GYRO_THRESH_DPS   3.0f   /* max gyro norm during stance */
#define ZUPT_WINDOW_SAMPLES    8      /* samples to average for detection */

void  zupt_init(zupt_state_t *s);
void  zupt_update(zupt_state_t *s, const imu_data_t *imu, float dt_s);
bool  zupt_detect_stance(const imu_data_t *window, int n);
void  zupt_print_state(const zupt_state_t *s);
