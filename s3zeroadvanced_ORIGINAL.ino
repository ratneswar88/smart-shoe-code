// GY86_ESP32S3_FootAlgo_ZUPT_SDA8_SCL9.ino
// ESP32-S3 + GY-86 (MPU6050 + MS5611 + HMC5883L/QMC5883L)
// Foot-mounted minimal algorithm with:
// - 2s gyro bias calibration
// - 200 Hz sampling, ~20 Hz low-pass
// - Complementary filter tilt (roll/pitch) from gyro+accel
// - Stance (ZUPT) via gyro |w| + accel variance window
// - Step events (heel-strike / toe-off), cadence
// - ZUPT-aided swing integration => stride length (horizontal displacement)
// - Barometer pressure->altitude; per-step Δh to detect uphill/downhill
// BLE: floats (roll/pitch/yaw/temp/steps/cadence/strideLen/altStep) + ASCII line.
// NimBLE only, no NimBLE2902, no override keywords.

#include <Arduino.h>
#include <math.h>
#include <Wire.h>
#include <NimBLEDevice.h>

// ---------- Utilities ----------
#ifndef LED_BUILTIN
#define LED_BUILTIN 2
#endif
#define LOGF(...) do { Serial.printf(__VA_ARGS__); Serial.flush(); } while(0)
#define LOGLN(x)  do { Serial.println(x); Serial.flush(); } while(0)
static const float PI_F = 3.14159265358979323846f;
static const float DEG2RAD = PI_F / 180.0f;
static const float RAD2DEG = 180.0f / PI_F;
static const float G_MPS2   = 9.80665f;

// ---------- I2C pins ----------
#undef SDA_PIN
#undef SCL_PIN
#define SDA_PIN 8
#define SCL_PIN 9

void i2cScan(const char* tag){
  LOGF("[I2C] Scan %s ...\n", tag);
  byte n = 0;
  for(byte a=1;a<127;a++){
    Wire.beginTransmission(a);
    if(Wire.endTransmission()==0){ LOGF(" - 0x%02X\n", a); n++; }
  }
  if(!n) LOGLN(" - none");
}

// ---------- MPU6050 ----------
#define MPU6050_ADDR 0x68
#define MPU6050_REG_PWR_MGMT_1 0x6B
#define MPU6050_REG_SMPLRT_DIV 0x19
#define MPU6050_REG_CONFIG     0x1A
#define MPU6050_REG_GYRO_CONFIG 0x1B
#define MPU6050_REG_ACCEL_CONFIG 0x1C
#define MPU6050_REG_ACCEL_XOUT_H 0x3B
#define MPU6050_REG_INT_PIN_CFG 0x37
#define MPU6050_REG_USER_CTRL   0x6A

// ±4g, ±500 dps
static float ACC_SENS = 8192.0f;  // LSB/g
static float GYR_SENS = 65.5f;    // LSB/(deg/s)

bool mpuWrite(uint8_t reg, uint8_t val) {
  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(reg); Wire.write(val);
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
bool mpuInit200Hz() {
  delay(50);
  if (!mpuWrite(MPU6050_REG_PWR_MGMT_1, 0x00)) return false; // wake
  delay(10);
  // DLPF ~20 Hz -> DLPF_CFG=4
  if (!mpuWrite(MPU6050_REG_CONFIG,     0x04)) return false; // ~20 Hz LPF
  if (!mpuWrite(MPU6050_REG_GYRO_CONFIG, 0x08)) return false; // ±500 dps
  if (!mpuWrite(MPU6050_REG_ACCEL_CONFIG,0x08)) return false; // ±4 g
  // Sample rate (with DLPF on): 1kHz / (1+DIV). DIV=4 -> 200 Hz.
  if (!mpuWrite(MPU6050_REG_SMPLRT_DIV, 4)) return false;     // 200 Hz
  delay(10);
  return true;
}
bool mpuEnableBypass(){
  if (!mpuWrite(MPU6050_REG_USER_CTRL, 0x00)) return false; // disable master
  delay(2);
  if (!mpuWrite(MPU6050_REG_INT_PIN_CFG, 0x02)) return false; // BYPASS_EN
  delay(2);
  uint8_t v=0; if (!mpuReadN(MPU6050_REG_INT_PIN_CFG, &v, 1)) return false;
  LOGF("[MPU] INT_PIN_CFG=0x%02X (BYPASS_EN)\n", v);
  return (v & 0x02) != 0;
}
bool mpuReadAll(float &ax_g,float &ay_g,float &az_g,float &gx_dps,float &gy_dps,float &gz_dps,int16_t &rawTemp){
  uint8_t b[14];
  if (!mpuReadN(MPU6050_REG_ACCEL_XOUT_H, b, 14)) return false;
  auto rd = [&](int i)->int16_t{ return (int16_t)((b[i]<<8)|b[i+1]); };
  int16_t ax=rd(0), ay=rd(2), az=rd(4), gx=rd(8), gy=rd(10), gz=rd(12);
  rawTemp = rd(6);
  ax_g=ax/ACC_SENS; ay_g=ay/ACC_SENS; az_g=az/ACC_SENS;
  gx_dps=gx/GYR_SENS; gy_dps=gy/GYR_SENS; gz_dps=gz/GYR_SENS;
  return true;
}

// ---------- MS5611 (pressure + temp) ----------
#define MS5611_ADDR 0x77
#define MS5611_CMD_RESET 0x1E
#define MS5611_CMD_CONV_D1_4096 0x48
#define MS5611_CMD_CONV_D2_4096 0x58
#define MS5611_CMD_ADC_READ 0x00
#define MS5611_CMD_PROM_READ_BASE 0xA2

uint16_t C_ms[7]; bool msPresent=false;

bool msWrite(uint8_t cmd){ Wire.beginTransmission(MS5611_ADDR); Wire.write(cmd); return Wire.endTransmission()==0; }
bool msReadN(uint8_t cmd, uint8_t *buf, size_t n){
  Wire.beginTransmission(MS5611_ADDR); Wire.write(cmd);
  if(Wire.endTransmission(false)!=0) return false;
  size_t r=Wire.requestFrom((int)MS5611_ADDR,(int)n);
  if(r!=n) return false;
  for(size_t i=0;i<n;++i) buf[i]=Wire.read();
  return true;
}
bool msReset(){ return msWrite(MS5611_CMD_RESET); }
bool msReadProm(){
  for(int i=0;i<6;i++){ uint8_t b[2];
    if(!msReadN(MS5611_CMD_PROM_READ_BASE+i*2,b,2)) return false;
    C_ms[i+1]=(b[0]<<8)|b[1];
  } return true;
}
bool msReadADC(uint32_t &val){
  uint8_t b[3]; if(!msReadN(MS5611_CMD_ADC_READ,b,3)) return false;
  val=((uint32_t)b[0]<<16)|((uint32_t)b[1]<<8)|b[2]; return true;
}
bool msReadPT(float &press_mbar, float &tempC){
  if(!msWrite(MS5611_CMD_CONV_D2_4096)) return false; delay(10);
  uint32_t D2=0; if(!msReadADC(D2)) return false;
  if(!msWrite(MS5611_CMD_CONV_D1_4096)) return false; delay(10);
  uint32_t D1=0; if(!msReadADC(D1)) return false;

  int32_t dT=(int32_t)D2 - ((int32_t)C_ms[5] << 8);
  int64_t OFF = ((int64_t)C_ms[2] << 16) + (((int64_t)C_ms[4] * dT) >> 7);
  int64_t SENS= ((int64_t)C_ms[1] << 15) + (((int64_t)C_ms[3] * dT) >> 8);
  int32_t TEMP= 2000 + ((int64_t)dT * (int32_t)C_ms[6]) / 8388608; // 2^23

  int32_t P= (int32_t)(((((int64_t)D1 * SENS) >> 21) - OFF) >> 15);
  press_mbar = P / 100.0f;
  tempC = TEMP / 100.0f;
  return true;
}
float pressureToAltitude(float p_mbar, float p0_mbar=1013.25f){
  // International Standard Atmosphere
  return 44330.0f * (1.0f - powf(p_mbar / p0_mbar, 0.19029495f));
}
bool msInit(){ if(!msReset()) return false; delay(5); return msReadProm(); }

// ---------- Magnetometer (optional smoothing for yaw) ----------
enum MagType { MAG_NONE, MAG_HMC5883L, MAG_QMC5883L };
MagType magType = MAG_NONE;
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

bool i2cWrite1(uint8_t addr, uint8_t reg, uint8_t val){ Wire.beginTransmission(addr); Wire.write(reg); Wire.write(val); return Wire.endTransmission()==0; }
bool i2cReadN_mag(uint8_t addr, uint8_t reg, uint8_t *buf, size_t n){ Wire.beginTransmission(addr); Wire.write(reg); if(Wire.endTransmission(false)!=0) return false; size_t r=Wire.requestFrom((int)addr,(int)n); if(r!=n) return false; for(size_t i=0;i<n;++i) buf[i]=Wire.read(); return true; }
bool hmcInit(){ uint8_t dummy[3]; if(!i2cReadN_mag(HMC_ADDR,0x0A,dummy,3)) return false;
  if(!i2cWrite1(HMC_ADDR,HMC_REG_CONF_A,0x70)) return false;
  if(!i2cWrite1(HMC_ADDR,HMC_REG_CONF_B,0x20)) return false;
  if(!i2cWrite1(HMC_ADDR,HMC_REG_MODE,0x00)) return false;
  magType=MAG_HMC5883L; return true;
}
bool qmcInit(){ i2cWrite1(QMC_ADDR,QMC_REG_CONF2,0x80); delay(10); i2cWrite1(QMC_ADDR,QMC_REG_RSTPER,0x01); if(!i2cWrite1(QMC_ADDR,QMC_REG_CONF1,0x59)) return false; magType=MAG_QMC5883L; return true; }
bool magInit(){ if(hmcInit()) return true; if(qmcInit()) return true; magType=MAG_NONE; return false; }
bool magReadRaw(float &mx, float &my, float &mz){
  if (magType==MAG_HMC5883L){ uint8_t b[6]; if(!i2cReadN_mag(HMC_ADDR,HMC_REG_DATA,b,6)) return false;
    int16_t X=(int16_t)((b[0]<<8)|b[1]); int16_t Z=(int16_t)((b[2]<<8)|b[3]); int16_t Y=(int16_t)((b[4]<<8)|b[5]);
    mx=(float)X; my=(float)Y; mz=(float)Z; return true; }
  if (magType==MAG_QMC5883L){ uint8_t b[6]; if(!i2cReadN_mag(QMC_ADDR,QMC_REG_DATA,b,6)) return false;
    int16_t X=(int16_t)((b[1]<<8)|b[0]); int16_t Y=(int16_t)((b[3]<<8)|b[2]); int16_t Z=(int16_t)((b[5]<<8)|b[4]);
    mx=(float)X; my=(float)Y; mz=(float)Z; return true; }
  return false;
}

// ---------- BLE UUIDs ----------
#define BLE_SERVICE_UUID        "0000feed-0000-1000-8000-00805f9b34fb"
#define BLE_CHAR_ROLL_UUID      "0000a001-0000-1000-8000-00805f9b34fb"
#define BLE_CHAR_PITCH_UUID     "0000a002-0000-1000-8000-00805f9b34fb"
#define BLE_CHAR_YAW_UUID       "0000a003-0000-1000-8000-00805f9b34fb"
#define BLE_CHAR_TEMP_UUID      "0000b001-0000-1000-8000-00805f9b34fb"
#define BLE_CHAR_STEPS_UUID     "0000c001-0000-1000-8000-00805f9b34fb"
#define BLE_CHAR_CADENCE_UUID   "0000c002-0000-1000-8000-00805f9b34fb"
#define BLE_CHAR_STRIDEL_UUID   "0000c003-0000-1000-8000-00805f9b34fb" // stride length (m)
#define BLE_CHAR_ALTDH_UUID     "0000b002-0000-1000-8000-00805f9b34fb" // per-step Δh (m)
#define BLE_CHAR_COMMAND_UUID   "0000d001-0000-1000-8000-00805f9b34fb"
#define BLE_CHAR_ASCII_UUID     "0000a0ee-0000-1000-8000-00805f9b34fb"

// ---------- BLE globals ----------
NimBLECharacteristic *chRoll=nullptr,*chPitch=nullptr,*chYaw=nullptr,*chTemp=nullptr,*chSteps=nullptr,*chCad=nullptr,*chStrideL=nullptr,*chAltDH=nullptr,*chCmd=nullptr,*chAscii=nullptr;

// ---------- Algorithm state ----------
struct OnlineStats{ float mean=0,M2=0; uint32_t n=0; void update(float x){ n++; float d=x-mean; mean+=d/n; M2+=d*(x-mean);} float var()const{return (n>1)?M2/(n-1):0;} float stddev()const{return sqrtf(var());}};

// Sampling/filters
const uint32_t SAMPLE_HZ = 200;           // target 200 Hz
const float    DT        = 1.0f / SAMPLE_HZ;
uint32_t samplePeriodMs  = 1000 / SAMPLE_HZ;
uint32_t notifyPeriodMs  = 1000 / 10;     // 10 Hz BLE

// 20 Hz IIR low-pass (extra, on top of MPU DLPF)
const float LPF_FC = 20.0f;
float lpfAlpha(float fc, float dt){ return 1.0f - expf(-2.0f*PI_F*fc*dt); }
float aLPF = lpfAlpha(LPF_FC, DT), gLPF = lpfAlpha(LPF_FC, DT);

// Complementary filter (tilt)
float roll_deg = 0.0f, pitch_deg = 0.0f, yaw_deg = 0.0f; // yaw only for display; not used in ZUPT
const float CF_ALPHA = 0.98f; // gyro trust

// Biases (computed in 2s calibration)
float g_bias_dps[3] = {0,0,0};
float a_bias_g[3]   = {0,0,0}; // optional (used to init tilt)

// Stance detection (ZUPT)
enum GaitState { STANCE=0, SWING=1 };
GaitState state = STANCE;
float gyroMag_dps = 0.0f;

// Rolling variance window over accel magnitude (m/s^2)
const float VAR_WIN_SEC = 0.10f; // 80-120 ms recommended; use 100 ms
const int   VAR_WIN_N   = (int)(SAMPLE_HZ * VAR_WIN_SEC);
float varBuf[ (int)(SAMPLE_HZ*0.2f) + 2 ]; // buffer >= 200ms
int   varN = VAR_WIN_N, varHead=0; bool varFilled=false;
double varSum=0.0, varSumSq=0.0;
float  varA_mps2_2 = 0.0f; // (m/s^2)^2

// ZUPT thresholds (tunable)
float TH_GYRO_DPS  = 25.0f;     // |ω| < 20–30 °/s
float TH_VAR_A     = 0.03f;     // var(a) < 0.02–0.05 (m/s^2)^2
const float STANCE_MIN_SEC = 0.06f;
int stanceHoldSamples = 0;
int stanceHoldNeeded  = (int)(STANCE_MIN_SEC * SAMPLE_HZ);

// Events & cadence
volatile uint32_t stepCount=0;
unsigned long lastHS_ms = 0; // last heel-strike time
float cadence_spm = 0.0f;    // steps per minute
unsigned long hsTimes[8]; int hsIdx=0;

// Swing integration (ZUPT)
float vx=0, vy=0, vz=0;   // world-frame velocities (m/s)
float px=0, py=0, pz=0;   // world-frame displacement during swing (m)
float lastStrideLen_m = 0.0f;

// Model-based quick estimate (optional)
float kGain = 0.50f;      // calibrate on a 20 m walkway for your user
float lastModelLen_m = 0.0f;
float swingVertPeak = G_MPS2; // track during swing

// Barometer
float lastTempC = 0.0f;
float lastPress = NAN, lastAlt_m = NAN;
float prevStepAlt_m = NAN;
float lastStepAltDelta_m = 0.0f; // per-step Δh

// Debug
bool debugPrint=false;

// ---------- BLE callbacks (supports old + new NimBLE callback signatures) ----------
static bool bleClientConnected = false;

static void handleBleConnected() {
  bleClientConnected = true;
  LOGLN("[BLE] Connected");
}

static void handleBleDisconnected(int reason) {
  bleClientConnected = false;
  LOGF("[BLE] Disconnected reason=%d -> re-adv\n", reason);
  delay(200);
  NimBLEDevice::startAdvertising();
}

class ServerCallbacks : public NimBLEServerCallbacks {
public:
  // Older NimBLE-Arduino callback signatures
  void onConnect(NimBLEServer*) { handleBleConnected(); }
  void onDisconnect(NimBLEServer*) { handleBleDisconnected(-1); }

  // Newer NimBLE-Arduino callback signatures
  void onConnect(NimBLEServer*, NimBLEConnInfo&) { handleBleConnected(); }
  void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int reason) { handleBleDisconnected(reason); }
};

class CmdCallbacks : public NimBLECharacteristicCallbacks {
public:
  void onWrite(NimBLECharacteristic* c) {
    std::string s = c->getValue(); if(s.empty()) return;
    String v(s.c_str()); v.trim(); LOGF("[CMD] %s\n", v.c_str());
    if(v.equalsIgnoreCase("reset")) { stepCount=0; vx=vy=vz=px=py=pz=0; c->setValue((uint8_t*)"OK",2); return; }
    if(v.startsWith("notify_hz=")){ int hz=v.substring(10).toInt(); hz=constrain(hz,1,50); notifyPeriodMs = 1000/(uint32_t)hz; c->setValue((uint8_t*)"OK",2); return; }
    if(v.startsWith("debug=")){ debugPrint = v.substring(6).toInt()!=0; c->setValue((uint8_t*)"OK",2); return; }
    if(v.startsWith("k=")){ kGain = v.substring(2).toFloat(); c->setValue((uint8_t*)"OK",2); return; }
    if(v.startsWith("gyro_th=")){ TH_GYRO_DPS = v.substring(8).toFloat(); c->setValue((uint8_t*)"OK",2); return; }
    if(v.startsWith("var_th=")){ TH_VAR_A = v.substring(7).toFloat(); c->setValue((uint8_t*)"OK",2); return; }
  }
};

// ---------- BLE setup ----------
void setupBLE(){
  NimBLEDevice::init("MADEPLUS SMART SHOE");
  NimBLEDevice::setPower(ESP_PWR_LVL_P3);

  NimBLEServer* server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  NimBLEService* svc = server->createService(BLE_SERVICE_UUID);

  chRoll    = svc->createCharacteristic(BLE_CHAR_ROLL_UUID,    NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  chPitch   = svc->createCharacteristic(BLE_CHAR_PITCH_UUID,   NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  chYaw     = svc->createCharacteristic(BLE_CHAR_YAW_UUID,     NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  chTemp    = svc->createCharacteristic(BLE_CHAR_TEMP_UUID,    NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  chSteps   = svc->createCharacteristic(BLE_CHAR_STEPS_UUID,   NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  chCad     = svc->createCharacteristic(BLE_CHAR_CADENCE_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  chStrideL = svc->createCharacteristic(BLE_CHAR_STRIDEL_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  chAltDH   = svc->createCharacteristic(BLE_CHAR_ALTDH_UUID,   NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  chCmd     = svc->createCharacteristic(BLE_CHAR_COMMAND_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  chAscii   = svc->createCharacteristic(BLE_CHAR_ASCII_UUID,   NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  chCmd->setCallbacks(new CmdCallbacks());

  float f0=0; uint32_t u0=0;
  chRoll->setValue((uint8_t*)&f0,sizeof(f0));
  chPitch->setValue((uint8_t*)&f0,sizeof(f0));
  chYaw->setValue((uint8_t*)&f0,sizeof(f0));
  chTemp->setValue((uint8_t*)&f0,sizeof(f0));
  chCad->setValue((uint8_t*)&f0,sizeof(f0));
  chStrideL->setValue((uint8_t*)&f0,sizeof(f0));
  chAltDH->setValue((uint8_t*)&f0,sizeof(f0));
  chSteps->setValue((uint8_t*)&u0,sizeof(u0));
  chAscii->setValue("boot");

  svc->start();
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  NimBLEAdvertisementData a; a.setFlags(0x06); a.addServiceUUID(BLE_SERVICE_UUID); adv->setAdvertisementData(a);
  NimBLEAdvertisementData s; s.setName("MADEPLUS SMART SHOE"); adv->setScanResponseData(s);
  NimBLEDevice::startAdvertising();
}

// ---------- Calibration (2 s still) ----------
void calibrateGyroBias(){
  LOGLN("[CAL] Hold still 2 s for gyro bias...");
  const uint32_t ms = 2000;
  uint32_t t0 = millis();
  uint32_t n=0;
  double sx=0,sy=0,sz=0;
  while(millis()-t0 < ms){
    float ax,ay,az,gx,gy,gz; int16_t rt;
    if(mpuReadAll(ax,ay,az,gx,gy,gz,rt)){
      sx += gx; sy += gy; sz += gz; n++;
    }
    delayMicroseconds((int)(DT*1e6));
  }
  if(n>0){ g_bias_dps[0]=sx/n; g_bias_dps[1]=sy/n; g_bias_dps[2]=sz/n; }
  LOGF("[CAL] g_bias dps = [%.3f, %.3f, %.3f]\n", g_bias_dps[0], g_bias_dps[1], g_bias_dps[2]);

  // Optional accel mean to seed tilt
  n=0; sx=sy=sz=0;
  t0 = millis();
  while(millis()-t0 < 500){ // quick average
    float ax,ay,az,gx,gy,gz; int16_t rt;
    if(mpuReadAll(ax,ay,az,gx,gy,gz,rt)){ sx+=ax; sy+=ay; sz+=az; n++; }
    delayMicroseconds((int)(DT*1e6));
  }
  if(n>0){ a_bias_g[0]=sx/n; a_bias_g[1]=sy/n; a_bias_g[2]=sz/n; }
  // Seed roll/pitch from gravity direction
  float ax=a_bias_g[0], ay=a_bias_g[1], az=a_bias_g[2];
  roll_deg  = atan2f(ay, az) * RAD2DEG;
  pitch_deg = atan2f(-ax, sqrtf(ay*ay+az*az)) * RAD2DEG;
  LOGF("[CAL] seed roll=%.2f pitch=%.2f\n", roll_deg, pitch_deg);
}

// ---------- Orientation helpers ----------
void bodyToWorld_RP(float roll_deg, float pitch_deg, float bx, float by, float bz, float &wx, float &wy, float &wz){
  // yaw ignored (indoor mag not reliable); R = Rz(yaw=0)*Ry(pitch)*Rx(roll)
  float r = roll_deg*DEG2RAD, p = pitch_deg*DEG2RAD;
  float sr=sinf(r), cr=cosf(r), sp=sinf(p), cp=cosf(p);
  // Apply Ry(p)*Rx(r) to body vector
  float vx = bx;
  float vy = cr*by - sr*bz;
  float vz = sr*by + cr*bz;
  wx = cp*vx + sp*vz;
  wy = vy;
  wz = -sp*vx + cp*vz;
}

// ---------- Setup ----------
unsigned long lastSample=0, lastNotify=0, lastAdvKick=0;

void setup(){
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, LOW);
  Serial.begin(115200);
  LOGLN("\n[BOOT] FootAlgo ZUPT — SDA=8 SCL=9");

  // BLE first
  setupBLE();

  // I2C + sensors
  Wire.begin(SDA_PIN,SCL_PIN,400000);
  i2cScan("pre-MPU");
  if(!mpuInit200Hz()){ LOGLN("[ERR] MPU init"); }
  if(!mpuEnableBypass()) LOGLN("[WARN] MPU BYPASS failed (mag may be hidden)");

  i2cScan("post-BYPASS");
  msPresent = msInit();
  LOGF("[MS5611] %s\n", msPresent?"OK":"not found");
  if(!magInit()) LOGLN("[MAG] not found (fine; yaw from mag disabled)"); else LOGLN("[MAG] found");

  // Calibration
  calibrateGyroBias();

  // Prime var buffer
  varN = max(5, VAR_WIN_N);
  for(int i=0;i<varN;i++){ varBuf[i]=0; }
  varHead=0; varFilled=false; varSum=varSumSq=0;

  LOGLN("[SETUP] done");
}

// ---------- Loop ----------
void loop(){
  // Blink + re-adv
  static uint32_t lastBlink=0;
  if(millis()-lastBlink>500){ lastBlink=millis(); digitalWrite(LED_BUILTIN, !digitalRead(LED_BUILTIN)); }
  if(!bleClientConnected && millis()-lastAdvKick > 5000){ NimBLEDevice::startAdvertising(); lastAdvKick=millis(); }

  const unsigned long now = millis();

  // ----- Sample @ 200 Hz -----
  if(now - lastSample >= samplePeriodMs){
    lastSample = now;

    // Read sensors
    float ax_g,ay_g,az_g,gx_dps,gy_dps,gz_dps; int16_t rawT=0;
    if(!mpuReadAll(ax_g,ay_g,az_g,gx_dps,gy_dps,gz_dps,rawT)) return;

    // Remove gyro bias
    gx_dps -= g_bias_dps[0]; gy_dps -= g_bias_dps[1]; gz_dps -= g_bias_dps[2];

    // Extra 20 Hz LPF (simple 1st order)
    static float axg_f=0, ayg_f=0, azg_f=0, gx_f=0, gy_f=0, gz_f=0;
    axg_f += aLPF*(ax_g - axg_f);
    ayg_f += aLPF*(ay_g - ayg_f);
    azg_f += aLPF*(az_g - azg_f);
    gx_f  += gLPF*(gx_dps - gx_f);
    gy_f  += gLPF*(gy_dps - gy_f);
    gz_f  += gLPF*(gz_dps - gz_f);

    // Complementary filter tilt
    float rollGyro  = roll_deg  + gx_f * DT; // deg
    float pitchGyro = pitch_deg + gy_f * DT; // deg
    float rollAcc   = atan2f(ayg_f, azg_f) * RAD2DEG;
    float pitchAcc  = atan2f(-axg_f, sqrtf(ayg_f*ayg_f + azg_f*azg_f)) * RAD2DEG;
    roll_deg  = CF_ALPHA*rollGyro  + (1.0f-CF_ALPHA)*rollAcc;
    pitch_deg = CF_ALPHA*pitchGyro + (1.0f-CF_ALPHA)*pitchAcc;

    // Gyro magnitude for ZUPT (deg/s)
    gyroMag_dps = sqrtf(gx_f*gx_f + gy_f*gy_f + gz_f*gz_f);

    // Accel magnitude variance over window (m/s^2)
    float ax_ms2 = axg_f * G_MPS2;
    float ay_ms2 = ayg_f * G_MPS2;
    float az_ms2 = azg_f * G_MPS2;
    float amag   = sqrtf(ax_ms2*ax_ms2 + ay_ms2*ay_ms2 + az_ms2*az_ms2);

    // Rolling var (online, fixed window)
    float old = varBuf[varHead];
    varBuf[varHead] = amag;
    varHead = (varHead + 1) % varN;
    if(!varFilled){ varSum += amag; varSumSq += (double)amag*amag; if(varHead==0) varFilled=true; }
    else { varSum += amag - old; varSumSq += (double)amag*amag - (double)old*old; }
    int N = varFilled ? varN : varHead;
    if(N>1){
      double mean = varSum / (double)N;
      varA_mps2_2 = (float)max(0.0, (varSumSq/(double)N) - mean*mean);
    }

    // Stance logic
    bool zuptCandidate = (gyroMag_dps < TH_GYRO_DPS) && (varA_mps2_2 < TH_VAR_A);
    if(zuptCandidate){ stanceHoldSamples++; } else { stanceHoldSamples = 0; }
    GaitState newState = (stanceHoldSamples >= stanceHoldNeeded) ? STANCE : SWING;

    // Events + swing integration
    if(state != newState){
      if(state==SWING && newState==STANCE){
        // Heel-strike
        stepCount++;
        unsigned long tnow = now;
        if(lastHS_ms>0){
          unsigned long dt_ms = tnow - lastHS_ms;
          if(dt_ms>0){
            // cadence from recent HS events
            hsTimes[hsIdx&7]=tnow; hsIdx++;
            int k = (hsIdx>=8)?8:hsIdx;
            unsigned long tNew=hsTimes[(hsIdx-1)&7];
            unsigned long tOld=hsTimes[(hsIdx-k)&7];
            unsigned long dSum=tNew-tOld;
            if(dSum>0) cadence_spm = 60000.0f * (float)(k-1) / (float)dSum;
          }
        }
        lastHS_ms = tnow;

        // End of swing → stride length
        float stepHoriz_m = sqrtf(px*px + py*py); // ignore vertical component
        lastStrideLen_m = stepHoriz_m;

        // Baro Δh per step
        if(msPresent){
          float p,t; if(msReadPT(p,t)){ lastPress=p; lastTempC=t; float alt=pressureToAltitude(p); lastAlt_m=alt;
            if(!isnan(prevStepAlt_m)){ lastStepAltDelta_m = alt - prevStepAlt_m; } else { lastStepAltDelta_m = 0.0f; }
            prevStepAlt_m = alt;
          }
        } else {
          // temp fallback from MPU
          lastTempC = (float)rawT/340.0f + 36.53f;
        }

        // Zero velocities (ZUPT) & reset displacement
        vx=vy=vz=0; px=py=pz=0; swingVertPeak = G_MPS2;

      } else if(state==STANCE && newState==SWING){
        // Toe-off: start swing; keep state, reset swing accumulators already done at HS
      }
      state = newState;
    }

    // During swing: integrate in world frame (roll/pitch only)
    if(state==SWING){
      // Remove gravity in body frame -> linear body
      float g_bx = -sinf(pitch_deg*DEG2RAD) * G_MPS2;
      float g_by =  sinf(roll_deg*DEG2RAD) * cosf(pitch_deg*DEG2RAD) * G_MPS2;
      float g_bz =  cosf(roll_deg*DEG2RAD) * cosf(pitch_deg*DEG2RAD) * G_MPS2;
      float lin_bx = ax_ms2 - g_bx;
      float lin_by = ay_ms2 - g_by;
      float lin_bz = az_ms2 - g_bz;

      // Rotate to world (yaw=0)
      float wx,wy,wz; bodyToWorld_RP(roll_deg,pitch_deg, lin_bx,lin_by,lin_bz, wx,wy,wz);

      // Integrate
      vx += wx*DT; vy += wy*DT; vz += wz*DT;
      px += vx*DT; py += vy*DT; pz += vz*DT;

      // Track vertical accel peak for model length (optional)
      if(lin_bz > swingVertPeak) swingVertPeak = lin_bz;
    }

    // Model-based quick estimate (baseline)
    float dv = swingVertPeak - G_MPS2;
    lastModelLen_m = (dv>0) ? (kGain * sqrtf(max(0.0f,dv)) ) : 0.0f;
    lastTempC = lastTempC; // (updated in notify)

    // Yaw (for display only): smooth with mag if available
    if(magType!=MAG_NONE){
      float mx,my,mz; if(magReadRaw(mx,my,mz)){
        float r=roll_deg*DEG2RAD, p=pitch_deg*DEG2RAD;
        float Xh=mx*cosf(p)+mz*sinf(p);
        float Yh=mx*sinf(r)*sinf(p)+my*cosf(r)-mz*sinf(r)*cosf(p);
        float hdg = atan2f(Yh,Xh)*RAD2DEG;
        // simple smooth
        static bool yawInit=false; if(!yawInit){ yaw_deg=hdg; yawInit=true; }
        yaw_deg = 0.95f*yaw_deg + 0.05f*hdg;
      }
    } // else leave yaw as-is (not used by algorithm)
  }

  // ----- Notify @ ~10 Hz -----
  if(now - lastNotify >= notifyPeriodMs){
    lastNotify = now;

    // Baro update (if not updated at HS)
    if(msPresent){
      float p,t; if(msReadPT(p,t)){ lastPress=p; lastTempC=t; lastAlt_m=pressureToAltitude(p); }
    }

    // ASCII & floats out
    uint32_t stepsSnap = stepCount;
    float cadSnap = cadence_spm;
    float strideSnap = lastStrideLen_m;
    float altSnap = lastStepAltDelta_m;
    float roll=roll_deg, pitch=pitch_deg, yaw=yaw_deg, temp=lastTempC;

    // Serial preview
    LOGF("[TX] S=%lu cad=%.1f L=%.3f dH=%.03f st=%s R=%.1f P=%.1f Y=%.1f T=%.2fC\n",
         (unsigned long)stepsSnap, cadSnap, strideSnap, altSnap, (state==STANCE?"ST":"SW"),
         roll, pitch, yaw, temp);

    // BLE floats
    chRoll->setValue((uint8_t*)&roll,sizeof(roll));       chRoll->notify();
    chPitch->setValue((uint8_t*)&pitch,sizeof(pitch));    chPitch->notify();
    chYaw->setValue((uint8_t*)&yaw,sizeof(yaw));          chYaw->notify();
    chTemp->setValue((uint8_t*)&temp,sizeof(temp));       chTemp->notify();
    chSteps->setValue((uint8_t*)&stepsSnap,sizeof(stepsSnap)); chSteps->notify();
    chCad->setValue((uint8_t*)&cadSnap,sizeof(cadSnap));  chCad->notify();
    chStrideL->setValue((uint8_t*)&strideSnap,sizeof(strideSnap)); chStrideL->notify();
    chAltDH->setValue((uint8_t*)&altSnap,sizeof(altSnap)); chAltDH->notify();

    // ASCII (easy in nRF Connect)
    char line[160];
    snprintf(line,sizeof(line),
      "st=%s S=%lu cad=%.1f Lzupt=%.3f Lmod=%.3f dH=%.03f R=%.1f P=%.1f Y=%.1f T=%.2f",
      (state==STANCE?"STANCE":"SWING"),
      (unsigned long)stepsSnap, cadSnap, lastStrideLen_m, lastModelLen_m, altSnap,
      roll_deg, pitch_deg, yaw_deg, temp);
    chAscii->setValue((uint8_t*)line, strlen(line));
    chAscii->notify();
  }
}
