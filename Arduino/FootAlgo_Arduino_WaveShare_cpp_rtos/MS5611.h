#pragma once
#include <Arduino.h>
bool msInit();
bool msReadPT(float &press_mbar, float &tempC);
float pressureToAltitude(float p_mbar, float p0_mbar=1013.25f);
