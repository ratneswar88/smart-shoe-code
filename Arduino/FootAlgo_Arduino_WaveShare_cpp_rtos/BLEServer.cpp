#include "BLEServer.h"
#include "Config.h"
#include "Types.h"
#include "Utils.h"
static NimBLECharacteristic *chRoll=nullptr,*chPitch=nullptr,*chYaw=nullptr,*chTemp=nullptr,*chSteps=nullptr,*chCad=nullptr,*chStrideL=nullptr,*chAltDH=nullptr,*chCmd=nullptr,*chAscii=nullptr;
class ServerCallbacks : public NimBLEServerCallbacks { public: void onConnect(NimBLEServer*) { LOGLN("[BLE] Connected"); } void onDisconnect(NimBLEServer*) { LOGLN("[BLE] Disconnected -> re-adv"); NimBLEDevice::startAdvertising(); } };
class CmdCallbacks : public NimBLECharacteristicCallbacks { public: void onWrite(NimBLECharacteristic* c) { std::string s = c->getValue(); if(s.empty()) return; String v(s.c_str()); v.trim(); LOGF("[CMD] %s\n", v.c_str()); bleHandleCommand(v); c->setValue((uint8_t*)"OK",2);} };
void bleSetup(){
  NimBLEDevice::init(BLE_DEVICE_NAME); NimBLEDevice::setPower(ESP_PWR_LVL_P9);
  NimBLEServer* server = NimBLEDevice::createServer(); server->setCallbacks(new ServerCallbacks());
  NimBLEService* svc = server->createService(BLE_SERVICE_UUID);
  chRoll=svc->createCharacteristic(BLE_CHAR_ROLL_UUID,NIMBLE_PROPERTY::READ|NIMBLE_PROPERTY::NOTIFY);
  chPitch=svc->createCharacteristic(BLE_CHAR_PITCH_UUID,NIMBLE_PROPERTY::READ|NIMBLE_PROPERTY::NOTIFY);
  chYaw=svc->createCharacteristic(BLE_CHAR_YAW_UUID,NIMBLE_PROPERTY::READ|NIMBLE_PROPERTY::NOTIFY);
  chTemp=svc->createCharacteristic(BLE_CHAR_TEMP_UUID,NIMBLE_PROPERTY::READ|NIMBLE_PROPERTY::NOTIFY);
  chSteps=svc->createCharacteristic(BLE_CHAR_STEPS_UUID,NIMBLE_PROPERTY::READ|NIMBLE_PROPERTY::NOTIFY);
  chCad=svc->createCharacteristic(BLE_CHAR_CADENCE_UUID,NIMBLE_PROPERTY::READ|NIMBLE_PROPERTY::NOTIFY);
  chStrideL=svc->createCharacteristic(BLE_CHAR_STRIDEL_UUID,NIMBLE_PROPERTY::READ|NIMBLE_PROPERTY::NOTIFY);
  chAltDH=svc->createCharacteristic(BLE_CHAR_ALTDH_UUID,NIMBLE_PROPERTY::READ|NIMBLE_PROPERTY::NOTIFY);
  chCmd=svc->createCharacteristic(BLE_CHAR_COMMAND_UUID,NIMBLE_PROPERTY::READ|NIMBLE_PROPERTY::WRITE|NIMBLE_PROPERTY::WRITE_NR);
  chAscii=svc->createCharacteristic(BLE_CHAR_ASCII_UUID,NIMBLE_PROPERTY::READ|NIMBLE_PROPERTY::NOTIFY);
  chCmd->setCallbacks(new CmdCallbacks());
  float f0=0; uint32_t u0=0;
  chRoll->setValue((uint8_t*)&f0,sizeof(f0)); chPitch->setValue((uint8_t*)&f0,sizeof(f0)); chYaw->setValue((uint8_t*)&f0,sizeof(f0));
  chTemp->setValue((uint8_t*)&f0,sizeof(f0)); chCad->setValue((uint8_t*)&f0,sizeof(f0)); chStrideL->setValue((uint8_t*)&f0,sizeof(f0));
  chAltDH->setValue((uint8_t*)&f0,sizeof(f0)); chSteps->setValue((uint8_t*)&u0,sizeof(u0)); chAscii->setValue("boot");
  svc->start(); NimBLEAdvertising* adv = NimBLEDevice::getAdvertising(); NimBLEAdvertisementData a; a.setFlags(0x06); a.addServiceUUID(BLE_SERVICE_UUID); adv->setAdvertisementData(a);
  NimBLEAdvertisementData s; s.setName(BLE_DEVICE_NAME); adv->setScanResponseData(s); NimBLEDevice::startAdvertising();
}
void bleNotifyNow(){
  Telemetry snap;
  if(xSemaphoreTake(gTelMtx, pdMS_TO_TICKS(50))==pdTRUE){ snap = gTel; xSemaphoreGive(gTelMtx);} else return;
  chRoll->setValue((uint8_t*)&snap.roll_deg,sizeof(float));   chRoll->notify();
  chPitch->setValue((uint8_t*)&snap.pitch_deg,sizeof(float)); chPitch->notify();
  chYaw->setValue((uint8_t*)&snap.yaw_deg,sizeof(float));     chYaw->notify();
  chTemp->setValue((uint8_t*)&snap.tempC,sizeof(float));      chTemp->notify();
  chCad->setValue((uint8_t*)&snap.cadence_spm,sizeof(float)); chCad->notify();
  chStrideL->setValue((uint8_t*)&snap.strideLen_m,sizeof(float)); chStrideL->notify();
  chAltDH->setValue((uint8_t*)&snap.altStep_m,sizeof(float)); chAltDH->notify();
  uint32_t steps = snap.steps; chSteps->setValue((uint8_t*)&steps,sizeof(uint32_t)); chSteps->notify();
  char line[160]; snprintf(line,sizeof(line),
    "st=%s S=%lu cad=%.1f Lzupt=%.3f dH=%.03f R=%.1f P=%.1f Y=%.1f T=%.2f",
    (snap.state==STANCE?"STANCE":"SWING"), (unsigned long)steps, snap.cadence_spm, snap.strideLen_m, snap.altStep_m,
    snap.roll_deg, snap.pitch_deg, snap.yaw_deg, snap.tempC);
  chAscii->setValue((uint8_t*)line, strlen(line)); chAscii->notify();
}
void bleKickAdv(){ static uint32_t lastKick=0; if(millis()-lastKick > 5000){ NimBLEDevice::startAdvertising(); lastKick=millis(); } }
void bleHandleCommand(const String& v){ extern uint32_t gNotifyPeriodMs; if(v.startsWith("notify_hz=")){ int hz=v.substring(10).toInt(); if(hz<1)hz=1; if(hz>50)hz=50; gNotifyPeriodMs = 1000u/(uint32_t)hz; } }
