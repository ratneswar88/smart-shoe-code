# SHOEML Train (bundle)

This bundle includes a minimal Flutter app with:
- BLE streaming for MADEPLUS Smart Shoe
- RSSI display
- Ambient temperature tile
- CSV saving to app sandbox (records/)
- Basic training (softmax) and real-time inference
- Branding (logo + MADEPLUS)

Place these files into a Flutter project folder, run `flutter pub get`, then build:
```
flutter build apk --release --target-platform=android-arm,android-arm64 --split-per-abi
```
