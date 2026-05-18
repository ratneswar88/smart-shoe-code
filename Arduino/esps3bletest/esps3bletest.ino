#include <Arduino.h>
#include <NimBLEDevice.h>

void setup() {
  Serial.begin(115200);
  unsigned long t0 = millis();
  while (!Serial && millis() - t0 < 4000) { delay(10); }
  Serial.println("\n[BOOT] S3 Serial OK, starting BLE...");

  // Init + TX power
  NimBLEDevice::init("S3 Zero Test");
  NimBLEDevice::setPower(ESP_PWR_LVL_P9); // use a valid enum level for your board

  // GATT: Device Information service 0x180A with Manufacturer Name 0x2A29
  NimBLEServer* server = NimBLEDevice::createServer();
  NimBLEService* svc   = server->createService(NimBLEUUID((uint16_t)0x180A));
  NimBLECharacteristic* ch = svc->createCharacteristic(
      NimBLEUUID((uint16_t)0x2A29), NIMBLE_PROPERTY::READ);
  ch->setValue("Waveshare");
  svc->start();

  // Advertising
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(NimBLEUUID((uint16_t)0x180A));
  adv->setName("S3 Zero Test");
  // Optional: control advertising interval (units = 0.625 ms)
  adv->setMinInterval(0x20); // ~20 ms
  adv->setMaxInterval(0x40); // ~40 ms
  // adv->setScanResponse(true); // Available in NimBLE; uncomment if you add scan data

  adv->start(); // or NimBLEDevice::startAdvertising();

  Serial.println("[BLE] Advertising as 'S3 Zero Test'");
}

void loop() {
  static uint32_t last = 0;
  if (millis() - last > 1000) {
    last = millis();
    Serial.println("[HB] alive...");
  }
}
