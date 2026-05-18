#pragma once
#include "Types.h"
struct OnlineVarWin {
  int Nwin = 0; int head = 0; bool filled = false; float *buf = nullptr;
  double sum = 0; double sumSq = 0; float var = 0;
  void init(int n, float* storage){ Nwin=n; buf=storage; head=0; filled=false; sum=0; sumSq=0; var=0; for(int i=0;i<Nwin;i++) buf[i]=0; }
  void push(float x){
    float old = buf[head]; buf[head] = x; head = (head + 1) % Nwin;
    if(!filled){ sum += x; sumSq += (double)x*x; if(head==0) filled = true; }
    else { sum += x - old; sumSq += (double)x*x - (double)old*old; }
    int n = filled ? Nwin : head;
    if(n>1){ double mean = sum / (double)n; double v = (sumSq/(double)n) - mean*mean; var = (float)(v>0 ? v : 0); } else var = 0;
  }
};
class FootAlgo {
public:
  void begin(); void calibrateGyroBias(); bool process(const Sample& s);
  void snapshot(Telemetry& out); void setNotifyHz(uint32_t hz);
  void setDebug(bool en){ (void)en; } void setThresholds(float gyro_dps, float var_a){ (void)gyro_dps; (void)var_a; }
  void setK(float k){ (void)k; } void onHeelStrikeBaro(float press_mbar, float tempC);
  void onBaro(float press_mbar, float tempC); void setBaroPresent(bool ok){ (void)ok; }

private:
  float roll_deg=0, pitch_deg=0;
  float aLPF=0, gLPF=0; float axg_f=0, ayg_f=0, azg_f=0, gx_f=0, gy_f=0, gz_f=0;
  static const int MAX_WIN = (int)(SAMPLE_HZ*0.2f)+2; int Nwin = 0; float varBuf[MAX_WIN]; OnlineVarWin varwin;
  float vx=0, vy=0, vz=0; float px=0, py=0, pz=0; float swingVertPeak = G_MPS2; float lastModelLen_m = 0;
};
