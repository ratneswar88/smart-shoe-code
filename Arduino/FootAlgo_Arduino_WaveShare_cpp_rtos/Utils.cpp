#include "Utils.h"
#include <Wire.h>
void i2cScan(const char* tag){
  LOGF("[I2C] Scan %s ...\n", tag);
  byte n = 0;
  for(byte a=1;a<127;a++){
    Wire.beginTransmission(a);
    if(Wire.endTransmission()==0){ LOGF(" - 0x%02X\n", a); n++; }
  }
  if(!n) LOGLN(" - none");
}
void bodyToWorld_RP(float roll_deg, float pitch_deg, float bx, float by, float bz, float &wx, float &wy, float &wz){
  float r = roll_deg*DEG2RAD, p = pitch_deg*DEG2RAD;
  float sr=sinf(r), cr=cosf(r), sp=sinf(p), cp=cosf(p);
  float vx = bx;
  float vy = cr*by - sr*bz;
  float vz = sr*by + cr*bz;
  wx = cp*vx + sp*vz; wy = vy; wz = -sp*vx + cp*vz;
}
