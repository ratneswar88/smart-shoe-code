import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
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
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // === Custom UUIDs (match your ESP32) ===
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
  BluetoothCharacteristic? chRoll, chPitch, chYaw, chTemp, chPress, chSteps, chCadence, chCmd;

  // Live values
  double roll = 0, pitch = 0, yaw = 0;
  double temperature = 0, pressure = 0;
  int steps = 0;
  double cadence = 0;

  bool isScanning = false;
  bool isConnecting = false;
  bool isConnected = false;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  List<ScanResult> _found = [];

  @override
  void initState() {
    super.initState();
    _initAndScan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connSub?.cancel();
    device?.disconnect();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ===== Permissions + Adapter + Scan =====
  Future<bool> _ensurePermissions() async {
    try {
      if (Platform.isAndroid) {
        final req = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse, // needed on some OEMs for scanning
        ].request();
        return req.values.every((s) => s.isGranted);
      } else if (Platform.isIOS) {
        final req = await [Permission.bluetooth].request();
        return req.values.every((s) => s.isGranted);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensureBluetoothOn() async {
    // prompts user to enable BT if off
    try {
      await FlutterBluePlus.turnOn();
    } catch (_) {}

    // Wait until the adapter is actually on
    try {
      final state = await FlutterBluePlus.adapterState.firstWhere(
        (s) => s == BluetoothAdapterState.on,
        orElse: () => BluetoothAdapterState.off,
      );
      if (state != BluetoothAdapterState.on) {
        _toast('Please enable Bluetooth to scan.');
      }
    } catch (_) {}
  }

  Future<void> _initAndScan() async {
    try {
      final supported = await FlutterBluePlus.isSupported;
      if (!supported) {
        _toast('BLE not supported on this device/emulator. Use a real phone.');
        return;
      }

      final ok = await _ensurePermissions();
      if (!ok) {
        _toast('Bluetooth/Location permissions are required.');
        return;
      }

      await _ensureBluetoothOn();
      await _startScan();
    } catch (e) {
      _toast('Init error: $e');
    }
  }

  Future<void> _startScan() async {
    if (isScanning) return;
    setState(() {
      isScanning = true;
      _found = [];
    });

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      if (results.isEmpty) return;
      setState(() {
        final map = <String, ScanResult>{};
        for (final r in results) {
          map[r.device.remoteId.str] = r;
        }
        _found = map.values.toList()
          ..sort((a, b) => b.rssi.compareTo(a.rssi));
      });
    }, onError: (err) {
      _toast('Scan error: $err');
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    } catch (e) {
      _toast('Start scan failed: $e');
    }

    FlutterBluePlus.isScanning.where((v) => v == false).first.then((_) {
      if (mounted) setState(() => isScanning = false);
    });
  }

  // ===== Connect & Discover =====
  Future<void> _connect(BluetoothDevice d) async {
    if (isConnecting || isConnected) return;
    setState(() {
      isConnecting = true;
      device = d;
    });

    _connSub?.cancel();
    _connSub = d.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) {
        setState(() {
          isConnected = false;
          isConnecting = false;
          device = null;
        });
        _toast('Disconnected');
      }
    });

    try {
      await d.connect(timeout: const Duration(seconds: 12));
      setState(() {
        isConnecting = false;
        isConnected = true;
      });
      await _discoverAndSubscribe();
    } catch (e) {
      setState(() {
        isConnecting = false;
        isConnected = false;
        device = null;
      });
      _toast('Connect error: $e');
    }
  }

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
      if (s.uuid == serviceUUID) {
        svc = s;
        break;
      }
    }
    if (svc == null) {
      _toast('Custom service not found on device.');
      return;
    }

    for (final c in svc.characteristics) {
      if (c.uuid == charRollUUID)  chRoll = c;
      if (c.uuid == charPitchUUID) chPitch = c;
      if (c.uuid == charYawUUID)   chYaw  = c;
      if (c.uuid == charTempUUID)  chTemp = c;
      if (c.uuid == charPressUUID) chPress = c;
      if (c.uuid == charStepsUUID) chSteps = c;
      if (c.uuid == charCadUUID)   chCadence = c;
      if (c.uuid == charCmdUUID)   chCmd = c;
    }

    if ([chRoll, chPitch, chYaw, chTemp, chPress, chSteps, chCadence].every((c) => c == null)) {
      _toast('No expected characteristics found.');
    }

    double f32(Uint8List b) => b.length >= 4 ? b.buffer.asByteData().getFloat32(0, Endian.little) : 0.0;
    int u32(Uint8List b)     => b.length >= 4 ? b.buffer.asByteData().getUint32(0, Endian.little) : 0;

    Future<void> sub(BluetoothCharacteristic? c, void Function(Uint8List) onData) async {
      if (c == null) return;
      try {
        await c.setNotifyValue(true);
        c.onValueReceived.listen((v) {
          try {
            onData(Uint8List.fromList(v));
          } catch (_) {}
        });
        try {
          final init = await c.read();
          onData(Uint8List.fromList(init));
        } catch (_) {}
      } catch (e) {
        _toast('Notify error (${c.uuid}): $e');
      }
    }

    await sub(chRoll,   (d) => setState(() => roll = f32(d)));
    await sub(chPitch,  (d) => setState(() => pitch = f32(d)));
    await sub(chYaw,    (d) => setState(() => yaw = f32(d)));
    await sub(chTemp,   (d) => setState(() => temperature = f32(d)));
    await sub(chPress,  (d) => setState(() => pressure = f32(d)));
    await sub(chSteps,  (d) => setState(() => steps = u32(d)));
    await sub(chCadence,(d) => setState(() => cadence = f32(d)));
  }

  // ===== Send Commands =====
  Future<void> _sendCmd(String s) async {
    if (chCmd == null) {
      _toast('Command characteristic not found.');
      return;
    }
    try {
      await chCmd!.write(utf8.encode(s), withoutResponse: false);
      _toast('Sent: $s');
    } catch (e) {
      _toast('Write error: $e');
    }
  }

  // ===== UI =====
  Widget _tile(String title, String value, IconData icon) {
    return Card(
      elevation: 3,
      child: ListTile(
        leading: Icon(icon, size: 28),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: Text(value, style: const TextStyle(fontSize: 18)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = isConnected
        ? "Connected to ${device?.platformName ?? device?.remoteId.str ?? 'device'}"
        : (isConnecting ? "Connecting..." : (isScanning ? "Scanning..." : "Disconnected"));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Shoe BLE'),
        actions: [
          IconButton(
            tooltip: 'Scan',
            onPressed: isScanning ? null : _startScan,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: isConnected
            ? SingleChildScrollView(
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.bluetooth, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(status)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _tile('Roll (°)', roll.toStringAsFixed(2), Icons.rotate_90_degrees_ccw),
                    _tile('Pitch (°)', pitch.toStringAsFixed(2), Icons.rotate_90_degrees_cw),
                    _tile('Yaw (°)', yaw.toStringAsFixed(2), Icons.explore),
                    _tile('Temperature (°C)', temperature.toStringAsFixed(2), Icons.thermostat),
                    _tile('Pressure (hPa)', pressure.toStringAsFixed(2), Icons.speed),
                    _tile('Steps', steps.toString(), Icons.directions_walk),
                    _tile('Cadence (spm)', cadence.toStringAsFixed(1), Icons.timer),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Commands', style: Theme.of(context).textTheme.titleMedium),
                    ),
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
                    const SizedBox(height: 24),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bluetooth_searching, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(status)),
                      if (isScanning) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _found.isEmpty
                        ? Center(
                            child: Text(
                              isScanning
                                  ? 'Scanning... (use a real phone, emulators don\'t support BLE)'
                                  : 'No devices found. Tap refresh.',
                            ),
                          )
                        : ListView.builder(
                            itemCount: _found.length,
                            itemBuilder: (context, i) {
                              final r = _found[i];
                              final name = r.advertisementData.advName.isNotEmpty
                                  ? r.advertisementData.advName
                                  : (r.device.platformName.isNotEmpty ? r.device.platformName : 'Unknown');
                              return Card(
                                child: ListTile(
                                  title: Text(name),
                                  subtitle: Text('${r.device.remoteId.str}  •  RSSI ${r.rssi}'),
                                  trailing: ElevatedButton(
                                    onPressed: isConnecting ? null : () async {
                                      try {
                                        await FlutterBluePlus.stopScan();
                                      } catch (_) {}
                                      setState(() => isScanning = false);
                                      _scanSub?.cancel(); _scanSub = null;
                                      await _connect(r.device);
                                    },
                                    child: const Text('Connect'),
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