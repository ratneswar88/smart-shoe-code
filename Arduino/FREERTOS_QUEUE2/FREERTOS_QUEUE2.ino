#define SENSOR_PIN 34
QueueHandle_t queue1;  // Create handle
struct dataPack{    // define struct for the variables to be sent
    unsigned long sensorTime;
    int sensorValue;
};
void setup() {
    Serial.begin(115200);
    queue1 = xQueueCreate(1, sizeof(dataPack));  // Create queue
    
    xTaskCreate(
        getSensorData,      // Function name of the task
        "Get Sensor Data",  // Name of the task (e.g. for debugging)
        2048,               // Stack size (bytes)
        NULL,               // Parameter to pass
        1,                  // Task priority
        NULL                // Task handle
    );
    xTaskCreate(
        printSensor,        // Function name of the task
        "Print sensor",     // Name of the task (e.g. for debugging)
        2048,               // Stack size (bytes)
        NULL, // Parameter to pass
        1,                  // Task priority
        NULL                // Task handle
    );
}
void getSensorData(void *pvParameters){
    static unsigned long startTime = millis();
    while(1){
        dataPack sensorData = {0,0};
        sensorData.sensorTime = (millis() - startTime)/1000;
        sensorData.sensorValue = (analogRead(SENSOR_PIN));
        xQueueSend(queue1, &sensorData, 0);  // Send queue
        delay(500);
    }
}
void printSensor(void *pvParameters){
    while(1){
        dataPack currentData;
        xQueueReceive(queue1, &currentData,0); // Receive queue
        Serial.print("Time: ");
        Serial.println(currentData.sensorTime);
        Serial.print("Value: ");
        Serial.println(currentData.sensorValue);
        delay(2000);
    }
}
void loop(){}