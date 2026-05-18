#pragma once
#include <Arduino.h>
#include "Config.h"
#define LOGF(...) do { Serial.printf(__VA_ARGS__); Serial.flush(); } while(0)
#define LOGLN(x)  do { Serial.println(x); Serial.flush(); } while(0)
inline float lpfAlpha(float fc, float dt){ return 1.0f - expf(-2.0f*PI_F*fc*dt); }
void i2cScan(const char* tag);
void bodyToWorld_RP(float roll_deg, float pitch_deg, float bx, float by, float bz, float &wx, float &wy, float &wz);
