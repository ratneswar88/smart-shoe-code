/*
 * Smart Belt - Waist Circumference Monitoring System
 * ESP32-S3 + Strain Gauge / Force Sensitive Resistor
 * 
 * Features:
 * - Continuous waist circumference tracking
 * - Strain gauge with Wheatstone bridge + instrumentation amplifier
 * - Temperature compensation
 * - Clothing thickness normalization
 * - Long-term trend analysis
 * - BLE connectivity for mobile app
 */

#include <Wire.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Preferences.h>
#include <movingAvg.h>

// ==================== CONFIGURATION ====================
// ADC pins
#define STRAIN_GAUGE_PIN 34       // ADC1_CH6
#define TEMP_SENSOR_PIN 35        // ADC1_CH7 (optional thermistor)
#define VREF_PIN 36               // ADC1_CH0 (voltage reference)

// LED indicator
#define LED_PIN 2

// ADC configuration
#define ADC_RESOLUTION 12         // 12-bit ADC (0-4095)
#define ADC_VREF 3.3f            // Reference voltage
#define ADC_SAMPLES 100          // Oversampling for noise reduction

// Strain gauge configuration
#define GAUGE_FACTOR 2.1f        // Typical for metal foil strain gauges
#define BRIDGE_SUPPLY_VOLTAGE 5.0f
#define AMPLIFIER_GAIN 500.0f    // INA128 gain setting
#define GAUGE_RESISTANCE 350.0f  // Ohms (nominal)

// Calibration
#define CIRCUMFERENCE_MIN 60.0f   // cm
#define CIRCUMFERENCE_MAX 150.0f  // cm
#define TEMP_COMPENSATION_COEFF 0.001f  // Per degree C

// Measurement intervals
#define MEASUREMENT_INTERVAL 5000     // 5 seconds
#define TREND_UPDATE_INTERVAL 300000  // 5 minutes
#define STORAGE_INTERVAL 3600000      // 1 hour

// BLE UUIDs
#define SERVICE_UUID_WAIST          "5fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHAR_UUID_CURRENT_CIRCUM    "ceb5483e-36e1-4688-b7f5-ea07361b26a8"
#define CHAR_UUID_DAILY_AVG         "ceb5483f-36e1-4688-b7f5-ea07361b26a8"
#define CHAR_UUID_WEEKLY_TREND      "ceb54840-36e1-4688-b7f5-ea07361b26a8"
#define CHAR_UUID_CALIBRATION       "ceb54841-36e1-4688-b7f5-ea07361b26a8"
#define CHAR_UUID_RAW_DATA          "ceb54842-36e1-4688-b7f5-ea07361b26a8"

// ==================== DATA STRUCTURES ====================
struct CalibrationData {
    float baselineADC;            // ADC value at known circumference
    float calibrationCircumference; // Known circumference (cm)
    float strainPerCm;            // Microstrain per cm change
    float tempCoefficient;        // Temperature compensation
    bool isValid;
};

struct WaistMeasurement {
    float circumference;          // Current circumference (cm)
    float rawStrain;              // Microstrain
    float temperature;            // Temperature (°C)
    float confidence;             // Measurement confidence (0-1)
    uint32_t timestamp;
    bool isValid;
};

struct TrendData {
    float hourlyAvg[24];          // 24-hour trend
    float dailyAvg[7];            // 7-day trend
    float weeklyAvg[4];           // 4-week trend
    uint32_t lastUpdateTime;
    uint16_t hourlyIndex;
    uint16_t dailyIndex;
    uint16_t weeklyIndex;
};

struct PostureContext {
    bool isSitting;               // From posture monitor
    bool isEating;                // Post-meal detection
    uint32_t lastMealTime;
    float mealExpansion;          // Temporary expansion (cm)
};

// ==================== GLOBAL VARIABLES ====================
Preferences preferences;

// BLE
BLEServer* pServer = NULL;
BLECharacteristic* pCharCurrentCircum = NULL;
BLECharacteristic* pCharDailyAvg = NULL;
BLECharacteristic* pCharWeeklyTrend = NULL;
BLECharacteristic* pCharCalibration = NULL;
BLECharacteristic* pCharRawData = NULL;
bool deviceConnected = false;

// Measurement state
CalibrationData calibration = {0};
WaistMeasurement currentMeasurement = {0};
TrendData trends = {0};
PostureContext postureContext = {0};

// Moving average filters
movingAvg strainFilter(20);      // 20-sample moving average
movingAvg tempFilter(10);

// Statistics
struct Stats {
    float minCircumference;
    float maxCircumference;
    float avgCircumference;
    uint32_t totalMeasurements;
} stats = {999.0f, 0.0f, 0.0f, 0};

// ==================== ADC FUNCTIONS ====================
float readADC(uint8_t pin, uint16_t samples) {
    uint32_t sum = 0;
    
    for (uint16_t i = 0; i < samples; i++) {
        sum += analogRead(pin);
        delayMicroseconds(100);
    }
    
    float avg = (float)sum / samples;
    return avg;
}

float adcToVoltage(float adcValue) {
    return (adcValue / 4095.0f) * ADC_VREF;
}

// ==================== STRAIN GAUGE CALCULATIONS ====================
float calculateMicrostrain(float voltage) {
    /*
     * Wheatstone bridge + instrumentation amplifier
     * 
     * Strain gauge in quarter-bridge configuration:
     * Vout = (Vex * GF * ε) / 4
     * Where: Vex = bridge excitation, GF = gauge factor, ε = strain
     * 
     * After amplification:
     * Vmeasured = Vout * Gain
     * 
     * Solving for strain (in microstrain):
     * ε = (Vmeasured * 4 * 1,000,000) / (Vex * GF * Gain)
     */
    
    float microstrain = (voltage * 4.0f * 1000000.0f) / 
                        (BRIDGE_SUPPLY_VOLTAGE * GAUGE_FACTOR * AMPLIFIER_GAIN);
    
    return microstrain;
}

float microstrainToCircumference(float microstrain, float temperature) {
    if (!calibration.isValid) {
        return 0.0f;
    }
    
    // Temperature compensation
    float tempCorrection = (temperature - 25.0f) * calibration.tempCoefficient;
    float correctedStrain = microstrain - tempCorrection;
    
    // Convert strain to circumference change
    float deltaCircumference = correctedStrain / calibration.strainPerCm;
    
    // Apply baseline
    float circumference = calibration.calibrationCircumference + deltaCircumference;
    
    return circumference;
}

// ==================== TEMPERATURE MEASUREMENT ====================
float readTemperature() {
    /*
     * Using NTC thermistor with voltage divider
     * R_thermistor = R_fixed * (Vcc / V_measured - 1)
     * Then apply Steinhart-Hart equation for temperature
     */
    
    float adcValue = readADC(TEMP_SENSOR_PIN, 50);
    float voltage = adcToVoltage(adcValue);
    
    // Simplified temperature calculation (calibrate with actual thermistor)
    // Using typical NTC 10k @ 25°C characteristics
    const float R_FIXED = 10000.0f;
    const float BETA = 3950.0f;
    const float T0 = 298.15f;  // 25°C in Kelvin
    
    if (voltage < 0.01f) return 25.0f;  // Sensor error, return room temp
    
    float resistance = R_FIXED * (ADC_VREF / voltage - 1.0f);
    float temperature = 1.0f / (1.0f / T0 + (1.0f / BETA) * log(resistance / R_FIXED));
    temperature -= 273.15f;  // Convert to Celsius
    
    return temperature;
}

// ==================== CALIBRATION ====================
void calibrateWaist(float knownCircumference) {
    Serial.printf("Calibrating waist at %.1f cm...\n", knownCircumference);
    Serial.println("Please stand still for 10 seconds...");
    
    // Collect baseline measurements
    float strainSum = 0.0f;
    float tempSum = 0.0f;
    int samples = 50;
    
    for (int i = 0; i < samples; i++) {
        float adcValue = readADC(STRAIN_GAUGE_PIN, ADC_SAMPLES);
        float voltage = adcToVoltage(adcValue);
        float strain = calculateMicrostrain(voltage);
        
        float temp = readTemperature();
        
        strainSum += strain;
        tempSum += temp;
        
        Serial.printf("Sample %d/%d: Strain=%.2f μɛ, Temp=%.1f°C\n", 
                     i+1, samples, strain, temp);
        
        delay(200);
    }
    
    calibration.baselineADC = readADC(STRAIN_GAUGE_PIN, ADC_SAMPLES * 2);
    calibration.calibrationCircumference = knownCircumference;
    calibration.strainPerCm = (strainSum / samples) / knownCircumference;
    calibration.tempCoefficient = TEMP_COMPENSATION_COEFF;
    calibration.isValid = true;
    
    // Save to flash
    preferences.begin("waist-cal", false);
    preferences.putFloat("baseline", calibration.baselineADC);
    preferences.putFloat("circum", calibration.calibrationCircumference);
    preferences.putFloat("strain_cm", calibration.strainPerCm);
    preferences.putFloat("temp_coeff", calibration.tempCoefficient);
    preferences.putBool("valid", true);
    preferences.end();
    
    Serial.println("Calibration complete and saved!");
    Serial.printf("Baseline: %.2f μɛ/cm\n", calibration.strainPerCm);
}

void loadCalibration() {
    preferences.begin("waist-cal", true);
    
    calibration.baselineADC = preferences.getFloat("baseline", 0.0f);
    calibration.calibrationCircumference = preferences.getFloat("circum", 0.0f);
    calibration.strainPerCm = preferences.getFloat("strain_cm", 0.0f);
    calibration.tempCoefficient = preferences.getFloat("temp_coeff", TEMP_COMPENSATION_COEFF);
    calibration.isValid = preferences.getBool("valid", false);
    
    preferences.end();
    
    if (calibration.isValid) {
        Serial.println("Calibration loaded from flash");
        Serial.printf("Reference: %.1f cm, Strain factor: %.2f μɛ/cm\n",
                     calibration.calibrationCircumference,
                     calibration.strainPerCm);
    } else {
        Serial.println("No valid calibration found");
    }
}

// ==================== MEASUREMENT FUNCTIONS ====================
WaistMeasurement measureWaist() {
    WaistMeasurement measurement = {0};
    measurement.timestamp = millis();
    
    // Read strain gauge
    float adcValue = readADC(STRAIN_GAUGE_PIN, ADC_SAMPLES);
    float voltage = adcToVoltage(adcValue);
    float rawStrain = calculateMicrostrain(voltage);
    
    // Apply moving average filter
    float filteredStrain = strainFilter.reading(rawStrain);
    
    // Read temperature
    float temperature = readTemperature();
    float filteredTemp = tempFilter.reading(temperature);
    
    // Convert to circumference
    float circumference = microstrainToCircumference(filteredStrain, filteredTemp);
    
    // Validate measurement
    bool isValid = (circumference >= CIRCUMFERENCE_MIN && 
                   circumference <= CIRCUMFERENCE_MAX &&
                   calibration.isValid);
    
    // Calculate confidence based on signal stability
    static float lastStrain = 0.0f;
    float strainVariation = fabs(filteredStrain - lastStrain);
    float confidence = 1.0f - constrain(strainVariation / 100.0f, 0.0f, 1.0f);
    lastStrain = filteredStrain;
    
    measurement.circumference = circumference;
    measurement.rawStrain = filteredStrain;
    measurement.temperature = filteredTemp;
    measurement.confidence = confidence;
    measurement.isValid = isValid;
    
    return measurement;
}

void detectPostureContext() {
    /*
     * Detect temporary waist expansion factors:
     * 1. Post-meal expansion (30-60 minutes after eating)
     * 2. Sitting vs standing (abdominal compression)
     * 3. Breathing patterns (diaphragm movement)
     */
    
    uint32_t now = millis();
    
    // Detect meal expansion pattern (gradual increase then decrease)
    static float lastCircumference = 0.0f;
    static float maxRecentCircumference = 0.0f;
    static uint32_t expansionStartTime = 0;
    
    float deltaCircum = currentMeasurement.circumference - lastCircumference;
    
    // Rapid increase (>0.5 cm in 5 min) suggests meal
    if (deltaCircum > 0.5f && (now - postureContext.lastMealTime) > 3600000) {
        postureContext.isEating = true;
        postureContext.lastMealTime = now;
        expansionStartTime = now;
        maxRecentCircumference = currentMeasurement.circumference;
        Serial.println("Meal expansion detected");
    }
    
    // Track meal expansion
    if (postureContext.isEating) {
        if (currentMeasurement.circumference > maxRecentCircumference) {
            maxRecentCircumference = currentMeasurement.circumference;
        }
        
        postureContext.mealExpansion = maxRecentCircumference - lastCircumference;
        
        // Reset after 2 hours
        if ((now - postureContext.lastMealTime) > 7200000) {
            postureContext.isEating = false;
            postureContext.mealExpansion = 0.0f;
        }
    }
    
    lastCircumference = currentMeasurement.circumference;
}

float getBaselineCircumference() {
    /*
     * Return circumference adjusted for temporary factors
     * This gives the "true" waist measurement for trending
     */
    
    float adjusted = currentMeasurement.circumference;
    
    // Subtract meal expansion
    if (postureContext.isEating) {
        adjusted -= postureContext.mealExpansion * 0.7f;  // 70% correction factor
    }
    
    // Adjust for sitting (abdomen compresses ~1-2 cm)
    if (postureContext.isSitting) {
        adjusted += 1.5f;
    }
    
    return adjusted;
}

// ==================== TREND ANALYSIS ====================
void updateTrends() {
    uint32_t now = millis();
    
    if ((now - trends.lastUpdateTime) < TREND_UPDATE_INTERVAL) {
        return;
    }
    
    float baseline = getBaselineCircumference();
    
    // Update hourly average
    trends.hourlyAvg[trends.hourlyIndex] = baseline;
    trends.hourlyIndex = (trends.hourlyIndex + 1) % 24;
    
    // Calculate daily average every 24 hours
    static uint32_t lastDailyUpdate = 0;
    if ((now - lastDailyUpdate) >= 86400000) {  // 24 hours
        float dailySum = 0.0f;
        for (int i = 0; i < 24; i++) {
            dailySum += trends.hourlyAvg[i];
        }
        trends.dailyAvg[trends.dailyIndex] = dailySum / 24.0f;
        trends.dailyIndex = (trends.dailyIndex + 1) % 7;
        lastDailyUpdate = now;
        
        Serial.printf("Daily average: %.2f cm\n", trends.dailyAvg[trends.dailyIndex]);
    }
    
    // Calculate weekly average
    static uint32_t lastWeeklyUpdate = 0;
    if ((now - lastWeeklyUpdate) >= 604800000) {  // 7 days
        float weeklySum = 0.0f;
        for (int i = 0; i < 7; i++) {
            weeklySum += trends.dailyAvg[i];
        }
        trends.weeklyAvg[trends.weeklyIndex] = weeklySum / 7.0f;
        trends.weeklyIndex = (trends.weeklyIndex + 1) % 4;
        lastWeeklyUpdate = now;
        
        Serial.printf("Weekly average: %.2f cm\n", trends.weeklyAvg[trends.weeklyIndex]);
    }
    
    trends.lastUpdateTime = now;
    
    // Update statistics
    updateStatistics(baseline);
}

void updateStatistics(float circumference) {
    stats.totalMeasurements++;
    
    if (circumference < stats.minCircumference) {
        stats.minCircumference = circumference;
    }
    
    if (circumference > stats.maxCircumference) {
        stats.maxCircumference = circumference;
    }
    
    // Running average
    stats.avgCircumference = ((stats.avgCircumference * (stats.totalMeasurements - 1)) + 
                              circumference) / stats.totalMeasurements;
}

// ==================== BLE FUNCTIONS ====================
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

class CalibrationCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
        std::string value = pCharacteristic->getValue();
        
        if (value.length() == sizeof(float)) {
            float knownCircumference;
            memcpy(&knownCircumference, value.data(), sizeof(float));
            calibrateWaist(knownCircumference);
        }
    }
};

void initBLE() {
    BLEDevice::init("SmartBelt-Waist");
    
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new ServerCallbacks());
    
    BLEService *pService = pServer->createService(SERVICE_UUID_WAIST);
    
    // Current circumference (notify)
    pCharCurrentCircum = pService->createCharacteristic(
        CHAR_UUID_CURRENT_CIRCUM,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
    );
    pCharCurrentCircum->addDescriptor(new BLE2902());
    
    // Daily average (read)
    pCharDailyAvg = pService->createCharacteristic(
        CHAR_UUID_DAILY_AVG,
        BLECharacteristic::PROPERTY_READ
    );
    
    // Weekly trend (read)
    pCharWeeklyTrend = pService->createCharacteristic(
        CHAR_UUID_WEEKLY_TREND,
        BLECharacteristic::PROPERTY_READ
    );
    
    // Calibration (write)
    pCharCalibration = pService->createCharacteristic(
        CHAR_UUID_CALIBRATION,
        BLECharacteristic::PROPERTY_WRITE
    );
    pCharCalibration->setCallbacks(new CalibrationCallbacks());
    
    // Raw data (read) - for debugging
    pCharRawData = pService->createCharacteristic(
        CHAR_UUID_RAW_DATA,
        BLECharacteristic::PROPERTY_READ
    );
    
    pService->start();
    
    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID_WAIST);
    pAdvertising->setScanResponse(true);
    BLEDevice::startAdvertising();
    
    Serial.println("BLE Waist Service started");
}

void updateBLECharacteristics() {
    if (!deviceConnected || !currentMeasurement.isValid) return;
    
    // Update current circumference
    pCharCurrentCircum->setValue(currentMeasurement.circumference);
    pCharCurrentCircum->notify();
    
    // Update daily average
    float dailySum = 0.0f;
    for (int i = 0; i < 7; i++) {
        dailySum += trends.dailyAvg[i];
    }
    float dailyAvg = dailySum / 7.0f;
    pCharDailyAvg->setValue(dailyAvg);
    
    // Update weekly trend (send array)
    pCharWeeklyTrend->setValue((uint8_t*)trends.weeklyAvg, sizeof(trends.weeklyAvg));
    
    // Update raw data (for debugging)
    struct RawData {
        float strain;
        float temperature;
        float confidence;
    } rawData;
    
    rawData.strain = currentMeasurement.rawStrain;
    rawData.temperature = currentMeasurement.temperature;
    rawData.confidence = currentMeasurement.confidence;
    
    pCharRawData->setValue((uint8_t*)&rawData, sizeof(rawData));
}

// ==================== MAIN SETUP & LOOP ====================
void setup() {
    Serial.begin(115200);
    while (!Serial) delay(10);
    
    Serial.println("Smart Belt - Waist Circumference Monitor");
    Serial.println("========================================");
    
    pinMode(LED_PIN, OUTPUT);
    
    // Configure ADC
    analogReadResolution(ADC_RESOLUTION);
    analogSetAttenuation(ADC_11db);  // 0-3.3V range
    
    // Initialize moving average filters
    strainFilter.begin();
    tempFilter.begin();
    
    // Load calibration from flash
    loadCalibration();
    
    // Initialize BLE
    initBLE();
    
    // Initialize trends
    memset(&trends, 0, sizeof(trends));
    
    if (!calibration.isValid) {
        Serial.println("\n*** CALIBRATION REQUIRED ***");
        Serial.println("Measure your waist with a tape measure");
        Serial.println("Then send: CAL:<circumference_in_cm>");
        Serial.println("Example: CAL:85.5");
    }
    
    digitalWrite(LED_PIN, HIGH);
    Serial.println("System ready");
}

void loop() {
    static uint32_t lastMeasurement = 0;
    static uint32_t lastBLEUpdate = 0;
    static uint32_t lastSerialPrint = 0;
    
    uint32_t now = millis();
    
    // Measure waist at regular intervals
    if (now - lastMeasurement >= MEASUREMENT_INTERVAL) {
        lastMeasurement = now;
        
        currentMeasurement = measureWaist();
        
        if (currentMeasurement.isValid) {
            detectPostureContext();
            updateTrends();
        }
    }
    
    // Update BLE characteristics
    if (deviceConnected && now - lastBLEUpdate >= 10000) {  // Every 10 seconds
        lastBLEUpdate = now;
        updateBLECharacteristics();
    }
    
    // Serial monitoring
    if (now - lastSerialPrint >= 5000) {
        lastSerialPrint = now;
        
        if (currentMeasurement.isValid) {
            float baseline = getBaselineCircumference();
            Serial.printf("Waist: %.2f cm (baseline: %.2f cm) | Strain: %.1f μɛ | Temp: %.1f°C | Conf: %.0f%%\n",
                         currentMeasurement.circumference,
                         baseline,
                         currentMeasurement.rawStrain,
                         currentMeasurement.temperature,
                         currentMeasurement.confidence * 100.0f);
            
            if (postureContext.isEating) {
                Serial.printf("  [Meal expansion: %.2f cm]\n", postureContext.mealExpansion);
            }
        } else if (!calibration.isValid) {
            Serial.println("Waiting for calibration...");
        }
    }
    
    // Handle serial commands
    if (Serial.available()) {
        String cmd = Serial.readStringUntil('\n');
        cmd.trim();
        
        if (cmd.startsWith("CAL:")) {
            float circumference = cmd.substring(4).toFloat();
            if (circumference >= CIRCUMFERENCE_MIN && circumference <= CIRCUMFERENCE_MAX) {
                calibrateWaist(circumference);
            } else {
                Serial.println("Invalid circumference value");
            }
        } else if (cmd == "STATS") {
            Serial.println("\n=== Statistics ===");
            Serial.printf("Measurements: %u\n", stats.totalMeasurements);
            Serial.printf("Min: %.2f cm\n", stats.minCircumference);
            Serial.printf("Avg: %.2f cm\n", stats.avgCircumference);
            Serial.printf("Max: %.2f cm\n", stats.maxCircumference);
            Serial.printf("Range: %.2f cm\n", stats.maxCircumference - stats.minCircumference);
        } else if (cmd == "RESET") {
            calibration.isValid = false;
            preferences.begin("waist-cal", false);
            preferences.clear();
            preferences.end();
            Serial.println("Calibration reset");
        }
    }
    
    // Handle BLE disconnection
    static bool oldDeviceConnected = false;
    if (!deviceConnected && oldDeviceConnected) {
        delay(500);
        pServer->startAdvertising();
        oldDeviceConnected = deviceConnected;
    }
    if (deviceConnected && !oldDeviceConnected) {
        oldDeviceConnected = deviceConnected;
    }
}
