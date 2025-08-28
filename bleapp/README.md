# Smart Shoe BLE App (Flutter)

A minimal Flutter app that connects to the **SmartShoe-ESP32** running `gy86peakwithble.ino`, subscribes to all notify characteristics, decodes the binary values (little-endian), and lets you send commands.

## Quick Start

1. **Install Flutter** and set up Android/iOS toolchains.
2. Create a fresh project:
   ```bash
   flutter create smart_shoe_ble_app
   cd smart_shoe_ble_app
   ```
3. Replace the generated files with the ones in this zip:
   - Overwrite `pubspec.yaml`
   - Copy the `lib/` folder
   - Merge Android and iOS config:
     - Replace `android/app/src/main/AndroidManifest.xml` with the one here.
     - Replace `ios/Runner/Info.plist` with the one here.
4. Get packages:
   ```bash
   flutter pub get
   ```
5. Run on a device:
   ```bash
   flutter run
   ```

## ESP32 Expectations

The sketch advertises a BLE service with UUID `0000feed-0000-1000-8000-00805f9b34fb` and the device name `SmartShoe-ESP32` and provides these characteristics:

- Roll (float, notify): `0000a001-0000-1000-8000-00805f9b34fb`
- Pitch (float, notify): `0000a002-0000-1000-8000-00805f9b34fb`
- Yaw (float, notify): `0000a003-0000-1000-8000-00805f9b34fb`
- Temperature (float, notify): `0000b001-0000-1000-8000-00805f9b34fb`
- Pressure (float, notify): `0000b002-0000-1000-8000-00805f9b34fb`
- Step count (uint32, notify): `0000c001-0000-1000-8000-00805f9b34fb`
- Cadence (float, notify): `0000c002-0000-1000-8000-00805f9b34fb`
- Command (write): `0000d001-0000-1000-8000-00805f9b34fb`

The app decodes `float` and `uint32` in **little-endian** (as written by the ESP32).

## Notes

- On Android 12+, the app requests `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` at runtime.
- On iOS, add your signing team in Xcode before building on device.
- If you change UUIDs in the ESP32 sketch, update them in `lib/main.dart`.

## Troubleshooting

- If scan shows nothing, ensure the ESP32 is powered and advertising.
- Toggle Bluetooth on the phone.
- On Android, ensure Location is ON (system setting) for scanning to work reliably on older versions.
