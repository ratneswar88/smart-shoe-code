#pragma once
#include <Arduino.h>
#define MPU6050_ADDR 0x68
#define MPU6050_REG_PWR_MGMT_1 0x6B
#define MPU6050_REG_SMPLRT_DIV 0x19
#define MPU6050_REG_CONFIG     0x1A
#define MPU6050_REG_GYRO_CONFIG 0x1B
#define MPU6050_REG_ACCEL_CONFIG 0x1C
#define MPU6050_REG_ACCEL_XOUT_H 0x3B
#define MPU6050_REG_INT_PIN_CFG 0x37
#define MPU6050_REG_USER_CTRL   0x6A
extern float ACC_SENS; extern float GYR_SENS;
bool mpuInit200Hz(); bool mpuEnableBypass();
bool mpuReadAll(float &ax_g,float &ay_g,float &az_g, float &gx_dps,float &gy_dps,float &gz_dps, int16_t &rawTemp);
