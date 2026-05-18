#define LED1 2
#define LED2 13
#define LED3 12
#define LED4 14
SemaphoreHandle_t countingSem; // Create semaphore handle
void setup() {
    countingSem = xSemaphoreCreateCounting(3,3); // Create counting semaphore
   
    xTaskCreate(blink1, "Blink 1", 2048, NULL, 1, NULL); 
    xTaskCreate(blink2, "Blink 2", 2048, NULL, 1, NULL);
    xTaskCreate(blink3, "Blink 3", 2048, NULL, 1, NULL);
    xTaskCreate(blink4, "Blink 4", 2048, NULL, 1, NULL);   
}
void blink1(void *parameter){
    pinMode(LED1, OUTPUT);
    while(1){
        /* Take a semaphore if available */
        xSemaphoreTake(countingSem, portMAX_DELAY); 
        for(int i=0; i<5; i++){
            digitalWrite(LED1, HIGH);
            delay(500); 
            digitalWrite(LED1, LOW);
            delay(500); 
        }
        /* Release the semaphore */
        xSemaphoreGive(countingSem);
        delay(300); // Short delay is needed
    }
}
void blink2(void *parameter){
    pinMode(LED2, OUTPUT);
    while(1){
        /* Take a semaphore if available */
        xSemaphoreTake(countingSem, portMAX_DELAY);
        for(int i=0; i<5; i++){
            digitalWrite(LED2, HIGH);
            delay(500);
            digitalWrite(LED2, LOW);
            delay(500);   
        }
        /* Release the semaphore */
        xSemaphoreGive(countingSem);
        delay(300); // Short delay is needed
    }
}
void blink3(void *parameter){
    pinMode(LED3, OUTPUT);
    while(1){
        /* Take a semaphore if available */
        xSemaphoreTake(countingSem, portMAX_DELAY);
        for(int i=0; i<5; i++){
            digitalWrite(LED3, HIGH);
            delay(500);//delay(333);
            digitalWrite(LED3, LOW);
            delay(500);   
        }
        /* Release the semaphore */
        xSemaphoreGive(countingSem);
        delay(300); // Short delay is needed
    }
}
void blink4(void *parameter){
    pinMode(LED4, OUTPUT);
    while(1){
        /* Take a semaphore if available */
        xSemaphoreTake(countingSem, portMAX_DELAY);
        for(int i=0; i<5; i++){
            digitalWrite(LED4, HIGH);
            delay(500);//delay(333);
            digitalWrite(LED4, LOW);
            delay(500);   
        }
        /* Release the semaphore */
        xSemaphoreGive(countingSem);
        delay(300); // Short delay is needed
    }
}
void loop(){}