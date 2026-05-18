//
// SmartShoeStepPro_bypass_fix.ino
// ESP32 + GY-86 — enables MPU6050 I2C BYPASS so HMC5883L/QMC5883L is visible on main I²C.
// Includes previous step-detector tunings + debug tools.
//

#include <Arduino.h>
#include <math.h>
#include <Wire.h>
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLE2902.h>

// ---------------- I2C helpers ----------------
void i2cScan(const char* tag){
  Serial.printf("[I2C] Scan %s ...\n", tag);
  byte count = 0;
  for(byte addr=1; addr<127; addr++){
    Wire.beginTransmission(addr);
    if(Wire.endTransmission()==0){
      Serial.printf(" - 0x%02X\n", addr);
      count++;
    }
  }
  if(count==0) Serial.println(" - none");
}

// ---------------- MPU6050 ----------------
#define MPU6050_ADDR 0x68
#define MPU6050_REG_PWR_MGMT_1 0x6B
#define MPU6050_REG_SMPLRT_DIV 0x19
#define MPU6050_REG_CONFIG     0x1A
#define MPU6050_REG_GYRO_CONFIG 0x1B
#define MPU6050_REG_ACCEL_CONFIG 0x1C
#define MPU6050_REG_ACCEL_XOUT_H 0x3B
#define MPU6050_REG_INT_PIN_CFG 0x37
#define MPU6050_REG_USER_CTRL   0x6A

#ifndef SDA_PIN
#define SDA_PIN 21
#endif
#ifndef SCL_PIN
#define SCL_PIN 22
#endif

static float ACC_SENS = 8192.0f;  // LSB/g for ±4g
static float GYR_SENS = 65.5f;    // LSB/(°/s) for ±500 dps

bool mpuWrite(uint8_t reg, uint8_t val) {
  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(reg);
  Wire.write(val);
  return Wire.endTransmission() == 0;
}
bool mpuReadN(uint8_t reg, uint8_t *buf, size_t n) {
  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) return false;
  size_t r = Wire.requestFrom((int)MPU6050_ADDR, (int)n);
  if (r != n) return false;
  for (size_t i = 0; i < n; ++i) buf[i] = Wire.read();
  return true;
}

bool mpuInit() {
  delay(50);
  if (!mpuWrite(MPU6050_REG_PWR_MGMT_1, 0x00)) return false; // wake
  delay(10);
  if (!mpuWrite(MPU6050_REG_CONFIG, 0x03)) return false;      // DLPF=3
  if (!mpuWrite(MPU6050_REG_GYRO_CONFIG, 0x08)) return false; // ±500 dps
  if (!mpuWrite(MPU6050_REG_ACCEL_CONFIG, 0x08)) return false;// ±4g
  if (!mpuWrite(MPU6050_REG_SMPLRT_DIV, 9)) return false;     // 100 Hz
  delay(10);
  return true;
}

// Enable I2C BYPASS so AUX bus devices (magnetometer) appear on main I2C (ESP32 pins)
bool mpuEnableBypass(){
  // Disable I2C Master mode
  if (!mpuWrite(MPU6050_REG_USER_CTRL, 0x00)) return false;
  delay(2);
  // Enable BYPASS_EN (bit1) on INT_PIN_CFG
  if (!mpuWrite(MPU6050_REG_INT_PIN_CFG, 0x02)) return false;
  delay(2);
  // Read back for confirmation
  uint8_t v=0;
  if (!mpuReadN(MPU6050_REG_INT_PIN_CFG, &v, 1)) return false;
  Serial.printf("[MPU] INT_PIN_CFG=0x%02X (expect BYPASS_EN bit1 set)\n", v);
  return (v & 0x02) != 0;
}

bool mpuRead(float &ax_g, float &ay_g, float &az_g, float &gx_dps, float &gy_dps, float &gz_dps, int16_t &rawTemp) {
  uint8_t buf[14];
  if (!mpuReadN(MPU6050_REG_ACCEL_XOUT_H, buf, 14)) return false;
  auto rd = [&](int idx) -> int16_t { return (int16_t)((buf[idx] << 8) | buf[idx+1]); };
  int16_t ax = rd(0), ay = rd(2), az = rd(4), gx = rd(8), gy = rd(10), gz = rd(12);
  rawTemp = rd(6);
  ax_g = (float)ax / ACC_SENS; ay_g = (float)ay / ACC_SENS; az_g = (float)az / ACC_SENS;
  gx_dps = (float)gx / GYR_SENS; gy_dps = (float)gy / GYR_SENS; gz_dps = (float)gz / GYR_SENS;
  return true;
}

// ---------------- MS5611 (Temp only) ----------------
#define MS5611_ADDR 0x77
#define MS5611_CMD_RESET 0x1E
#define MS5611_CMD_CONV_D2_4096 0x58
#define MS5611_CMD_ADC_READ 0x00
#define MS5611_CMD_PROM_READ_BASE 0xA2
uint16_t C_ms[7]; bool ms5611Present=false;
bool msWrite(uint8_t cmd){ Wire.beginTransmission(MS5611_ADDR); Wire.write(cmd); return Wire.endTransmission()==0; }
bool msReadN(uint8_t cmd, uint8_t *buf, size_t n){ Wire.beginTransmission(MS5611_ADDR); Wire.write(cmd); if(Wire.endTransmission(false)!=0) return false; size_t r=Wire.requestFrom((int)MS5611_ADDR,(int)n); if(r!=n) return false; for(size_t i=0;i<n;++i) buf[i]=Wire.read(); return true; }
bool msReset(){ return msWrite(MS5611_CMD_RESET); }
bool msReadProm(){ for(int i=0;i<6;i++){ uint8_t b[2]; if(!msReadN(MS5611_CMD_PROM_READ_BASE+i*2,b,2)) return false; C_ms[i+1]=(b[0]<<8)|b[1]; } return true; }
bool msReadADC(uint32_t &val){ uint8_t b[3]; if(!msReadN(MS5611_CMD_ADC_READ,b,3)) return false; val=((uint32_t)b[0]<<16)|((uint32_t)b[1]<<8)|b[2]; return true; }
bool msReadTemp(float &tempC){ if(!msWrite(MS5611_CMD_CONV_D2_4096)) return false; delay(10); uint32_t D2=0; if(!msReadADC(D2)) return false; int32_t dT=(int32_t)D2-((int32_t)C_ms[5]<<8); int32_t TEMP=2000+((int64_t)dT*(int32_t)C_ms[6])/8388608; tempC=TEMP/100.0f; return true; }
bool msInit(){ if(!msReset()) return false; delay(5); return msReadProm(); }

// ---------------- Magnetometer (HMC5883L / QMC5883L) ----------------
enum MagType { MAG_NONE, MAG_HMC5883L, MAG_QMC5883L };
MagType magType = MAG_NONE;
#define HMC_ADDR 0x1E
#define QMC_ADDR 0x0D
#define HMC_REG_CONF_A 0x00
#define HMC_REG_CONF_B 0x01
#define HMC_REG_MODE   0x02
#define HMC_REG_DATA   0x03
#define HMC_REG_IDA    0x0A
#define HMC_REG_IDB    0x0B
#define HMC_REG_IDC    0x0C
#define QMC_REG_DATA   0x00
#define QMC_REG_CONF1  0x09
#define QMC_REG_CONF2  0x0A
#define QMC_REG_RSTPER 0x0B
bool i2cWrite1(uint8_t addr, uint8_t reg, uint8_t val){ Wire.beginTransmission(addr); Wire.write(reg); Wire.write(val); return Wire.endTransmission()==0; }
bool i2cReadN(uint8_t addr, uint8_t reg, uint8_t *buf, size_t n){ Wire.beginTransmission(addr); Wire.write(reg); if(Wire.endTransmission(false)!=0) return false; size_t r=Wire.requestFrom((int)addr,(int)n); if(r!=n) return false; for(size_t i=0;i<n;++i) buf[i]=Wire.read(); return true; }
bool hmcInit(){ uint8_t id[3]; if(!i2cReadN(HMC_ADDR,HMC_REG_IDA,id,3)) return false; if(!(id[0]==0x48 && id[1]==0x34 && id[2]==0x33)){ Serial.printf("[MAG] HMC ID mismatch: %02X %02X %02X\n", id[0],id[1],id[2]); return false; } if(!i2cWrite1(HMC_ADDR,HMC_REG_CONF_A,0x70)) return false; if(!i2cWrite1(HMC_ADDR,HMC_REG_CONF_B,0x20)) return false; if(!i2cWrite1(HMC_ADDR,HMC_REG_MODE,0x00)) return false; magType=MAG_HMC5883L; return true; }
bool qmcInit(){ i2cWrite1(QMC_ADDR,QMC_REG_CONF2,0x80); delay(10); i2cWrite1(QMC_ADDR,QMC_REG_RSTPER,0x01); if(!i2cWrite1(QMC_ADDR,QMC_REG_CONF1,0x59)) return false; magType=MAG_QMC5883L; return true; }
bool magInit(){ if(hmcInit()) return true; if(qmcInit()) return true; magType=MAG_NONE; return false; }
bool magReadRaw(float &mx, float &my, float &mz){
  if (magType==MAG_HMC5883L){ uint8_t b[6]; if(!i2cReadN(HMC_ADDR,HMC_REG_DATA,b,6)) return false; int16_t X=(int16_t)((b[0]<<8)|b[1]); int16_t Z=(int16_t)((b[2]<<8)|b[3]); int16_t Y=(int16_t)((b[4]<<8)|b[5]); mx=(float)X; my=(float)Y; mz=(float)Z; return true; }
  if (magType==MAG_QMC5883L){ uint8_t b[6]; if(!i2cReadN(QMC_ADDR,QMC_REG_DATA,b,6)) return false; int16_t X=(int16_t)((b[1]<<8)|b[0]); int16_t Y=(int16_t)((b[3]<<8)|b[2]); int16_t Z=(int16_t)((b[5]<<8)|b[4]); mx=(float)X; my=(float)Y; mz=(float)Z; return true; }
  return false;
}

// ---------------- BLE (UUID map) ----------------
#define BLE_SERVICE_UUID        "0000feed-0000-1000-8000-00805f9b34fb"
#define BLE_CHAR_ROLL_UUID      "0000a001-0000-1000-8000-00805f9b34fb"
#define BLE_CHAR_PITCH_UUID     "0000a002-0000-1000-8000-00805f9b34fb"
#define BLE_CHAR_YAW_UUID       "0000a003-0000-1000-8000-00805f9b34fb"
#define BLE_CHAR_TEMP_UUID      "0000b001-0000-1000-8000-00805f9b34fb"
#define BLE_CHAR_STEPS_UUID     "0000c001-0000-1000-8000-00805f9b34fb"
#define BLE_CHAR_CADENCE_UUID   "0000c002-0000-1000-8000-00805f9b34fb"
#define BLE_CHAR_COMMAND_UUID   "0000d001-0000-1000-8000-00805f9b34fb"

BLEServer *pServer = nullptr;
BLECharacteristic *chRoll  = nullptr;
BLECharacteristic *chPitch = nullptr;
BLECharacteristic *chYaw   = nullptr;
BLECharacteristic *chTemp  = nullptr;
BLECharacteristic *chSteps = nullptr;
BLECharacteristic *chCad   = nullptr;
BLECharacteristic *chCmd   = nullptr;
bool deviceConnected = false;

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pS) override { deviceConnected = true; Serial.println("[BLE] Connected"); }
  void onDisconnect(BLEServer* pS) override { deviceConnected = false; Serial.println("[BLE] Disconnected"); pS->startAdvertising(); }
};

// ---- Command handler using Arduino String ----
bool debugPrint=false;
class CmdCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    auto raw=c->getValue(); String v=String(raw.c_str()); v.trim(); if(!v.length()) return; Serial.printf("[CMD] %s\n", v.c_str());
    if (v.equalsIgnoreCase("reset")){ extern volatile uint32_t stepCount; stepCount=0; c->setValue((uint8_t*)"OK",2); return; }
    if (v.startsWith("notify_hz=")){ int hz=v.substring(10).toInt(); if(hz<1) hz=1; if(hz>25) hz=25; extern uint32_t notifyPeriodMs; notifyPeriodMs=1000/(uint32_t)hz; c->setValue((uint8_t*)"OK",2); return; }
    if (v.startsWith("debug=")){ debugPrint = v.substring(6).toInt()!=0; c->setValue((uint8_t*)"OK",2); return; }
  }
};

void setupBLE() {
  BLEDevice::init("MADEPLUS SMART SHOE");
  BLEServer* srv = BLEDevice::createServer();
  srv->setCallbacks(new ServerCallbacks());
  BLEService* svc = srv->createService(BLE_SERVICE_UUID);
  chRoll  = svc->createCharacteristic(BLE_CHAR_ROLL_UUID,    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  chPitch = svc->createCharacteristic(BLE_CHAR_PITCH_UUID,   BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  chYaw   = svc->createCharacteristic(BLE_CHAR_YAW_UUID,     BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  chTemp  = svc->createCharacteristic(BLE_CHAR_TEMP_UUID,    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  chSteps = svc->createCharacteristic(BLE_CHAR_STEPS_UUID,   BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  chCad   = svc->createCharacteristic(BLE_CHAR_CADENCE_UUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  chCmd   = svc->createCharacteristic(BLE_CHAR_COMMAND_UUID, BLECharacteristic::PROPERTY_READ  | BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  chRoll->addDescriptor(new BLE2902()); chPitch->addDescriptor(new BLE2902()); chYaw->addDescriptor(new BLE2902());
  chTemp->addDescriptor(new BLE2902()); chSteps->addDescriptor(new BLE2902()); chCad->addDescriptor(new BLE2902());
  chCmd->setCallbacks(new CmdCallbacks());
  svc->start(); BLEAdvertising* adv=BLEDevice::getAdvertising(); adv->addServiceUUID(BLE_SERVICE_UUID); adv->setScanResponse(true); adv->setMinPreferred(0x06); adv->setMaxPreferred(0x12); BLEDevice::startAdvertising();
  Serial.println("[BLE] Advertising");
}

// ---------------- Step Detector (same tuned version) ----------------
struct OnlineStats{ float mean=0,M2=0; uint32_t n=0; void update(float x){ n++; float d=x-mean; mean+=d/n; M2+=d*(x-mean);} float var()const{return (n>1)?M2/(n-1):0;} float stddev()const{return sqrtf(var());}};
volatile uint32_t stepCount=0; float cadence=0.0f; unsigned long lastStepMs=0; unsigned long lastPeaks[8]; int peakIdx=0;
static float g_est_x=0,g_est_y=0,g_est_z=0, hp_prev=0,x_prev=0,lp_prev=0; static OnlineStats stats;
float LPF_gravity_fc=1.0f, HPF_step_fc=0.4f, LPF_step_fc=4.5f, thresh_k_sigma=1.2f, thresh_min=0.08f, peak_hysteresis=0.03f, cadence_alpha=0.25f;
unsigned long minISIms=200, maxISIms=2000; bool warmedUp=false; unsigned long startMs=0;

inline float bandpassStep(float lin_mag, float dt){ float a_h=1.0f/(1.0f+1.0f/(2.0f*PI*HPF_step_fc*dt)); float y_h=a_h*(hp_prev+lin_mag-x_prev); hp_prev=y_h; x_prev=lin_mag; float b_l=expf(-2.0f*PI*LPF_step_fc*dt); float y_bp=b_l*lp_prev+(1.0f-b_l)*y_h; lp_prev=y_bp; return y_bp; }

void processStepDetectionPro(float ax,float ay,float az,float gx_dps,float gy_dps,float gz_dps){
  const unsigned long now=millis(); static unsigned long lastMs=now; float dt=(now-lastMs)*0.001f; if(dt<=0) dt=0.01f; lastMs=now;
  float alpha_g=1.0f-expf(-2.0f*PI*LPF_gravity_fc*dt); g_est_x+=alpha_g*(ax-g_est_x); g_est_y+=alpha_g*(ay-g_est_y); g_est_z+=alpha_g*(az-g_est_z);
  float lin_x=ax-g_est_x, lin_y=ay-g_est_y, lin_z=az-g_est_z; float lin_mag=sqrtf(lin_x*lin_x+lin_y*lin_y+lin_z*lin_z);
  float s=bandpassStep(lin_mag,dt);
  if(!warmedUp){ stats.update(s); if(millis()-startMs>1500) warmedUp=true; return; }
  stats.update(s); float sigma=fmaxf(0.001f,stats.stddev()); float dynThresh=fmaxf(thresh_min,thresh_k_sigma*sigma);
  static float s_prev=0,s_prev2=0; bool slopeDown=(s_prev-s)>0.0f && (s_prev2-s_prev)<0.0f; s_prev2=s_prev; s_prev=s;
  unsigned long isiMin=minISIms; if(cadence>0.1f){ float isi_est=60000.0f/cadence; isiMin=(unsigned long)fmaxf(minISIms,0.45f*isi_est); }
  bool overThresh=(s_prev>dynThresh), hysteresisOK=(s_prev-s)>peak_hysteresis; unsigned long isi=now-lastStepMs; bool isiOK=isi>isiMin && isi<maxISIms;
  if(debugPrint){ static uint32_t lp=0; if(now-lp>200){ Serial.printf("[DBG] s=%.3f thr=%.3f sig=%.3f slopeDown=%d hyst=%d isi=%lu ok=%d\n", s_prev,dynThresh,sigma,slopeDown,hysteresisOK,isi,(int)isiOK); lp=now; } }
  if(slopeDown && overThresh && hysteresisOK && isiOK){ stepCount++; lastStepMs=now; lastPeaks[peakIdx&7]=now; peakIdx++; if(peakIdx>1){ int k=(peakIdx>=8)?8:peakIdx; unsigned long tNew=lastPeaks[(peakIdx-1)&7]; unsigned long tOld=lastPeaks[(peakIdx-k)&7]; unsigned long dtSum=tNew-tOld; if(dtSum>0){ float instCad=(float)(k-1)*60000.0f/(float)dtSum; cadence=(1.0f-cadence_alpha)*cadence+cadence_alpha*instCad; } } }
}

// ---------------- App ----------------
const uint32_t SAMPLE_HZ=100; uint32_t NOTIFY_HZ=10; uint32_t samplePeriodMs=1000/SAMPLE_HZ; uint32_t notifyPeriodMs=1000/10;
unsigned long lastSample=0,lastNotify=0; float lastRoll=0,lastPitch=0,lastYaw=0,lastTemp=0; float declinationDeg=0.0f;

void setup(){
  Serial.begin(115200); delay(300); Serial.println("SmartShoeStepPro (BYPASS fix)");
  Wire.begin(SDA_PIN,SCL_PIN,400000);
  i2cScan("before MPU init");
  if(!mpuInit()){ Serial.println("MPU6050 init FAILED"); while(1){ delay(1000);} }
  if(mpuEnableBypass()) Serial.println("[MPU] BYPASS enabled"); else Serial.println("[MPU] BYPASS enable FAILED");
  i2cScan("after BYPASS");
  ms5611Present = msInit(); Serial.printf("MS5611 temp %s\n", ms5611Present?"OK":"not found");
  if(!magInit()) Serial.println("Magnetometer not found (yaw will be 0)");
  else Serial.printf("Magnetometer type: %s\n", (magType==MAG_HMC5883L?"HMC5883L":"QMC5883L"));
  setupBLE(); Serial.println("BLE started.");
  startMs=millis();
}

void loop(){
  unsigned long now=millis();
  if(now-lastSample>=samplePeriodMs){
    lastSample=now; float ax,ay,az,gx,gy,gz; int16_t rawT=0;
    if(mpuRead(ax,ay,az,gx,gy,gz,rawT)){
      processStepDetectionPro(ax,ay,az,gx,gy,gz);
      lastRoll=atan2f(ay,az)*57.29578f; lastPitch=atan2f(-ax,sqrtf(ay*ay+az*az))*57.29578f;
    }
  }
  if(now-lastNotify>=notifyPeriodMs){
    lastNotify=now;
    float tC=0; if(ms5611Present && msReadTemp(tC)) lastTemp=tC; else { float ax,ay,az,gx,gy,gz; int16_t rawT; if(mpuRead(ax,ay,az,gx,gy,gz,rawT)) lastTemp=(float)rawT/340.0f+36.53f; }
    if(magType!=MAG_NONE){ float mx,my,mz; if(magReadRaw(mx,my,mz)){ float r=lastRoll*0.017453293f, p=lastPitch*0.017453293f; float Xh=mx*cosf(p)+mz*sinf(p); float Yh=mx*sinf(r)*sinf(p)+my*cosf(r)-mz*sinf(r)*cosf(p); float heading=atan2f(Yh,Xh)*57.29578f+declinationDeg; if(heading>180) heading-=360; if(heading<-180) heading+=360; lastYaw=heading; } }
    else lastYaw=0.0f;
    if(deviceConnected){ uint32_t steps=stepCount; float cad=cadence;
      chRoll->setValue((uint8_t*)&lastRoll,sizeof(lastRoll)); chRoll->notify();
      chPitch->setValue((uint8_t*)&lastPitch,sizeof(lastPitch)); chPitch->notify();
      chYaw->setValue((uint8_t*)&lastYaw,sizeof(lastYaw)); chYaw->notify();
      chTemp->setValue((uint8_t*)&lastTemp,sizeof(lastTemp)); chTemp->notify();
      chSteps->setValue((uint8_t*)&steps,sizeof(steps)); chSteps->notify();
      chCad->setValue((uint8_t*)&cad,sizeof(cad)); chCad->notify();
      static uint32_t lp=0; if(now-lp>1000){ Serial.printf("[BLE] steps=%lu cad=%.1f R=%.1f P=%.1f Y=%.1f T=%.2fC\n",(unsigned long)steps,cad,lastRoll,lastPitch,lastYaw,lastTemp); lp=now; }
    }
  }
}
