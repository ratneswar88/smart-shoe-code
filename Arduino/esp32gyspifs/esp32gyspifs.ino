// GY-86 ESP32 + Sensor Fusion + Web Dashboard using SPIFFS for HTML
#include <WiFi.h>
#include <Wire.h>
#include <ESPAsyncWebServer.h>
#include <SPIFFS.h>
#include <MadgwickAHRS.h>

#define MPU_ADDR    0x68

const char* ssid = "Fios-2wD3M";
const char* password = "will36fend47fur";

AsyncWebServer server(80);
Madgwick filter;

float accX, accY, accZ;
float gyroX, gyroY, gyroZ;
float tempMPU;

unsigned long lastUpdate = 0;

void setupMPU() {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x6B);
  Wire.write(0);
  Wire.endTransmission();
}

void readMPU() {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x3B);
  Wire.endTransmission(false);
  Wire.requestFrom(MPU_ADDR, 14);

  int16_t ax = Wire.read() << 8 | Wire.read();
  int16_t ay = Wire.read() << 8 | Wire.read();
  int16_t az = Wire.read() << 8 | Wire.read();
  int16_t tempRaw = Wire.read() << 8 | Wire.read();
  int16_t gx = Wire.read() << 8 | Wire.read();
  int16_t gy = Wire.read() << 8 | Wire.read();
  int16_t gz = Wire.read() << 8 | Wire.read();

  accX = ax / 16384.0;
  accY = ay / 16384.0;
  accZ = az / 16384.0;
  tempMPU = (tempRaw / 340.0) + 36.53;
  gyroX = gx * (250.0 / 32768.0);
  gyroY = gy * (250.0 / 32768.0);
  gyroZ = gz * (250.0 / 32768.0);
}

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("Booting...");

  if (!SPIFFS.begin(true)) {
    Serial.println("An error occurred while mounting SPIFFS");
    return;
  }

  Wire.begin();
  setupMPU();
  filter.begin(100);

  WiFi.begin(ssid, password);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected");
  Serial.print("IP address: ");
  Serial.println(WiFi.localIP());

  server.on("/", HTTP_GET, [](AsyncWebServerRequest *request) {
    request->send(SPIFFS, "/index.html", "text/html");
  });

  server.on("/data", HTTP_GET, [](AsyncWebServerRequest *request) {
    float roll = filter.getRoll();
    float pitch = filter.getPitch();
    float yaw = filter.getYaw();
    String json = "{";
    json += "\"roll\":" + String(roll, 2) + ",";
    json += "\"pitch\":" + String(pitch, 2) + ",";
    json += "\"yaw\":" + String(yaw, 2);
    json += "}";
    request->send(200, "application/json", json);
  });
  server.begin();
}

void loop() {
  readMPU();
  unsigned long now = millis();
  float dt = (now - lastUpdate) / 1000.0;
  lastUpdate = now;
  filter.updateIMU(gyroX, gyroY, gyroZ, accX, accY, accZ);
  delay(10);
}
