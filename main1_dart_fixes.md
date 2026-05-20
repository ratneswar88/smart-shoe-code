# Complete Fix for main1.dart - RSSI Display & Auto-Reconnect

## Issues Found:
1. RSSI not displaying - type mismatch (nullable vs non-nullable)
2. UUID parsing errors causing BLE connection issues
3. Auto-reconnect not working

## All Changes Required:

### 1. Add Auto-Reconnect Fields to ShoeBle Class (after line 333)

Add these two fields:
```dart
String? _deviceId;
bool _shouldReconnect = false;   // ADD THIS LINE
Timer? _reconnectTimer;          // ADD THIS LINE
```

### 2. Fix UUID Parsing Errors (lines 339-340)

BEFORE:
```dart
final Uuid yawUuid     = Uuid.parse("0000a003-0000-1000-00805f9b34fb");
final Uuid tempUuid    = Uuid.parse("0000b001-0000-1000-00805f9b34fb");
```

AFTER (add missing "8000"):
```dart
final Uuid yawUuid     = Uuid.parse("0000a003-0000-1000-8000-00805f9b34fb");
final Uuid tempUuid    = Uuid.parse("0000b001-0000-1000-8000-00805f9b34fb");
```

### 3. Replace the connect() method (lines 365-394)

REPLACE the entire connect method with this:

```dart
// ------------- Connect with Auto-Reconnect -------------
Future<void> connect(String id) async {
  await disconnect();
  _shouldReconnect = true;  // Enable auto-reconnect
  _deviceId = id;
  await _attemptConnection(id);
}

Future<void> _attemptConnection(String id) async {
  if (!_shouldReconnect) return;
  
  _connSub?.cancel();
  _connSub = _ble.connectToDevice(id: id).listen((u) async {
    _connState.add(u.connectionState);

    if (u.connectionState == DeviceConnectionState.connected) {
      _reconnectTimer?.cancel();  // Stop reconnect timer when connected
      
      // Ensure GATT is ready before starting RSSI
      try { await _ble.discoverAllServices(id); } catch (_) {}

      await _subscribeAll();

      // Kick RSSI immediately + periodic
      await _readRssiOnce();
      _startRssi();
    }

    if (u.connectionState == DeviceConnectionState.disconnected) {
      _stopRssi();
      await _unsubscribeAll();
      
      // Auto-reconnect if enabled
      if (_shouldReconnect && _deviceId != null) {
        debugPrint("[BLE] Disconnected. Will attempt reconnect in 3 seconds...");
        _reconnectTimer?.cancel();
        _reconnectTimer = Timer(const Duration(seconds: 3), () {
          if (_shouldReconnect && _deviceId != null) {
            debugPrint("[BLE] Attempting reconnect...");
            _attemptConnection(_deviceId!);
          }
        });
      }
    }
  }, onError: (e, _) async {
    debugPrint("[BLE] Connection error: $e");
    _connState.add(DeviceConnectionState.disconnected);
    _stopRssi();
    await _unsubscribeAll();
    
    // Auto-reconnect on error if enabled
    if (_shouldReconnect && _deviceId != null) {
      debugPrint("[BLE] Error occurred. Will attempt reconnect in 3 seconds...");
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 3), () {
        if (_shouldReconnect && _deviceId != null) {
          debugPrint("[BLE] Attempting reconnect after error...");
          _attemptConnection(_deviceId!);
        }
      });
    }
  });
}
```

### 4. Update disconnect() method (lines 396-402)

REPLACE with:
```dart
Future<void> disconnect() async {
  _shouldReconnect = false;  // Disable auto-reconnect
  _reconnectTimer?.cancel();  // ADD THIS LINE
  _stopRssi();
  await _unsubscribeAll();
  try { await _connSub?.cancel(); } catch (_) {}
  _connSub = null;
  _deviceId = null;
}
```

### 5. Update dispose() method (lines 404-416)

ADD these lines at the beginning:
```dart
void dispose() {
  _shouldReconnect = false;   // ADD THIS LINE
  _reconnectTimer?.cancel();  // ADD THIS LINE
  disconnect();
  try { _connState.close(); } catch (_) {}
  // ... rest remains the same
}
```

### 6. Fix RSSI Variable Type (line 539)

BEFORE:
```dart
int steps = 0, rssi = 0;
```

AFTER:
```dart
int steps = 0;
int? rssi;  // Changed to nullable
```

### 7. Fix RSSI Display (line 682)

BEFORE:
```dart
label: Text(
  "RSSI $rssi dBm",
```

AFTER:
```dart
label: Text(
  "RSSI ${rssi ?? '—'} dBm",  // Handle null value
```

### 8. Add required import (if not already present at top of file)

Make sure you have:
```dart
import 'package:flutter/foundation.dart'; // for debugPrint
```

## How Auto-Reconnect Works:

1. When `connect(id)` is called, it sets `_shouldReconnect = true`
2. If the device disconnects or has an error, a 3-second timer starts
3. After 3 seconds, it attempts to reconnect automatically
4. This continues until the user manually calls `disconnect()` or the app closes
5. Debug messages will appear in the console showing reconnection attempts

## Testing:

1. Connect to the device
2. Turn off Bluetooth on the shoe or move it out of range
3. Wait 3 seconds - you should see reconnection attempts in the console
4. Bring the device back in range - it should reconnect automatically
5. RSSI should now display properly when connected
