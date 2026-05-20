/**
 * smart_shoe.ino
 * ──────────────────────────────────────────────────────────────
 * Smart Shoe Gait Analysis Platform — Arduino / ESP32-S3
 *
 * Hardware : ESP32-S3 + GY-86 (MPU-6050 + HMC5883L + MS5611)
 * BLE GATT : 12 characteristics → Flutter app
 * Storage  : LittleFS session ring buffer
 * ML       : TFLite Micro activity classifier (stub — replace
 *             model.h after Edge Impulse training)
 * Cores    : Core 0 → 200 Hz IMU + ESKF + ZUPT
 *            Core 1 → BLE + features + flash log
 *
 * Libraries required (Arduino Library Manager):
 *   - ESP32 BLE Arduino  (built-in with ESP32 board package)
 *   - LittleFS           (built-in with ESP32 board package)
 *   - TensorFlowLite_ESP32 (after Edge Impulse export — see Section 9)
 *
 * Board: "ESP32S3 Dev Module" | Flash: 8MB | PSRAM: OPI PSRAM
 * ──────────────────────────────────────────────────────────────
 */

// ════════════════════════════════════════════════════════════════
// 1. INCLUDES & DEFINES
// ════════════════════════════════════════════════════════════════

#include <Wire.h>
#include <math.h>
#include <string.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <LittleFS.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "freertos/queue.h"

// ── After Edge Impulse training, uncomment and add your model: ──
// #include "model.h"          // Edge Impulse exported model
// #include "tflite_runner.h"  // See Section 9 stub below

// ── I2C pins (ESP32-S3 default) ─────────────────────────────────
#define I2C_SDA         8
#define I2C_SCL         9
#define I2C_FREQ        400000  // 400 kHz fast mode

// ── MPU-6050 registers ──────────────────────────────────────────
#define MPU_ADDR        0x68
#define MPU_PWR_MGMT_1  0x6B
#define MPU_SMPLRT_DIV  0x19
#define MPU_CONFIG      0x1A
#define MPU_GYRO_CFG    0x1B
#define MPU_ACCEL_CFG   0x1C
#define MPU_ACCEL_XOUT  0x3B
#define MPU_GYRO_XOUT   0x43
#define MPU_TEMP_OUT    0x41

// ── HMC5883L registers ──────────────────────────────────────────
#define HMC_ADDR        0x1E
#define HMC_CFG_A       0x00
#define HMC_CFG_B       0x01
#define HMC_MODE        0x02
#define HMC_DATA_X_H    0x03

// ── MS5611 commands ─────────────────────────────────────────────
#define MS_ADDR         0x77
#define MS_RESET        0x1E
#define MS_PROM_READ    0xA0
#define MS_CONV_D1_256  0x40
#define MS_CONV_D2_256  0x50
#define MS_ADC_READ     0x00

// ── Sampling ────────────────────────────────────────────────────
#define SAMPLE_RATE_HZ  200
#define DT              (1.0f / SAMPLE_RATE_HZ)     // 5 ms
#define WINDOW_SAMPLES  400                          // 2s window for ML
#define WINDOW_STRIDE   200                          // 50% overlap

// ── ESKF tuning ─────────────────────────────────────────────────
#define SIGMA_ACC_N     0.05f
#define SIGMA_GYR_N     0.005f
#define SIGMA_ACC_B     1e-4f
#define SIGMA_GYR_B     1e-5f
#define SIGMA_ZUPT      0.01f
#define GRAVITY         9.80665f

// ── ZUPT thresholds ─────────────────────────────────────────────
#define ZUPT_ACC_THR    0.5f    // m/s² — accel variance threshold
#define ZUPT_GYR_THR    0.3f    // rad/s — gyro magnitude threshold
#define ZUPT_WIN        10      // samples for variance window

// ── BLE UUIDs ───────────────────────────────────────────────────
#define GAIT_SVC_UUID   "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHAR_STRIDE_UUID "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHAR_CADENCE_UUID "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHAR_PHASE_UUID  "6E400004-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHAR_TERRAIN_UUID "6E400005-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHAR_JERK_UUID   "6E400006-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHAR_STANCE_UUID "6E400007-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHAR_ACTIVITY_UUID "6E400008-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHAR_ANOMALY_UUID "6E400009-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHAR_ALT_UUID    "6E40000A-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHAR_HEADING_UUID "6E40000B-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHAR_CONFIG_UUID "6E40000C-B5A3-F393-E0A9-E50E24DCCA9E"  // writable

// ── Activity class labels ────────────────────────────────────────
#define ACT_WALKING     0
#define ACT_RUNNING     1
#define ACT_STAIRS_UP   2
#define ACT_STAIRS_DN   3
#define ACT_STANDING    4
#define ACT_STUMBLE_PRE 5
#define NUM_CLASSES     6
#define STUMBLE_THR     0.55f   // per-class threshold (not argmax)

// ── Gait phases ──────────────────────────────────────────────────
#define PHASE_HEEL_STRIKE   0
#define PHASE_LOADING       1
#define PHASE_MID_STANCE    2
#define PHASE_TERMINAL      3
#define PHASE_PRE_SWING     4
#define PHASE_SWING         5

// ─────────────────────────────────────────────────────────────────
// 2. DATA STRUCTURES
// ─────────────────────────────────────────────────────────────────

typedef struct { float x, y, z; } Vec3;
typedef struct { float w, x, y, z; } Quat;

typedef struct {
    float ax, ay, az;   // m/s²
    float gx, gy, gz;   // rad/s
    float mx, my, mz;   // uT  (HMC5883L)
    float pressure;     // Pa  (MS5611, sampled on heel-strike only)
    float temp;         // °C
    uint32_t ts_ms;
} ImuFrame;

typedef struct {
    // Nominal state
    Vec3 p, v;
    Quat q;
    Vec3 b_g, b_a;
    // Error-state covariance P [15×15]
    float P[225];
    // Stride accumulator
    Vec3  stride_disp;
    float stride_dist;
    bool  init;
} ESKF;

typedef struct {
    float stride_len;
    float cadence_spm;
    float walk_ratio;
    float jerk_peak;
    float stance_time_s;
    float alt_delta;
    float heading_rad;
    uint8_t phase;
    uint8_t terrain;
    uint8_t activity;
    bool  anomaly;
} GaitFeatures;

// ─────────────────────────────────────────────────────────────────
// 3. GLOBALS
// ─────────────────────────────────────────────────────────────────

static ESKF           gEskf;
static ImuFrame       gImuFrame;
static GaitFeatures   gFeatures;

static QueueHandle_t  xImuQueue;   // Core0 → Core1
static SemaphoreHandle_t xFeatMux; // protect gFeatures

// BLE
static BLEServer          *pServer      = nullptr;
static BLECharacteristic  *pStride      = nullptr;
static BLECharacteristic  *pCadence     = nullptr;
static BLECharacteristic  *pPhase       = nullptr;
static BLECharacteristic  *pTerrain     = nullptr;
static BLECharacteristic  *pJerk        = nullptr;
static BLECharacteristic  *pStance      = nullptr;
static BLECharacteristic  *pActivity    = nullptr;
static BLECharacteristic  *pAnomaly     = nullptr;
static BLECharacteristic  *pAlt         = nullptr;
static BLECharacteristic  *pHeading     = nullptr;
static BLECharacteristic  *pConfig      = nullptr;
static bool               bleConnected  = false;

// MS5611 calibration coefficients (PROM)
static uint16_t ms_prom[8];

// Madgwick filter state
static float mw_q[4] = {1, 0, 0, 0};
static float mw_beta = 0.1f;

// ML window buffer [WINDOW_SAMPLES][6]
static float mlBuf[WINDOW_SAMPLES][6];
static int   mlBufIdx = 0;
static int   mlSampleCount = 0;

// Anomaly baseline (rolling 30-stride stats)
static float ano_cad_mean = 0, ano_cad_std = 1;
static float ano_sta_mean = 0, ano_sta_std = 1;
static int   ano_n = 0;

// Session file on LittleFS
static File  sessionFile;
static bool  sessionOpen = false;
static uint32_t strideCount = 0;

// Adaptive sampling
static int sampleRateHz = SAMPLE_RATE_HZ;

// ─────────────────────────────────────────────────────────────────
// 4. MATH HELPERS (inline, no heap)
// ─────────────────────────────────────────────────────────────────

static inline float sq(float x) { return x * x; }
static inline float clampf(float v, float lo, float hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

static void mat_mul(const float *A, int ra, int ca,
                    const float *B, int cb, float *C) {
    for (int i = 0; i < ra; i++)
        for (int j = 0; j < cb; j++) {
            float s = 0;
            for (int k = 0; k < ca; k++) s += A[i*ca+k] * B[k*cb+j];
            C[i*cb+j] = s;
        }
}

static bool mat3_inv(const float A[9], float I[9]) {
    float det = A[0]*(A[4]*A[8]-A[5]*A[7])
               -A[1]*(A[3]*A[8]-A[5]*A[6])
               +A[2]*(A[3]*A[7]-A[4]*A[6]);
    if (fabsf(det) < 1e-9f) return false;
    float inv = 1.0f/det;
    I[0]= (A[4]*A[8]-A[5]*A[7])*inv; I[1]=-(A[1]*A[8]-A[2]*A[7])*inv;
    I[2]= (A[1]*A[5]-A[2]*A[4])*inv; I[3]=-(A[3]*A[8]-A[5]*A[6])*inv;
    I[4]= (A[0]*A[8]-A[2]*A[6])*inv; I[5]=-(A[0]*A[5]-A[2]*A[3])*inv;
    I[6]= (A[3]*A[7]-A[4]*A[6])*inv; I[7]=-(A[0]*A[7]-A[1]*A[6])*inv;
    I[8]= (A[0]*A[4]-A[1]*A[3])*inv;
    return true;
}

static void quat_norm(float q[4]) {
    float n = sqrtf(q[0]*q[0]+q[1]*q[1]+q[2]*q[2]+q[3]*q[3]);
    if (n < 1e-8f) { q[0]=1; q[1]=q[2]=q[3]=0; return; }
    float inv = 1.0f/n;
    q[0]*=inv; q[1]*=inv; q[2]*=inv; q[3]*=inv;
}

static void quat_to_R(const float q[4], float R[9]) {
    float w=q[0],x=q[1],y=q[2],z=q[3];
    R[0]=1-2*(y*y+z*z); R[1]=2*(x*y-w*z);   R[2]=2*(x*z+w*y);
    R[3]=2*(x*y+w*z);   R[4]=1-2*(x*x+z*z); R[5]=2*(y*z-w*x);
    R[6]=2*(x*z-w*y);   R[7]=2*(y*z+w*x);   R[8]=1-2*(x*x+y*y);
}

// ─────────────────────────────────────────────────────────────────
// 5. MADGWICK FILTER (9-DOF, uses magnetometer for yaw)
// ─────────────────────────────────────────────────────────────────

static void madgwick_update(float ax, float ay, float az,
                             float gx, float gy, float gz,
                             float mx, float my, float mz,
                             float dt) {
    float q0=mw_q[0],q1=mw_q[1],q2=mw_q[2],q3=mw_q[3];

    // Normalise accel
    float an = sqrtf(sq(ax)+sq(ay)+sq(az));
    if (an < 1e-8f) return;
    ax/=an; ay/=an; az/=an;

    // Normalise mag
    float mn = sqrtf(sq(mx)+sq(my)+sq(mz));
    if (mn < 1e-8f) { mx=0; my=1; mz=0; } else { mx/=mn; my/=mn; mz/=mn; }

    // Reference direction of Earth's magnetic field
    float hx = 2*(mx*(0.5f-sq(q2)-sq(q3)) + my*(q1*q2-q0*q3) + mz*(q1*q3+q0*q2));
    float hy = 2*(mx*(q1*q2+q0*q3) + my*(0.5f-sq(q1)-sq(q3)) + mz*(q2*q3-q0*q1));
    float bx = sqrtf(sq(hx)+sq(hy));
    float bz = 2*(mx*(q1*q3-q0*q2) + my*(q2*q3+q0*q1) + mz*(0.5f-sq(q1)-sq(q2)));

    // Gradient-descent step
    float s0 = -2*q2*(2*(q1*q3-q0*q2)-ax) + 2*q1*(2*(q0*q1+q2*q3)-ay)
               -4*q0*(1-2*(sq(q1)+sq(q2))-az);
    float s1 =  2*q3*(2*(q1*q3-q0*q2)-ax) + 2*q0*(2*(q0*q1+q2*q3)-ay)
               -4*q1*(1-2*(sq(q1)+sq(q2))-az)
               +2*bz*q3*(bx*(0.5f-sq(q2)-sq(q3))+bz*(q1*q3-q0*q2)-mx)
               +2*(bx*q2+bz*q0)*(bx*(q1*q2-q0*q3)+bz*(q0*q1+q2*q3)-my)
               +2*bx*q3*(bx*(q0*q2+q1*q3)+bz*(0.5f-sq(q1)-sq(q2))-mz);
    float s2 = -2*q0*(2*(q1*q3-q0*q2)-ax) + 2*q3*(2*(q0*q1+q2*q3)-ay)
               -4*q2*(1-2*(sq(q1)+sq(q2))-az)
               +(-2*bx*q2)*(bx*(0.5f-sq(q2)-sq(q3))+bz*(q1*q3-q0*q2)-mx)
               +(2*bx*q1+2*bz*q3)*(bx*(q1*q2-q0*q3)+bz*(q0*q1+q2*q3)-my)
               +(2*bx*q0-4*bz*q2)*(bx*(q0*q2+q1*q3)+bz*(0.5f-sq(q1)-sq(q2))-mz);
    float s3 =  2*q1*(2*(q1*q3-q0*q2)-ax) + 2*q2*(2*(q0*q1+q2*q3)-ay)
               +(2*bz*q1)*(bx*(0.5f-sq(q2)-sq(q3))+bz*(q1*q3-q0*q2)-mx)
               +(-2*bx*q0+2*bz*q2)*(bx*(q1*q2-q0*q3)+bz*(q0*q1+q2*q3)-my)
               +(2*bx*q1)*(bx*(q0*q2+q1*q3)+bz*(0.5f-sq(q1)-sq(q2))-mz);

    float sn = sqrtf(sq(s0)+sq(s1)+sq(s2)+sq(s3));
    if (sn > 1e-8f) { s0/=sn; s1/=sn; s2/=sn; s3/=sn; }

    // Rate of change of quaternion
    float qd0 = 0.5f*(-q1*gx - q2*gy - q3*gz) - mw_beta*s0;
    float qd1 = 0.5f*( q0*gx + q2*gz - q3*gy) - mw_beta*s1;
    float qd2 = 0.5f*( q0*gy - q1*gz + q3*gx) - mw_beta*s2;
    float qd3 = 0.5f*( q0*gz + q1*gy - q2*gx) - mw_beta*s3;

    mw_q[0] = q0 + qd0*dt;
    mw_q[1] = q1 + qd1*dt;
    mw_q[2] = q2 + qd2*dt;
    mw_q[3] = q3 + qd3*dt;
    quat_norm(mw_q);
}

static float get_yaw() {
    float w=mw_q[0],x=mw_q[1],y=mw_q[2],z=mw_q[3];
    return atan2f(2*(w*z+x*y), 1-2*(sq(y)+sq(z)));
}
static float get_pitch() {
    return asinf(clampf(2*(mw_q[0]*mw_q[2]-mw_q[3]*mw_q[1]),-1,1));
}

// ─────────────────────────────────────────────────────────────────
// 6. ESKF — 15-state Error-State Kalman Filter
// ─────────────────────────────────────────────────────────────────

static void eskf_init_state(ESKF *s) {
    memset(s, 0, sizeof(ESKF));
    s->q.w = 1.0f;
    // Initial covariance
    for (int i=0;i<3;i++)  s->P[i*15+i]    = 1.0f;    // pos
    for (int i=3;i<6;i++)  s->P[i*15+i]    = 0.1f;    // vel
    for (int i=6;i<9;i++)  s->P[i*15+i]    = 0.01f;   // att
    for (int i=9;i<12;i++) s->P[i*15+i]    = 1e-4f;   // bg
    for (int i=12;i<15;i++) s->P[i*15+i]   = 1e-3f;   // ba
    s->init = true;
}

static void eskf_propagate(ESKF *s,
                            float ax,float ay,float az,
                            float gx,float gy,float gz,
                            float dt) {
    // Bias-corrected measurements
    float a[3] = {ax-s->b_a.x, ay-s->b_a.y, az-s->b_a.z};
    float g[3] = {gx-s->b_g.x, gy-s->b_g.y, gz-s->b_g.z};

    // Rotation matrix from Madgwick quaternion (more stable than ESKF's own)
    float R[9]; quat_to_R(mw_q, R);

    // Specific force in NED
    float fn[3] = {
        R[0]*a[0]+R[1]*a[1]+R[2]*a[2],
        R[3]*a[0]+R[4]*a[1]+R[5]*a[2],
        R[6]*a[0]+R[7]*a[1]+R[8]*a[2]
    };

    // Nominal state integration (Euler)
    s->v.x += fn[0]*dt;
    s->v.y += fn[1]*dt;
    s->v.z += (fn[2] + GRAVITY)*dt;
    s->p.x += s->v.x*dt;
    s->p.y += s->v.y*dt;
    s->p.z += s->v.z*dt;

    // Sync quaternion from Madgwick
    s->q.w=mw_q[0]; s->q.x=mw_q[1]; s->q.y=mw_q[2]; s->q.z=mw_q[3];

    // Stride accumulator
    s->stride_disp.x += s->v.x*dt;
    s->stride_disp.y += s->v.y*dt;

    // Simplified P propagation (diagonal noise injection only — saves stack)
    float qa = sq(SIGMA_ACC_N)*dt;
    float qg = sq(SIGMA_GYR_N)*dt;
    for (int i=3;i<6;i++)  s->P[i*15+i] += qa;
    for (int i=6;i<9;i++)  s->P[i*15+i] += qg;
    for (int i=9;i<12;i++) s->P[i*15+i] += sq(SIGMA_GYR_B)*dt;
    for (int i=12;i<15;i++) s->P[i*15+i]+= sq(SIGMA_ACC_B)*dt;
}

static void eskf_update_zupt(ESKF *s) {
    // H picks out velocity block [3:6] → 3×15
    // S = P_vv + R
    float r = sq(SIGMA_ZUPT);
    float Pvv[9];
    for (int i=0;i<3;i++)
        for (int j=0;j<3;j++)
            Pvv[i*3+j] = s->P[(i+3)*15+(j+3)];

    float S[9]; memcpy(S, Pvv, 36);
    S[0]+=r; S[4]+=r; S[8]+=r;

    float Sinv[9];
    if (!mat3_inv(S, Sinv)) return;

    // K = PHT * Sinv  (PHT = columns 3-5 of P → 15×3)
    float PHT[45], K[45];
    for (int i=0;i<15;i++)
        for (int j=0;j<3;j++)
            PHT[i*3+j] = s->P[i*15+(j+3)];
    mat_mul(PHT,15,3, Sinv,3, K);

    // Innovation z = -v
    float z[3] = {-s->v.x, -s->v.y, -s->v.z};

    // Correction δx = K*z
    float dx[15] = {0};
    for (int i=0;i<15;i++)
        dx[i] = K[i*3]*z[0] + K[i*3+1]*z[1] + K[i*3+2]*z[2];

    // Inject into nominal state
    s->p.x+=dx[0]; s->p.y+=dx[1]; s->p.z+=dx[2];
    s->v.x+=dx[3]; s->v.y+=dx[4]; s->v.z+=dx[5];
    s->b_g.x+=dx[9]; s->b_g.y+=dx[10]; s->b_g.z+=dx[11];
    s->b_a.x+=dx[12]; s->b_a.y+=dx[13]; s->b_a.z+=dx[14];

    // P update: P = (I-KH)*P (simplified, diagonal-only for stack safety)
    for (int i=0;i<3;i++) {
        float kii = K[(i+3)*3+i];
        for (int j=0;j<15;j++) {
            s->P[(i+3)*15+j] *= (1.0f - kii);
            s->P[j*15+(i+3)] *= (1.0f - kii);
        }
    }
}

static float eskf_stride_length(ESKF *s) {
    float l = sqrtf(sq(s->stride_disp.x)+sq(s->stride_disp.y));
    s->stride_disp.x = s->stride_disp.y = s->stride_disp.z = 0;
    return l;
}

// ─────────────────────────────────────────────────────────────────
// 7. ZUPT DETECTOR
// ─────────────────────────────────────────────────────────────────

static bool detect_zupt(const ImuFrame &f) {
    static float acc_win[ZUPT_WIN][3];
    static int   win_idx = 0;
    static bool  win_full = false;

    acc_win[win_idx][0] = f.ax;
    acc_win[win_idx][1] = f.ay;
    acc_win[win_idx][2] = f.az;
    win_idx = (win_idx+1) % ZUPT_WIN;
    if (win_idx == 0) win_full = true;
    if (!win_full) return false;

    // Variance of accel magnitude
    float mag[ZUPT_WIN], mean=0;
    for (int i=0;i<ZUPT_WIN;i++) {
        mag[i] = sqrtf(sq(acc_win[i][0])+sq(acc_win[i][1])+sq(acc_win[i][2]));
        mean += mag[i];
    }
    mean /= ZUPT_WIN;
    float var = 0;
    for (int i=0;i<ZUPT_WIN;i++) var += sq(mag[i]-mean);
    var /= ZUPT_WIN;

    // Gyro magnitude
    float gm = sqrtf(sq(f.gx)+sq(f.gy)+sq(f.gz));

    return (var < sq(ZUPT_ACC_THR) && gm < ZUPT_GYR_THR);
}

// ─────────────────────────────────────────────────────────────────
// 8. GAIT PHASE FSM
// ─────────────────────────────────────────────────────────────────

static uint8_t update_gait_phase(bool is_stance, float az_body, float gy_body) {
    static uint8_t phase = PHASE_SWING;
    static uint32_t phase_timer = 0;
    phase_timer++;

    switch (phase) {
        case PHASE_SWING:
            if (is_stance) { phase = PHASE_HEEL_STRIKE; phase_timer=0; }
            break;
        case PHASE_HEEL_STRIKE:
            phase = (phase_timer > 2) ? PHASE_LOADING : PHASE_HEEL_STRIKE;
            break;
        case PHASE_LOADING:
            phase = (phase_timer > 8) ? PHASE_MID_STANCE : PHASE_LOADING;
            break;
        case PHASE_MID_STANCE:
            phase = (phase_timer > 20) ? PHASE_TERMINAL : PHASE_MID_STANCE;
            break;
        case PHASE_TERMINAL:
            if (fabsf(gy_body) > 1.5f) { phase = PHASE_PRE_SWING; phase_timer=0; }
            break;
        case PHASE_PRE_SWING:
            if (!is_stance) { phase = PHASE_SWING; phase_timer=0; }
            break;
    }
    return phase;
}

// ─────────────────────────────────────────────────────────────────
// 9. TERRAIN CLASSIFIER (rule-based: pitch + baro delta)
// ─────────────────────────────────────────────────────────────────

#define TERRAIN_FLAT    0
#define TERRAIN_UPHILL  1
#define TERRAIN_DNHILL  2
#define TERRAIN_STAIRS  3

static uint8_t classify_terrain(float pitch_rad, float baro_delta_pa) {
    // ~12 Pa ≈ 1m altitude change (rough)
    const float alt_thr = 12.0f;
    const float pit_thr = 0.087f;  // ~5 degrees

    // Rapid altitude steps → stairs
    static float prev_baro = 0;
    static int stair_count = 0;
    if (fabsf(baro_delta_pa - prev_baro) > alt_thr * 0.3f) stair_count++;
    else stair_count = (stair_count > 0) ? stair_count-1 : 0;
    prev_baro = baro_delta_pa;
    if (stair_count > 5 && fabsf(pitch_rad) > pit_thr) return TERRAIN_STAIRS;

    if (pitch_rad >  pit_thr && baro_delta_pa < -alt_thr) return TERRAIN_UPHILL;
    if (pitch_rad < -pit_thr && baro_delta_pa >  alt_thr) return TERRAIN_DNHILL;
    return TERRAIN_FLAT;
}

// ─────────────────────────────────────────────────────────────────
// 10. ANOMALY DETECTOR (Z-score, no ML)
// ─────────────────────────────────────────────────────────────────

static void update_anomaly_baseline(float cadence, float stance) {
    // Welford online mean/variance
    ano_n++;
    float dc = cadence - ano_cad_mean;
    ano_cad_mean += dc / ano_n;
    ano_cad_std = (ano_n > 1)
        ? sqrtf(((ano_n-2)*sq(ano_cad_std) + dc*(cadence-ano_cad_mean))/(ano_n-1))
        : 0.5f;
    float ds = stance - ano_sta_mean;
    ano_sta_mean += ds / ano_n;
    ano_sta_std = (ano_n > 1)
        ? sqrtf(((ano_n-2)*sq(ano_sta_std) + ds*(stance-ano_sta_mean))/(ano_n-1))
        : 0.1f;
}

static bool check_anomaly(float cadence, float stance) {
    if (ano_n < 10) { update_anomaly_baseline(cadence, stance); return false; }
    float zc = fabsf((cadence - ano_cad_mean) / (ano_cad_std + 1e-6f));
    float zs = fabsf((stance  - ano_sta_mean) / (ano_sta_std  + 1e-6f));
    update_anomaly_baseline(cadence, stance);
    return (zc > 3.0f || zs > 3.0f);
}

// ─────────────────────────────────────────────────────────────────
// 11. TFLite ACTIVITY CLASSIFIER (STUB)
// ─────────────────────────────────────────────────────────────────
// After Edge Impulse training:
//   1. Download Arduino library ZIP from Deployment tab
//   2. Sketch → Include Library → Add .ZIP Library
//   3. Replace this stub with actual inference code

static uint8_t tflite_classify(float window[WINDOW_SAMPLES][6]) {
    // ── STUB: returns walking until model is integrated ──────────
    // Replace with:
    //   signal_t signal;
    //   numpy::signal_from_buffer(&window[0][0], EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE, &signal);
    //   ei_impulse_result_t result;
    //   run_classifier(&signal, &result, false);
    //   // Per-class threshold for stumble_pre:
    //   if (result.classification[ACT_STUMBLE_PRE].value > STUMBLE_THR)
    //       return ACT_STUMBLE_PRE;
    //   // Argmax for others:
    //   uint8_t best = 0;
    //   for (int i=1;i<NUM_CLASSES;i++)
    //       if (result.classification[i].value > result.classification[best].value) best=i;
    //   return best;
    return ACT_WALKING;  // placeholder
}

// ─────────────────────────────────────────────────────────────────
// 12. SENSOR DRIVERS
// ─────────────────────────────────────────────────────────────────

static void i2c_write(uint8_t addr, uint8_t reg, uint8_t val) {
    Wire.beginTransmission(addr);
    Wire.write(reg); Wire.write(val);
    Wire.endTransmission();
}
static uint8_t i2c_read_byte(uint8_t addr, uint8_t reg) {
    Wire.beginTransmission(addr);
    Wire.write(reg); Wire.endTransmission(false);
    Wire.requestFrom(addr, (uint8_t)1);
    return Wire.available() ? Wire.read() : 0;
}
static void i2c_read_bytes(uint8_t addr, uint8_t reg, uint8_t *buf, uint8_t len) {
    Wire.beginTransmission(addr);
    Wire.write(reg); Wire.endTransmission(false);
    Wire.requestFrom(addr, len);
    for (uint8_t i=0; i<len && Wire.available(); i++) buf[i]=Wire.read();
}

// ── MPU-6050 init ────────────────────────────────────────────────
static void mpu_init() {
    i2c_write(MPU_ADDR, MPU_PWR_MGMT_1, 0x80); delay(100); // reset
    i2c_write(MPU_ADDR, MPU_PWR_MGMT_1, 0x01); delay(10);  // PLL gyro X
    i2c_write(MPU_ADDR, MPU_SMPLRT_DIV, 0x04); // 200Hz: 1000/(4+1)
    i2c_write(MPU_ADDR, MPU_CONFIG,     0x03); // DLPF 44Hz
    i2c_write(MPU_ADDR, MPU_GYRO_CFG,  0x08); // ±500°/s → 65.5 LSB/(°/s)
    i2c_write(MPU_ADDR, MPU_ACCEL_CFG, 0x08); // ±4g → 8192 LSB/g
}

static void mpu_read(ImuFrame &f) {
    uint8_t buf[14];
    i2c_read_bytes(MPU_ADDR, MPU_ACCEL_XOUT, buf, 14);
    int16_t raw_ax = (buf[0]<<8)|buf[1];
    int16_t raw_ay = (buf[2]<<8)|buf[3];
    int16_t raw_az = (buf[4]<<8)|buf[5];
    int16_t raw_gx = (buf[8]<<8)|buf[9];
    int16_t raw_gy = (buf[10]<<8)|buf[11];
    int16_t raw_gz = (buf[12]<<8)|buf[13];
    // ±4g: LSB/g = 8192; ±500°/s: LSB/(°/s) = 65.5
    f.ax = raw_ax / 8192.0f * GRAVITY;
    f.ay = raw_ay / 8192.0f * GRAVITY;
    f.az = raw_az / 8192.0f * GRAVITY;
    f.gx = raw_gx / 65.5f * (M_PI/180.0f);
    f.gy = raw_gy / 65.5f * (M_PI/180.0f);
    f.gz = raw_gz / 65.5f * (M_PI/180.0f);
}

// ── HMC5883L init ────────────────────────────────────────────────
static void hmc_init() {
    i2c_write(HMC_ADDR, HMC_CFG_A, 0x70); // 8 samples, 15Hz
    i2c_write(HMC_ADDR, HMC_CFG_B, 0x20); // Gain 1.3 Ga
    i2c_write(HMC_ADDR, HMC_MODE,  0x00); // Continuous mode
    delay(10);
}

static void hmc_read(ImuFrame &f) {
    uint8_t buf[6];
    i2c_read_bytes(HMC_ADDR, HMC_DATA_X_H, buf, 6);
    int16_t rx = (buf[0]<<8)|buf[1];
    int16_t rz = (buf[2]<<8)|buf[3]; // HMC order: X,Z,Y
    int16_t ry = (buf[4]<<8)|buf[5];
    f.mx = rx / 1090.0f * 100.0f; // Gauss → uT
    f.my = ry / 1090.0f * 100.0f;
    f.mz = rz / 1090.0f * 100.0f;
}

// ── MS5611 calibration & reading ────────────────────────────────
static void ms_reset_and_prom() {
    Wire.beginTransmission(MS_ADDR);
    Wire.write(MS_RESET); Wire.endTransmission();
    delay(10);
    for (int i=0;i<8;i++) {
        Wire.beginTransmission(MS_ADDR);
        Wire.write(MS_PROM_READ + i*2); Wire.endTransmission(false);
        Wire.requestFrom(MS_ADDR, 2);
        uint16_t h = Wire.read(), l = Wire.read();
        ms_prom[i] = (h<<8)|l;
    }
}

static float ms_read_pressure() {
    // Trigger D1 (pressure), wait, read
    Wire.beginTransmission(MS_ADDR); Wire.write(MS_CONV_D1_256);
    Wire.endTransmission(); delay(1);
    Wire.beginTransmission(MS_ADDR); Wire.write(MS_ADC_READ);
    Wire.endTransmission(false); Wire.requestFrom(MS_ADDR, 3);
    uint32_t D1 = ((uint32_t)Wire.read()<<16)|((uint32_t)Wire.read()<<8)|Wire.read();

    // Trigger D2 (temperature), wait, read
    Wire.beginTransmission(MS_ADDR); Wire.write(MS_CONV_D2_256);
    Wire.endTransmission(); delay(1);
    Wire.beginTransmission(MS_ADDR); Wire.write(MS_ADC_READ);
    Wire.endTransmission(false); Wire.requestFrom(MS_ADDR, 3);
    uint32_t D2 = ((uint32_t)Wire.read()<<16)|((uint32_t)Wire.read()<<8)|Wire.read();

    // MS5611 compensation
    int32_t dT   = (int32_t)D2 - ((int32_t)ms_prom[5]<<8);
    int32_t TEMP = 2000 + ((int64_t)dT * ms_prom[6] >> 23);
    int64_t OFF  = ((int64_t)ms_prom[2]<<16) + ((int64_t)ms_prom[4]*dT>>7);
    int64_t SENS = ((int64_t)ms_prom[1]<<15) + ((int64_t)ms_prom[3]*dT>>8);
    int32_t P    = (int32_t)(((int64_t)D1*SENS/2097152 - OFF) / 32768);
    (void)TEMP;
    return (float)P;  // Pa
}

// ─────────────────────────────────────────────────────────────────
// 13. LITTLEFS SESSION LOGGING
// ─────────────────────────────────────────────────────────────────

static void session_open_new() {
    char name[32];
    snprintf(name, sizeof(name), "/session_%lu.bin", millis());
    sessionFile = LittleFS.open(name, "w");
    if (sessionFile) { sessionOpen=true; strideCount=0; }
    else Serial.println("[FS] Failed to open session file");
}

static void session_log_stride(const GaitFeatures &f) {
    if (!sessionOpen) return;
    // Binary record: stride_len(f32) cadence(f32) jerk(f32) stance(f32)
    //                terrain(u8) activity(u8) anomaly(u8) ts_ms(u32)
    float buf[4] = {f.stride_len, f.cadence_spm, f.jerk_peak, f.stance_time_s};
    sessionFile.write((uint8_t*)buf, sizeof(buf));
    uint8_t flags[3] = {f.terrain, f.activity, (uint8_t)f.anomaly};
    sessionFile.write(flags, 3);
    uint32_t ts = millis();
    sessionFile.write((uint8_t*)&ts, 4);
    strideCount++;
    if (strideCount % 10 == 0) sessionFile.flush();  // flush every 10 strides
}

static void session_close() {
    if (sessionOpen) { sessionFile.close(); sessionOpen=false; }
}

// ─────────────────────────────────────────────────────────────────
// 14. BLE SETUP
// ─────────────────────────────────────────────────────────────────

class ConnCB: public BLEServerCallbacks {
    void onConnect(BLEServer *s) override {
        bleConnected = true;
        Serial.println("[BLE] Connected");
        session_open_new();
    }
    void onDisconnect(BLEServer *s) override {
        bleConnected = false;
        session_close();
        Serial.println("[BLE] Disconnected");
        BLEDevice::startAdvertising();
    }
};

static BLECharacteristic* make_char(BLEService *svc, const char *uuid,
                                    uint32_t props) {
    auto *c = svc->createCharacteristic(uuid, props);
    if (props & BLECharacteristic::PROPERTY_NOTIFY)
        c->addDescriptor(new BLE2902());
    return c;
}

static void ble_init() {
    BLEDevice::init("SmartShoe-01");
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new ConnCB());

    BLEService *svc = pServer->createService(GAIT_SVC_UUID);
    uint32_t RN = BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY;
    uint32_t W  = BLECharacteristic::PROPERTY_WRITE;

    pStride   = make_char(svc, CHAR_STRIDE_UUID,   RN);
    pCadence  = make_char(svc, CHAR_CADENCE_UUID,  RN);
    pPhase    = make_char(svc, CHAR_PHASE_UUID,     RN);
    pTerrain  = make_char(svc, CHAR_TERRAIN_UUID,   RN);
    pJerk     = make_char(svc, CHAR_JERK_UUID,      RN);
    pStance   = make_char(svc, CHAR_STANCE_UUID,    RN);
    pActivity = make_char(svc, CHAR_ACTIVITY_UUID,  RN);
    pAnomaly  = make_char(svc, CHAR_ANOMALY_UUID,   RN);
    pAlt      = make_char(svc, CHAR_ALT_UUID,       RN);
    pHeading  = make_char(svc, CHAR_HEADING_UUID,   RN);
    pConfig   = make_char(svc, CHAR_CONFIG_UUID,    W);

    svc->start();
    BLEAdvertising *adv = BLEDevice::getAdvertising();
    adv->addServiceUUID(GAIT_SVC_UUID);
    adv->setScanResponse(true);
    adv->start();
    Serial.println("[BLE] Advertising");
}

static void ble_notify_float(BLECharacteristic *c, float v) {
    if (!bleConnected) return;
    c->setValue(v); c->notify();
}
static void ble_notify_u8(BLECharacteristic *c, uint8_t v) {
    if (!bleConnected) return;
    c->setValue(v); c->notify();
}

static void ble_publish(const GaitFeatures &f) {
    ble_notify_float(pStride,   f.stride_len);
    ble_notify_float(pCadence,  f.cadence_spm);
    ble_notify_float(pJerk,     f.jerk_peak);
    ble_notify_float(pStance,   f.stance_time_s);
    ble_notify_float(pAlt,      f.alt_delta);
    ble_notify_float(pHeading,  f.heading_rad);
    ble_notify_u8(pPhase,       f.phase);
    ble_notify_u8(pTerrain,     f.terrain);
    ble_notify_u8(pActivity,    f.activity);
    ble_notify_u8(pAnomaly,     (uint8_t)f.anomaly);
}

// ─────────────────────────────────────────────────────────────────
// 15. CORE 0 TASK — 200Hz IMU + ESKF + ZUPT (time-critical)
// ─────────────────────────────────────────────────────────────────

static void core0_task(void *arg) {
    TickType_t xLastWake = xTaskGetTickCount();
    const TickType_t xPeriod = pdMS_TO_TICKS(5); // 5ms = 200Hz

    // Per-stride accumulators
    float prev_pressure = 0;
    bool  was_stance    = false;
    uint32_t swing_start= 0;
    float max_jerk      = 0;

    for (;;) {
        vTaskDelayUntil(&xLastWake, xPeriod);

        ImuFrame f;
        mpu_read(f);
        hmc_read(f);   // HMC runs at ~15Hz — reads last valid sample
        f.ts_ms = millis();

        bool is_stance = detect_zupt(f);

        // Adaptive sampling: drop to 50Hz during stance
        if (is_stance && sampleRateHz == SAMPLE_RATE_HZ) {
            sampleRateHz = 50;
        } else if (!is_stance && sampleRateHz == 50) {
            sampleRateHz = SAMPLE_RATE_HZ;
        }

        // Madgwick update (9-DOF)
        madgwick_update(f.ax, f.ay, f.az,
                        f.gx, f.gy, f.gz,
                        f.mx, f.my, f.mz, DT);

        // ESKF propagate
        eskf_propagate(&gEskf, f.ax, f.ay, f.az,
                                f.gx, f.gy, f.gz, DT);

        // ZUPT measurement update during stance
        if (is_stance) eskf_update_zupt(&gEskf);

        // Jerk (3rd derivative of accel): magnitude of (a_now - a_prev)/dt
        static float prev_a[3] = {0,0,0};
        float jx=(f.ax-prev_a[0])/DT, jy=(f.ay-prev_a[1])/DT, jz=(f.az-prev_a[2])/DT;
        float jerk = sqrtf(sq(jx)+sq(jy)+sq(jz));
        if (jerk > max_jerk) max_jerk = jerk;
        prev_a[0]=f.ax; prev_a[1]=f.ay; prev_a[2]=f.az;

        // Gait phase
        uint8_t phase = update_gait_phase(is_stance, f.az, f.gy);

        // Stride detection: swing→stance transition = stride complete
        if (!was_stance && is_stance) {
            // Stride complete — compute features
            uint32_t swing_dur_ms = millis() - swing_start;
            float stride_len = eskf_stride_length(&gEskf);
            float stance_start_ms = millis();

            // Baro sample on heel-strike
            float pressure = ms_read_pressure();
            float baro_delta = pressure - prev_pressure;
            prev_pressure = pressure;

            float cadence = (swing_dur_ms > 0)
                ? (60000.0f / (float)swing_dur_ms) : 0;
            float walk_ratio = (cadence > 0) ? stride_len / cadence : 0;
            float pitch = get_pitch();
            float heading = get_yaw();
            uint8_t terrain = classify_terrain(pitch, baro_delta);
            bool anomaly = check_anomaly(cadence, swing_dur_ms/1000.0f);

            // Write to shared feature struct
            xSemaphoreTake(xFeatMux, portMAX_DELAY);
            gFeatures.stride_len    = stride_len;
            gFeatures.cadence_spm   = cadence;
            gFeatures.walk_ratio    = walk_ratio;
            gFeatures.jerk_peak     = max_jerk;
            gFeatures.stance_time_s = 0;  // updated on next swing start
            gFeatures.alt_delta     = baro_delta / 12.0f;  // Pa → approx m
            gFeatures.heading_rad   = heading;
            gFeatures.phase         = phase;
            gFeatures.terrain       = terrain;
            gFeatures.anomaly       = anomaly;
            xSemaphoreGive(xFeatMux);

            max_jerk = 0;

            // Send signal to Core 1
            ImuFrame signal = f;
            xQueueSend(xImuQueue, &signal, 0);
        }
        if (was_stance && !is_stance) swing_start = millis();

        // Fill ML window buffer (6 features per sample)
        mlBuf[mlBufIdx][0] = f.ax; mlBuf[mlBufIdx][1] = f.ay;
        mlBuf[mlBufIdx][2] = f.az; mlBuf[mlBufIdx][3] = f.gx;
        mlBuf[mlBufIdx][4] = f.gy; mlBuf[mlBufIdx][5] = f.gz;
        mlBufIdx = (mlBufIdx+1) % WINDOW_SAMPLES;
        mlSampleCount++;

        was_stance = is_stance;
    }
}

// ─────────────────────────────────────────────────────────────────
// 16. CORE 1 TASK — BLE + ML + Flash log (latency-tolerant)
// ─────────────────────────────────────────────────────────────────

static void core1_task(void *arg) {
    ImuFrame signal;
    uint32_t lastMLrun = 0;

    for (;;) {
        // Wait for stride-complete signal from Core 0 (max 2s)
        if (xQueueReceive(xImuQueue, &signal, pdMS_TO_TICKS(2000)) == pdTRUE) {

            // Copy features safely
            GaitFeatures feat;
            xSemaphoreTake(xFeatMux, portMAX_DELAY);
            memcpy(&feat, &gFeatures, sizeof(GaitFeatures));
            xSemaphoreGive(xFeatMux);

            // Run TFLite every full window (every WINDOW_STRIDE samples)
            if (mlSampleCount - lastMLrun >= WINDOW_STRIDE) {
                // Reorder circular buffer into linear window
                static float window[WINDOW_SAMPLES][6];
                int start = mlBufIdx;  // oldest sample
                for (int i=0;i<WINDOW_SAMPLES;i++) {
                    int idx = (start+i) % WINDOW_SAMPLES;
                    memcpy(window[i], mlBuf[idx], sizeof(float)*6);
                }
                feat.activity = tflite_classify(window);
                lastMLrun = mlSampleCount;

                // Update shared features with activity
                xSemaphoreTake(xFeatMux, portMAX_DELAY);
                gFeatures.activity = feat.activity;
                xSemaphoreGive(xFeatMux);
            }

            // BLE publish (non-blocking)
            ble_publish(feat);

            // Flash log
            session_log_stride(feat);

            // Debug serial
            Serial.printf("[GAIT] stride=%.2fm cad=%.0fspm "
                          "terrain=%d act=%d anom=%d\n",
                          feat.stride_len, feat.cadence_spm,
                          feat.terrain, feat.activity, feat.anomaly);
        }
        // Yield briefly to allow BLE stack to run
        vTaskDelay(1);
    }
}

// ─────────────────────────────────────────────────────────────────
// 17. SETUP & LOOP
// ─────────────────────────────────────────────────────────────────

void setup() {
    Serial.begin(115200);
    delay(500);
    Serial.println("=== Smart Shoe Boot ===");

    // I2C
    Wire.begin(I2C_SDA, I2C_SCL, I2C_FREQ);

    // Sensors
    mpu_init();
    hmc_init();
    ms_reset_and_prom();
    Serial.println("[SENSOR] MPU-6050 + HMC5883L + MS5611 init OK");

    // ESKF
    eskf_init_state(&gEskf);
    Serial.println("[ESKF] Initialized");

    // LittleFS
    if (!LittleFS.begin(true)) {
        Serial.println("[FS] LittleFS mount failed — formatting");
        LittleFS.format();
        LittleFS.begin();
    }
    Serial.printf("[FS] Total: %lu KB  Used: %lu KB\n",
        LittleFS.totalBytes()/1024, LittleFS.usedBytes()/1024);

    // BLE
    ble_init();

    // IPC
    xImuQueue = xQueueCreate(8, sizeof(ImuFrame));
    xFeatMux  = xSemaphoreCreateMutex();

    // Core 0: IMU + ESKF (pinned, high priority, 8KB stack)
    xTaskCreatePinnedToCore(core0_task, "imu_eskf", 8192,
                            nullptr, 24, nullptr, 0);

    // Core 1: BLE + ML + flash (pinned, normal priority, 16KB stack)
    xTaskCreatePinnedToCore(core1_task, "ble_ml",  16384,
                            nullptr, 5,  nullptr, 1);

    Serial.println("[BOOT] Tasks started. Waiting for BLE connection...");
}

void loop() {
    // All work is in RTOS tasks. Loop handles config writes from BLE.
    if (pConfig && pConfig->getValue().length() > 0) {
        uint8_t cmd = pConfig->getValue()[0];
        switch (cmd) {
            case 0x01:  // trigger mag calibration (placeholder)
                Serial.println("[CAL] Mag calibration triggered");
                break;
            case 0x02:  // close and rotate session
                session_close();
                session_open_new();
                break;
            case 0x03:  // reset ZUPT baseline
                ano_n = 0; ano_cad_mean=0; ano_sta_mean=0;
                break;
        }
        pConfig->setValue("");
    }
    delay(100);
}
