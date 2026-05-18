#include "Tasks.h"
#include "Config.h"
#include "Types.h"
#include "Utils.h"
#include "MPU6050.h"
#include "MS5611.h"
#include "Mag.h"
#include "Algorithm.h"
#include "BLEServer.h"
#include <Wire.h>

QueueHandle_t gSampleQ = nullptr;
SemaphoreHandle_t gTelMtx = nullptr;
Telemetry gTel;
uint32_t gNotifyPeriodMs = 1000u/NOTIFY_HZ;
float gThGyroDps = ZUPT_GYRO_DPS;
float gThVarA = ZUPT_VAR_A;
float gModelK = MODEL_K_GAIN;
bool gBaroPresent = false;

static FootAlgo algo;
static void blinkTask(void*){
  pinMode(LED_BUILTIN, OUTPUT);
  while(true){
    digitalWrite(LED_BUILTIN, !digitalRead(LED_BUILTIN));
    vTaskDelay(pdMS_TO_TICKS(500));
    bleKickAdv();
  }
}
static void sensorTask(void*){
  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN, 400000);
  i2cScan("pre-MPU");
  if(!mpuInit200Hz()){ LOGLN("[ERR] MPU init"); }
  if(!mpuEnableBypass()) LOGLN("[WARN] MPU BYPASS failed (mag may be hidden)");
  i2cScan("post-BYPASS");
  gBaroPresent = msInit();
  LOGLN(gBaroPresent ? "[MS5611] OK" : "[MS5611] not found");
  if(!magInit()) LOGLN("[MAG] not found"); else LOGLN("[MAG] found");
  algo.begin();
  const TickType_t periodTicks = pdMS_TO_TICKS(1000u/SAMPLE_HZ);
  TickType_t last = xTaskGetTickCount();
  while(true){
    vTaskDelayUntil(&last, periodTicks);
    float ax,ay,az,gx,gy,gz; int16_t rt=0;
    if(!mpuReadAll(ax,ay,az,gx,gy,gz,rt)) continue;
    Sample s{ax,ay,az,gx,gy,gz,rt,(uint32_t)millis()};
    (void)algo.process(s);
  }
}
static void bleTask(void*){
  bleSetup();
  while(true){
    bleNotifyNow();
    vTaskDelay(pdMS_TO_TICKS(gNotifyPeriodMs));
  }
}
void createTasks(){
  gSampleQ = xQueueCreate(10, sizeof(Sample));
  gTelMtx = xSemaphoreCreateMutex();
  xTaskCreatePinnedToCore(blinkTask, "blink", STACK_BLINK, nullptr, PRIO_BLINK, nullptr, 0);
  xTaskCreatePinnedToCore(sensorTask,"sensor",STACK_SENSOR,nullptr,PRIO_SENSOR,nullptr, 1);
  xTaskCreatePinnedToCore(bleTask,   "ble",   STACK_BLE,   nullptr,PRIO_BLE,   nullptr, 0);
}
