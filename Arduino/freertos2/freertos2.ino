#define LED 2
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
void setup()
 {
    pinMode(LED,OUTPUT);
  
    xTaskCreatePinnedToCore(
        blink2,     // Function name of the task
        "Blink 2",  // Name of the task (e.g. for debugging)
        2048,       // Stack size (bytes)
        NULL,       // Parameter to pass
        1,          // Task priority
        NULL,      // Task handle
         0            // run on Core 0
    );
     xTaskCreatePinnedToCore(
        ble,     // Function name of the task
        "ble 1",  // Name of the task (e.g. for debugging)
        2048,       // Stack size (bytes)
        NULL,       // Parameter to pass
        2,          // Task priority
        NULL,        // Task handle
         1           // run on Core 1
    );
}
void blink2(void *parameter) {
    pinMode(LED, OUTPUT);
    while(1) {
        digitalWrite(LED, HIGH);
        delay(333);
        digitalWrite(LED, LOW);
        delay(333);
    }
}

void ble(void *parameter) {
   
    while(1){
  Serial.begin(115200);
  Serial.println("Starting BLE work!");

  BLEDevice::init("rtosdemo");
  BLEServer *pServer = BLEDevice::createServer();
  BLEService *pService = pServer->createService(SERVICE_UUID);
  BLECharacteristic *pCharacteristic = pService->createCharacteristic(
                                         CHARACTERISTIC_UUID,
                                         BLECharacteristic::PROPERTY_READ |
                                         BLECharacteristic::PROPERTY_WRITE
                                       );

  pCharacteristic->setValue("Hello World says Neil");
  pService->start();
  // BLEAdvertising *pAdvertising = pServer->getAdvertising();  // this still is working for backward compatibility
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);  // functions that help with iPhone connections issue
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.println("Characteristic defined! Now you can read it in your phone!");
}
    }




void loop()
{
  
}
