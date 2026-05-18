#include "MS5611.h"
#include <Wire.h>
#define MS5611_ADDR 0x77
#define MS5611_CMD_RESET 0x1E
#define MS5611_CMD_CONV_D1_4096 0x48
#define MS5611_CMD_CONV_D2_4096 0x58
#define MS5611_CMD_ADC_READ 0x00
#define MS5611_CMD_PROM_READ_BASE 0xA2
static uint16_t C_ms[7]; 
static bool msPresent=false;
static bool msWrite(uint8_t cmd){ Wire.beginTransmission(MS5611_ADDR); Wire.write(cmd); return Wire.endTransmission()==0; }
static bool msReadN(uint8_t cmd, uint8_t *buf, size_t n){
  Wire.beginTransmission(MS5611_ADDR); Wire.write(cmd);
  if(Wire.endTransmission(false)!=0) return false;
  size_t r=Wire.requestFrom((int)MS5611_ADDR,(int)n);
  if(r!=n) return false;
  for(size_t i=0;i<n;++i) buf[i]=Wire.read();
  return true;
}
static bool msReset(){ return msWrite(MS5611_CMD_RESET); }
static bool msReadProm(){
  for(int i=0;i<6;i++){ uint8_t b[2];
    if(!msReadN(MS5611_CMD_PROM_READ_BASE+i*2,b,2)) return false;
    C_ms[i+1]=(b[0]<<8)|b[1];
  } return true;
}
static bool msReadADC(uint32_t &val){
  uint8_t b[3]; if(!msReadN(MS5611_CMD_ADC_READ,b,3)) return false;
  val=((uint32_t)b[0]<<16)|((uint32_t)b[1]<<8)|b[2]; return true;
}
bool msInit(){ if(!msReset()) return false; delay(5); msPresent = msReadProm(); return msPresent; }
bool msReadPT(float &press_mbar, float &tempC){
  if(!msWrite(MS5611_CMD_CONV_D2_4096)) return false; delay(10);
  uint32_t D2=0; if(!msReadADC(D2)) return false;
  if(!msWrite(MS5611_CMD_CONV_D1_4096)) return false; delay(10);
  uint32_t D1=0; if(!msReadADC(D1)) return false;
  int32_t dT=(int32_t)D2 - ((int32_t)C_ms[5] << 8);
  int64_t OFF = ((int64_t)C_ms[2] << 16) + (((int64_t)C_ms[4] * dT) >> 7);
  int64_t SENS= ((int64_t)C_ms[1] << 15) + (((int64_t)C_ms[3] * dT) >> 8);
  int32_t TEMP= 2000 + ((int64_t)dT * (int32_t)C_ms[6]) / 8388608;
  int32_t P= (int32_t)(((((int64_t)D1 * SENS) >> 21) - OFF) >> 15);
  press_mbar = P / 100.0f; tempC = TEMP / 100.0f; return true;
}
float pressureToAltitude(float p_mbar, float p0_mbar){ return 44330.0f * (1.0f - powf(p_mbar / p0_mbar, 0.19029495f)); }
