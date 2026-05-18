// FootAlgo_Arduino_WaveShare.ino
#include <Arduino.h>
#include "Config.h"
#include "Tasks.h"
#include "Utils.h"

void setup(){
  Serial.begin(115200);
  LOGLN("\n[BOOT] FootAlgo ZUPT — Arduino — SDA=8 SCL=9");
  createTasks();
}
void loop(){
  vTaskDelay(pdMS_TO_TICKS(1000));
}
