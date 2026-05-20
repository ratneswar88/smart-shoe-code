/* ─────────────────────────────────────────────────────────────────────────────
 * ble_stub.h / ble_stub.c  —  BLE GATT stub for QEMU
 *
 * Replaces esp_ble_gatts_send_indicate() with UART printf.
 * Your app code calls ble_notify_*() — the stub routes to stdout in QEMU,
 * real BLE on hardware.
 * ───────────────────────────────────────────────────────────────────────────*/
#pragma once
#include <stdint.h>
#include "zupt.h"
#include "imu.h"

/* GATT characteristic handles (match your real BLE profile) */
#define BLE_HANDLE_STEP_COUNT     0x0010
#define BLE_HANDLE_DISTANCE       0x0012
#define BLE_HANDLE_VELOCITY       0x0014
#define BLE_HANDLE_POSITION       0x0016
#define BLE_HANDLE_HEADING        0x0018
#define BLE_HANDLE_STRIDE_LEN     0x001A
#define BLE_HANDLE_ACCEL_RAW      0x001C
#define BLE_HANDLE_GYRO_RAW       0x001E
#define BLE_HANDLE_GAIT_PHASE     0x0020
#define BLE_HANDLE_ZUPT_STATE     0x0022
#define BLE_HANDLE_CADENCE        0x0024

void ble_stub_init(void);
void ble_notify_zupt_state(const zupt_state_t *s);
void ble_notify_imu_raw(const imu_data_t *imu);
void ble_notify_gait_phase(uint8_t phase);
void ble_notify_raw(uint16_t handle, const uint8_t *data, uint16_t len);
