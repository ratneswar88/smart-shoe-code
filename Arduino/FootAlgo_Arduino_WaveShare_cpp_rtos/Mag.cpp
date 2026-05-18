#include "Mag.h"
#include <Wire.h>
#define HMC_ADDR 0x1E
#define QMC_ADDR 0x0D
#define HMC_REG_CONF_A 0x00
#define HMC_REG_CONF_B 0x01
#define HMC_REG_MODE   0x02
#define HMC_REG_DATA   0x03
#define QMC_REG_DATA   0x00
#define QMC_REG_CONF1  0x09
#define QMC_REG_CONF2  0x0A
#define QMC_REG_RSTPER 0x0B
static MagType sType = MAG_NONE;
static bool i2cWrite1(uint8_t addr, uint8_t reg, uint8_t val){ Wire.beginTransmission(addr); Wire.write(reg); Wire.write(val); return Wire.endTransmission()==0; }
static bool i2cReadN(uint8_t addr, uint8_t reg, uint8_t *buf, size_t n){ Wire.beginTransmission(addr); Wire.write(reg); if(Wire.endTransmission(false)!=0) return false; size_t r=Wire.requestFrom((int)addr,(int)n); if(r!=n) return false; for(size_t i=0;i<n;++i) buf[i]=Wire.read(); return true; }
static bool hmcInit(){ uint8_t dummy[3]; if(!i2cReadN(HMC_ADDR,0x0A,dummy,3)) return false;
  if(!i2cWrite1(HMC_ADDR,HMC_REG_CONF_A,0x70)) return false;
  if(!i2cWrite1(HMC_ADDR,HMC_REG_CONF_B,0x20)) return false;
  if(!i2cWrite1(HMC_ADDR,HMC_REG_MODE,0x00)) return false;
  sType=MAG_HMC5883L; return true;
}
static bool qmcInit(){ i2cWrite1(QMC_ADDR,QMC_REG_CONF2,0x80); delay(10); i2cWrite1(QMC_ADDR,QMC_REG_RSTPER,0x01); if(!i2cWrite1(QMC_ADDR,QMC_REG_CONF1,0x59)) return false; sType=MAG_QMC5883L; return true; }
bool magInit(){ if(hmcInit()) return true; if(qmcInit()) return true; sType=MAG_NONE; return false; }
MagType magGetType(){ return sType; }
bool magReadRaw(float &mx, float &my, float &mz){
  if (sType==MAG_HMC5883L){ uint8_t b[6]; if(!i2cReadN(HMC_ADDR,HMC_REG_DATA,b,6)) return false;
    int16_t X=(int16_t)((b[0]<<8)|b[1]); int16_t Z=(int16_t)((b[2]<<8)|b[3]); int16_t Y=(int16_t)((b[4]<<8)|b[5]);
    mx=(float)X; my=(float)Y; mz=(float)Z; return true; }
  if (sType==MAG_QMC5883L){ uint8_t b[6]; if(!i2cReadN(QMC_ADDR,QMC_REG_DATA,b,6)) return false;
    int16_t X=(int16_t)((b[1]<<8)|b[0]); int16_t Y=(int16_t)((b[3]<<8)|b[2]); int16_t Z=(int16_t)((b[5]<<8)|b[4]);
    mx=(float)X; my=(float)Y; mz=(float)Z; return true; }
  return false;
}
