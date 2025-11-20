// MadePlus SHOEML — split tabs: Dashboard, Graphs, Training, Tutorial
// Requires: flutter_reactive_ble, permission_handler, app_settings, fl_chart,
//           path_provider, intl, share_plus

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart'; // for debugPrint
import 'dart:ui' as ui;
import 'package:app_settings/app_settings.dart';



class TrainingRouteMap extends StatelessWidget { 
  final List<LatLng> points;
  final String distanceLabel;
  final double height;

  const TrainingRouteMap({
    super.key,
    required this.points,
    this.distanceLabel = '',
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    // empty route → simple card
    if (points.isEmpty) {
      return _wrap(Container(
        alignment: Alignment.center,
        child: const Text('No route yet'),
      ));
    }

    final bounds = LatLngBounds.fromPoints(points);

    return _wrap(
      Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(
                bounds: bounds,
                padding: const EdgeInsets.all(24),
                maxZoom: 18.0,
              ),
              interactionOptions:
                  const InteractionOptions(flags: InteractiveFlag.none),
              maxZoom: 19,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.smartshoe.shoeml',
              ),
              if (points.length > 1)
                PolylineLayer(polylines: [
                  Polyline(points: points, strokeWidth: 4),
                ]),
              MarkerLayer(markers: [
                Marker(
                  point: points.first, width: 28, height: 28,
                  child: const Icon(Icons.flag, color: Colors.green, size: 24),
                ),
                Marker(
                  point: points.last, width: 28, height: 28,
                  child: const Icon(Icons.place, color: Colors.red, size: 24),
                ),
              ]),
            ],
          ),
          if (distanceLabel.isNotEmpty)
            Positioned(
              right: 12, top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(distanceLabel, style: const TextStyle(color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _wrap(Widget child) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(height: height, width: double.infinity, child: child),
      );
}
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch framework errors (don’t let them kill the process)
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };

  // Catch all uncaught async/native-bridged Dart errors
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    // swallow so the process isn’t killed by uncaught Dart exceptions
    return true;
  };

  runZonedGuarded(
    () => runApp(const ShoeMLApp()),
    (e, st) { /* swallow */ },
  );
}

class ShoeMLApp extends StatefulWidget {
  const ShoeMLApp({super.key});
  @override
  State<ShoeMLApp> createState() => _ShoeMLAppState();
}

class _ShoeMLAppState extends State<ShoeMLApp> {
  Color _seed = const Color(0xFF00639A);
  ThemeMode _mode = ThemeMode.system;

  void _pickColor(BuildContext context) async {
    final presets = <Color>[
      const Color(0xFF00639A),
      const Color(0xFF00796B),
      const Color(0xFF7B1FA2),
      const Color(0xFF2E7D32),
      const Color(0xFFEF6C00),
      const Color(0xFFAD1457),
    ];
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Pick theme color"),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: presets
              .map((c) => InkWell(
                    onTap: () {
                      setState(() => _seed = c);
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black12),
                      ),
                    ),
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() => _mode = ThemeMode.light),
            child: const Text("Light"),
          ),
          TextButton(
            onPressed: () => setState(() => _mode = ThemeMode.dark),
            child: const Text("Dark"),
          ),
          TextButton(
            onPressed: () => setState(() => _mode = ThemeMode.system),
            child: const Text("System"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: _seed,
      brightness:
          _mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MADEPLUS SHOEML',
      theme: theme,
      darkTheme: theme.copyWith(brightness: Brightness.dark),
      themeMode: _mode,
      home: HomeShell(onPickColor: () => _pickColor(context)),
    );
  }
}

/// Bottom navigation shell with four tabs.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.onPickColor});
  final VoidCallback onPickColor;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  final ShoeBle _ble = ShoeBle();

  @override
  void initState() {
    super.initState();
    _ensurePerms();
  }

  Future<void> _ensurePerms() async {
    final req = [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.storage,
    ];
    await req.request();
	await _ble.reconnectLastIfAny();
  }

  @override
  void dispose() {
_ble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(ble: _ble),
      GraphsPage(ble: _ble),
      TrainingPage(ble: _ble),
      const TutorialPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              "assets/madeplus_logo.png",
              height: 28,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
            const SizedBox(width: 8),
            const Text("MADEPLUS SHOEML"),
          ],
        ),
        actions: [
          IconButton(
            tooltip: "Theme & color",
            onPressed: widget.onPickColor,
            icon: const Icon(Icons.palette_outlined),
          ),
          IconButton(
  tooltip: "Bluetooth settings",
  onPressed: () async {
    try {
      // Android: opens system Bluetooth settings
      // iOS: opens Settings (iOS does not allow deep-linking to Bluetooth)
      await AppSettings.openAppSettings(type: AppSettingsType.bluetooth);
    } catch (_) {
      // Fallback: at least open the general Settings screen
      await AppSettings.openAppSettings();
    }
  },
  icon: const Icon(Icons.bluetooth),
),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined), label: "Dashboard"),
          NavigationDestination(
              icon: Icon(Icons.show_chart), label: "Graphs"),
          NavigationDestination(
              icon: Icon(Icons.school_outlined), label: "Training"),
          NavigationDestination(
              icon: Icon(Icons.help_outline), label: "Tutorial"),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                                    BLE                                     */
/* -------------------------------------------------------------------------- */
// =============================== ShoeBle ===============================
class ShoeBle {
  // ---------------- Streams ----------------
  final _connState = StreamController<DeviceConnectionState>.broadcast();
  Stream<DeviceConnectionState> get connection$ => _connState.stream;

  final _rssi = StreamController<int?>.broadcast();         // nullable now
  Stream<int?> get rssi$ => _rssi.stream;

  final roll$    = StreamController<double>.broadcast();
  final pitch$   = StreamController<double>.broadcast();
  final yaw$     = StreamController<double>.broadcast();
  final steps$   = StreamController<int>.broadcast();
  final cadence$ = StreamController<double>.broadcast();
  final stride$  = StreamController<double>.broadcast();
  final dh$      = StreamController<double>.broadcast();

  // Temp
  final _tempCtrl = StreamController<double?>.broadcast();
  Stream<double?> get temp$ => _tempCtrl.stream;

  // ---------------- Core ----------------
  final _ble = FlutterReactiveBle();
  String? _deviceId;
  bool _shouldReconnect = false;  
  Timer? _reconnectTimer;       
  static const String _prefsKeyLastDeviceId = 'shoeml_last_device_id';
  


  // UUIDs (unchanged; use yours)
  final Uuid serviceUuid = Uuid.parse("0000feed-0000-1000-8000-00805f9b34fb");
  final Uuid rollUuid    = Uuid.parse("0000a001-0000-1000-8000-00805f9b34fb");
  final Uuid pitchUuid   = Uuid.parse("0000a002-0000-1000-8000-00805f9b34fb");
  final Uuid yawUuid     = Uuid.parse("0000a003-0000-1000-8000-00805f9b34fb");
  final Uuid tempUuid    = Uuid.parse("0000b001-0000-1000-8000-00805f9b34fb");
  final Uuid stepsUuid   = Uuid.parse("0000c001-0000-1000-8000-00805f9b34fb");
  final Uuid cadenceUuid = Uuid.parse("0000c002-0000-1000-8000-00805f9b34fb");
  final Uuid strideUuid  = Uuid.parse("0000c003-0000-1000-8000-00805f9b34fb");
  final Uuid altdhUuid   = Uuid.parse("0000c004-0000-1000-8000-00805f9b34fb");

  // Subs
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _sRoll, _sPitch, _sYaw, _sTemp, _sSteps, _sCad, _sStride, _sDh;

  // RSSI timer
  Timer? _rssiTimer;

  // ------------- Scan (unchanged) -------------
  Future<DiscoveredDevice?> scanOnce({Duration timeout = const Duration(seconds: 6)}) async {
    DiscoveredDevice? found;
    final sub = _ble.scanForDevices(withServices: [serviceUuid]).listen((d) {
      found ??= d;
    }, onError: (_) {});
    await Future.delayed(timeout);
    await sub.cancel();
    return found;
  }

  // ------------- Connect -------------
 Future<void> connect(String id) async {
    await disconnect();
    _shouldReconnect = true;  // Enable auto-reconnect
    _deviceId = id;
	await _saveLastDeviceId(id);
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

  Future<void> disconnect() async {
  _shouldReconnect = false;  // Disable auto-reconnect
  _reconnectTimer?.cancel();
  _stopRssi();
  await _unsubscribeAll();
  try { await _connSub?.cancel(); } catch (_) {}
  _connSub = null;
  _deviceId = null;

  // 🔴 NEW: explicitly notify listeners that we are now disconnected
  if (!_connState.isClosed) {
    _connState.add(DeviceConnectionState.disconnected);
  }
  await _clearLastDeviceId();
}
Future<void> _saveLastDeviceId(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyLastDeviceId, id);
    } catch (_) {}
  }

  Future<void> _clearLastDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKeyLastDeviceId);
    } catch (_) {}
  }

  Future<void> reconnectLastIfAny() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_prefsKeyLastDeviceId);
      if (id == null) return;

      // Start auto-reconnect loop with the remembered device
      _shouldReconnect = true;
      _deviceId = id;
      await _attemptConnection(id);
    } catch (_) {}
  }

 void dispose() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    disconnect();
    try { _connState.close(); } catch (_) {}
    try { _rssi.close(); } catch (_) {}
    try { roll$.close(); } catch (_) {}
    try { pitch$.close(); } catch (_) {}
    try { yaw$.close(); } catch (_) {}
    try { steps$.close(); } catch (_) {}
    try { cadence$.close(); } catch (_) {}
    try { stride$.close(); } catch (_) {}
    try { dh$.close(); } catch (_) {}
    try { _tempCtrl.close(); } catch (_) {}
  }

  // ------------- Notify subscriptions -------------
  Future<void> _subscribeAll() async {
    if (_deviceId == null) return;
    final id = _deviceId!;
    Future<StreamSubscription<List<int>>> sub(
      Uuid c, void Function(List<int>) onData) async {
      final q = QualifiedCharacteristic(deviceId: id, serviceId: serviceUuid, characteristicId: c);
      return _ble.subscribeToCharacteristic(q).listen(onData, onError: (_) {});
    }

    _sRoll   = await sub(rollUuid,   (b) => roll$.add(_f32(b)));
    _sPitch  = await sub(pitchUuid,  (b) => pitch$.add(_f32(b)));
    _sYaw    = await sub(yawUuid,    (b) => yaw$.add(_f32(b)));
    _sTemp   = await sub(tempUuid,   (b) => _tempCtrl.add(_f32Nullable(b)));
    _sSteps  = await sub(stepsUuid,  (b) => steps$.add(_i32(b)));
    _sCad    = await sub(cadenceUuid,(b) => cadence$.add(_f32(b)));
    _sStride = await sub(strideUuid, (b) => stride$.add(_f32(b)));
    _sDh     = await sub(altdhUuid,  (b) => dh$.add(_f32(b)));
  }

  Future<void> _unsubscribeAll() async {
    for (final s in [_sRoll, _sPitch, _sYaw, _sTemp, _sSteps, _sCad, _sStride, _sDh]) {
      try { await s?.cancel(); } catch (_) {}
    }
    _sRoll = _sPitch = _sYaw = _sTemp = _sSteps = _sCad = _sStride = _sDh = null;
  }

  // ------------- RSSI helpers -------------
  Future<void> _readRssiOnce() async {
    final id = _deviceId;
    if (id == null) return;
    try {
      final v = await _ble.readRssi(id);                     // requires connected
      // debug:
      // ignore: avoid_print
      print("[RSSI] immediate read: $v");
      if (!_rssi.isClosed) _rssi.add(v);
    } catch (e) {
      // ignore: avoid_print
      print("[RSSI] immediate read failed: $e");
      if (!_rssi.isClosed) _rssi.add(null);
    }
  }

  void _startRssi() {
    _stopRssi();
    _rssiTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final id = _deviceId;
      if (id == null) return;
      try {
        final v = await _ble.readRssi(id);
        // ignore: avoid_print
        print("[RSSI] tick: $v");
        if (!_rssi.isClosed) _rssi.add(v);
      } catch (e) {
        // ignore: avoid_print
        print("[RSSI] tick failed: $e");
        if (!_rssi.isClosed) _rssi.add(null);
      }
    });
  }

  void _stopRssi() {
    try { _rssiTimer?.cancel(); } catch (_) {}
    _rssiTimer = null;
    if (!_rssi.isClosed) _rssi.add(null);
  }
}
  

// ---------- payload helpers (unchanged) ----------
double _f32(List<int> b) {
  if (b.length < 4) return 0.0;
  final bb = ByteData.sublistView(Uint8List.fromList(b));
  final val = bb.getFloat32(0, Endian.little);
  // Filter out invalid values
  if (val.isNaN || val.isInfinite) return 0.0;
  return val;
}

double? _f32Nullable(List<int> b) {
  if (b.length < 4) return null;
  final v = _f32(b);
  // _f32 already filters NaN/Infinity, but double-check
  if (v == 0.0) return null;  // Treat 0.0 as null for nullable values
  return v;
}

int _i32(List<int> b) {
  if (b.length < 4) return 0;
  final bb = ByteData.sublistView(Uint8List.fromList(b));
  return bb.getInt32(0, Endian.little);
}


/* -------------------------------------------------------------------------- */
/*                                 DASHBOARD                                  */
/* -------------------------------------------------------------------------- */
// --- chart state (scoped to this file) ---
double _t = 0.0;                 // simple time counter for R/P/Y charts
DateTime? _t0;                   // wall-clock base for temperature series

final List<FlSpot> _r = [];      // roll series
final List<FlSpot> _p = [];      // pitch series
final List<FlSpot> _y = [];      // yaw series
final List<FlSpot> _temp = [];   // temperature series

StreamSubscription<double>? _sr, _sp, _sy;     // roll/pitch/yaw subs
StreamSubscription<double?>? _sTemp;           // temperature sub

void _push(List<FlSpot> series, double t, double v) {
  // CRITICAL: Filter invalid values
  if (v.isNaN || v.isInfinite || t.isNaN || t.isInfinite) return;
  series.add(FlSpot(t, v));
  if (series.length > 600) series.removeAt(0);
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.ble});
  final ShoeBle ble;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String? _id;
  double roll = 0, pitch = 0, yaw = 0, cadence = 0, stride = 0, dh = 0;
  double? tempC;
  int steps = 0;int? rssi ;
  DeviceConnectionState conn = DeviceConnectionState.disconnected;

  StreamSubscription? _s1, _s2, _s3, _s4, _s5, _s6, _s7, _s8, _s9, _s10;

  @override
  void initState() {
    super.initState();

    // Bind metric streams (connection, steps, cadence, etc.)
    _bind();
    // Plot streams for charts with validation
  _sr = widget.ble.roll$.stream.listen((v) {
    if (!mounted || v.isNaN || v.isInfinite) return;  // ADD VALIDATION
    setState(() {
      _t += 0.1;
      _push(_r, _t, v);
    });
  });

  _sp = widget.ble.pitch$.stream.listen((v) {
    if (!mounted || v.isNaN || v.isInfinite) return;  // ADD VALIDATION
    setState(() {
      _t += 0.1;
      _push(_p, _t, v);
    });
  });

  _sy = widget.ble.yaw$.stream.listen((v) {
    if (!mounted || v.isNaN || v.isInfinite) return;  // ADD VALIDATION
    setState(() {
      _t += 0.1;
      _push(_y, _t, v);
    });
  });

  _t0 ??= DateTime.now();
  _sTemp = widget.ble.temp$.listen((v) {
    if (v == null || !mounted || v.isNaN || v.isInfinite) return;  // ADD VALIDATION
    final t = DateTime.now().difference(_t0!).inMilliseconds / 1000.0;
    _push(_temp, t, v);
    setState(() => tempC = v);
  });
    
  }

  void _bind() {
    _s1  = widget.ble.connection$.listen((c) => setState(() => conn = c));
    _s2  = widget.ble.roll$.stream.listen((v)   => setState(() => roll   = v));
    _s3  = widget.ble.pitch$.stream.listen((v)  => setState(() => pitch  = v));
    _s4  = widget.ble.yaw$.stream.listen((v)    => setState(() => yaw    = v));
    _s5  = widget.ble.temp$.listen((v)          => setState(() => tempC  = v));
    _s6  = widget.ble.steps$.stream.listen((v)  => setState(() => steps  = v));
    _s7  = widget.ble.cadence$.stream.listen((v)=> setState(() => cadence= v));
    _s8  = widget.ble.stride$.stream.listen((v) => setState(() => stride = v));
    _s9  = widget.ble.dh$.stream.listen((v)     => setState(() => dh     = v));
    _s10 = widget.ble.rssi$.listen((v)          => setState(() => rssi   = v));
  }

  @override
  void dispose() {
    for (final s in [_s1, _s2, _s3, _s4, _s5, _s6, _s7, _s8, _s9, _s10]) {
      try { s?.cancel(); } catch (_) {}
    }
    try { _sr?.cancel(); } catch (_) {}
    try { _sp?.cancel(); } catch (_) {}
    try { _sy?.cancel(); } catch (_) {}
    try { _sTemp?.cancel(); } catch (_) {}
    super.dispose();
  }

  String _connLabel(DeviceConnectionState s) {
    switch (s) {
      case DeviceConnectionState.connecting:    return "Connecting...";
      case DeviceConnectionState.connected:     return "Connected";
      case DeviceConnectionState.disconnecting: return "Disconnecting...";
      case DeviceConnectionState.disconnected:  return "Disconnected";
    }
  }

  Future<void> _scanAndConnect() async {
    final d = await widget.ble.scanOnce();
    if (!mounted) return;
    if (d == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No device advertising the service.")),
      );
      return;
    }
    setState(() => _id = d.id);
    await widget.ble.connect(d.id);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.bluetooth),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _connLabel(conn),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              _id == null ? "Not connected" : _id!,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Use Wrap to prevent horizontal overflow on small screens
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        label: Text(
                          "RSSI ${rssi ?? '—'} dBm",
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                        ),
                        avatar: const Icon(Icons.network_cell, size: 16),
                      ),
                      ElevatedButton.icon(
                        onPressed: _scanAndConnect,
                        icon: const Icon(Icons.search),
                        label: const Text("Scan & Connect"),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => widget.ble.disconnect(),
                        icon: const Icon(Icons.link_off),
                        label: const Text("Disconnect"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metric(cs, "Roll (°)", roll.toStringAsFixed(1), Icons.rotate_90_degrees_ccw),
              _metric(cs, "Pitch (°)", pitch.toStringAsFixed(1), Icons.rotate_90_degrees_cw),
              _metric(cs, "Yaw (°)", yaw.toStringAsFixed(1), Icons.refresh),
              _metric(cs, "Temp (°C)", tempC?.toStringAsFixed(1) ?? "—", Icons.thermostat),
              _metric(cs, "Steps", steps.toString(), Icons.directions_walk),
              _metric(cs, "Cadence", "${cadence.toStringAsFixed(1)} spm", Icons.speed),
              _metric(cs, "Stride", "${stride.toStringAsFixed(2)} m", Icons.straighten),
              _metric(cs, "Elevation Δh", "${dh.toStringAsFixed(2)} m", Icons.landscape),
            ],
          ),
          const SizedBox(height: 16),
          _info(cs, "MADEPLUS", "Smart shoe analytics & on-device training."),
        ],
      ),
    );
  }

  Widget _metric(ColorScheme cs, String title, String value, IconData icon) {
    return SizedBox(
      width: 240,
      child: Card(
        color: cs.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(value,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _info(ColorScheme cs, String title, String body) {
    return Card(
      color: cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(body),
            ]),
      ),
    );
  }
}

//
/* -------------------------------------------------------------------------- */
/*                                   GRAPHS                                   */
/* -------------------------------------------------------------------------- */

class GraphsPage extends StatefulWidget {
  const GraphsPage({super.key, required this.ble});
  final ShoeBle ble;

  @override
  State<GraphsPage> createState() => _GraphsPageState();
}

class _GraphsPageState extends State<GraphsPage> {
  final List<FlSpot> _r = [], _p = [], _y = [];
  //final List<FlSpot> _stance = [], _swing = [];
         StreamSubscription<double?>? _sTemp;
         DateTime? _t0;
         final List<FlSpot> _temp = [];

  double _t = 0;

  StreamSubscription? _sr, _sp, _sy, _scad;

void _push(List<FlSpot> s, double t, double v, {int keep = 300}) {
  // CRITICAL: Filter invalid values
  if (v.isNaN || v.isInfinite || t.isNaN || t.isInfinite) return;
  s.add(FlSpot(t, v));
  if (s.length > keep) s.removeAt(0);
}

  @override
  void initState() {
  super.initState();
  _sr = widget.ble.roll$.stream.listen((v) {
    if (v.isNaN || v.isInfinite) return;  // ADD VALIDATION
    setState(() {
      _t += 0.1;
      _push(_r, _t, v);
    });
  });
  
  _sp = widget.ble.pitch$.stream.listen((v) {
    if (v.isNaN || v.isInfinite) return;  // ADD VALIDATION
    setState(() {
      _t += 0.1;
      _push(_p, _t, v);
    });
  });
  
  _sy = widget.ble.yaw$.stream.listen((v) {
    if (v.isNaN || v.isInfinite) return;  // ADD VALIDATION
    setState(() {
      _t += 0.1;
      _push(_y, _t, v);
    });
  });
  
  _t0 ??= DateTime.now();
  _sTemp = widget.ble.temp$.listen((v) {
    if (v == null || v.isNaN || v.isInfinite) return;  // ADD VALIDATION
    final t = DateTime.now().difference(_t0!).inMilliseconds / 1000.0;
    _push(_temp, t, v);
    if (mounted) setState(() {});
  });
}

  @override
  void dispose() {
for (final s in [_sr, _sp, _sy, _sTemp]) {
         try { s?.cancel(); } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          _lineCard(cs, "Roll (°)", _r),
          _lineCard(cs, "Pitch (°)", _p),
          _lineCard(cs, "Yaw (°)", _y),
		  _lineCard(cs, "Temp (°C)", _temp),
         // _lineCard(cs, "Gait: Stance (fraction)", _stance, minY: 0, maxY: 1),
         // _lineCard(cs, "Gait: Swing (fraction)", _swing, minY: 0, maxY: 1),
        ],
      ),
    );
  }

 Widget _lineCard(ColorScheme cs, String title, List<FlSpot> pts,
    {double? minY, double? maxY}) {
  // Compute numeric summary so user can read values
  double? current;
  double? minVal;
  double? maxVal;
  if (pts.isNotEmpty) {
    current = pts.last.y;
    minVal = pts.map((p) => p.y).reduce(math.min);
    maxVal = pts.map((p) => p.y).reduce(math.max);
  }

  return Card(
    color: cs.surfaceContainerHigh,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + current value
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (current != null)
                Text(
                  'Now: ${current.toStringAsFixed(1)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(0.7),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Chart
          SizedBox(
            height: 180,
            width: double.infinity,
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                gridData: const FlGridData(show: true),
                // keep axes hidden to avoid overlap
                titlesData: const FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: true),
                lineBarsData: [
                  LineChartBarData(
                    spots: pts,
                    isCurved: true,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),

          // Min–max range under the chart
          if (minVal != null && maxVal != null) ...[
            const SizedBox(height: 4),
            Text(
              'Range: ${minVal.toStringAsFixed(1)} – ${maxVal.toStringAsFixed(1)}',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}


}

/* -------------------------------------------------------------------------- */
/*                                  TRAINING                                  */
/* -------------------------------------------------------------------------- */

class TrainingPage extends StatefulWidget {
  const TrainingPage({super.key, required this.ble});
  final ShoeBle ble;

  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  final _labels = [
    "walking",
    "running",
    "stairs_up",
    "stairs_down",
    "standing",
    "sitting"
  ];
  String _label = "walking";
  final _modelNameCtrl = TextEditingController();

  bool _collecting = false;
 DeviceConnectionState _conn = DeviceConnectionState.disconnected;
  StreamSubscription<DeviceConnectionState>? _connSub;
  
  // Map & route tracking
  final MapController _mapController = MapController();
  final GlobalKey _mapKey = GlobalKey();
  List<LatLng> _track = [];
  List<DateTime> _trackTs = [];
  StreamSubscription<Position>? _posSub;
  DateTime? _tStart;
  double _lastDistM = 0;
  Duration _lastDur = Duration.zero;
// raw samples buffer for CSV/windows
  final List<_RawSample> _buffer = [];
  StreamSubscription? _sr, _sp, _sy, _st, _sc, _ss, _sdh;

  @override
   @override
  void initState() {
    super.initState();
    _bind();

    // 🔴 Watch BLE connection state
    _connSub = widget.ble.connection$.listen((c) {
      if (!mounted) return;
      setState(() {
        _conn = c;

        // Optional: if connection drops while collecting, auto-stop & discard
        if (_collecting && c != DeviceConnectionState.connected) {
          _collecting = false;
          _stopLocation();
          _buffer.clear();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Training stopped: sensor disconnected.'),
            ),
          );
        }
      });
    });
  }


  @override
   @override
   void dispose() {
    for (final s in [_sr, _sp, _sy, _st, _sc, _ss, _sdh]) {
      try { s?.cancel(); } catch (_) {}
    }
    try { _posSub?.cancel(); } catch (_) {}
    try { _connSub?.cancel(); } catch (_) {}
    _modelNameCtrl.dispose();
    super.dispose();
  }

  void _bind() {
    double t = 0;
    _sr = widget.ble.roll$.stream.listen((v) {
      t += 0.1;
      _buffer.add(_RawSample(t, v, null, null, null, null, null, null));
    });
    _sp = widget.ble.pitch$.stream.listen((v) {
      if (_buffer.isNotEmpty) _buffer.last.pitch = v;
    });
    _sy = widget.ble.yaw$.stream.listen((v) {
      if (_buffer.isNotEmpty) _buffer.last.yaw = v;
    });
    _st = widget.ble.temp$.listen((v) {
      if (_buffer.isNotEmpty) _buffer.last.tempC = v;
    });
    _sc = widget.ble.cadence$.stream.listen((v) {
      if (_buffer.isNotEmpty) _buffer.last.cadence = v;
    });
    _ss = widget.ble.stride$.stream.listen((v) {
      if (_buffer.isNotEmpty) _buffer.last.strideM = v;
    });
    _sdh = widget.ble.dh$.stream.listen((v) {
      if (_buffer.isNotEmpty) _buffer.last.dH = v;
    });
  }

  Future<Directory> _appDir() async {
    final d = await getApplicationDocumentsDirectory();
    final dir = Directory("${d.path}/shoeml");
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<Directory> _ensureDir(Directory base, String child) async {
    final d = Directory("${base.path}/$child");
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Future<File?> _saveCsv() async {
    final dir = await _ensureDir(await _appDir(), "sessions");
    final stamp = DateFormat("yyMMdd_HHmmss").format(DateTime.now());
    final file = File("${dir.path}/${_label}_$stamp.csv");

    const header = "t,roll,pitch,yaw,tempC,cadence,strideM,deltaH,label\n";
    final meta1 = '# distance_m=${_lastDistM.toStringAsFixed(1)}\n';
    final meta2 = '# duration_s=${_lastDur.inSeconds}\n';
    final meta3 = '# pace=${_formatPace(_lastDistM, _lastDur)}\n';
    final sb = StringBuffer(meta1 + meta2 + meta3 + header);
       for (final s in _buffer) {
           sb.write("${s.t.toStringAsFixed(3)},"
         "${s.roll?.toStringAsFixed(3) ?? ""},"
         "${s.pitch?.toStringAsFixed(3) ?? ""},"
         "${s.yaw?.toStringAsFixed(3) ?? ""},"
         "${s.tempC?.toStringAsFixed(2) ?? ""},"
         "${s.cadence?.toStringAsFixed(1) ?? ""},"
         "${s.strideM?.toStringAsFixed(3) ?? ""},"
         "${s.dH?.toStringAsFixed(3) ?? ""},"
         "$_label\n");
         }

    await file.writeAsString(sb.toString(), flush: true);
    if (!mounted) return null;ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Saved: ${file.path.split('/').last}")),
    );
  
    return file;
}

Future<void> _toggleCollect() async {
  // 🔴 If we are about to START collecting, require BLE connection
  if (!_collecting && _conn != DeviceConnectionState.connected) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please connect to the shoe before starting training.'),
      ),
    );
    return;
  }

  setState(() => _collecting = !_collecting);

  if (_collecting) {
    // START: clear buffers + reset route + start GPS
    _buffer.clear();
    _track = [];
    _trackTs = [];
    _tStart = DateTime.now();
    await _startLocation();
  } else {
    // STOP: stop GPS and compute stats
    await _stopLocation();
    _lastDistM = _computeDistanceMeters();
    _lastDur   = _tStart != null
        ? DateTime.now().difference(_tStart!)
        : Duration.zero;

    await _fitRoute();
    final f = await _saveCsv();
    if (f != null) {
      final png = await _captureMapPng(f);
      final geo = await _saveGeoJson(f);
      final gpx = await _saveGpx(f);
      final kml = await _saveKml(f);
      await _showSummarySheet(f, png, geo, gpx, kml);
    }
  }
}



  Future<void> _trainAndSave() async {
    // windows + features
    final wins = _windows(_buffer, winSec: 3.0, hopSec: 1.5);
    if (wins.isEmpty) {
      if (!mounted) return;ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No data to train.")));
      return;
    }
    final feats = wins.map(_features).toList();
    final labels =
        List<int>.filled(feats.length, _labels.indexOf(_label));

    // split 80/20
    final n = feats.length;
    final m = (n * 0.8).floor().clamp(1, n - 1);
    final Xtr = feats.take(m).toList();
    final ytr = labels.take(m).toList();
    final Xte = feats.skip(m).toList();
    final yte = labels.skip(m).toList();

    final clf = SoftmaxClassifier()
      ..init(numClasses: _labels.length, inDim: Xtr.first.length)
      ..fit(Xtr, ytr, epochs: 50, lr: 0.05, l2: 1e-4, batch: 64);

    final acc = clf.accuracy(Xte, yte);

    // save model JSON
    final dir = await _ensureDir(await _appDir(), "models");
    final stamp = DateFormat("yyMMdd_HHmmss").format(DateTime.now());
    final baseName = _modelNameCtrl.text.trim().isEmpty
        ? _label
        : _modelNameCtrl.text.trim();
    final name = "${baseName}_$stamp.json";
    final f = File("${dir.path}/$name");
    await f.writeAsString(jsonEncode({
      "labels": _labels,
      "W": clf.W,
      "b": clf.b,
    }));

    if (!mounted) return;ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            "Trained acc ${(acc * 100).toStringAsFixed(1)}% • Saved $name")));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
	final bool canStart = (_conn == DeviceConnectionState.connected);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Collect samples", style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  const Text("Pick a label, Start/Stop capture, CSV auto-saves on stop."),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButton<String>(
                          value: _label,
                          items: _labels
                              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (v) => setState(() => _label = v ?? _label),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                            onPressed: _collecting
                            ? _toggleCollect                      // always allow Stop
                            : (canStart ? _toggleCollect : null), // disable Start when not connected
                            icon: Icon(_collecting ? Icons.stop : Icons.fiber_manual_record),
                            label: Text(_collecting ? "Stop & Save CSV" : "Start"),
                           ),

                    ],
                  )
                ],
              ),
            ),
          ),
const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Route (start → end)", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 220,
                    child: RepaintBoundary(
                      key: _mapKey,
                      child: Stack(
                        children: [
                          Builder(
                            builder: (context) {
                              try {
                                final validTrack = _validTrack;
                                
                                if (validTrack.isEmpty) {
                                  return Container(
                                    color: Colors.grey[200],
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.location_searching, 
                                               size: 48, color: Colors.grey[400]),
                                          const SizedBox(height: 8),
                                          Text('Waiting for GPS...', 
                                               style: TextStyle(color: Colors.grey[600])),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                                
                                return FlutterMap(
								
                                  mapController: _mapController,
                                  options: MapOptions(
                                    initialZoom: 16,
                                    initialCenter: validTrack.last,
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      userAgentPackageName: 'com.madeplus.shoeml',
                                    ),
                                    if (validTrack.length > 1)
                                      PolylineLayer(polylines: [
                                        Polyline(points: validTrack, strokeWidth: 4)
                                      ]),
                                    if (validTrack.isNotEmpty)
                                      MarkerLayer(markers: [
                                        Marker(
                                          width: 30, height: 30, 
                                          point: validTrack.first, 
                                          child: const Icon(Icons.flag, color: Colors.green)
                                        ),
                                        Marker(
                                          width: 30, height: 30, 
                                          point: validTrack.last, 
                                          child: const Icon(Icons.place, color: Colors.red)
                                        ),
                                      ]),
                                  ],
                                );
                              } catch (e) {
                                return Container(
                                  color: Colors.grey[200],
                                  child: Center(
                                    child: Text('Map error', 
                                         style: TextStyle(color: Colors.grey[600])),
                                  ),
                                );
                              }
                            },
                          ),
                          Positioned(
                            right: 8, top: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black54, 
                                borderRadius: BorderRadius.circular(16)
                              ),
                              child: Text(
                                'Dist: ${_formatDistance(_computeDistanceMeters())}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12), 
          Card(
            color: cs.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Train & Save Model",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _modelNameCtrl,
                      decoration: const InputDecoration(
                        labelText: "Model name (optional)",
                        hintText: "e.g. walking_outdoor",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                        "Windows: 3s / hop 1.5s • Features: mean/var/RMS + cadence/stride/temp"),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _trainAndSave,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text("Train & Save"),
                    ),
                  ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text("Share last CSV"),
              subtitle: const Text(
                  "Open Files → Android/data/<pkg>/files/shoeml/sessions"),
              trailing: IconButton(
                icon: const Icon(Icons.share),
                onPressed: () async {
                  final dir =
                      await _ensureDir(await _appDir(), "sessions");
                  final files = dir
                      .listSync()
                      .whereType<File>()
                      .where((f) => f.path.endsWith(".csv"))
                      .toList()
                    ..sort((a, b) => b
                        .lastModifiedSync()
                        .compareTo(a.lastModifiedSync()));
                  if (files.isEmpty) return;
                  await Share.shareXFiles([XFile(files.first.path)]);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Return windows of samples, not a flattened list.
  List<List<_RawSample>> _windows(List<_RawSample> buf,
      {double winSec = 3.0, double hopSec = 1.5}) {
    if (buf.length < 2) return [];
    final dt = (buf.last.t - buf.first.t) / (buf.length - 1);
    final win = (winSec / dt).round().clamp(1, buf.length);
    final hop = (hopSec / dt).round().clamp(1, buf.length);
    final out = <List<_RawSample>>[];
    for (int i = 0; i + win <= buf.length; i += hop) {
      out.add(buf.sublist(i, i + win));
    }
    return out;
  }

  List<double> _features(List<_RawSample> w) {
    List<double> col(List<double?> v) {
      final r = v.whereType<double>().toList();
      return r.isEmpty ? [0] : r;
    }

    final roll = col(w.map((e) => e.roll).toList());
    final pitch = col(w.map((e) => e.pitch).toList());
    final yaw = col(w.map((e) => e.yaw).toList());
    final cadence = col(w.map((e) => e.cadence).toList());
    final stride = col(w.map((e) => e.strideM).toList());
    final temp = col(w.map((e) => e.tempC).toList());

    List<double> stats(List<double> x) {
      final n = x.length;
      final mean = x.reduce((a, b) => a + b) / n;
      final varr = x
              .map((v) => (v - mean) * (v - mean))
              .reduce((a, b) => a + b) /
          n;
      final rms =
          math.sqrt(x.map((v) => v * v).reduce((a, b) => a + b) / n);
      return [mean, varr, rms];
    }

    final out = <double>[];
    out.addAll(stats(roll));
    out.addAll(stats(pitch));
    out.addAll(stats(yaw));
    out.addAll(stats(cadence));
    out.addAll(stats(stride));
    out.addAll(stats(temp));
    return out;
  }

  Future<bool> _ensureLocationPermission() async {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied')),
        );
      }
      return false;
    }
    return true;
  }

 Future<void> _startLocation() async {
  if (!await _ensureLocationPermission()) return;
  _tStart = DateTime.now();

  try {
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );

    // Defensive: ignore any bogus reading
    if (!pos.latitude.isFinite || !pos.longitude.isFinite) {
      return;
    }

    setState(() {
      _track = [LatLng(pos.latitude, pos.longitude)];
      _trackTs = [DateTime.now()];
    });
  } catch (_) {
    // ignore; user will just see no route
  }

  await _posSub?.cancel();
  _posSub = Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 3,
    ),
  ).listen((pos) {
    if (!pos.latitude.isFinite || !pos.longitude.isFinite) return;
    setState(() {
      _track.add(LatLng(pos.latitude, pos.longitude));
      _trackTs.add(DateTime.now());
    });
  });
}


  Future<void> _stopLocation() async {
    await _posSub?.cancel();
    _posSub = null;
  }

double _computeDistanceMeters() {
  // Drop any bogus points first
  final clean = _track
      .where((p) => p.latitude.isFinite && p.longitude.isFinite)
      .toList();

  if (clean.length < 2) return 0.0;

  const Distance d = Distance();
  double sum = 0;
  for (int i = 1; i < clean.length; i++) {
    sum += d.as(LengthUnit.Meter, clean[i - 1], clean[i]);
  }

  if (!sum.isFinite) return 0.0;
  return sum;
}


  String _formatDistance(double meters) {
    return meters >= 1000
        ? '${(meters / 1000).toStringAsFixed(2)} km'
        : '${meters.toStringAsFixed(0)} m';
  }

  String _formatDuration(Duration dur) {
    final h = dur.inHours;
    final m = dur.inMinutes.remainder(60);
    final s = dur.inSeconds.remainder(60);
    return h > 0
        ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatPace(double meters, Duration dur) {
  // Guard against nonsense values
  if (!meters.isFinite || meters <= 0 || dur.inSeconds <= 0) {
    return '—';
  }

  final km = meters / 1000.0;
  if (!km.isFinite || km <= 0) return '—';

  final secPerKm = dur.inSeconds / km;
  if (!secPerKm.isFinite || secPerKm <= 0) return '—';

  // Work in integer seconds to avoid NaN/Infinity -> toInt issues
  final totalSec = secPerKm.round(); // int
  final m = totalSec ~/ 60;
  final s = totalSec % 60;

  return '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')} / km';
}

Future<void> _fitRoute() async {
  final validTrack = _validTrack;
  if (validTrack.length < 2) return;

  try {
    final bounds = _boundsFromTrack(validTrack);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(24),
      ),
    );
    await Future.delayed(const Duration(milliseconds: 300));
  } catch (e) {
    debugPrint("[Map] fitRoute error: $e");
  }
}
  Future<File?> _saveGeoJson(File csvFile) async {
    try {
      final validTrack = _validTrack;
	  if (_track.isEmpty) return null;
      final dir = csvFile.parent;
      final name = csvFile.uri.pathSegments.last.replaceAll('.csv', '.geojson');
      final coords = _track.map((p) => [p.longitude, p.latitude]).toList();
        // PATCH: temp stats for GeoJSON
  final temps = _buffer.map((s) => s.tempC).whereType<double>().toList();
  final tempAvg = temps.isEmpty ? null : (temps.reduce((a,b)=>a+b) / temps.length);
  final tempMin = temps.isEmpty ? null : temps.reduce((a,b)=>a<b?a:b);
  final tempMax = temps.isEmpty ? null : temps.reduce((a,b)=>a>b?a:b);
final fc = {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "properties": {
              "label": _label,
              "distance_m": _lastDistM,
              "duration_s": _lastDur.inSeconds,
               "avg_pace_min_per_km": (_lastDistM > 0)
                   ? (_lastDur.inSeconds / (_lastDistM / 1000.0)) / 60.0
                   : null,
             "tempC_avg": tempAvg,
             "tempC_min": tempMin,
             "tempC_max": tempMax
                },
            "geometry": {"type": "LineString", "coordinates": coords}
          }
        ]
      };
      final f = File('${dir.path}/$name');
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert(fc));
      return f;
    } catch (_) {
      return null;
    }
  }

  Future<File?> _saveGpx(File csvFile) async {
    try {
      if (_track.isEmpty) return null;
      final dir = csvFile.parent;
      final name = csvFile.uri.pathSegments.last.replaceAll('.csv', '.gpx');
      final b = StringBuffer();
      b.writeln('<?xml version="1.0" encoding="UTF-8"?>');
      b.writeln('<gpx version="1.1" creator="ShoeML" xmlns="http://www.topografix.com/GPX/1/1">');
      b.writeln('  <trk>');
      b.writeln('    <name>${_label}</name>');
      b.writeln('    <trkseg>');
      for (int i = 0; i < _track.length; i++) {
        final p = _track[i];
        final t = (i < _trackTs.length)
            ? _trackTs[i].toUtc().toIso8601String()
            : DateTime.now().toUtc().toIso8601String();
        b.writeln('      <trkpt lat="${p.latitude}" lon="${p.longitude}"><time>${t}Z</time></trkpt>');
      }
      b.writeln('    </trkseg>');
      b.writeln('  </trk>');
      b.writeln('</gpx>');
      final f = File('${dir.path}/$name');
      await f.writeAsString(b.toString());
      return f;
    } catch (_) {
      return null;
    }
  }

Future<File?> _saveKml(File csvFile) async {
  try {
    if (_track.isEmpty) return null;
    final dir = await _ensureDir(await _appDir(), "ShoeML/kml");
    final stamp = DateTime.now().toIso8601String().replaceAll(":", "-");
    final name = "track_${_label != null ? _label!.replaceAll(RegExp(r'\W+'), '_') : 'session'}_$stamp.kml";
    final f = File("\${dir.path}/\$name");
    final b = StringBuffer();
    b.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    b.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
    b.writeln('  <Document>');
    b.writeln('    <name>' + (_label ?? 'session') + '</name>');
    b.writeln('    <Placemark>');
    b.writeln('      <name>Route</name>');
    b.writeln('      <LineString>');
    b.writeln('        <tessellate>1</tessellate>');
    b.writeln('        <coordinates>');
    for (int i = 0; i < _track.length; i++) {
      final p = _track[i];
      final t = (i < _trackTs.length) ? _trackTs[i].toUtc().toIso8601String() : DateTime.now().toUtc().toIso8601String();
      b.writeln('          \${p.longitude},\${p.latitude},0 <!-- \${t} -->');
    }
    b.writeln('        </coordinates>');
    b.writeln('      </LineString>');
    b.writeln('    </Placemark>');
    b.writeln('  </Document>');
    b.writeln('</kml>');
    await f.writeAsString(b.toString());
    return f;
  } catch (_) {
    return null;
  }
}



  Future<File?> _captureMapPng(File csvFile) async {
    try {
      final ctx = _mapKey.currentContext;
      if (ctx == null) return null;
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final ui.Image image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      final dir = csvFile.parent;
      final name = csvFile.uri.pathSegments.last.replaceAll('.csv', '_map.png');
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(byteData.buffer.asUint8List());
      return f;
    } catch (_) {
      return null;
    }
  }

  Future<void> _showSummarySheet(File f, File? png, File? geo, File? gpx, File? kml) async {
    final distTxt = _formatDistance(_lastDistM);
    final durTxt  = _formatDuration(_lastDur);
    final paceTxt = _formatPace(_lastDistM, _lastDur);
    if (!mounted) return;await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Wrap(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Training Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(ctx).pop()),
                ],
              ),
              const SizedBox(height: 8),
              Text('Distance: $distTxt', style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 6),
              Text('Duration: $durTxt',  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 6),
              Text('Avg pace: $paceTxt', style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 12),
SizedBox(
  height: 220,
  child: buildSummaryRouteMap(_track),
),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  final msg = 'Training: $distTxt, $durTxt ($paceTxt)';
                  final files = <XFile>[XFile(f.path)];
                  if (geo != null) files.add(XFile(geo.path));
                  if (gpx != null) files.add(XFile(gpx.path));
                  if (kml != null) files.add(XFile(kml.path));
                  if (png != null) files.add(XFile(png.path));
                  await Share.shareXFiles(files, text: msg);
                },
                icon: const Icon(Icons.share),
                label: const Text('Share summary'),
              ),
            ],
          ),
        );
      },
    );
  }
Widget buildSummaryRouteMap(List<LatLng> track) {
  // Clean out any NaN / Infinity points
  final clean = track
      .where((p) => p.latitude.isFinite && p.longitude.isFinite)
      .toList();

  // If we don't have a real route, show a friendly placeholder
  if (clean.length < 2) {
    return Container(
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: const Text(
        'No route recorded',
        textAlign: TextAlign.center,
      ),
    );
  }

  final mc = MapController();

  return SizedBox(
    height: 260,
    child: FlutterMap(
      mapController: mc,
      options: MapOptions(
        initialCenter: clean.last,
        initialZoom: 14,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onMapReady: () {
          final bounds = _boundsFromTrack(clean);
          mc.fitCamera(
            CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.all(24),
            ),
          );
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'shoeml_learning',
        ),
        PolylineLayer(
          polylines: [
            Polyline(points: clean, strokeWidth: 4),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: clean.first,
              width: 28,
              height: 28,
              child: const Icon(Icons.flag, size: 24),
            ),
            Marker(
              point: clean.last,
              width: 28,
              height: 28,
              child: const Icon(Icons.place, size: 24),
            ),
          ],
        ),
      ],
    ),
  );
}


// Compute LatLngBounds for a list of points.
LatLngBounds _boundsFromTrack(List<LatLng> pts) {
  final validPts = pts.where((p) =>
      p.latitude.isFinite &&
      p.longitude.isFinite &&
      p.latitude.abs() <= 90 &&
      p.longitude.abs() <= 180).toList();

  if (validPts.isEmpty) {
    // Very small non-zero box to keep flutter_map happy
    return LatLngBounds(const LatLng(0, 0), const LatLng(0.001, 0.001));
  }

  double minLat = validPts.first.latitude,  maxLat = validPts.first.latitude;
  double minLon = validPts.first.longitude, maxLon = validPts.first.longitude;

  for (final p in validPts) {
    if (p.latitude  < minLat) minLat = p.latitude;
    if (p.latitude  > maxLat) maxLat = p.latitude;
    if (p.longitude < minLon) minLon = p.longitude;
    if (p.longitude > maxLon) maxLon = p.longitude;
  }

  // 🔴 CRITICAL: avoid zero-area bounds (which cause Infinity/NaN in flutter_map)
  const double minSpan = 1e-4; // ~11m at equator
  if ((maxLat - minLat).abs() < minSpan) {
    minLat -= minSpan / 2;
    maxLat += minSpan / 2;
  }
  if ((maxLon - minLon).abs() < minSpan) {
    minLon -= minSpan / 2;
    maxLon += minSpan / 2;
  }

  return LatLngBounds(LatLng(minLat, minLon), LatLng(maxLat, maxLon));
}

// Helper to get valid track points
List<LatLng> get _validTrack {
  return _track.where((p) => 
    !p.latitude.isNaN && !p.latitude.isInfinite &&
    !p.longitude.isNaN && !p.longitude.isInfinite &&
    p.latitude.abs() <= 90 && p.longitude.abs() <= 180
  ).toList();
}

}

class _RawSample {
  _RawSample(this.t, this.roll, this.pitch, this.yaw, this.tempC,
      this.cadence, this.strideM, this.dH);
  double t;
  double? roll, pitch, yaw, tempC, cadence, strideM, dH;
}


/* -------------------------------------------------------------------------- */
/*                                  TUTORIAL                                  */
/* -------------------------------------------------------------------------- */

class TutorialPage extends StatelessWidget {
  const TutorialPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          Card(
            color: cs.surfaceContainerHigh,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                "Tutorial\n\n"
                "1) Tap Scan & Connect on Dashboard to connect to the shoe.\n"
                "2) Watch live metrics (RSSI, roll/pitch/yaw, temp, steps).\n"
                "3) Graphs tab shows smooth lines for R/P/Y and gait phases.\n"
                "4) Training tab: choose a label, Start → Stop (auto-saves CSV),\n"
                "   then Train & Save to create a model JSON.\n"
                "5) Share last CSV from Training tab or browse app files.\n\n"
                "Tip: use the Palette icon to change theme/color.",
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                              SOFTMAX CLASSIFIER                             */
/* -------------------------------------------------------------------------- */

class SoftmaxClassifier {
  late int C, D;
  late List<List<double>> W;
  late List<double> b;

  void init({required int numClasses, required int inDim}) {
    C = numClasses;
    D = inDim;
    final rnd = math.Random(42);
    W = List.generate(
        C,
        (_) =>
            List.generate(D, (_) => (rnd.nextDouble() - 0.5) * 0.01));
    b = List.filled(C, 0.0);
  }

  List<double> _softmax(List<double> z) {
    final m = z.reduce(math.max);
    final exps = z.map((v) => math.exp(v - m)).toList();
    final s = exps.reduce((a, b) => a + b);
    return exps.map((v) => v / s).toList();
  }

  int predict(List<double> x) {
    final z = List<double>.generate(
        C,
        (k) =>
            List<double>.generate(D, (j) => W[k][j] * x[j])
                    .reduce((a, b) => a + b) +
            b[k]);
    final p = _softmax(z);
    int arg = 0;
    double best = p[0];
    for (int i = 1; i < p.length; i++) {
      if (p[i] > best) {
        best = p[i];
        arg = i;
      }
    }
    return arg;
  }

  void fit(List<List<double>> X, List<int> y,
      {int epochs = 50,
      double lr = 0.05,
      double l2 = 1e-4,
      int batch = 64}) {
    final n = X.length;
    for (int ep = 0; ep < epochs; ep++) {
      for (int i0 = 0; i0 < n; i0 += batch) {
        final i1 = math.min(n, i0 + batch);
        final m = i1 - i0;

        final dW = List.generate(C, (_) => List.filled(D, 0.0));
        final db = List.filled(C, 0.0);

        for (int i = i0; i < i1; i++) {
          final x = X[i];
          final yi = y[i];

          final z = List<double>.generate(
              C,
              (k) =>
                  List<double>.generate(D, (j) => W[k][j] * x[j])
                          .reduce((a, b) => a + b) +
                  b[k]);
          final p = _softmax(z);

          for (int k = 0; k < C; k++) {
            final grad = p[k] - (k == yi ? 1.0 : 0.0);
            for (int j = 0; j < D; j++) {
              dW[k][j] += grad * x[j];
            }
            db[k] += grad;
          }
        }

        for (int k = 0; k < C; k++) {
          for (int j = 0; j < D; j++) {
            W[k][j] -= lr * ((dW[k][j] / m) + l2 * W[k][j]);
          }
          b[k] -= lr * (db[k] / m);
        }
      }
    }
  }

  double accuracy(List<List<double>> X, List<int> y) {
    int correct = 0;
    for (int i = 0; i < X.length; i++) {
      if (predict(X[i]) == y[i]) correct++;
    }
    return X.isEmpty ? 0.0 : correct / X.length;
  }
}

double? _decodeTemp(List<int> d) {
  try {
    if (d.length >= 4) {
      final bd = ByteData.sublistView(Uint8List.fromList(d));
      return bd.getFloat32(0, Endian.little); // IEEE754 float32 (LE)
    }
    if (d.length >= 2) {
      final bd = ByteData.sublistView(Uint8List.fromList(d));
      final raw = bd.getInt16(0, Endian.little); // int16 centi-degC
      return raw / 100.0;
    }
  } catch (_) {}
  return null;
}

double? decodeTempOrNull(List<int> b) {
  try {
    if (b.isEmpty) return null;
    if (b.length >= 4) {
      final d = ByteData.sublistView(Uint8List.fromList(b)).getFloat32(0, Endian.little);
      if (d.isNaN || d.isInfinite) return null;
      if (d < -50 || d > 120) return null; // sanity
      return d;
    }
    if (b.length >= 2) {
      final s = ByteData.sublistView(Uint8List.fromList(b)).getInt16(0, Endian.little);
      return s / 100.0; // some firmwares send centi-degC
    }
  } catch (_) {}
  return null;
}


