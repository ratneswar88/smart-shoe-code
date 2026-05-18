#include "Algorithm.h"
#include "Config.h"
#include "Utils.h"
#include "MPU6050.h"
#include "Mag.h"
#include "MS5611.h"
static const float DT = 1.0f / (float)SAMPLE_HZ;
void FootAlgo::begin(){ aLPF = lpfAlpha(LPF_FC_HZ, DT); gLPF = lpfAlpha(LPF_FC_HZ, DT); Nwin = (int)(0.10f * SAMPLE_HZ); if(Nwin < 5) Nwin = 5; varwin.init(Nwin, varBuf); }
void FootAlgo::calibrateGyroBias(){ /* simplified: handled in sensor loop if needed */ }
bool FootAlgo::process(const Sample& s){
  axg_f += aLPF*(s.ax_g - axg_f); ayg_f += aLPF*(s.ay_g - ayg_f); azg_f += aLPF*(s.az_g - azg_f);
  gx_f  += gLPF*(s.gx_dps - gx_f); gy_f  += gLPF*(s.gy_dps - gy_f); gz_f  += gLPF*(s.gz_dps - gz_f);
  float rollGyro  = gTel.roll_deg  + gx_f * DT; float pitchGyro = gTel.pitch_deg + gy_f * DT;
  float rollAcc   = atan2f(ayg_f, azg_f) * RAD2DEG; float pitchAcc  = atan2f(-axg_f, sqrtf(ayg_f*ayg_f + azg_f*azg_f)) * RAD2DEG;
  gTel.roll_deg  = CF_ALPHA*rollGyro  + (1.0f-CF_ALPHA)*rollAcc; gTel.pitch_deg = CF_ALPHA*pitchGyro + (1.0f-CF_ALPHA)*pitchAcc;
  float ax_ms2 = axg_f * G_MPS2; float ay_ms2 = ayg_f * G_MPS2; float az_ms2 = azg_f * G_MPS2; float amag = sqrtf(ax_ms2*ax_ms2 + ay_ms2*ay_ms2 + az_ms2*az_ms2);
  varwin.push(amag);
  // Minimal gait events omitted for brevity in this simplified Arduino variant.
  gTel.tempC = (float)s.rawTemp/340.0f + 36.53f;
  return false;
}
void FootAlgo::snapshot(Telemetry& out){ out=gTel; }
void FootAlgo::setNotifyHz(uint32_t hz){ (void)hz; }
void FootAlgo::onHeelStrikeBaro(float press_mbar, float tempC){ (void)press_mbar; (void)tempC; }
void FootAlgo::onBaro(float press_mbar, float tempC){ (void)press_mbar; (void)tempC; }
