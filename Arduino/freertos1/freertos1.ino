#define LED 2
//#define LED2 26
//#define LED3 17
void setup()
 {
    pinMode(LED,OUTPUT);
  
    xTaskCreate(
        blink2,     // Function name of the task
        "Blink 2",  // Name of the task (e.g. for debugging)
        2048,       // Stack size (bytes)
        NULL,       // Parameter to pass
        1,          // Task priority
        NULL        // Task handle
    );
}

/*
void blink1(void *parameter) {
    pinMode(LED1, OUTPUT);
    while(1){
        digitalWrite(LED1, HIGH);
        delay(500); // Delay for Tasks 
        digitalWrite(LED1, LOW);
        delay(500);
    }
*/

void blink2(void *parameter) {
    pinMode(LED, OUTPUT);
    while(1) {
        digitalWrite(LED, HIGH);
        delay(333);
        digitalWrite(LED, LOW);
        delay(333);
    }
}
/*
void loop(){
    digitalWrite(LED, HIGH);
    delay(1111);
    digitalWrite(LED, LOW);
    delay(1111);
}
*/
void loop()
{
  
}
