#include <Wire.h>
#include "hmc.h"
#include <MPU6050.h>
#include <MS5611.h>

void loop() {
  
getdata_hmc();
show_data(); 
}