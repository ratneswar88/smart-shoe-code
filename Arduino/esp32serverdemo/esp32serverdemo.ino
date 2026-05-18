#include <WiFi.h>

const char* ssid = "Fios-2wD3M";
const char* password = "will36fend47fur";

const char* serverIP = "192.168.1.181";  // Replace with your Flask server IP (Desktop IP)
const int serverPort = 5000;  // Port number where Flask server is running

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

  // Prepare the data to send (simulating sensor data)
  String data = "value=10";  // Replace with actual sensor value

  // Send POST request to the Flask server
  WiFiClient client;
  if (client.connect(serverIP, serverPort)) {  // Connect to server (replace IP)
    Serial.println("Connected to server!");

    // Send HTTP POST request with sensor data
    client.println("POST /data HTTP/1.1");
    client.println("Host: " + String(serverIP));  // Server IP
    client.println("Content-Type: application/x-www-form-urlencoded");  // Content type for form data
    client.print("Content-Length: ");
    client.println(data.length());  // Send length of the data
    client.println();  // End of headers
    client.print(data);  // Send the actual data

    // Wait for the server's response and print it to the Serial Monitor
    while (client.available()) {
      String line = client.readStringUntil('\n');
      Serial.println(line);  // Print server response
    }

    // Close the connection to the server
    client.stop();
    Serial.println("Data sent and connection closed.");
  } else {
    Serial.println("Connection to server failed!");
  }
}

void loop() {
  // Nothing to do here for now
}