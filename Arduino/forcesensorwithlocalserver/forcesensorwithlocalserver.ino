#include <WiFi.h>
#include <HTTPClient.h>

const char* ssid = "Fios-2wD3M";
const char* password = "will36fend47fur";
const char* serverIP = "192.168.1.181"; // Replace with your Flask server IP (Desktop IP)
const int serverPort = 5000;          // Port number where Flask server is running
const int sensorPin = 34;             // The analog pin the FSR is connected to

void setup() {
  // Start Serial Monitor
  Serial.begin(115200);

  // Connect to Wi-Fi
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(1000);
    Serial.println("Connecting to WiFi...");
  }
  Serial.println("Connected to WiFi!");

  // Print ESP32 local IP address for reference
  Serial.print("ESP32 IP Address: ");
  Serial.println(WiFi.localIP());

  // Initialize the analog pin (FSR)
  pinMode(sensorPin, INPUT);

  // Read and send the sensor value every 2 seconds
 
}

void sendData() {
  // Read FSR sensor value (analog input)
  int sensorValue = analogRead(sensorPin);  // Range: 0 to 4095

  // Map the sensor value to a more usable range if needed
  float voltage = (sensorValue / 4095.0) * 3.3;  // Convert to voltage (3.3V reference)
  Serial.print("FSR Sensor Value: ");
  Serial.println(sensorValue);  // Print the raw sensor value
  Serial.print("FSR Voltage: ");
  Serial.println(voltage);  // Print the sensor voltage

  // Prepare data to send (e.g., sensor value as a string)
  String data = "value=" + String(sensorValue);  // The data sent in POST request

  // Prepare the HTTP POST request
  HTTPClient http;
  http.begin("http://" + String(serverIP) + ":" + String(serverPort) + "/data");  // Server URL
  http.addHeader("Content-Type", "application/x-www-form-urlencoded");  // Specify content type
  http.addHeader("Connection", "close");  // Close connection after the response

  // Send the POST request with sensor data
  int httpResponseCode = http.POST(data);  // Send data

  // Check the server's response
  if (httpResponseCode > 0) {
    String response = http.getString();
    Serial.println("Server Response: " + response);  // Print response from the Flask server
  } else {
    Serial.println("Error in POST request: " + String(httpResponseCode));
  }

  // Close the connection
  http.end();

  // Wait before sending the next data (every 2 seconds)
  delay(3000);
}

void loop() {
   sendData();
  // Nothing to do in the loop, everything is handled in sendData()
}
