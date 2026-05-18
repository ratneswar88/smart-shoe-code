#include "MPU6050.h"
#include <Wire.h>
float ACC_SENS = 8192.0f; float GYR_SENS = 65.5f;
static bool mpuWrite(uint8_t reg, uint8_t val) { Wire.beginTransmission(MPU6050_ADDR); Wire.write(reg); Wire.write(val); return Wire.endTransmission() == 0; }
static bool mpuReadN(uint8_t reg, uint8_t *buf, size_t n) {
  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) return false;
  size_t r = Wire.requestFrom((int)MPU6050_ADDR, (int)n);
  if (r != n) return false;
  for (size_t i = 0; i < n; ++i) buf[i] = Wire.read();
  return true;
}
bool mpuInit200Hz() {
  delay(50);
  if (!mpuWrite(MPU6050_REG_PWR_MGMT_1, 0x00)) return false;
  delay(10);
  if (!mpuWrite(MPU6050_REG_CONFIG,     0x04)) return false;
  if (!mpuWrite(MPU6050_REG_GYRO_CONFIG, 0x08)) return false;
  if (!mpuWrite(MPU6050_REG_ACCEL_CONFIG,0x08)) return false;
  if (!mpuWrite(MPU6050_REG_SMPLRT_DIV, 4)) return false;
  delay(10);
  return true;
}
bool mpuEnableBypass(){
  if (!mpuWrite(MPU6050_REG_USER_CTRL, 0x00)) return false;
  delay(2);
  if (!mpuWrite(MPU6050_REG_INT_PIN_CFG, 0x02)) return false;
  delay(2);
  uint8_t v=0; if (!mpuReadN(MPU6050_REG_INT_PIN_CFG, &v, 1)) return false;
  return (v & 0x02) != 0;
}
bool mpuReadAll(float &ax_g,float &ay_g,float &az_g, float &gx_dps,float &gy_dps,float &gz_dps, int16_t &rawTemp){
  uint8_t b[14];
  if (!mpuReadN(MPU6050_REG_ACCEL_XOUT_H, b, 14)) return false;
  auto rd = [&](int i)->int16_t{ return (int16_t)((b[i]<<8)|b[i+1]); };
  int16_t ax=rd(0), ay=rd(2), az=rd(4), gx=rd(8), gy=rd(10), gz=rd(12);
  rawTemp = rd(6);
  ax_g=ax/ACC_SENS; ay_g=ay/ACC_SENS; az_g=az/ACC_SENS;
  gx_dps=gx/GYR_SENS; gy_dps=gy/GYR_SENS; gz_dps=gz/GYR_SENS;
  return true;
}
