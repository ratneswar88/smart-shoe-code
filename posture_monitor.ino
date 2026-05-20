/*
 * Smart Belt - Posture Monitoring System
 * ESP32-S3 + MPU9250/ICM-20948 IMU
 * 
 * Features:
 * - Real-time posture angle calculation
 * - Slouch detection with configurable thresholds
 * - Sitting/standing classification
 * - Sitting time tracking with break reminders
 * - BLE connectivity for mobile app
 * - Power-optimized with motion interrupts
 */

#include <Wire.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "MPU9250.h"

// ==================== CONFIGURATION ====================
#define IMU_I2C_SDA 21
#define IMU_I2C_SCL 22
#define HAPTIC_MOTOR_PIN 5
#define LED_PIN 2

// Posture thresholds (degrees)
#define SLOUCH_THRESHOLD_MILD 15.0f
#define SLOUCH_THRESHOLD_SEVERE 30.0f
#define SLOUCH_TIME_THRESHOLD 30000  // 30 seconds
#define SITTING_THRESHOLD 0.85f      // Gravity component threshold

// Power management
#define MOTION_INTERRUPT_PIN 4
#define IDLE_TIMEOUT 300000          // 5 minutes to sleep
#define SAMPLING_RATE_ACTIVE 50      // Hz
#define SAMPLING_RATE_IDLE 10        // Hz

// BLE UUIDs
#define SERVICE_UUID_POSTURE        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHAR_UUID_TILT_ANGLE        "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define CHAR_UUID_POSTURE_SCORE     "beb5483f-36e1-4688-b7f5-ea07361b26a8"
#define CHAR_UUID_SITTING_TIME      "beb54840-36e1-4688-b7f5-ea07361b26a8"
#define CHAR_UUID_CONFIG            "beb54841-36e1-4688-b7f5-ea07361b26a8"
#define CHAR_UUID_CALIBRATE         "beb54842-36e1-4688-b7f5-ea07361b26a8"

// ==================== GLOBAL VARIABLES ====================
MPU9250 imu(Wire, 0x68);

// BLE
BLEServer* pServer = NULL;
BLECharacteristic* pCharTiltAngle = NULL;
BLECharacteristic* pCharPostureScore = NULL;
BLECharacteristic* pCharSittingTime = NULL;
BLECharacteristic* pCharConfig = NULL;
BLECharacteristic* pCharCalibrate = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// Quaternion for sensor fusion
struct Quaternion {
    float w, x, y, z;
};

// Posture state
struct PostureState {
    Quaternion referenceQuat;     // Calibrated good posture
    Quaternion currentQuat;        // Current orientation
    float tiltAngle;               // Deviation from reference (degrees)
    float pelvicTilt;              // Anterior/posterior tilt
    bool isSlouchingMild;
    bool isSlouchingSevere;
    bool isSitting;
    uint32_t sittingStartTime;
    uint32_t totalSittingTime;
    uint32_t lastPostureChangeTime;
    float postureScore;            // 0-100 score
    bool isCalibrated;
};

PostureState posture = {0};

// Sensor data
struct IMUData {
    float ax, ay, az;              // Accelerometer (g)
    float gx, gy, gz;              // Gyroscope (rad/s)
    float mx, my, mz;              // Magnetometer (uT)
};

IMUData imuData = {0};

// Complementary filter state
float alpha = 0.98f;               // Gyro weight
uint32_t lastUpdateTime = 0;

// Configuration
struct Config {
    float slouchThresholdMild;
    float slouchThresholdSevere;
    uint32_t slouchTimeThreshold;
    bool hapticsEnabled;
    uint32_t breakReminderInterval;  // Minutes
} config = {
    SLOUCH_THRESHOLD_MILD,
    SLOUCH_THRESHOLD_SEVERE,
    SLOUCH_TIME_THRESHOLD,
    true,
    30
};

// ==================== BLE CALLBACKS ====================
class ServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
        deviceConnected = true;
        Serial.println("BLE Client Connected");
    }

    void onDisconnect(BLEServer* pServer) {
        deviceConnected = false;
        Serial.println("BLE Client Disconnected");
    }
};

class ConfigCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
        std::string value = pCharacteristic->getValue();
        if (value.length() == sizeof(Config)) {
            memcpy(&config, value.data(), sizeof(Config));
            Serial.println("Configuration updated");
        }
    }
};

class CalibrateCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
        std::string value = pCharacteristic->getValue();
        if (value.length() > 0 && value[0] == 0x01) {
            calibratePosture();
            Serial.println("Posture calibrated");
        }
    }
};

// ==================== QUATERNION MATH ====================
Quaternion quaternionMultiply(Quaternion q1, Quaternion q2) {
    Quaternion result;
    result.w = q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z;
    result.x = q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y;
    result.y = q1.w * q2.y - q1.x * q2.z + q1.y * q2.w + q1.z * q2.x;
    result.z = q1.w * q2.z + q1.x * q2.y - q1.y * q2.x + q1.z * q2.w;
    return result;
}

Quaternion quaternionConjugate(Quaternion q) {
    return {q.w, -q.x, -q.y, -q.z};
}

void quaternionNormalize(Quaternion* q) {
    float norm = sqrt(q->w * q->w + q->x * q->x + q->y * q->y + q->z * q->z);
    if (norm > 0.0001f) {
        q->w /= norm;
        q->x /= norm;
        q->y /= norm;
        q->z /= norm;
    }
}

float quaternionAngleBetween(Quaternion q1, Quaternion q2) {
    // Calculate angle between two quaternions
    Quaternion q2_conj = quaternionConjugate(q2);
    Quaternion diff = quaternionMultiply(q1, q2_conj);
    
    // Extract angle from quaternion
    float angle = 2.0f * acos(fabs(diff.w)) * 180.0f / PI;
    return angle;
}

// ==================== SENSOR FUSION ====================
void updateQuaternion(Quaternion* q, float gx, float gy, float gz, float dt) {
    // Integrate gyroscope to update quaternion
    float halfdt = dt * 0.5f;
    
    Quaternion dq;
    dq.w = 1.0f;
    dq.x = gx * halfdt;
    dq.y = gy * halfdt;
    dq.z = gz * halfdt;
    
    *q = quaternionMultiply(*q, dq);
    quaternionNormalize(q);
}

void complementaryFilter(float ax, float ay, float az, float gx, float gy, float gz, float dt) {
    // Gyroscope integration (high-pass)
    updateQuaternion(&posture.currentQuat, gx, gy, gz, dt);
    
    // Accelerometer correction (low-pass)
    // Calculate tilt from accelerometer
    float accelNorm = sqrt(ax*ax + ay*ay + az*az);
    if (accelNorm > 0.001f) {
        ax /= accelNorm;
        ay /= accelNorm;
        az /= accelNorm;
        
        // Calculate correction quaternion from accelerometer
        float pitch = atan2(-ax, sqrt(ay*ay + az*az));
        float roll = atan2(ay, az);
        
        Quaternion accelQuat;
        float cy = cos(roll * 0.5f);
        float sy = sin(roll * 0.5f);
        float cp = cos(pitch * 0.5f);
        float sp = sin(pitch * 0.5f);
        
        accelQuat.w = cy * cp;
        accelQuat.x = cy * sp;
        accelQuat.y = sy * cp;
        accelQuat.z = -sy * sp;
        
        // Blend with complementary filter
        posture.currentQuat.w = alpha * posture.currentQuat.w + (1.0f - alpha) * accelQuat.w;
        posture.currentQuat.x = alpha * posture.currentQuat.x + (1.0f - alpha) * accelQuat.x;
        posture.currentQuat.y = alpha * posture.currentQuat.y + (1.0f - alpha) * accelQuat.y;
        posture.currentQuat.z = alpha * posture.currentQuat.z + (1.0f - alpha) * accelQuat.z;
        
        quaternionNormalize(&posture.currentQuat);
    }
}

// ==================== IMU FUNCTIONS ====================
bool initIMU() {
    Wire.begin(IMU_I2C_SDA, IMU_I2C_SCL);
    Wire.setClock(400000);  // 400kHz I2C
    
    int status = imu.begin();
    if (status < 0) {
        Serial.println("IMU initialization failed");
        return false;
    }
    
    // Configure IMU
    imu.setAccelRange(MPU9250::ACCEL_RANGE_4G);
    imu.setGyroRange(MPU9250::GYRO_RANGE_500DPS);
    imu.setDlpfBandwidth(MPU9250::DLPF_BANDWIDTH_41HZ);
    imu.setSrd(19);  // 50Hz sample rate
    
    // Enable motion interrupt
    pinMode(MOTION_INTERRUPT_PIN, INPUT);
    
    Serial.println("IMU initialized successfully");
    return true;
}

void readIMU() {
    imu.readSensor();
    
    // Read accelerometer (convert to g)
    imuData.ax = imu.getAccelX_mss() / 9.81f;
    imuData.ay = imu.getAccelY_mss() / 9.81f;
    imuData.az = imu.getAccelZ_mss() / 9.81f;
    
    // Read gyroscope (already in rad/s)
    imuData.gx = imu.getGyroX_rads();
    imuData.gy = imu.getGyroY_rads();
    imuData.gz = imu.getGyroZ_rads();
    
    // Read magnetometer
    imuData.mx = imu.getMagX_uT();
    imuData.my = imu.getMagY_uT();
    imuData.mz = imu.getMagZ_uT();
}

// ==================== POSTURE ANALYSIS ====================
void calibratePosture() {
    Serial.println("Calibrating posture... Stand/sit with good posture");
    
    // Average over 3 seconds for stable calibration
    Quaternion avgQuat = {0, 0, 0, 0};
    int samples = 150;  // 3 seconds at 50Hz
    
    for (int i = 0; i < samples; i++) {
        readIMU();
        uint32_t now = millis();
        float dt = (now - lastUpdateTime) / 1000.0f;
        lastUpdateTime = now;
        
        complementaryFilter(imuData.ax, imuData.ay, imuData.az,
                          imuData.gx, imuData.gy, imuData.gz, dt);
        
        avgQuat.w += posture.currentQuat.w;
        avgQuat.x += posture.currentQuat.x;
        avgQuat.y += posture.currentQuat.y;
        avgQuat.z += posture.currentQuat.z;
        
        delay(20);
    }
    
    posture.referenceQuat.w = avgQuat.w / samples;
    posture.referenceQuat.x = avgQuat.x / samples;
    posture.referenceQuat.y = avgQuat.y / samples;
    posture.referenceQuat.z = avgQuat.z / samples;
    quaternionNormalize(&posture.referenceQuat);
    
    posture.isCalibrated = true;
    Serial.println("Calibration complete!");
}

void detectSittingStanding() {
    // Use gravity component in Z-axis to detect sitting vs standing
    // When sitting, lumbar region is more horizontal
    float gravityZ = fabs(imuData.az);
    
    bool wasSitting = posture.isSitting;
    posture.isSitting = (gravityZ < SITTING_THRESHOLD);
    
    uint32_t now = millis();
    
    if (posture.isSitting && !wasSitting) {
        // Just started sitting
        posture.sittingStartTime = now;
    } else if (!posture.isSitting && wasSitting) {
        // Just stood up
        posture.totalSittingTime += (now - posture.sittingStartTime);
        posture.sittingStartTime = 0;
    }
}

void analyzePosture() {
    if (!posture.isCalibrated) {
        return;
    }
    
    // Calculate tilt angle from reference posture
    posture.tiltAngle = quaternionAngleBetween(posture.currentQuat, posture.referenceQuat);
    
    // Calculate pelvic tilt (anterior/posterior)
    // Extract pitch angle from quaternion
    float sinp = 2.0f * (posture.currentQuat.w * posture.currentQuat.y - 
                         posture.currentQuat.z * posture.currentQuat.x);
    posture.pelvicTilt = asin(sinp) * 180.0f / PI;
    
    // Detect sitting vs standing
    detectSittingStanding();
    
    // Slouch detection
    uint32_t now = millis();
    bool wasSlouchingMild = posture.isSlouchingMild;
    bool wasSlouchingSevere = posture.isSlouchingSevere;
    
    posture.isSlouchingMild = (posture.tiltAngle > config.slouchThresholdMild);
    posture.isSlouchingSevere = (posture.tiltAngle > config.slouchThresholdSevere);
    
    // Time-based slouch detection (must slouch continuously)
    static uint32_t slouchStartTime = 0;
    
    if (posture.isSlouchingMild) {
        if (!wasSlouchingMild) {
            slouchStartTime = now;
        } else if ((now - slouchStartTime) > config.slouchTimeThreshold) {
            // Trigger haptic feedback
            if (config.hapticsEnabled) {
                triggerHapticAlert(posture.isSlouchingSevere ? 2 : 1);
            }
        }
    } else {
        slouchStartTime = 0;
    }
    
    // Calculate posture score (0-100)
    float scoreBase = 100.0f - (posture.tiltAngle / config.slouchThresholdSevere) * 100.0f;
    posture.postureScore = constrain(scoreBase, 0.0f, 100.0f);
    
    // Check for break reminder
    static uint32_t lastBreakReminder = 0;
    if (posture.isSitting) {
        uint32_t sittingDuration = (now - posture.sittingStartTime) / 60000;  // Minutes
        if (sittingDuration >= config.breakReminderInterval && 
            (now - lastBreakReminder) > (config.breakReminderInterval * 60000)) {
            triggerHapticAlert(3);  // Break reminder pattern
            lastBreakReminder = now;
        }
    }
}

void triggerHapticAlert(uint8_t pattern) {
    switch (pattern) {
        case 1:  // Mild slouch - single pulse
            digitalWrite(HAPTIC_MOTOR_PIN, HIGH);
            delay(200);
            digitalWrite(HAPTIC_MOTOR_PIN, LOW);
            break;
            
        case 2:  // Severe slouch - double pulse
            for (int i = 0; i < 2; i++) {
                digitalWrite(HAPTIC_MOTOR_PIN, HIGH);
                delay(200);
                digitalWrite(HAPTIC_MOTOR_PIN, LOW);
                delay(100);
            }
            break;
            
        case 3:  // Break reminder - triple pulse
            for (int i = 0; i < 3; i++) {
                digitalWrite(HAPTIC_MOTOR_PIN, HIGH);
                delay(150);
                digitalWrite(HAPTIC_MOTOR_PIN, LOW);
                delay(100);
            }
            break;
    }
}

// ==================== BLE FUNCTIONS ====================
void initBLE() {
    BLEDevice::init("SmartBelt-Posture");
    
    // Create BLE Server
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new ServerCallbacks());
    
    // Create Posture Service
    BLEService *pService = pServer->createService(SERVICE_UUID_POSTURE);
    
    // Tilt Angle Characteristic (notify)
    pCharTiltAngle = pService->createCharacteristic(
        CHAR_UUID_TILT_ANGLE,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
    );
    pCharTiltAngle->addDescriptor(new BLE2902());
    
    // Posture Score Characteristic (notify)
    pCharPostureScore = pService->createCharacteristic(
        CHAR_UUID_POSTURE_SCORE,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
    );
    pCharPostureScore->addDescriptor(new BLE2902());
    
    // Sitting Time Characteristic (read)
    pCharSittingTime = pService->createCharacteristic(
        CHAR_UUID_SITTING_TIME,
        BLECharacteristic::PROPERTY_READ
    );
    
    // Configuration Characteristic (read/write)
    pCharConfig = pService->createCharacteristic(
        CHAR_UUID_CONFIG,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE
    );
    pCharConfig->setCallbacks(new ConfigCallbacks());
    
    // Calibration Characteristic (write)
    pCharCalibrate = pService->createCharacteristic(
        CHAR_UUID_CALIBRATE,
        BLECharacteristic::PROPERTY_WRITE
    );
    pCharCalibrate->setCallbacks(new CalibrateCallbacks());
    
    // Start service
    pService->start();
    
    // Start advertising
    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID_POSTURE);
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06);
    pAdvertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();
    
    Serial.println("BLE Posture Service started");
}

void updateBLECharacteristics() {
    if (!deviceConnected) return;
    
    // Update tilt angle
    pCharTiltAngle->setValue(posture.tiltAngle);
    pCharTiltAngle->notify();
    
    // Update posture score
    pCharPostureScore->setValue(posture.postureScore);
    pCharPostureScore->notify();
    
    // Update sitting time (current session + total)
    uint32_t currentSittingTime = posture.totalSittingTime;
    if (posture.isSitting && posture.sittingStartTime > 0) {
        currentSittingTime += (millis() - posture.sittingStartTime);
    }
    pCharSittingTime->setValue(currentSittingTime);
}

// ==================== MAIN SETUP & LOOP ====================
void setup() {
    Serial.begin(115200);
    while (!Serial) delay(10);
    
    Serial.println("Smart Belt - Posture Monitor");
    Serial.println("============================");
    
    // Initialize hardware
    pinMode(LED_PIN, OUTPUT);
    pinMode(HAPTIC_MOTOR_PIN, OUTPUT);
    
    // Initialize IMU
    if (!initIMU()) {
        Serial.println("FATAL: IMU initialization failed");
        while (1) {
            digitalWrite(LED_PIN, !digitalRead(LED_PIN));
            delay(100);
        }
    }
    
    // Initialize quaternion to identity
    posture.currentQuat = {1, 0, 0, 0};
    posture.referenceQuat = {1, 0, 0, 0};
    
    lastUpdateTime = millis();
    
    // Initialize BLE
    initBLE();
    
    // Prompt for initial calibration
    Serial.println("\nSend '1' to calibrate good posture");
    
    digitalWrite(LED_PIN, HIGH);
}

void loop() {
    static uint32_t lastIMURead = 0;
    static uint32_t lastBLEUpdate = 0;
    static uint32_t lastSerialPrint = 0;
    
    uint32_t now = millis();
    
    // Read IMU at 50Hz
    if (now - lastIMURead >= 20) {
        lastIMURead = now;
        
        readIMU();
        
        float dt = (now - lastUpdateTime) / 1000.0f;
        lastUpdateTime = now;
        
        // Apply complementary filter
        complementaryFilter(imuData.ax, imuData.ay, imuData.az,
                          imuData.gx, imuData.gy, imuData.gz, dt);
        
        // Analyze posture
        analyzePosture();
    }
    
    // Update BLE characteristics at 5Hz
    if (deviceConnected && now - lastBLEUpdate >= 200) {
        lastBLEUpdate = now;
        updateBLECharacteristics();
    }
    
    // Handle BLE disconnection
    if (!deviceConnected && oldDeviceConnected) {
        delay(500);
        pServer->startAdvertising();
        Serial.println("Restarting advertising");
        oldDeviceConnected = deviceConnected;
    }
    
    if (deviceConnected && !oldDeviceConnected) {
        oldDeviceConnected = deviceConnected;
    }
    
    // Serial monitoring at 1Hz
    if (now - lastSerialPrint >= 1000) {
        lastSerialPrint = now;
        
        if (posture.isCalibrated) {
            Serial.printf("Tilt: %.1f° | Score: %.0f | %s | %s\n",
                         posture.tiltAngle,
                         posture.postureScore,
                         posture.isSitting ? "SITTING" : "STANDING",
                         posture.isSlouchingSevere ? "SEVERE SLOUCH" : 
                         (posture.isSlouchingMild ? "MILD SLOUCH" : "GOOD"));
        }
    }
    
    // Handle serial commands
    if (Serial.available()) {
        char cmd = Serial.read();
        if (cmd == '1') {
            calibratePosture();
        }
    }
}
