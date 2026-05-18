#define LED1 2
#define LED2 13
SemaphoreHandle_t sem; // Create semaphore handle
void setup() {
    sem = xSemaphoreCreateBinary(); // Create binary semaphore
         
    xTaskCreate(
        blink1,      // Function name of the task
        "Blink 1",   // Name of the task (e.g. for debugging)
        2048,        // Stack size (bytes)
        NULL,        // Parameter to pass
        1,           // Task priority
        NULL         // Task handle
    );
    xTaskCreate(
        blink2,     // Function name of the task
        "Blink 2",  // Name of the task (e.g. for debugging)
        2048,       // Stack size (bytes)
        NULL,       // Parameter to pass
        1,          // Task priority
        NULL        // Task handle
    );
    xSemaphoreGive(sem);
}
void blink1(void *pvParameters){
    pinMode(LED1, OUTPUT);
    while(1){
        xSemaphoreTake(sem,portMAX_DELAY);
        for(int i=0; i<2; i++){
            digitalWrite(LED1, HIGH);
            delay(1000);
            digitalWrite(LED1, LOW);
            delay(1000);
        }
        xSemaphoreGive(sem);
        delay(100); // Short delay is needed!
    }
}
void blink2(void *pvParameters){
    pinMode(LED2, OUTPUT);
    while(1){
        xSemaphoreTake(sem,portMAX_DELAY);
        for(int i=0; i<2; i++){
            digitalWrite(LED2, HIGH);
            delay(1000);
            digitalWrite(LED2, LOW);
            delay(1000);   
        }
        xSemaphoreGive(sem);
        delay(100); // Short delay is needed!
    }
}
void loop(){}
 