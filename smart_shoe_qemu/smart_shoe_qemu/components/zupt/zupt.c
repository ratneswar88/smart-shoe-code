#include "zupt.h"
#include <math.h>
#include <string.h>
#include <stdio.h>

#define GRAVITY_MPS2   9.80665f

void zupt_init(zupt_state_t *s) {
    memset(s, 0, sizeof(*s));
    printf("[ZUPT] Initialised dead reckoning engine\n");
}

/* ── Stance detector ─────────────────────────────────────────────────────── */
bool zupt_detect_stance(const imu_data_t *window, int n) {
    if (n < 2) return false;

    /* Compute mean and variance of accel magnitude over window */
    float sum_mag = 0.0f;
    for (int i = 0; i < n; i++) {
        float mag = sqrtf(window[i].ax_g * window[i].ax_g +
                          window[i].ay_g * window[i].ay_g +
                          window[i].az_g * window[i].az_g);
        sum_mag += mag;
    }
    float mean_mag = sum_mag / n;

    float var = 0.0f;
    for (int i = 0; i < n; i++) {
        float mag = sqrtf(window[i].ax_g * window[i].ax_g +
                          window[i].ay_g * window[i].ay_g +
                          window[i].az_g * window[i].az_g);
        float diff = mag - mean_mag;
        var += diff * diff;
    }
    var /= n;

    /* Check gyro norm on last sample */
    const imu_data_t *last = &window[n - 1];
    float gyro_norm = sqrtf(last->gx_dps * last->gx_dps +
                            last->gy_dps * last->gy_dps +
                            last->gz_dps * last->gz_dps);

    return (sqrtf(var) < ZUPT_ACCEL_THRESH_G) &&
           (gyro_norm  < ZUPT_GYRO_THRESH_DPS);
}

/* ── Main update — call at IMU_SAMPLE_RATE_HZ ────────────────────────────── */
void zupt_update(zupt_state_t *s, const imu_data_t *imu, float dt_s) {

    /* 1. Subtract gravity (assume az_g ≈ 1g during stance for bias estimate) */
    float ax_corrected = imu->ax_g - s->accel_bias.x;
    float ay_corrected = imu->ay_g - s->accel_bias.y;
    float az_corrected = imu->az_g - s->accel_bias.z - 1.0f; /* remove gravity */

    /* 2. Integrate acceleration → velocity */
    s->velocity.x += ax_corrected * GRAVITY_MPS2 * dt_s;
    s->velocity.y += ay_corrected * GRAVITY_MPS2 * dt_s;
    s->velocity.z += az_corrected * GRAVITY_MPS2 * dt_s;

    /* 3. Integrate heading from gyro (yaw = gz) */
    s->heading_rad += imu->gz_dps * (M_PI / 180.0f) * dt_s;

    /* 4. ZUPT — zero velocity during stance */
    if (s->zupt_active) {
        /* Record displacement before zeroing */
        float step_disp = sqrtf(s->velocity.x * s->velocity.x +
                                 s->velocity.y * s->velocity.y);
        if (step_disp > 0.01f) {   /* >1cm = valid step */
            s->stride_length_m  = step_disp;
            s->total_distance_m += step_disp;
            s->step_count++;
        }

        /* Update accel bias estimate (slow drift correction) */
        s->accel_bias.x += 0.01f * imu->ax_g;
        s->accel_bias.y += 0.01f * imu->ay_g;
        s->accel_bias.z += 0.01f * (imu->az_g - 1.0f);

        /* Zero velocity — the ZUPT correction */
        s->velocity.x = 0.0f;
        s->velocity.y = 0.0f;
        s->velocity.z = 0.0f;
    }

    /* 5. Integrate velocity → position */
    s->position.x += s->velocity.x * dt_s;
    s->position.y += s->velocity.y * dt_s;
    s->position.z += s->velocity.z * dt_s;
}

void zupt_print_state(const zupt_state_t *s) {
    printf("[ZUPT] pos=(%.3f, %.3f, %.3f)m  vel=(%.3f, %.3f, %.3f)m/s  "
           "steps=%u  dist=%.2fm  heading=%.1f°  zupt=%s\n",
           s->position.x, s->position.y, s->position.z,
           s->velocity.x,  s->velocity.y,  s->velocity.z,
           (unsigned)s->step_count,
           s->total_distance_m,
           s->heading_rad * (180.0f / M_PI),
           s->zupt_active ? "ON" : "off");
}
