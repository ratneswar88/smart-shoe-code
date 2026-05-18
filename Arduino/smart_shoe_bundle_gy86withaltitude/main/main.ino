#include <Wire.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <MadgwickAHRS.h>
#include <esp_task_wdt.h>  // Include the watchdog timer library

#define MPU_ADDR 0x68
#define MS5611_ADDR 0x77

const char* ssid = "Fios-2wD3M";
const char* password = "will36fend47fur";
const char* serverUrl = "http://192.168.1.181:5000/upload";

Madgwick filter;

unsigned long lastTime = 0;

float accX, accY, accZ, gyroX, gyroY, gyroZ, mpuTemp;
float pressure = 0.0, ms5611Temp = 0.0, altitude = 0.0;
uint16_t C[7];
uint32_t D1_raw, D2_raw;
int32_t dT, TEMP, P;
int64_t OFF, SENS;

// Step detection variables
int stepCount = 0;
bool stepDetected = false;
float prevAccMag = 0.0;
const float stepThreshold = 1.2;  // Adjust this for sensitivity

// ========== MS5611 HELPERS ==========
void readCalibration() {
  Serial.println("Calibration Constants:");
  for (int i = 0; i < 6; i++) {
    Wire.beginTransmission(MS5611_ADDR);
    Wire.write(0xA2 + i * 2);
    Wire.endTransmission();
    Wire.requestFrom(MS5611_ADDR, 2);
    if (Wire.available() == 2) {
      C[i + 1] = (Wire.read() << 8) | Wire.read();
      Serial.printf("C[%d]: %d\n", i + 1, C[i + 1]);
    }
  }
}

uint32_t readADC() {
  Wire.beginTransmission(MS5611_ADDR);
  Wire.write(0x00);
  Wire.endTransmission();
  Wire.requestFrom(MS5611_ADDR, 3);
  return ((uint32_t)Wire.read() << 16) | (Wire.read() << 8) | Wire.read();
}

void readMS5611() {
  Wire.beginTransmission(MS5611_ADDR);
  Wire.write(0x48);  // D1
  Wire.endTransmission();
  delay(10);
  D1_raw = readADC();

  Wire.beginTransmission(MS5611_ADDR);
  Wire.write(0x58);  // D2
  Wire.endTransmission();
  delay(10);
  D2_raw = readADC();

  dT = D2_raw - ((int32_t)C[5] << 8);
  OFF = ((int64_t)C[2] << 16) + (((int64_t)C[4] * dT) >> 7);
  SENS = ((int64_t)C[1] << 15) + (((int64_t)C[3] * dT) >> 8);
  TEMP = 2000 + ((int64_t)dT * C[6]) / 8388608;
  P = (((D1_raw * SENS) >> 21) - OFF) >> 15;

  ms5611Temp = TEMP / 100.0;
  pressure = P / 100.0;
  altitude = 44330.0 * (1.0 - pow(pressure / 1019.8, 0.1903));

  Serial.printf("Raw Pressure (D1): %lu\n", D1_raw);
  Serial.printf("Raw Temperature (D2): %lu\n", D2_raw);
  Serial.printf("Compensated Temperature (°C): %.2f\n", ms5611Temp);
  Serial.printf("Compensated Pressure (hPa): %.2f\n", pressure);
  Serial.printf("Estimated Altitude (m): %.2f\n", altitude);
}

// ========== MPU6050 ==========
void readMPU6050() {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x3B);
  Wire.endTransmission(false);
  Wire.requestFrom(MPU_ADDR, 14);

  accX = (Wire.read() << 8 | Wire.read()) / 16384.0;
  accY = (Wire.read() << 8 | Wire.read()) / 16384.0;
  accZ = (Wire.read() << 8 | Wire.read()) / 16384.0;
  int16_t tempRaw = Wire.read() << 8 | Wire.read();
  gyroX = (Wire.read() << 8 | Wire.read()) / 131.0;
  gyroY = (Wire.read() << 8 | Wire.read()) / 131.0;
  gyroZ = (Wire.read() << 8 | Wire.read()) / 131.0;

  mpuTemp = (tempRaw / 340.0) + 36.53;
}

// ========== STEP DETECTION ==========
void detectStep() {
  float accMag = sqrt(accX * accX + accY * accY + accZ * accZ);
  if (accMag > stepThreshold && !stepDetected) {
    stepCount++;
    stepDetected = true;
  } else if (accMag < stepThreshold) {
    stepDetected = false;
  }
}

// ========== WIFI + POST ==========
void postData(String json) {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin(serverUrl);
    http.addHeader("Content-Type", "application/json");
    int code = http.POST(json);
    Serial.printf("POST Code: %d\n", code);
    http.end();
  }
}

// ========== SETUP ==========
void setup() {
  Serial.begin(115200);
  Wire.begin();

  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected");

  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x6B);
  Wire.write(0);
  Wire.endTransmission();

  Wire.beginTransmission(MS5611_ADDR);
  Wire.write(0x1E); // Reset
  Wire.endTransmission();
  delay(100);
  readCalibration();

  filter.begin(100);

  // Manually creating the watchdog timer configuration
  esp_task_wdt_config_t config;
  config.timeout_ms = 3000;  // Set timeout to 3 seconds

  esp_task_wdt_init(&config);  // Initialize the WDT
  esp_task_wdt_add(NULL);      // Add current task to the WDT
}

// ========== LOOP ==========
void loop() {
  if (millis() - lastTime < 100) return;
  lastTime = millis();

  readMPU6050();
  readMS5611();
  filter.updateIMU(gyroX, gyroY, gyroZ, accX, accY, accZ);

  float roll = filter.getRoll();
  float pitch = filter.getPitch();
  float yaw = filter.getYaw();

  detectStep();

  String json = "{";
  json += "\"roll\":" + String(roll, 2) + ",";
  json += "\"pitch\":" + String(pitch, 2) + ",";
  json += "\"yaw\":" + String(yaw, 2) + ",";
  json += "\"temperature\":" + String(ms5611Temp, 2) + ",";
  json += "\"pressure\":" + String(pressure, 2) + ",";
  json += "\"altitude\":" + String(altitude, 2) + ",";
  json += "\"steps\":" + String(stepCount);
  json += "}";

  Serial.println("Posting: " + json);
  postData(json);

  // Reset the watchdog timer to prevent a timeout
  esp_task_wdt_reset();  
}
