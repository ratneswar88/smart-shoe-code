/* ─────────────────────────────────────────────────────────────────────────────
 * main/smart_shoe_qemu_test.c
 *
 * QEMU test harness for the smart shoe firmware.
 * Wires together:  IMU stub → complementary filter → ZUPT → BLE stub
 *
 * FreeRTOS tasks mirror the real firmware architecture:
 *   Task 1 (imu_task)    : reads IMU at 200Hz, feeds filter + ZUPT
 *   Task 2 (ble_task)    : publishes GATT notifications at 10Hz
 *   Task 3 (monitor_task): prints summary every 2 seconds
 * ───────────────────────────────────────────────────────────────────────────*/

#include <stdio.h>
#include <math.h>
#include <string.h>

#include "imu.h"
#include "zupt.h"
#include "ble_stub.h"

#ifdef CONFIG_IDF_TARGET
  #include "freertos/FreeRTOS.h"
  #include "freertos/task.h"
  #include "freertos/queue.h"
  #include "freertos/semphr.h"
  #include "esp_log.h"
  #define LOG_TAG "SHOE"
  #define LOGI(fmt, ...) ESP_LOGI(LOG_TAG, fmt, ##__VA_ARGS__)
#else
  #include <zephyr/kernel.h>
  #define LOGI(fmt, ...) printk("[SHOE] " fmt "\n", ##__VA_ARGS__)
#endif

/* ── Shared state (protected by mutex) ──────────────────────────────────── */
static zupt_state_t   g_zupt;
static imu_data_t     g_imu_window[ZUPT_WINDOW_SAMPLES];
static int            g_window_idx = 0;

/* ── Complementary filter state ─────────────────────────────────────────── */
typedef struct {
    float roll_rad;
    float pitch_rad;
    float alpha;     /* high-pass weight for gyro (0.98 typical) */
} comp_filter_t;

static comp_filter_t g_filter = { .roll_rad = 0, .pitch_rad = 0, .alpha = 0.98f };

static void comp_filter_update(comp_filter_t *f,
                                const imu_data_t *imu, float dt_s) {
    /* Accel-based angle (absolute, noisy) */
    float roll_acc  = atan2f(imu->ay_g, imu->az_g);
    float pitch_acc = atan2f(-imu->ax_g,
                              sqrtf(imu->ay_g * imu->ay_g +
                                    imu->az_g * imu->az_g));

    /* Gyro integration (relative, drift over time) */
    float roll_gyro  = f->roll_rad  + imu->gx_dps * (M_PI / 180.0f) * dt_s;
    float pitch_gyro = f->pitch_rad + imu->gy_dps * (M_PI / 180.0f) * dt_s;

    /* Complementary fusion */
    f->roll_rad  = f->alpha * roll_gyro  + (1.0f - f->alpha) * roll_acc;
    f->pitch_rad = f->alpha * pitch_gyro + (1.0f - f->alpha) * pitch_acc;
}

/* ── IMU task — 200Hz ────────────────────────────────────────────────────── */
#ifdef CONFIG_IDF_TARGET
static void imu_task(void *arg) {
#else
void imu_task(void *arg, void *b, void *c) {
#endif
    const float dt_s = 1.0f / IMU_SAMPLE_RATE_HZ;
    imu_data_t imu;
    uint32_t sample_count = 0;

    LOGI("IMU task started at %d Hz", IMU_SAMPLE_RATE_HZ);

    while (1) {
        /* Read one sample (stub delays 5ms to simulate 200Hz) */
        if (imu_read(&imu) != 0) continue;

        /* ── Complementary filter ── */
        comp_filter_update(&g_filter, &imu, dt_s);

        /* ── Sliding window for ZUPT detection ── */
        g_imu_window[g_window_idx % ZUPT_WINDOW_SAMPLES] = imu;
        g_window_idx++;

        /* ── ZUPT stance detection ── */
        if (g_window_idx >= ZUPT_WINDOW_SAMPLES) {
            g_zupt.zupt_active = zupt_detect_stance(g_imu_window,
                                                     ZUPT_WINDOW_SAMPLES);
        }

        /* ── Dead reckoning update ── */
        zupt_update(&g_zupt, &imu, dt_s);

        /* Log at every 200 samples (1 second) */
        sample_count++;
        if (sample_count % 200 == 0) {
            LOGI("t=%us  roll=%.1f°  pitch=%.1f°",
                 (unsigned)(sample_count / IMU_SAMPLE_RATE_HZ),
                 g_filter.roll_rad  * (180.0f / M_PI),
                 g_filter.pitch_rad * (180.0f / M_PI));
            zupt_print_state(&g_zupt);
        }
    }
}

/* ── BLE task — 10Hz ─────────────────────────────────────────────────────── */
#ifdef CONFIG_IDF_TARGET
static void ble_task(void *arg) {
#else
void ble_task(void *arg, void *b, void *c) {
#endif
    LOGI("BLE notify task started at 10 Hz");

    while (1) {
        /* Publish all GATT characteristics */
        ble_notify_zupt_state(&g_zupt);

#ifdef CONFIG_IDF_TARGET
        vTaskDelay(pdMS_TO_TICKS(100));   /* 10Hz */
#else
        k_msleep(100);
#endif
    }
}

/* ── Monitor task — 2Hz ─────────────────────────────────────────────────── */
#ifdef CONFIG_IDF_TARGET
static void monitor_task(void *arg) {
#else
void monitor_task(void *arg, void *b, void *c) {
#endif
    uint32_t tick = 0;
    while (1) {
        tick++;
        printf("\n══════════════ SMART SHOE STATUS (t=%us) ══════════════\n",
               (unsigned)(tick * 2));
        printf("  Steps:        %u\n",        (unsigned)g_zupt.step_count);
        printf("  Distance:     %.2f m\n",    g_zupt.total_distance_m);
        printf("  Stride len:   %.3f m\n",    g_zupt.stride_length_m);
        printf("  Position:     (%.3f, %.3f, %.3f) m\n",
               g_zupt.position.x, g_zupt.position.y, g_zupt.position.z);
        printf("  Heading:      %.1f°\n",
               g_zupt.heading_rad * (180.0f / M_PI));
        printf("  Roll/Pitch:   %.1f° / %.1f°\n",
               g_filter.roll_rad  * (180.0f / M_PI),
               g_filter.pitch_rad * (180.0f / M_PI));
        printf("  ZUPT active:  %s\n",        g_zupt.zupt_active ? "YES" : "no");
        printf("  IMU mode:     %s\n",        imu_is_stub() ? "STUB (QEMU)" : "REAL (GY-86)");
        printf("══════════════════════════════════════════════════════\n\n");

#ifdef CONFIG_IDF_TARGET
        vTaskDelay(pdMS_TO_TICKS(2000));
#else
        k_msleep(2000);
#endif
    }
}

/* ── Entry point ─────────────────────────────────────────────────────────── */
#ifdef CONFIG_IDF_TARGET

void app_main(void) {
    printf("\n");
    printf("╔══════════════════════════════════════════════════╗\n");
    printf("║   SMART SHOE QEMU TEST — ESP32-S3 / ESP-IDF      ║\n");
    printf("║   IMU stub + ZUPT + CompFilter + BLE stub        ║\n");
    printf("╚══════════════════════════════════════════════════╝\n\n");

    /* Init subsystems */
    imu_init();
    zupt_init(&g_zupt);
    ble_stub_init();

    /* Create FreeRTOS tasks */
    xTaskCreate(imu_task,     "imu",     4096, NULL, 5, NULL);
    xTaskCreate(ble_task,     "ble",     4096, NULL, 3, NULL);
    xTaskCreate(monitor_task, "monitor", 4096, NULL, 2, NULL);

    /* app_main returns — FreeRTOS scheduler takes over */
}

#else  /* Zephyr */

/* Zephyr thread stacks */
K_THREAD_DEFINE(imu_tid,     2048, imu_task,     NULL, NULL, NULL, 5, 0, 0);
K_THREAD_DEFINE(ble_tid,     2048, ble_task,     NULL, NULL, NULL, 3, 0, 0);
K_THREAD_DEFINE(monitor_tid, 2048, monitor_task, NULL, NULL, NULL, 2, 0, 0);

int main(void) {
    printf("\n");
    printf("╔══════════════════════════════════════════════════╗\n");
    printf("║   SMART SHOE QEMU TEST — Zephyr RTOS            ║\n");
    printf("║   IMU stub + ZUPT + CompFilter + BLE stub       ║\n");
    printf("╚══════════════════════════════════════════════════╝\n\n");

    imu_init();
    zupt_init(&g_zupt);
    ble_stub_init();
    return 0;
}

#endif
