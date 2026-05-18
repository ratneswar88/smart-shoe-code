#pragma once
#include <Arduino.h>
enum MagType { MAG_NONE, MAG_HMC5883L, MAG_QMC5883L };
bool magInit(); MagType magGetType(); bool magReadRaw(float &mx, float &my, float &mz);
