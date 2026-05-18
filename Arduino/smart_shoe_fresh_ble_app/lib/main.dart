import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartShoeApp());
}

class SmartShoeApp extends StatelessWidget {
  const SmartShoeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Shoe BLE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const BLEHomePage(),
    );
  }
}

class BLEHomePage extends StatefulWidget {
  const BLEHomePage({super.key});
  @override
  State<BLEHomePage> createState() => _BLEHomePageState();
}

class _BLEHomePageState extends State<BLEHomePage> {
  // Custom UUIDs from your ESP32 sketch
  final Guid serviceUUID   = Guid("0000feed-0000-1000-8000-00805f9b34fb");
  final Guid charRollUUID  = Guid("0000a001-0000-1000-8000-00805f9b34fb");
  final Guid charPitchUUID = Guid("0000a002-0000-1000-8000-00805f9b34fb");
  final Guid charYawUUID   = Guid("0000a003-0000-1000-8000-00805f9b34fb");
  final Guid charTempUUID  = Guid("0000b001-0000-1000-8000-00805f9b34fb");
  final Guid charPressUUID = Guid("0000b002-0000-1000-8000-00805f9b34fb");
  final Guid charStepsUUID = Guid("0000c001-0000-1000-8000-00805f9b34fb");
  final Guid charCadUUID   = Guid("0000c002-0000-1000-8000-00805f9b34fb");
  final Guid charCmdUUID   = Guid("0000d001-0000-1000-8000-00805f9b34fb");

  BluetoothDevice? device;
  BluetoothCharacteristic? chTemp, chPress, chSteps, chCadence, chCmd;

  double temperature = 0, pressure = 0, cadence = 0;
  int steps = 0;

  bool isScanning = false;
  bool isConnecting = false;
  bool isConnected = false;

  List<ScanResult> _found = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _init() async {
    final supported = await FlutterBluePlus.isSupported;
    if (!supported) {
      _toast('BLE not supported on this device. Use a real phone.');
      return;
    }

    // Permissions (Android)
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    await _startScan();
  }

  Future<void> _startScan() async {
    if (isScanning) return;
    setState(() { isScanning = true; _found = []; });

    // Listen to results
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      final byId = <String, ScanResult>{};
      for (final r in results) {
        byId[r.device.remoteId.str] = r;
      }
      setState(() {
        _found = byId.values.toList()..sort((a,b)=>b.rssi.compareTo(a.rssi));
      });
    }, onError: (e) => _toast('Scan error: $e'));

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    } catch (e) {
      _toast('Start scan failed: $e');
    }

    await FlutterBluePlus.isScanning.firstWhere((s) => s == false);
    await sub.cancel();
    if (mounted) setState(() => isScanning = false);
  }

  Future<void> _connect(ScanResult r) async {
    if (isConnecting || isConnected) return;
    setState(() { isConnecting = true; device = r.device; });

    try {
      await r.device.connect(timeout: const Duration(seconds: 12));
      setState(() { isConnected = true; isConnecting = false; });
      await _discoverAndSubscribe();
    } catch (e) {
      setState(() { isConnected = false; isConnecting = false; device = null; });
      _toast('Connect error: $e');
    }
  }

  double _f32(Uint8List b) => b.length >= 4 ? b.buffer.asByteData().getFloat32(0, Endian.little) : 0.0;
  int _u32(Uint8List b)     => b.length >= 4 ? b.buffer.asByteData().getUint32(0, Endian.little) : 0;

  Future<void> _discoverAndSubscribe() async {
    if (device == null) return;
    List<BluetoothService> services = [];
    try {
      services = await device!.discoverServices();
    } catch (e) {
      _toast('Discover error: $e');
      return;
    }

    BluetoothService? svc;
    for (final s in services) {
      if (s.uuid == serviceUUID) { svc = s; break; }
    }
    if (svc == null) {
      _toast('Custom service not found.');
      return;
    }

    for (final c in svc.characteristics) {
      if (c.uuid == charTempUUID)  chTemp = c;
      if (c.uuid == charPressUUID) chPress = c;
      if (c.uuid == charStepsUUID) chSteps = c;
      if (c.uuid == charCadUUID)   chCadence = c;
      if (c.uuid == charCmdUUID)   chCmd = c;
    }

    Future<void> sub(BluetoothCharacteristic? c, void Function(Uint8List) onData) async {
      if (c == null) return;
      try {
        await c.setNotifyValue(true);
        c.onValueReceived.listen((v) => onData(Uint8List.fromList(v)));
        try {
          final init = await c.read();
          onData(Uint8List.fromList(init));
        } catch (_) {}
      } catch (e) {
        _toast('Notify error (${c.uuid}): $e');
      }
    }

    await sub(chTemp,   (d) => setState(() => temperature = _f32(d)));
    await sub(chPress,  (d) => setState(() => pressure = _f32(d)));
    await sub(chSteps,  (d) => setState(() => steps = _u32(d)));
    await sub(chCadence,(d) => setState(() => cadence = _f32(d)));
  }

  Future<void> _sendCmd(String s) async {
    if (chCmd == null) { _toast('Command characteristic not found'); return; }
    try {
      await chCmd!.write(utf8.encode(s), withoutResponse: false);
      _toast('Sent: $s');
    } catch (e) { _toast('Write error: $e'); }
  }

  Widget _metric(String title, String value, IconData icon) {
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 28),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: Text(value, style: const TextStyle(fontSize: 18)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Shoe BLE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Scan',
            onPressed: isScanning ? null : _startScan,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: isConnected
            ? SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _metric('Temperature (°C)', temperature.toStringAsFixed(2), Icons.thermostat),
                    _metric('Pressure (hPa)', pressure.toStringAsFixed(2), Icons.speed),
                    _metric('Steps', steps.toString(), Icons.directions_walk),
                    _metric('Cadence (spm)', cadence.toStringAsFixed(1), Icons.timer),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton(onPressed: () => _sendCmd('RESET_STEPS'), child: const Text('Reset Steps')),
                        ElevatedButton(onPressed: () => _sendCmd('STOP'), child: const Text('Stop')),
                        ElevatedButton(onPressed: () => _sendCmd('START'), child: const Text('Start')),
                        ElevatedButton(onPressed: () => _sendCmd('SET_TH:1.3'), child: const Text('TH 1.3g')),
                        ElevatedButton(onPressed: () => _sendCmd('SET_DEBOUNCE:300'), child: const Text('Debounce 300ms')),
                      ],
                    ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(isScanning ? 'Scanning...' : 'Tap refresh to scan')),
                      if (isScanning)
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _found.isEmpty
                        ? Center(
                            child: Text(
                              isScanning
                                  ? "Scanning... (use a real phone; emulators don't support BLE well)"
                                  : "No devices found. Tap refresh.",
                            ),
                          )
                        : ListView.builder(
                            itemCount: _found.length,
                            itemBuilder: (context, i) {
                              final r = _found[i];
                              final name = r.advertisementData.advName.isNotEmpty
                                  ? r.advertisementData.advName
                                  : (r.device.platformName.isNotEmpty
                                      ? r.device.platformName
                                      : r.device.remoteId.str);
                              return Card(
                                child: ListTile(
                                  title: Text(name),
                                  subtitle: Text('RSSI ${r.rssi}  •  ${r.device.remoteId.str}'),
                                  trailing: ElevatedButton(
                                    child: const Text('Connect'),
                                    onPressed: isConnecting ? null : () => _connect(r),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
