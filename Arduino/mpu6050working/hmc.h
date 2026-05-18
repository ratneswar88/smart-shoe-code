#include <Wire.h>
#include <MPU6050.h>
#include <MS5611.h>
#define HMC_ADDR 0x1E
MPU6050 accelgyro;
MS5611 ms5611;

float heading;
float temp;
float pres;
int16_t ax,ay,az,gx,gy,gz;
float accelX,accelY,accelZ,gyroX,gyroY,gyroZ;

void setup() {
  Serial.begin(9600);
  Wire.begin();
  Wire.beginTransmission(HMC_ADDR);
  Wire.write(0x02); // Mode register
  Wire.write(0x00); // Continuous mode
  Wire.endTransmission();
  accelgyro.initialize();
  ms5611.begin();
}

void getdata_hmc() {
  Wire.beginTransmission(HMC_ADDR);
  Wire.write(0x03); // Data output X MSB
  Wire.endTransmission();

  Wire.requestFrom(HMC_ADDR, 6);
  
accelgyro.getMotion6(&ax, &ay, &az,&gx,&gy,&gz);
float pre;
 temp = ms5611.readTemperature(); //Reads temperature.
 pre = ms5611.readPressure(); //Reads pressure.
  int16_t x = Wire.read()<<8 | Wire.read();
  int16_t z = Wire.read()<<8 | Wire.read();
  int16_t y = Wire.read()<<8 | Wire.read();

  heading = atan2(y, x) * 180/M_PI;
  pres = pre/1000;
  // Convert to physical units
 // ±2g range
 /*
  float accelX = ax / 16384.0; // ±2g range
  float accelY = ay / 16384.0;
  float accelZ = az / 16384.0;
  */
   accelX = ax / 8192.0; // ±4g range
   accelY = ay / 8192.0;
  accelZ = az / 8192.0;
   gyroX = gx / 131.0; // ±250°/s range
   gyroY = gy / 131.0;
   gyroZ = gz / 131.0;
  if (heading < 0) heading += 360;

 
}

void show_data()
{
  Serial.print("Heading (raw): ");
  Serial.print(heading, 1);
  Serial.println("°");
  Serial.print("Accel (g): X=");
  Serial.print(accelX,3);
  Serial.print(",");
  Serial.print(" Y=");
  Serial.print(",");
  Serial.print(accelY, 3);
  Serial.print(" Z=");
  Serial.print(",");
  Serial.print(accelZ, 3);
  Serial.print("\n");
  
  Serial.print("  Gyro: ");
  Serial.print(gx);
  Serial.print(", ");
  Serial.print(gy);
  Serial.print(", ");
  Serial.print(gz);
   Serial.print("\n");
 
  Serial.print("Temperature: ");
  Serial.print(temp, 2);
  Serial.println(" °C");
   Serial.print(", ");
  Serial.print("Pressure: ");
  Serial.print(pres, 2);
  Serial.println(" bar");
  delay(6000);
}
