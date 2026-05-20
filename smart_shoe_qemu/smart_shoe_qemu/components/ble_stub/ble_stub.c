#include "ble_stub.h"
#include <stdio.h>
#include <string.h>
#include <math.h>

/* Notification counter — mirrors what a real BLE client would receive */
static uint32_t s_notify_count = 0;

void ble_stub_init(void) {
    printf("[BLE STUB] GATT server initialised (QEMU mode — output to UART)\n");
    printf("[BLE STUB] Handles: steps=0x%04x dist=0x%04x vel=0x%04x "
           "pos=0x%04x heading=0x%04x\n",
           BLE_HANDLE_STEP_COUNT, BLE_HANDLE_DISTANCE,
           BLE_HANDLE_VELOCITY,   BLE_HANDLE_POSITION,
           BLE_HANDLE_HEADING);
}

void ble_notify_zupt_state(const zupt_state_t *s) {
    s_notify_count++;

    /* ── Characteristic: Step Count (uint32) ── */
    printf("[BLE 0x%04x] STEP_COUNT   = %u\n",
           BLE_HANDLE_STEP_COUNT, (unsigned)s->step_count);

    /* ── Characteristic: Total Distance (float32, metres) ── */
    printf("[BLE 0x%04x] DISTANCE     = %.3f m\n",
           BLE_HANDLE_DISTANCE, s->total_distance_m);

    /* ── Characteristic: Velocity (3x float32, m/s) ── */
    printf("[BLE 0x%04x] VELOCITY     = (%.4f, %.4f, %.4f) m/s\n",
           BLE_HANDLE_VELOCITY,
           s->velocity.x, s->velocity.y, s->velocity.z);

    /* ── Characteristic: Position (3x float32, metres) ── */
    printf("[BLE 0x%04x] POSITION     = (%.3f, %.3f, %.3f) m\n",
           BLE_HANDLE_POSITION,
           s->position.x, s->position.y, s->position.z);

    /* ── Characteristic: Heading (float32, degrees) ── */
    printf("[BLE 0x%04x] HEADING      = %.1f deg\n",
           BLE_HANDLE_HEADING,
           s->heading_rad * (180.0f / M_PI));

    /* ── Characteristic: Stride Length (float32, metres) ── */
    printf("[BLE 0x%04x] STRIDE_LEN   = %.3f m\n",
           BLE_HANDLE_STRIDE_LEN, s->stride_length_m);

    /* ── Characteristic: ZUPT active flag ── */
    printf("[BLE 0x%04x] ZUPT_STATE   = %s\n",
           BLE_HANDLE_ZUPT_STATE, s->zupt_active ? "STANCE" : "swing");

    printf("─────────────────────── notify #%u ───\n",
           (unsigned)s_notify_count);
}

void ble_notify_imu_raw(const imu_data_t *imu) {
    printf("[BLE 0x%04x] ACCEL_RAW    = (%.4f, %.4f, %.4f) g\n",
           BLE_HANDLE_ACCEL_RAW,
           imu->ax_g, imu->ay_g, imu->az_g);
    printf("[BLE 0x%04x] GYRO_RAW     = (%.2f, %.2f, %.2f) dps\n",
           BLE_HANDLE_GYRO_RAW,
           imu->gx_dps, imu->gy_dps, imu->gz_dps);
}

void ble_notify_gait_phase(uint8_t phase) {
    const char *names[] = { "UNKNOWN", "STANCE", "HEEL_STRIKE",
                             "PUSH_OFF", "SWING" };
    const char *name = (phase < 5) ? names[phase] : "INVALID";
    printf("[BLE 0x%04x] GAIT_PHASE   = %s (%u)\n",
           BLE_HANDLE_GAIT_PHASE, name, phase);
}

void ble_notify_raw(uint16_t handle, const uint8_t *data, uint16_t len) {
    printf("[BLE 0x%04x] RAW(%u bytes) = ", handle, len);
    for (uint16_t i = 0; i < len && i < 16; i++)
        printf("%02x ", data[i]);
    if (len > 16) printf("...");
    printf("\n");
}
