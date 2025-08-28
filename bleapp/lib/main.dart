
// Flutter app for SmartShoe-ESP32 BLE sketch
// Uses flutter_reactive_ble to scan, connect, subscribe to notifications, and send commands.
// Matches service/characteristic UUIDs in gy86peakwithble.ino.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(const SmartShoeApp());
}

class SmartShoeApp extends StatelessWidget {
  const SmartShoeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => FlutterReactiveBle()),
        ChangeNotifierProvider(create: (ctx) => BleController(ctx.read<FlutterReactiveBle>())),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Smart Shoe BLE',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const HomePage(),
      ),
    );
  }
}

// UUIDs copied from the ESP32 sketch
const Uuid serviceUuid    = Uuid.parse("0000feed-0000-1000-8000-00805f9b34fb");
const Uuid rollUuid       = Uuid.parse("0000a001-0000-1000-8000-00805f9b34fb");
const Uuid pitchUuid      = Uuid.parse("0000a002-0000-1000-8000-00805f9b34fb");
const Uuid yawUuid        = Uuid.parse("0000a003-0000-1000-8000-00805f9b34fb");
const Uuid tempUuid       = Uuid.parse("0000b001-0000-1000-8000-00805f9b34fb");
const Uuid pressUuid      = Uuid.parse("0000b002-0000-1000-8000-00805f9b34fb");
const Uuid stepsUuid      = Uuid.parse("0000c001-0000-1000-8000-00805f9b34fb");
const Uuid cadenceUuid    = Uuid.parse("0000c002-0000-1000-8000-00805f9b34fb");
const Uuid commandUuid    = Uuid.parse("0000d001-0000-1000-8000-00805f9b34fb");

class BleController extends ChangeNotifier {
  final FlutterReactiveBle _ble;

  BleController(this._ble);

  DiscoveredDevice? device;
  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;

  QualifiedCharacteristic? chRoll;
  QualifiedCharacteristic? chPitch;
  QualifiedCharacteristic? chYaw;
  QualifiedCharacteristic? chTemp;
  QualifiedCharacteristic? chPress;
  QualifiedCharacteristic? chSteps;
  QualifiedCharacteristic? chCadence;
  QualifiedCharacteristic? chCommand;

  StreamSubscription<List<int>>? _subRoll;
  StreamSubscription<List<int>>? _subPitch;
  StreamSubscription<List<int>>? _subYaw;
  StreamSubscription<List<int>>? _subTemp;
  StreamSubscription<List<int>>? _subPress;
  StreamSubscription<List<int>>? _subSteps;
  StreamSubscription<List<int>>? _subCadence;

  bool scanning = false;
  bool connecting = false;
  bool connected = false;
  String status = "Idle";

  double? roll, pitch, yaw, tempC, presshPa, cadence;
  int? steps;

  Future<void> startScan() async {
    status = "Requesting permissions...";
    notifyListeners();

    // Android 12+ needs BLUETOOTH_SCAN/CONNECT. permission_handler maps appropriately.
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse, // for older Androids
    ].request();

    // iOS doesn't need explicit perms in code (only Info.plist strings).

    scanning = true;
    status = "Scanning for SmartShoe-ESP32...";
    notifyListeners();

    _scanSub?.cancel();
    _scanSub = _ble.scanForDevices(
      withServices: [serviceUuid],
      scanMode: ScanMode.lowLatency,
    ).listen((d) {
      // Prefer advertised name "SmartShoe-ESP32" but fall back to service
      if (d.name.startsWith("SmartShoe") || d.serviceUuids.contains(serviceUuid)) {
        device = d;
        status = "Found device ${d.name} (${d.id})";
        notifyListeners();
        stopScan();
      }
    }, onError: (e) {
      status = "Scan error: $e";
      scanning = false;
      notifyListeners();
    });
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    scanning = false;
    notifyListeners();
  }

  Future<void> connect() async {
    final dev = device;
    if (dev == null) return;
    connecting = true;
    status = "Connecting...";
    notifyListeners();

    _connSub?.cancel();
    _connSub = _ble.connectToDevice(
      id: dev.id,
      servicesWithCharacteristicsToDiscover: {
        serviceUuid: {
          rollUuid, pitchUuid, yawUuid, tempUuid, pressUuid, stepsUuid, cadenceUuid, commandUuid
        }
      },
      connectionTimeout: const Duration(seconds: 10),
    ).listen((update) async {
      if (update.connectionState == DeviceConnectionState.connected) {
        connected = true;
        connecting = false;
        status = "Connected";
        _setupCharacteristics(dev);
        await _subscribeAll();
        notifyListeners();
      } else if (update.connectionState == DeviceConnectionState.disconnected) {
        connected = false;
        connecting = false;
        status = "Disconnected";
        _disposeSubs();
        notifyListeners();
      }
    }, onError: (e) {
      connecting = false;
      status = "Connection error: $e";
      notifyListeners();
    });
  }

  void _setupCharacteristics(DiscoveredDevice dev) {
    chRoll    = QualifiedCharacteristic(deviceId: dev.id, serviceId: serviceUuid, characteristicId: rollUuid);
    chPitch   = QualifiedCharacteristic(deviceId: dev.id, serviceId: serviceUuid, characteristicId: pitchUuid);
    chYaw     = QualifiedCharacteristic(deviceId: dev.id, serviceId: serviceUuid, characteristicId: yawUuid);
    chTemp    = QualifiedCharacteristic(deviceId: dev.id, serviceId: serviceUuid, characteristicId: tempUuid);
    chPress   = QualifiedCharacteristic(deviceId: dev.id, serviceId: serviceUuid, characteristicId: pressUuid);
    chSteps   = QualifiedCharacteristic(deviceId: dev.id, serviceId: serviceUuid, characteristicId: stepsUuid);
    chCadence = QualifiedCharacteristic(deviceId: dev.id, serviceId: serviceUuid, characteristicId: cadenceUuid);
    chCommand = QualifiedCharacteristic(deviceId: dev.id, serviceId: serviceUuid, characteristicId: commandUuid);
  }

  Future<void> _subscribeAll() async {
    _subRoll?.cancel();
    _subPitch?.cancel();
    _subYaw?.cancel();
    _subTemp?.cancel();
    _subPress?.cancel();
    _subSteps?.cancel();
    _subCadence?.cancel();

    if (chRoll != null) {
      _subRoll = _ble.subscribeToCharacteristic(chRoll!).listen((data) {
        roll = _leFloat(data);
        notifyListeners();
      });
    }
    if (chPitch != null) {
      _subPitch = _ble.subscribeToCharacteristic(chPitch!).listen((data) {
        pitch = _leFloat(data);
        notifyListeners();
      });
    }
    if (chYaw != null) {
      _subYaw = _ble.subscribeToCharacteristic(chYaw!).listen((data) {
        yaw = _leFloat(data);
        notifyListeners();
      });
    }
    if (chTemp != null) {
      _subTemp = _ble.subscribeToCharacteristic(chTemp!).listen((data) {
        tempC = _leFloat(data);
        notifyListeners();
      });
    }
    if (chPress != null) {
      _subPress = _ble.subscribeToCharacteristic(chPress!).listen((data) {
        presshPa = _leFloat(data);
        notifyListeners();
      });
    }
    if (chSteps != null) {
      _subSteps = _ble.subscribeToCharacteristic(chSteps!).listen((data) {
        steps = _leUint32(data);
        notifyListeners();
      });
    }
    if (chCadence != null) {
      _subCadence = _ble.subscribeToCharacteristic(chCadence!).listen((data) {
        cadence = _leFloat(data);
        notifyListeners();
      });
    }
  }

  Future<void> disconnect() async {
    await _connSub?.cancel();
    connected = false;
    status = "Disconnected";
    _disposeSubs();
    notifyListeners();
  }

  void _disposeSubs() {
    _subRoll?.cancel();
    _subPitch?.cancel();
    _subYaw?.cancel();
    _subTemp?.cancel();
    _subPress?.cancel();
    _subSteps?.cancel();
    _subCadence?.cancel();
  }

  Future<void> sendCommand(String text) async {
    if (chCommand == null || text.isEmpty) return;
    // Simple command protocol: send UTF-8 bytes (your ESP32 handler can parse)
    await _ble.writeCharacteristicWithResponse(chCommand!, value: text.codeUnits);
  }

  // Helpers to decode little-endian values from ESP32
  static double? _leFloat(List<int> data) {
    if (data.length < 4) return null;
    final b = ByteData.sublistView(Uint8List.fromList(data));
    return b.getFloat32(0, Endian.little);
    // If the sketch changes to double, use getFloat64 with 8 bytes.
  }

  static int? _leUint32(List<int> data) {
    if (data.length < 4) return null;
    final b = ByteData.sublistView(Uint8List.fromList(data));
    return b.getUint32(0, Endian.little);
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final cmdCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Smart Shoe BLE"),
        actions: [
          IconButton(
            tooltip: "Scan",
            onPressed: ble.scanning ? null : ble.startScan,
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: ble.connected ? "Disconnect" : "Connect",
            onPressed: () => ble.connected ? ble.disconnect() : ble.connect(),
            icon: Icon(ble.connected ? Icons.bluetooth_disabled : Icons.bluetooth_connected),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ble.status, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 12),
            if (ble.device != null)
              Card(
                child: ListTile(
                  title: Text(ble.device!.name.isEmpty ? "(Unnamed)" : ble.device!.name),
                  subtitle: Text(ble.device!.id),
                  trailing: Text("RSSI ${ble.device!.rssi}"),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metricCard(context, "Roll (°)", ble.roll?.toStringAsFixed(2)),
                _metricCard(context, "Pitch (°)", ble.pitch?.toStringAsFixed(2)),
                _metricCard(context, "Yaw (°)", ble.yaw?.toStringAsFixed(2)),
                _metricCard(context, "Temp (°C)", ble.tempC?.toStringAsFixed(2)),
                _metricCard(context, "Pressure (hPa)", ble.presshPa?.toStringAsFixed(2)),
                _metricCard(context, "Steps", ble.steps?.toString()),
                _metricCard(context, "Cadence (spm)", ble.cadence?.toStringAsFixed(1)),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: cmdCtrl,
                    decoration: const InputDecoration(
                      labelText: "Command to ESP32 (e.g., THRESH=1.2)",
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (t) => ble.sendCommand(t),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => ble.sendCommand(cmdCtrl.text),
                  child: const Text("Send"),
                )
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _metricCard(BuildContext context, String title, String? value) {
    return SizedBox(
      width: 160,
      height: 90,
      child: Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelMedium),
              const Spacer(),
              Text(value ?? "--", style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
      ),
    );
  }
}
