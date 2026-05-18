const int sensorPin = 14;  // Analog input pin
//const int ledPin = 13;     // LED pin
//const int threshold = 300; // Tune this based on your sensor readings

void setup() {
  //pinMode(ledPin, OUTPUT);
  Serial.begin(9600);
}

void loop() {
  int sensorValue = analogRead(sensorPin); // Read from FSR
  Serial.println(sensorValue);             // Output to Serial Monitor

  /*
  if (sensorValue > threshold) {
    digitalWrite(ledPin, HIGH);            // Turn LED on
  } else {
    digitalWrite(ledPin, LOW);             // Turn LED off
  }
  */

  delay(100);
}