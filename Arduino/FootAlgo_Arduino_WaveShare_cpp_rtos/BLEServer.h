#pragma once
#include <Arduino.h>
#include <NimBLEDevice.h>
#include "Types.h"
void bleSetup(); void bleNotifyNow(); void bleKickAdv(); void bleHandleCommand(const String& v);
