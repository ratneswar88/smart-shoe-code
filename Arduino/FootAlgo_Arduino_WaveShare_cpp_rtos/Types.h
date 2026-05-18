#pragma once
#include <Arduino.h>
#include "Config.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
enum GaitState { STANCE=0, SWING=1 };
struct Sample { float ax_g, ay_g, az_g; float gx_dps, gy_dps, gz_dps; int16_t rawTemp; uint32_t ms; };
struct Telemetry {
  float roll_deg = 0, pitch_deg = 0, yaw_deg = 0;
  float tempC = 0; uint32_t steps = 0; float cadence_spm = 0;
  float strideLen_m = 0; float altStep_m = 0; GaitState state = STANCE;
};
extern QueueHandle_t gSampleQ; extern SemaphoreHandle_t gTelMtx; extern Telemetry gTel;
extern uint32_t gNotifyPeriodMs; extern float gThGyroDps; extern float gThVarA; extern float gModelK;
extern bool gBaroPresent;
