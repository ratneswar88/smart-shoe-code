#include<Wire.h>
#include <WiFi.h>
#include <WiFiClient.h>
const int MPU_addr=0x68;
int16_t AcX,AcY,AcZ,Tmp,GyX,GyY,GyZ;
int16_t prevAccelX, prevAccelY, prevAccelZ;
double x,y, z;
int minVal=265;
int maxVal=402;
int stepCount = 0;
float cburn=0.0;
 
 
void setup()
{
Wire.begin();
Wire.beginTransmission(MPU_addr);
Wire.write(0x6B);
Wire.write(0);
Wire.endTransmission(true);
Serial.begin(9600);
//Blynk.begin(auth, ssid, pass);
 }

void loop()
{
//Blynk.run();
Wire.beginTransmission(MPU_addr);
Wire.write(0x3B);
Wire.endTransmission(false);
Wire.requestFrom(MPU_addr,14,true);
 
 
AcX=Wire.read()<<8|Wire.read();
AcY=Wire.read()<<8|Wire.read();
AcZ=Wire.read()<<8|Wire.read();
int xAng = map(AcX,minVal,maxVal,-90,90);
int yAng = map(AcY,minVal,maxVal,-90,90);
int zAng = map(AcZ,minVal,maxVal,-90,90);
 
x= RAD_TO_DEG * (atan2(-yAng, -zAng)+PI);
y= RAD_TO_DEG * (atan2(-xAng, -zAng)+PI);
z= RAD_TO_DEG * (atan2(-yAng, -xAng)+PI);

 
 // Calculate the magnitude of the current acceleration vector
  float currentAccelMag = sqrt(pow(AcX, 2) + pow(AcY, 2) + pow(AcZ, 2));
//Serial.println(currentAccelMag);
  // Calculate the magnitude of the previous acceleration vector
  float prevAccelMag = sqrt(pow(prevAccelX, 2) + pow(prevAccelY, 2) + pow(prevAccelZ, 2));
//Serial.println(prevAccelMag);
  // Check for a significant change in acceleration
  if ((currentAccelMag - prevAccelMag) > 3000) {
    // Increment the step count
    stepCount++;
  }
 
 
  prevAccelX = AcX;
  prevAccelY = AcY;
  prevAccelZ = AcZ;
  cburn=0.04*stepCount;
 Serial.print("stepCount: ");
 Serial.println(stepCount); 
 delay(3000);
Serial.print("Calories Burned :");
Serial.println(cburn);
Serial.print("Acceleration along X= ");
Serial.println(AcX);
Serial.print("Acceleration along Y= ");
Serial.println(AcY);
Serial.print("Acceleration along Y= ");
Serial.println(AcZ);
delay(3000);
Serial.print("AngleX= ");
Serial.println(x);
 
Serial.print("AngleY= ");
Serial.println(y);
 
Serial.print("AngleZ= ");
Serial.println(z);
Serial.println("-----------------------------------------");
delay(3000);
 /*
if(stepCount%5==0)
{
  Blynk.logEvent("step_count_notification", String("Congrats on ")+stepCount+String(" steps! Ready for the next leap?"));
}
 
int force= digitalRead(5);
WidgetLED led(V2);
if(force==0)
{
  Serial.println("Presence Detected");
  led.on();
}
else
{
    Serial.println("Presence not Detected");
  led.off();
}
 
 
Blynk.virtualWrite(V0,stepCount);
Blynk.virtualWrite(V1, cburn);
 
Blynk.run();
timer.run();  
*/  
}
