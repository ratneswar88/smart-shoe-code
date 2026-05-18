// MadePlus SHOEML — split tabs: Dashboard, Graphs, Training, Tutorial
// Requires: flutter_reactive_ble, permission_handler, app_settings, fl_chart,
//           path_provider, intl, share_plus

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
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
import 'connect_home_page.dart';

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
                  point: points.first,
                  width: 28,
                  height: 28,
                  child:
                      const Icon(Icons.flag, color: Colors.green, size: 24),
                ),
                Marker(
                  point: points.last,
                  width: 28,
                  height: 28,
                  child:
                      const Icon(Icons.place, color: Colors.red, size: 24),
                ),
              ]),
            ],
          ),
          if (distanceLabel.isNotEmpty)
            Positioned(
              right: 12,
              top: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(distanceLabel,
                    style: const TextStyle(color: Colors.white)),
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
    (e, st) {/* swallow */},
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
     home: ConnectHomePage(
  connection$: _ble.connection$,
  rssi$: _ble.rssi$,
  scanOnce: _ble.scanOnce,
  connect: _ble.connect,
  disconnect: _ble.disconnect,
  reconnectLastIfAny: _ble.reconnectLastIfAny,
  dashboardBuilder: (_) => HomeShell(
    ble: _ble,
    onPickColor: () => _pickColor(context),
  ),
),
    );
  }
 final ShoeBle _ble = ShoeBle();

@override
void dispose() {
  _ble.dispose();
  super.dispose();
}
}

/// Bottom navigation shell with four tabs.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.onPickColor,
    required this.ble,
  });

  final VoidCallback onPickColor;
  final ShoeBle ble;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  ShoeBle get _ble => widget.ble;

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
    // No reconnect here — ConnectHomePage already handles that.
  }

  @override
  void dispose() {
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
            const Text("SMARTSHOE"),
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
                await AppSettings.openAppSettings(
                  type: AppSettingsType.bluetooth,
                );
              } catch (_) {
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
            icon: Icon(Icons.dashboard_outlined),
            label: "Dashboard",
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart),
            label: "Graphs",
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            label: "Training",
          ),
          NavigationDestination(
            icon: Icon(Icons.help_outline),
            label: "Tutorial",
          ),
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

  final _rssi = StreamController<int?>.broadcast(); // nullable now
  Stream<int?> get rssi$ => _rssi.stream;

  final roll$ = StreamController<double>.broadcast();
  final pitch$ = StreamController<double>.broadcast();
  final yaw$ = StreamController<double>.broadcast();
  final steps$ = StreamController<int>.broadcast();
  final cadence$ = StreamController<double>.broadcast();
  final stride$ = StreamController<double>.broadcast();
  final dh$ = StreamController<double>.broadcast();

  // Temp
  final _tempCtrl = StreamController<double?>.broadcast();
  Stream<double?> get temp$ => _tempCtrl.stream;

  // ---- App-side analytics: steps / cadence / stride ----
  final _stepsAnalyticCtrl = StreamController<int>.broadcast();
  final _cadenceAnalyticCtrl = StreamController<double>.broadcast();
  final _strideAnalyticCtrl = StreamController<double>.broadcast();

  Stream<int> get stepsAnalytic$ => _stepsAnalyticCtrl.stream;
  Stream<double> get cadenceAnalytic$ => _cadenceAnalyticCtrl.stream;
  Stream<double> get strideAnalytic$ => _strideAnalyticCtrl.stream;

  // ---------------- Core ----------------
  final _ble = FlutterReactiveBle();
  String? _deviceId;
  bool _shouldReconnect = false;
  Timer? _reconnectTimer;
  static const String _prefsKeyLastDeviceId = 'shoeml_last_device_id';

  // UUIDs (unchanged; use yours)
  final Uuid serviceUuid = Uuid.parse("0000feed-0000-1000-8000-00805f9b34fb");
  final Uuid rollUuid = Uuid.parse("0000a001-0000-1000-8000-00805f9b34fb");
  final Uuid pitchUuid = Uuid.parse("0000a002-0000-1000-8000-00805f9b34fb");
  final Uuid yawUuid = Uuid.parse("0000a003-0000-1000-8000-00805f9b34fb");
  final Uuid tempUuid = Uuid.parse("0000b001-0000-1000-8000-00805f9b34fb");
  final Uuid stepsUuid = Uuid.parse("0000c001-0000-1000-8000-00805f9b34fb");
  final Uuid cadenceUuid = Uuid.parse("0000c002-0000-1000-8000-00805f9b34fb");
  final Uuid strideUuid = Uuid.parse("0000c003-0000-1000-8000-00805f9b34fb");
  final Uuid altdhUuid = Uuid.parse("0000b002-0000-1000-8000-00805f9b34fb");

  // Subs
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _sRoll,
      _sPitch,
      _sYaw,
      _sTemp,
      _sSteps,
      _sCad,
      _sStride,
      _sDh;

  // RSSI timer
  Timer? _rssiTimer;

  // ---- Live step detection state (app-side analytics) ----
  double _tAnalytic = 0.0; // accumulated time in seconds
  double _baselinePitch = 0.0;
  bool _baselineInit = false;

  double _lastCentered = 0.0;
  double _lastStepTime = -1.0;
  int _cumSteps = 0;

  final List<double> _stepTimes = [];
  static const double _cadenceWindowSec = 10.0;

  // NEW: track real time for dt and remember last stride
  DateTime? _lastPitchTs;
  double _lastStrideFromCadence = 0.0;

  // ------------- Scan (unchanged) -------------
  Future<DiscoveredDevice?> scanOnce(
      {Duration timeout = const Duration(seconds: 6)}) async {
    DiscoveredDevice? found;
    final sub =
        _ble.scanForDevices(withServices: [serviceUuid]).listen((d) {
      found ??= d;
    }, onError: (_) {});
    await Future.delayed(timeout);
    await sub.cancel();
    return found;
  }

  // ------------- Connect -------------
  Future<void> connect(String id) async {
    await disconnect(clearLastDevice: false);
    _shouldReconnect = true; // Enable auto-reconnect
    _deviceId = id;
    await _saveLastDeviceId(id);

    _resetAnalytics(); // reset app-side steps/cadence/stride

    await _attemptConnection(id);
  }

  Future<void> _attemptConnection(String id) async {
    if (!_shouldReconnect) return;

   try {
  await _connSub?.cancel();
} catch (_) {}
    _connSub = _ble.connectToDevice(id: id).listen((u) async {
      _connState.add(u.connectionState);

      if (u.connectionState == DeviceConnectionState.connected) {
        _reconnectTimer?.cancel(); // Stop reconnect timer when connected

        // Ensure GATT is ready before starting RSSI
        try {
          await _ble.discoverAllServices(id);
        } catch (_) {}

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
          debugPrint(
              "[BLE] Disconnected. Will attempt reconnect in 3 seconds...");
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
        debugPrint(
            "[BLE] Error occurred. Will attempt reconnect in 3 seconds...");
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

  Future<void> disconnect({bool clearLastDevice = true}) async {
  _shouldReconnect = false; // Disable auto-reconnect
  _reconnectTimer?.cancel();
  _stopRssi();
  await _unsubscribeAll();

  try {
    await _connSub?.cancel();
  } catch (_) {}

  _connSub = null;
  _deviceId = null;

  _resetAnalytics(); // clear analytics on manual disconnect

  if (!_connState.isClosed) {
    _connState.add(DeviceConnectionState.disconnected);
  }

  if (clearLastDevice) {
    await _clearLastDeviceId();
  }
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
    final savedId = prefs.getString(_prefsKeyLastDeviceId);

    // BEST PATH: scan for a live advertising device first
    final hit = await scanOncePreferLast(
      timeout: const Duration(seconds: 8),
    );

    if (hit != null) {
      debugPrint('[BLE] Reconnect via fresh scan: ${hit.id}');
      await connect(hit.id);
      return;
    }

    // LAST RESORT: try saved id directly
    if (savedId != null && savedId.isNotEmpty) {
      debugPrint('[BLE] Reconnect via saved id: $savedId');
      await connect(savedId);
    }
  } catch (e) {
    debugPrint('[BLE] reconnectLastIfAny failed: $e');
  }
}
Future<DiscoveredDevice?> scanOncePreferLast({
  Duration timeout = const Duration(seconds: 6),
}) async {
  final prefs = await SharedPreferences.getInstance();
  final lastId = prefs.getString(_prefsKeyLastDeviceId);

  DiscoveredDevice? preferred;
  DiscoveredDevice? fallback;

  final sub = _ble.scanForDevices(withServices: [serviceUuid]).listen((d) {
    fallback ??= d;
    if (lastId != null && d.id == lastId) {
      preferred ??= d;
    }
  }, onError: (_) {});

  await Future.delayed(timeout);
  await sub.cancel();

  return preferred ?? fallback;
}
  void dispose() {
  _shouldReconnect = false;
  _reconnectTimer?.cancel();
  disconnect(clearLastDevice: false);
  try {
    _connState.close();
  } catch (_) {}
  try {
    _rssi.close();
  } catch (_) {}
  try {
    roll$.close();
  } catch (_) {}
  try {
    pitch$.close();
  } catch (_) {}
  try {
    yaw$.close();
  } catch (_) {}
  try {
    steps$.close();
  } catch (_) {}
  try {
    cadence$.close();
  } catch (_) {}
  try {
    stride$.close();
  } catch (_) {}
  try {
    dh$.close();
  } catch (_) {}
  try {
    _tempCtrl.close();
  } catch (_) {}
  try {
    _stepsAnalyticCtrl.close();
  } catch (_) {}
  try {
    _cadenceAnalyticCtrl.close();
  } catch (_) {}
  try {
    _strideAnalyticCtrl.close();
  } catch (_) {}
}

  // ------------- Notify subscriptions -------------
  Future<void> _subscribeAll() async {
    if (_deviceId == null) return;
    final id = _deviceId!;
    Future<StreamSubscription<List<int>>> sub(
      Uuid c,
      void Function(List<int>) onData,
    ) async {
      final q = QualifiedCharacteristic(
        deviceId: id,
        serviceId: serviceUuid,
        characteristicId: c,
      );
      return _ble.subscribeToCharacteristic(q).listen(onData, onError: (_) {});
    }

    _sRoll = await sub(rollUuid, (b) => roll$.add(_f32(b)));
    _sPitch = await sub(pitchUuid, (b) {
      final v = _f32(b);
      pitch$.add(v);
      _updateAnalyticsFromPitch(v); // 🔥 app-side steps/cadence update
    });
    _sYaw = await sub(yawUuid, (b) => yaw$.add(_f32(b)));
    _sTemp = await sub(tempUuid, (b) => _tempCtrl.add(_f32Nullable(b)));
    _sSteps = await sub(stepsUuid, (b) => steps$.add(_i32(b)));
    _sCad = await sub(cadenceUuid, (b) => cadence$.add(_f32(b)));
    _sStride = await sub(strideUuid, (b) => stride$.add(_f32(b)));
    _sDh = await sub(altdhUuid, (b) => dh$.add(_f32(b)));
  }

  Future<void> _unsubscribeAll() async {
    for (final s in [
      _sRoll,
      _sPitch,
      _sYaw,
      _sTemp,
      _sSteps,
      _sCad,
      _sStride,
      _sDh
    ]) {
      try {
        await s?.cancel();
      } catch (_) {}
    }
    _sRoll =
        _sPitch = _sYaw = _sTemp = _sSteps = _sCad = _sStride = _sDh = null;
  }

  // ---- Analytics helpers ----
  void _resetAnalytics() {
    _tAnalytic = 0.0;
    _baselinePitch = 0.0;
    _baselineInit = false;
    _lastCentered = 0.0;
    _lastStepTime = -1.0;
    _cumSteps = 0;
    _stepTimes.clear();
    _lastPitchTs = null;
    _lastStrideFromCadence = 0.0;

    if (!_stepsAnalyticCtrl.isClosed) {
      _stepsAnalyticCtrl.add(0);
    }
    if (!_cadenceAnalyticCtrl.isClosed) {
      _cadenceAnalyticCtrl.add(0.0);
    }
    if (!_strideAnalyticCtrl.isClosed) {
      _strideAnalyticCtrl.add(0.0);
    }
  }

  void _updateAnalyticsFromPitch(double pitchDeg) {
    final now = DateTime.now();

    // --- 1) time step (dt) from real timestamps ---
    double dt = 0.1; // fallback
    if (_lastPitchTs != null) {
      dt = now.difference(_lastPitchTs!).inMilliseconds / 1000.0;
      if (dt <= 0) dt = 0.1;
      if (dt > 0.5) dt = 0.5; // clamp unreasonable gaps
    }
    _lastPitchTs = now;

    _tAnalytic += dt;

    // --- 2) low-pass baseline for pitch ---
    const double alpha = 0.01;
    if (!_baselineInit) {
      _baselinePitch = pitchDeg;
      _baselineInit = true;
    } else {
      _baselinePitch += alpha * (pitchDeg - _baselinePitch);
    }

    final centered = pitchDeg - _baselinePitch;

    // --- 3) Step detection ---
    const double ampThresh = 5.0; // degrees
    const double minStepDt = 0.30; // seconds

    final bool upwardCross = (_lastCentered <= 0.0 && centered > 0.0);
    final double dtFromLast =
        _lastStepTime < 0 ? 999.0 : (_tAnalytic - _lastStepTime);

    if (upwardCross &&
        centered.abs() >= ampThresh &&
        dtFromLast >= minStepDt) {
      _lastStepTime = _tAnalytic;
      _cumSteps++;

      _stepTimes.add(_tAnalytic);
      // keep only last _cadenceWindowSec seconds
      while (_stepTimes.isNotEmpty &&
          _stepTimes.first < _tAnalytic - _cadenceWindowSec) {
        _stepTimes.removeAt(0);
      }
    }

    _lastCentered = centered;

    // --- 4) Publish steps (cumulative) ---
    if (!_stepsAnalyticCtrl.isClosed) {
      _stepsAnalyticCtrl.add(_cumSteps);
    }

    // --- 5) Cadence (spm) over last window ---
    double cadenceSpm = 0.0;
    if (_stepTimes.length >= 2) {
      final int count = _stepTimes.length;
      final double dur = _stepTimes.last - _stepTimes.first;
      if (dur > 0) {
        final freqHz = (count - 1) / dur;
        cadenceSpm = freqHz * 60.0;
      }
    }
    if (!_cadenceAnalyticCtrl.isClosed) {
      _cadenceAnalyticCtrl.add(cadenceSpm);
    }

    // --- 6) Stride heuristic from cadence ---
    // We don't have GPS distance on Dashboard live,
    // so we approximate stride from cadence only:
    //
    //   stride ≈ k * cadenceHz
    //
    // Pick k so that at ~100 spm (≈1.67 Hz), stride ≈ 0.8 m:
    //   k ≈ 0.48 → 0.48 * 1.67 ≈ 0.8 m
    double strideM = _lastStrideFromCadence;

    if (cadenceSpm > 0.0) {
      final freqHz = cadenceSpm / 60.0;
      const double kStride = 0.48; // heuristic gain
      strideM = kStride * freqHz;

      // clamp to a reasonable human range
      if (strideM < 0.3) strideM = 0.3;
      if (strideM > 1.8) strideM = 1.8;

      _lastStrideFromCadence = strideM;
    }

    if (!_strideAnalyticCtrl.isClosed) {
      _strideAnalyticCtrl.add(strideM);
    }
  }

  // ------------- RSSI helpers -------------
  Future<void> _readRssiOnce() async {
    final id = _deviceId;
    if (id == null) return;
    try {
      final v = await _ble.readRssi(id); // requires connected
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
    try {
      _rssiTimer?.cancel();
    } catch (_) {}
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
  if (v == 0.0) return null; // Treat 0.0 as null for nullable values
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
double _t = 0.0; // simple time counter for R/P/Y charts
DateTime? _t0; // wall-clock base for temperature series

final List<FlSpot> _r = []; // roll series
final List<FlSpot> _p = []; // pitch series
final List<FlSpot> _y = []; // yaw series
final List<FlSpot> _temp = []; // temperature series

StreamSubscription<double>? _sr, _sp, _sy; // roll/pitch/yaw subs
StreamSubscription<double?>? _sTemp; // temperature sub

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
class _LiveModelEntry {
  _LiveModelEntry({
    required this.path,
    required this.model,
  });

  final String path;
  final LoadedActivityModel model;

  String get shortName {
    // Use last segment after platform separator or '/'
    final parts = path.split(Platform.pathSeparator);
    if (parts.isNotEmpty) return parts.last;
    final slashParts = path.split('/');
    if (slashParts.isNotEmpty) return slashParts.last;
    return path;
  }
}


class _DashboardPageState extends State<DashboardPage> {
  String? _id;
  double roll = 0, pitch = 0, yaw = 0, cadence = 0, stride = 0, dh = 0;
  double? tempC;
  int steps = 0;
  int? rssi;
  DeviceConnectionState conn = DeviceConnectionState.disconnected;

  StreamSubscription? _s1, _s2, _s3, _s4, _s5, _s6, _s7, _s8, _s9, _s10;

  // ----- Live activity classification state -----
  final List<_RawSample> _liveBuf = [];
final List<_LiveModelEntry> _liveModels = [];
String? _liveActivity;
double? _liveConf;
bool _modelLoading = false;
double _tLive = 0.0; // synthetic time counter for live buffer
// NEW: min confidence to show a prediction
double _liveConfThreshold = 0.6;
    // Which classes from the loaded model are allowed for live prediction.
 // NEW: which labels of the model are enabled for live prediction
  Set<String> _enabledLiveLabels = {};


  @override
  void initState() {
    super.initState();
   _loadConfThreshold(); // NEW: restore saved threshold
    _loadEnabledLiveLabels();  // restore per-label filters



    // Bind metric streams (connection, steps, cadence, etc.)
    _bind();

    // Plot streams for charts with validation (global series _r, _p, _y, _temp)
    _sr = widget.ble.roll$.stream.listen((v) {
      if (!mounted || v.isNaN || v.isInfinite) return;
      setState(() {
        _t += 0.1;
        _push(_r, _t, v);
      });
    });

    _sp = widget.ble.pitch$.stream.listen((v) {
      if (!mounted || v.isNaN || v.isInfinite) return;
      setState(() {
        _t += 0.1;
        _push(_p, _t, v);
      });
    });

    _sy = widget.ble.yaw$.stream.listen((v) {
      if (!mounted || v.isNaN || v.isInfinite) return;
      setState(() {
        _t += 0.1;
        _push(_y, _t, v);
      });
    });

    _t0 ??= DateTime.now();
    _sTemp = widget.ble.temp$.listen((v) {
      if (v == null || !mounted || v.isNaN || v.isInfinite) return;
      final t = DateTime.now().difference(_t0!).inMilliseconds / 1000.0;
      _push(_temp, t, v);
      setState(() => tempC = v);
    });
  }

  void _bind() {
    _s1 = widget.ble.connection$.listen((c) => setState(() => conn = c));

    _s2 = widget.ble.roll$.stream.listen((v) {
      setState(() => roll = v);
      _onNewLiveRoll(v);
    });

    _s3 = widget.ble.pitch$.stream.listen((v) {
      setState(() => pitch = v);
      if (_liveBuf.isNotEmpty) {
        _liveBuf.last.pitch = v;
      }
    });

    _s4 = widget.ble.yaw$.stream.listen((v) {
      setState(() => yaw = v);
      if (_liveBuf.isNotEmpty) {
        _liveBuf.last.yaw = v;
      }
    });

    _s5 = widget.ble.temp$.listen((v) {
      setState(() => tempC = v);
      if (v != null && _liveBuf.isNotEmpty) {
        _liveBuf.last.tempC = v;
      }
    });

    _s6 = widget.ble.stepsAnalytic$.listen((v) {
      setState(() => steps = v);
      // We don't use steps directly in features, so no need to store.
    });

    _s7 = widget.ble.cadenceAnalytic$.listen((v) {
      setState(() => cadence = v);
      if (_liveBuf.isNotEmpty) {
        _liveBuf.last.cadence = v;
      }
    });

    _s8 = widget.ble.strideAnalytic$.listen((v) {
      setState(() => stride = v);
      if (_liveBuf.isNotEmpty) {
        _liveBuf.last.strideM = v;
      }
    });

    _s9 = widget.ble.dh$.stream.listen((v) {
      setState(() => dh = v);
    });

    _s10 = widget.ble.rssi$.listen((v) {
      setState(() => rssi = v);
    });
  }

  @override
  void dispose() {
    for (final s in [_s1, _s2, _s3, _s4, _s5, _s6, _s7, _s8, _s9, _s10]) {
      try {
        s?.cancel();
      } catch (_) {}
    }
    try {
      _sr?.cancel();
    } catch (_) {}
    try {
      _sp?.cancel();
    } catch (_) {}
    try {
      _sy?.cancel();
    } catch (_) {}
    try {
      _sTemp?.cancel();
    } catch (_) {}
    super.dispose();
  }

  String _connLabel(DeviceConnectionState s) {
    switch (s) {
      case DeviceConnectionState.connecting:
        return "Connecting...";
      case DeviceConnectionState.connected:
        return "Connected";
      case DeviceConnectionState.disconnecting:
        return "Disconnecting...";
      case DeviceConnectionState.disconnected:
        return "Disconnected";
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

  // ---------------- Live classifier helpers ----------------

void _onNewLiveRoll(double v) {
  // Only buffer when at least one model is loaded
  if (_liveModels.isEmpty) return;
  if (v.isNaN || v.isInfinite) return;

  _tLive += 0.1; // approximate 10 Hz
  _liveBuf.add(
    _RawSample(
      _tLive,
      v,
      null,
      null,
      null,
      null,
      null,
      null,
    ),
  );
  _trimLiveBuf();
  _tryClassifyLive();
}


  void _trimLiveBuf() {
    if (_liveBuf.length < 2) return;
    const maxSpanSec = 20.0;
    final tMax = _liveBuf.last.t;
    while (_liveBuf.isNotEmpty && tMax - _liveBuf.first.t > maxSpanSec) {
      _liveBuf.removeAt(0);
    }
  }

    void _tryClassifyLive() {
    if (_liveModels.isEmpty) return;
    if (_liveBuf.length < 5) return;

    final buf = _liveBuf;
    final dt = (buf.last.t - buf.first.t) / (buf.length - 1);
    if (!dt.isFinite || dt <= 0) return;

    // ~3 s window
    final win = (3.0 / dt).round().clamp(1, buf.length);
    if (buf.length < win) return;

    final window = buf.sublist(buf.length - win);
    final feat = _liveFeatures(window);

    String? bestLabel;
    double bestConf = -1.0;

    for (final entry in _liveModels) {
      final pred = entry.model.predictLabel(feat);
      final label = pred.key;
      final conf = pred.value; // 0–1 probability

      // Per-label enable/disable:
      // If _enabledLiveLabels is empty → treat as "all allowed".
      final bool allowed = _enabledLiveLabels.isEmpty ||
          _enabledLiveLabels.contains(label);
      if (!allowed) continue;

      if (conf > bestConf) {
        bestConf = conf;
        bestLabel = label;
      }
    }

    String? finalLabel;
    double? finalConf;

    // Apply confidence threshold: if below, show no prediction
    if (bestLabel != null && bestConf >= _liveConfThreshold) {
      finalLabel = bestLabel;
      finalConf = bestConf;
    } else {
      finalLabel = null;
      finalConf = null;
    }

    if (!mounted) return;
    setState(() {
      _liveActivity = finalLabel;
      _liveConf = finalConf;
    });
  }





  List<double> _liveFeatures(List<_RawSample> w) {
    List<double> col(List<double?> v) {
      final r = v.whereType<double>().toList();
      return r.isEmpty ? <double>[0.0] : r;
    }

    List<double> stats(List<double> x) {
      final n = x.length;
      final mean = x.reduce((a, b) => a + b) / n;
      final varr =
          x.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / n;
      final rms = math.sqrt(
          x.map((v) => v * v).reduce((a, b) => a + b) / n);
      return [mean, varr, rms];
    }

    final rollCol = col(w.map((e) => e.roll).toList());
    final pitchCol = col(w.map((e) => e.pitch).toList());
    final yawCol = col(w.map((e) => e.yaw).toList());
    final cadCol = col(w.map((e) => e.cadence).toList());
    final strideCol = col(w.map((e) => e.strideM).toList());
    final tempCol = col(w.map((e) => e.tempC).toList());

    final out = <double>[];
    out
      ..addAll(stats(rollCol))
      ..addAll(stats(pitchCol))
      ..addAll(stats(yawCol))
      ..addAll(stats(cadCol))
      ..addAll(stats(strideCol))
      ..addAll(stats(tempCol));
    return out;
  }
  Future<void> _loadEnabledLiveLabels() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(kEnabledLiveLabelsKey);
    if (list != null && mounted) {
      setState(() {
        _enabledLiveLabels = list.toSet();
      });
    }
  } catch (_) {
    // ignore; default "all enabled" behaviour if empty
  }
}

Future<void> _saveEnabledLiveLabels() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      kEnabledLiveLabelsKey,
      _enabledLiveLabels.toList(),
    );
  } catch (_) {
    // ignore
  }
}

/// Toggle a label on/off for live predictions.
///
/// If this is the first time the user touches label filters and the set is
/// empty, we initialize it with *all* labels from all loaded models so the
/// user starts from "all on" and toggles a few off (e.g. only disable "sitting").
void _toggleLiveLabel(String label) {
  setState(() {
    // First time: initialize with all labels from loaded models.
    if (_enabledLiveLabels.isEmpty) {
      final all = <String>{};
      for (final e in _liveModels) {
        all.addAll(e.model.labels);
      }
      _enabledLiveLabels = all;
    }

    if (_enabledLiveLabels.contains(label)) {
      _enabledLiveLabels.remove(label);
    } else {
      _enabledLiveLabels.add(label);
    }
  });

  _saveEnabledLiveLabels();
}

Future<void> _loadConfThreshold() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getDouble(kLiveConfThresholdKey);
    if (v != null && mounted) {
      setState(() {
        _liveConfThreshold = v.clamp(0.0, 1.0);
      });
    }
  } catch (_) {
    // ignore, keep default
  }
}

Future<void> _saveConfThreshold(double v) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(kLiveConfThresholdKey, v.clamp(0.0, 1.0));
  } catch (_) {
    // ignore
  }
}

    Future<void> _loadActiveModel() async {
  if (_modelLoading) return;
  setState(() => _modelLoading = true);

  try {
    final prefs = await SharedPreferences.getInstance();

    // Multi-select list of paths
    List<String> paths =
        prefs.getStringList(kActiveModelPathsKey) ?? const [];

    // Backwards-compat: fall back to single active path, if present
    final legacy = prefs.getString(kActiveModelPathKey);
    if (paths.isEmpty && legacy != null && legacy.isNotEmpty) {
      paths = [legacy];
    }

    if (paths.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "No active models selected. Go to Training → \"Active model for live classification\" and choose one or more models.",
          ),
        ),
      );
      return;
    }

    final List<_LiveModelEntry> loaded = [];
    for (final path in paths) {
      final f = File(path);
      if (!await f.exists()) continue;

      try {
        final txt = await f.readAsString();
        final decoded = jsonDecode(txt);
        if (decoded is! Map<String, dynamic>) continue;
        final m = LoadedActivityModel.fromJson(decoded);
        loaded.add(_LiveModelEntry(path: path, model: m));
      } catch (_) {
        // ignore malformed model file
      }
    }

    if (loaded.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Active model files not found. Pick models again on the Training tab.",
          ),
        ),
      );
      return;
    }

    setState(() {
      _liveModels
        ..clear()
        ..addAll(loaded);
      _liveBuf.clear();
      _tLive = 0.0;
      _liveActivity = null;
      _liveConf = null;
    });

    if (!mounted) return;
    final names = loaded.map((e) => e.shortName).join(", ");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Loaded ${loaded.length} active model(s): $names",
        ),
      ),
    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Failed to load active models: $e"),
      ),
    );
  } finally {
    if (mounted) {
      setState(() => _modelLoading = false);
    }
  }
}


  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          // Connection + BLE controls
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
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                            Text(
                              _id == null ? "Not connected" : _id!,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall,
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 12),

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
                        avatar:
                            const Icon(Icons.network_cell, size: 16),
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

          // Metrics grid
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metric(cs, "Roll (°)",
                  roll.toStringAsFixed(1), Icons.rotate_90_degrees_ccw),
              _metric(cs, "Pitch (°)",
                  pitch.toStringAsFixed(1), Icons.rotate_90_degrees_cw),
              _metric(cs, "Yaw (°)",
                  yaw.toStringAsFixed(1), Icons.refresh),
              _metric(cs, "Temp (°C)",
                  tempC?.toStringAsFixed(1) ?? "—", Icons.thermostat),
              _metric(cs, "Steps", steps.toString(),
                  Icons.directions_walk),
              _metric(cs, "Cadence",
                  "${cadence.toStringAsFixed(1)} spm", Icons.speed),
              _metric(cs, "Stride",
                  "${stride.toStringAsFixed(2)} m", Icons.straighten),
              _metric(cs, "Elevation Δh",
                  "${dh.toStringAsFixed(2)} m", Icons.landscape),
            ],
          ),

          const SizedBox(height: 16),

          // Live classifier card
          _activityClassifierCard(cs),

          const SizedBox(height: 16),

          _info(cs, "MADEPLUS",
              "Smart shoe analytics, live activity classification, and on-device training."),
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
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(value,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

 Widget _activityClassifierCard(ColorScheme cs) {
  final hasModels = _liveModels.isNotEmpty;
  final loadedNames = _liveModels.map((e) => e.shortName).join(", ");

  return Card(
    color: cs.surfaceContainerHigh,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Live activity classifier",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasModels
                ? "Using ${_liveModels.length} model(s). Each ~3-second IMU window is evaluated across all loaded models; the highest-confidence label is shown below."
                : "Train one or more models on the Training tab, then use \"Active model for live classification\" to select which JSON files to use. Finally, tap \"Load active models\" here to start live walking / running / stairs prediction.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Text(
            "Loaded models: ${hasModels ? loadedNames : 'none (set on Training tab)'}",
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontStyle: FontStyle.italic),
          ),
		    // NEW: threshold control
          const SizedBox(height: 10),
          Text(
            "Show prediction only if confidence ≥ "
            "${(_liveConfThreshold * 100).toStringAsFixed(0)}%",
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Slider(
            value: _liveConfThreshold,
            min: 0.3,
            max: 0.99,
            divisions: 14, // ~5% steps
            label: "${(_liveConfThreshold * 100).toStringAsFixed(0)}%",
            onChanged: (v) {
              setState(() {
                _liveConfThreshold = v;
              });
            },
            onChangeEnd: (v) {
              _saveConfThreshold(v);
            },
          ),
		   // --- Per-label enable/disable chips ---
          if (hasModels) ...[
            const SizedBox(height: 10),
            Text(
              "Enabled labels for live prediction:",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _buildLabelChips(cs),
            ),
          ],
          const SizedBox(height: 10),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _modelLoading ? null : _loadActiveModel,
                icon: const Icon(Icons.auto_awesome),
                label: Text(
                  hasModels
                      ? "Reload active models"
                      : "Load active models",
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Prediction: ${_liveActivity ?? '-'}",
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_liveConf != null)
                      Text(
                        "Confidence: ${(_liveConf! * 100).toStringAsFixed(1)}%",
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.primary),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
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
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(body),
            ]),
      ),
    );
  }
    List<Widget> _buildLabelChips(ColorScheme cs) {
    // Collect all labels from all loaded models
    final allLabels = <String>{};
    for (final e in _liveModels) {
      allLabels.addAll(e.model.labels);
    }

    final labels = allLabels.toList()..sort();
    if (labels.isEmpty) {
      return [
        Text(
          "No labels found in loaded models.",
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ];
    }

    return labels.map((lbl) {
      // If user has never customized filters, _enabledLiveLabels is empty
      // → treat as "label is enabled".
      final enabled = _enabledLiveLabels.isEmpty ||
          _enabledLiveLabels.contains(lbl);

      return FilterChip(
        label: Text(lbl),
        selected: enabled,
        onSelected: (_) => _toggleLiveLabel(lbl),
        selectedColor: cs.primaryContainer,
        checkmarkColor: cs.onPrimaryContainer,
      );
    }).toList();
  }

}

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
      if (v.isNaN || v.isInfinite) return; // ADD VALIDATION
      setState(() {
        _t += 0.1;
        _push(_r, _t, v);
      });
    });

    _sp = widget.ble.pitch$.stream.listen((v) {
      if (v.isNaN || v.isInfinite) return; // ADD VALIDATION
      setState(() {
        _t += 0.1;
        _push(_p, _t, v);
      });
    });

    _sy = widget.ble.yaw$.stream.listen((v) {
      if (v.isNaN || v.isInfinite) return; // ADD VALIDATION
      setState(() {
        _t += 0.1;
        _push(_y, _t, v);
      });
    });

    _t0 ??= DateTime.now();
    _sTemp = widget.ble.temp$.listen((v) {
      if (v == null || v.isNaN || v.isInfinite) return; // ADD VALIDATION
      final t = DateTime.now().difference(_t0!).inMilliseconds / 1000.0;
      _push(_temp, t, v);
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final s in [_sr, _sp, _sy, _sTemp]) {
      try {
        s?.cancel();
      } catch (_) {}
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
  String _label = "walking"; // current active label
  final _modelNameCtrl = TextEditingController();

  bool _collecting = false;
  DeviceConnectionState _conn = DeviceConnectionState.disconnected;
  StreamSubscription<DeviceConnectionState>? _connSub;

  // Raw IMU samples for training
  final List<_RawSample> _buffer = [];
   double _tTrain = 0.0; // NEW: logical time for training samples

  // BLE stream subscriptions
  StreamSubscription<double>? _sr; // roll
  StreamSubscription<double>? _sp; // pitch
  StreamSubscription<double>? _sy; // yaw
  StreamSubscription<double?>? _st; // temp
  StreamSubscription<double>? _sc; // cadence (from firmware, but we override)
  StreamSubscription<double>? _ss; // stride (from firmware, but we override)
  StreamSubscription<double>? _sdh; // deltaH

  // Route / GPS
  final _mapKey = GlobalKey();
  final MapController _mapController = MapController();
  List<LatLng> _track = [];
  List<DateTime> _trackTs = [];
  StreamSubscription<Position>? _posSub;
  DateTime? _tStart;
  double _lastDistM = 0.0;
  Duration _lastDur = Duration.zero;

  // --- Model management for live classification ---
  List<File> _modelFiles = [];
  Set<String> _activeModelPaths = {};
  bool _loadingModels = false;

  @override
  void initState() {
    super.initState();
    _connSub = widget.ble.connection$.listen((s) {
      setState(() => _conn = s);
    });
    _bind();
    _loadModelsAndActive();
  }

  void _bind() {
    double t = 0;
    _sr = widget.ble.roll$.stream.listen((v) {
      t += 0.1;
	   if (!_collecting) return;                  // NEW
      _tTrain += 0.1;                            // use logical time
      // capture the active label index at the moment this sample arrives
      final lblIdx = _labels.indexOf(_label);
      _buffer.add(
        _RawSample(
          t,
          v,
          null,
          null,
          null,
          null,
          null,
          null,
          labelIdx: lblIdx,
        ),
      );
    });
    _sp = widget.ble.pitch$.stream.listen((v) {
	  if (!_collecting || _buffer.isEmpty) return;
      if (_buffer.isNotEmpty) _buffer.last.pitch = v;
    });
    _sy = widget.ble.yaw$.stream.listen((v) {
	  if (!_collecting || _buffer.isEmpty) return;
      if (_buffer.isNotEmpty) _buffer.last.yaw = v;
    });
    _st = widget.ble.temp$.listen((v) {
	  if (!_collecting || _buffer.isEmpty) return;
      if (_buffer.isNotEmpty) _buffer.last.tempC = v;
    });
    _sc = widget.ble.cadence$.stream.listen((v) {
	  if (!_collecting || _buffer.isEmpty) return;
      if (_buffer.isNotEmpty) _buffer.last.cadence = v;
    });
    _ss = widget.ble.stride$.stream.listen((v) {
	  if (!_collecting || _buffer.isEmpty) return;
      if (_buffer.isNotEmpty) _buffer.last.strideM = v;
    });
    _sdh = widget.ble.dh$.stream.listen((v) {
	  if (!_collecting || _buffer.isEmpty) return;
      if (_buffer.isNotEmpty) _buffer.last.dH = v;
    });
  }

  @override
  void dispose() {
    for (final s in [_sr, _sp, _sy, _st, _sc, _ss, _sdh]) {
      try {
        s?.cancel();
      } catch (_) {}
    }
    try {
      _posSub?.cancel();
    } catch (_) {}
    try {
      _connSub?.cancel();
    } catch (_) {}
    _modelNameCtrl.dispose();
    super.dispose();
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

  /// Save the collected buffer as CSV, including steps/cadence/stride
  /// and *per-sample label* (multi-label session).
  Future<File?> _saveCsv() async {
    final dir = await _ensureDir(await _appDir(), "sessions");
    final stamp = DateFormat("yyMMdd_HHmmss").format(DateTime.now());
    final file = File("${dir.path}/${_label}_$stamp.csv");

    const header =
        "t,roll,pitch,yaw,tempC,steps,cadence,strideM,deltaH,label\n";
    final meta1 = '# distance_m=${_lastDistM.toStringAsFixed(1)}\n';
    final meta2 = '# duration_s=${_lastDur.inSeconds}\n';
    final meta3 = '# pace=${_formatPace(_lastDistM, _lastDur)}\n';
    final sb = StringBuffer(meta1 + meta2 + meta3 + header);

    for (final s in _buffer) {
      final labelStr =
          (s.labelIdx != null &&
                  s.labelIdx! >= 0 &&
                  s.labelIdx! < _labels.length)
              ? _labels[s.labelIdx!]
              : _label;
      sb.write("${s.t.toStringAsFixed(3)},"
          "${s.roll?.toStringAsFixed(3) ?? ""},"
          "${s.pitch?.toStringAsFixed(3) ?? ""},"
          "${s.yaw?.toStringAsFixed(3) ?? ""},"
          "${s.tempC?.toStringAsFixed(2) ?? ""},"
          "${s.steps?.toString() ?? ""},"
          "${s.cadence?.toStringAsFixed(1) ?? ""},"
          "${s.strideM?.toStringAsFixed(3) ?? ""},"
          "${s.dH?.toStringAsFixed(3) ?? ""},"
          "$labelStr\n");
    }

    await file.writeAsString(sb.toString(), flush: true);
    if (!mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Saved: ${file.path.split('/').last}")),
    );

    return file;
  }

  Future<void> _toggleCollect() async {
    // If we are about to START collecting, require BLE connection
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
	  _tTrain = 0.0; 
      _track = [];
      _trackTs = [];
      _tStart = DateTime.now();
      await _startLocation();
    } else {
      // STOP: stop GPS and compute stats
      await _stopLocation();
      _lastDistM = _computeDistanceMeters();
      _lastDur =
          _tStart != null ? DateTime.now().difference(_tStart!) : Duration.zero;

      // derive steps, cadence, stride length on the app side
      _fillStepsCadenceStrideFromPitch();

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
  Future<void> _deleteModel(File f) async {
  // Ask for confirmation first
  final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Delete model?"),
          content: Text(
            "This will permanently delete:\n${f.path.split('/').last}",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: const Text("Delete"),
            ),
          ],
        ),
      ) ??
      false;

  if (!confirmed) return;

  try {
    // Delete file on disk (if it still exists)
    if (await f.exists()) {
      await f.delete();
    }

    // Remove from in-memory model list
    final newFiles = List<File>.from(_modelFiles)
      ..removeWhere((mf) => mf.path == f.path);

    // Remove from active paths (if selected)
    final newActive = Set<String>.from(_activeModelPaths)
      ..remove(f.path);

    // Persist active list in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      kActiveModelPathsKey,
      newActive.toList(),
    );

    // Keep legacy single-key roughly in sync
    if (newActive.isNotEmpty) {
      await prefs.setString(kActiveModelPathKey, newActive.first);
    } else {
      await prefs.remove(kActiveModelPathKey);
    }

    if (!mounted) return;
    setState(() {
      _modelFiles = newFiles;
      _activeModelPaths = newActive;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text("Deleted model: ${f.path.split('/').last}"),
      ),
    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Failed to delete model: $e"),
      ),
    );
  }
}


   /// Train ONLY on the current buffer's data
  Future<void> _trainAndSave() async {
    // windows
    final wins = _windows(_buffer, winSec: 3.0, hopSec: 1.5);
    if (wins.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No data to train.")),
      );
      return;
    }

    // Features per window
    final feats = wins.map(_features).toList();

    // ---- Majority label index per window (old indices: 0.._labels.length-1) ----
    final winLabelIdx = <int>[];
    for (final w in wins) {
      final counts = List<int>.filled(_labels.length, 0);
      for (final s in w) {
        final idx = s.labelIdx ?? _labels.indexOf(_label);
        if (idx >= 0 && idx < counts.length) counts[idx]++;
      }
      int bestIdx = 0;
      int bestCount = -1;
      for (int i = 0; i < counts.length; i++) {
        if (counts[i] > bestCount) {
          bestCount = counts[i];
          bestIdx = i;
        }
      }
      winLabelIdx.add(bestIdx);
    }

    // ---- Which labels actually appear in this session? ----
    final presentSet = <int>{};
    for (final idx in winLabelIdx) {
      presentSet.add(idx);
    }
    if (presentSet.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No labels found in this session.")),
      );
      return;
    }

    final present = presentSet.toList()..sort();
    // Map old index -> new compact index
    final Map<int, int> remap = {};
    for (int newIdx = 0; newIdx < present.length; newIdx++) {
      remap[present[newIdx]] = newIdx;
    }

    // New label list for this model only
    final usedLabels = <String>[];
    for (final oldIdx in present) {
      usedLabels.add(_labels[oldIdx]);
    }

    // Remap labels for training
    final allY = winLabelIdx.map((old) => remap[old]!).toList();

    // ---- Train / test split ----
    final n = feats.length;
    if (n < 2) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Need at least 2 windows to train (try recording a bit longer)."),
        ),
      );
      return;
    }

    int nTrain = (0.8 * n).floor();
    if (nTrain < 1) nTrain = 1;
    if (nTrain >= n) nTrain = n - 1;

    final Xtr = feats.sublist(0, nTrain);
    final Ytr = allY.sublist(0, nTrain);
    final Xte = feats.sublist(nTrain);
    final Yte = allY.sublist(nTrain);

    final clf = SoftmaxClassifier()
      ..init(numClasses: usedLabels.length, inDim: Xtr.first.length)
      ..fit(Xtr, Ytr, lr: 0.01, epochs: 200);

    final acc = clf.accuracy(Xte, Yte);

    // ---- Save model JSON with ONLY usedLabels ----
    final dir = await _ensureDir(await _appDir(), "models");
    final baseName = _modelNameCtrl.text.trim().isEmpty
        ? "multi_label"
        : _modelNameCtrl.text.trim();
    final stamp = DateFormat("yyMMdd_HHmmss").format(DateTime.now());
    final name = "${baseName}_$stamp.json";

    final f = File("${dir.path}/$name");
    await f.writeAsString(jsonEncode({
      "labels": usedLabels,
      "W": clf.W,
      "b": clf.b,
    }));

    // Make this model part of the active set (multi-select)
    try {
      final prefs = await SharedPreferences.getInstance();
      final current =
          prefs.getStringList(kActiveModelPathsKey) ?? <String>[];
      if (!current.contains(f.path)) {
        current.add(f.path);
      }
      await prefs.setStringList(kActiveModelPathsKey, current);
      // keep legacy single for backward compat
      await prefs.setString(kActiveModelPathKey, f.path);
    } catch (_) {}

    await _loadModelsAndActive();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Trained on ${usedLabels.join(', ')} • "
          "acc ${(acc * 100).toStringAsFixed(1)}% • saved: $name",
        ),
      ),
    );
  }


  Future<List<File>> _recentSessionCsvFiles({int limit = 50}) async {
    final dir = await _ensureDir(await _appDir(), "sessions");
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith(".csv"))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    if (files.length > limit) {
      return files.sublist(0, limit);
    }
    return files;
  }

  Future<void> _showShareCsvPicker() async {
    final files = await _recentSessionCsvFiles(limit: 50);
    if (files.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No CSV sessions found yet.")),
      );
      return;
    }

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text("Share CSV session"),
                subtitle: Text("Tap a file to share it"),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final f = files[index];
                    final name = f.path.split('/').last;
                    return ListTile(
                      title: Text(name),
                      onTap: () async {
                        Navigator.of(context).pop();
                        await Share.shareXFiles(
                          [XFile(f.path)],
                          text: "MadePlus ShoeML session CSV: $name",
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Return windows of samples, not a flattened list.
  List<List<_RawSample>> _windows(
    List<_RawSample> buf, {
    double winSec = 3.0,
    double hopSec = 1.5,
  }) {
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
      final varr =
          x.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / n;
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

  // -------- Model list + active model helpers --------

   Future<void> _loadModelsAndActive() async {
  if (mounted) {
    setState(() => _loadingModels = true);
  }
  try {
    final root = await shoeMlRootDir();
    final dir = Directory("${root.path}/models");
    List<File> models = [];
    if (dir.existsSync()) {
      models = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith(".json"))
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    }

    final prefs = await SharedPreferences.getInstance();

    // New: multi-select list of active model paths
    final list = prefs.getStringList(kActiveModelPathsKey) ?? const [];
    final legacySingle = prefs.getString(kActiveModelPathKey);

    final paths = <String>{};
    paths.addAll(list);
    if (legacySingle != null && legacySingle.isNotEmpty) {
      // keep backward-compatibility
      paths.add(legacySingle);
    }

    if (mounted) {
      setState(() {
        _modelFiles = models;
        _activeModelPaths = paths;
      });
    }
  } catch (_) {
    if (mounted) {
      setState(() {
        _modelFiles = [];
        _activeModelPaths = {};
      });
    }
  } finally {
    if (mounted) {
      setState(() => _loadingModels = false);
    }
  }
}


Future<void> _toggleActiveModel(File f) async {
  try {
    final prefs = await SharedPreferences.getInstance();

    final paths = Set<String>.from(_activeModelPaths);
    if (paths.contains(f.path)) {
      paths.remove(f.path);
    } else {
      paths.add(f.path);
    }

    // Persist multi-select list
    await prefs.setStringList(kActiveModelPathsKey, paths.toList());

    // Keep old single-key roughly in sync with "first" active model (for backward-compat)
    if (paths.isNotEmpty) {
      await prefs.setString(kActiveModelPathKey, paths.first);
    } else {
      await prefs.remove(kActiveModelPathKey);
    }

    if (!mounted) return;
    setState(() {
      _activeModelPaths = paths;
    });

    final names =
        paths.map((p) => p.split('/').last).join(', ');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          paths.isEmpty
              ? "No active models selected."
              : "Active models: $names",
        ),
      ),
    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Failed to set active model(s): $e"),
      ),
    );
  }
}


  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool canStart = (_conn == DeviceConnectionState.connected);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          // -------- Collect samples --------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Collect samples",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Tap a label preset (you can even switch while recording), "
                    "then Start/Stop capture. CSV auto-saves on stop.",
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Label chips (multi-class presets)
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: _labels.map((lbl) {
                            final pretty = lbl.replaceAll('_', ' ');
                            return ChoiceChip(
                              label: Text(pretty),
                              selected: _label == lbl,
                              onSelected: (selected) {
                                if (!selected) return;
                                setState(() => _label = lbl);
                              },
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Start / Stop button
                      FilledButton.icon(
                        onPressed: _collecting
                            ? _toggleCollect // always allow Stop
                            : (canStart ? _toggleCollect : null),
                        icon: Icon(
                          _collecting
                              ? Icons.stop
                              : Icons.fiber_manual_record,
                        ),
                        label: Text(
                          _collecting ? "Stop & Save CSV" : "Start",
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _collecting
                        ? "Recording…"
                        : "Not recording. Last: ${_lastDistM.toStringAsFixed(1)} m in ${_lastDur.inSeconds}s",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // -------- Route (start → end) --------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Route (start → end)",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
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
                                  // No GPS yet → show placeholder
                                  return Container(
                                    color: Colors.grey[200],
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.location_searching,
                                            size: 48,
                                            color: Colors.grey[400],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Waiting for GPS...',
                                            style: TextStyle(
                                                color: Colors.grey[600]),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }

                                // Normal route map
                                return FlutterMap(
                                  mapController: _mapController,
                                  options: MapOptions(
                                    initialZoom: 16,
                                    initialCenter: validTrack.last,
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate:
                                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      userAgentPackageName:
                                          'com.madeplus.shoeml',
                                    ),

                                    // Polyline for route
                                    if (validTrack.length > 1)
                                      PolylineLayer(polylines: [
                                        Polyline(
                                          points: validTrack,
                                          strokeWidth: 4,
                                        )
                                      ]),

                                    // Start (flag) + End (pin)
                                    if (validTrack.isNotEmpty)
                                      MarkerLayer(markers: [
                                        Marker(
                                          width: 30,
                                          height: 30,
                                          point: validTrack.first,
                                          child: const Icon(
                                            Icons.flag,
                                            color: Colors.green,
                                          ),
                                        ),
                                        Marker(
                                          width: 30,
                                          height: 30,
                                          point: validTrack.last,
                                          child: const Icon(
                                            Icons.place,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ]),
                                  ],
                                );
                              } catch (e) {
                                // If FlutterMap throws for some reason
                                return Container(
                                  color: Colors.grey[200],
                                  child: Center(
                                    child: Text(
                                      'Map error',
                                      style:
                                          TextStyle(color: Colors.grey[600]),
                                    ),
                                  ),
                                );
                              }
                            },
                          ),

                          // Distance overlay at top-right
                          Positioned(
                            right: 8,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                'Dist: ${_formatDistance(_lastDistM)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Distance: ${_formatDistance(_lastDistM)} • "
                    "Duration: ${_formatDuration(_lastDur)} • "
                    "Pace: ${_formatPace(_lastDistM, _lastDur)}",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // -------- Train classifier (current buffer) --------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Train classifier",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Train a simple softmax classifier on the collected windowed features. "
                    "Windows are labeled using the majority label inside each window.",
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _modelNameCtrl,
                    decoration: const InputDecoration(
                      labelText: "Model base name",
                      hintText: "e.g., walk_run_v1",
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _buffer.length < 10 ? null : _trainAndSave,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text("Train & Save"),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // -------- Active model for live classification --------
          _activeModelCard(cs),

          const SizedBox(height: 12),

          // -------- Reports (PDF) - share & compare --------
          Card(
            child: ListTile(
              title: const Text("Share / Compare reports"),
              subtitle: const Text(
                "Browse all generated PDF reports, share them, or compare sessions",
              ),
              trailing: IconButton(
                icon: const Icon(Icons.picture_as_pdf),
                onPressed: _showShareReportsPicker,
              ),
            ),
          ),
        ],
      ),
    );
  }

Widget _activeModelCard(ColorScheme cs) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Active model for live classification",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            "Pick one or more trained JSON models. "
            "These will be loaded on the Dashboard when you tap "
            "\"Load active models\" and will be used together for live prediction.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),

          if (_loadingModels)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_modelFiles.isEmpty)
            Text(
              "No models found yet. Train & Save to create one.",
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            Column(
              children: _modelFiles.map((f) {
                final name = f.path.split('/').last;
                final isActive = _activeModelPaths.contains(f.path);

                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Checkbox(
                    value: isActive,
                    onChanged: (_) => _toggleActiveModel(f),
                  ),
                  title: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: isActive
                      ? Text(
                          "Active",
                          style: TextStyle(
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : null,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    color: cs.error,
                    tooltip: "Delete this model",
                    onPressed: () => _deleteModel(f),
                  ),
                  // Tapping row also toggles active state
                  onTap: () => _toggleActiveModel(f),
                );
              }).toList(),
            ),

          const SizedBox(height: 8),
          Text(
            _activeModelPaths.isEmpty
                ? "Current active: none"
                : "Current active: ${_activeModelPaths.map((p) => p.split('/').last).join(', ')}",
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}




  Future<bool> _ensureLocationPermission() async {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
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
    // Ask for location permission first
    final ok = await _ensureLocationPermission();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied')),
        );
      }
      return;
    }

    _tStart = DateTime.now();

    // ---- First fix-point (starting position) ----
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      // Defensive: ignore any bogus reading
      if (!pos.latitude.isFinite || !pos.longitude.isFinite) {
        return;
      }

      final first = LatLng(pos.latitude, pos.longitude);

      setState(() {
        _track = [first];
        _trackTs = [DateTime.now()];
      });

      // Center the map on the first point
      try {
        _mapController.move(first, 16);
      } catch (_) {}
    } catch (_) {
      // ignore; user will just see no route
    }

    // ---- Live updates with "no-move" filtering ----
    await _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 3, // OS wakes us when it thinks we moved ≥3 m
      ),
    ).listen((pos) {
      // Filter out bad coords
      if (!pos.latitude.isFinite || !pos.longitude.isFinite) return;

      final pt = LatLng(pos.latitude, pos.longitude);

      if (_track.isNotEmpty) {
        final last = _track.last;

        // Distance from last accepted point
        final dist = Geolocator.distanceBetween(
          last.latitude,
          last.longitude,
          pt.latitude,
          pt.longitude,
        );

        // Speed reported by GPS (m/s). Often 0 or -1 when standing still.
        final speed = pos.speed;

        // Tunable thresholds:
        const double minRealMoveDist = 8.0;   // meters – ignore jitter < 8 m
        const double minRealMoveSpeed = 0.5;  // m/s ≈ 1.8 km/h (slow walk)

        // Discard totally crazy jumps too
        final bool isCrazyJump = dist > 1000.0;

        // Treat as "still" if distance is tiny AND speed is basically 0
        final bool looksStationary =
            dist < minRealMoveDist &&
            (!speed.isFinite || speed < minRealMoveSpeed);

        if (isCrazyJump || looksStationary) {
          // Sensor is not really moving → do NOT extend route or distance
          return;
        }
      }

      // Only real movement reaches here
      setState(() {
        _track.add(pt);
        _trackTs.add(DateTime.now());
      });

      // Make the map actually follow the latest point
      try {
        _mapController.move(pt, _mapController.camera.zoom);
      } catch (_) {}
    });
  }


  Future<void> _stopLocation() async {
    await _posSub?.cancel();
    _posSub = null;
  }

  double _computeDistanceMeters() {
    if (_track.length < 2) return 0.0;
    double d = 0.0;
    for (int i = 1; i < _track.length; i++) {
      d += Geolocator.distanceBetween(
        _track[i - 1].latitude,
        _track[i - 1].longitude,
        _track[i].latitude,
        _track[i].longitude,
      );
    }
    return d;
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return "${meters.toStringAsFixed(1)} m";
    return "${(meters / 1000).toStringAsFixed(2)} km";
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return "${m}m ${s}s";
  }

  String _formatPace(double distM, Duration d) {
    if (distM <= 0 || d.inSeconds <= 0) return "-";
    final paceSecPerKm = d.inSeconds / (distM / 1000.0);
    final pm = paceSecPerKm ~/ 60;
    final ps = (paceSecPerKm % 60).round();
    return "${pm}m ${ps.toString().padLeft(2, '0')}s /km";
  }

  Future<void> _fitRoute() async {
    if (_track.length < 2) return;
    await Future.delayed(const Duration(milliseconds: 100));
    final bounds = _boundsFromTrack(_track);
    _mapController.fitCamera(CameraFit.bounds(
      bounds: bounds,
      padding: const EdgeInsets.all(20),
    ));
  }

  Future<String?> _saveGeoJson(File csvFile) async {
    if (_track.isEmpty) return null;
    final coords =
        _track.map((p) => [p.longitude, p.latitude]).toList(growable: false);
    final temps = _buffer
        .map((s) => s.tempC)
        .whereType<double>()
        .toList(growable: false);

    final feature = {
      "type": "Feature",
      "properties": {
        "label": _label,
        "distance_m": _lastDistM,
        "duration_s": _lastDur.inSeconds,
        "avg_pace_min_per_km": (_lastDistM > 0)
            ? (_lastDur.inSeconds / (_lastDistM / 1000.0)) / 60.0
            : null,
        "tempC_mean": temps.isNotEmpty
            ? temps.reduce((a, b) => a + b) / temps.length
            : null,
      },
      "geometry": {
        "type": "LineString",
        "coordinates": coords,
      },
    };

    final geo = {
      "type": "FeatureCollection",
      "features": [feature],
    };

    final dir = await _ensureDir(await _appDir(), "geojson");
    final name =
        csvFile.uri.pathSegments.last.replaceAll(".csv", ".geojson");
    final f = File("${dir.path}/$name");
    await f.writeAsString(jsonEncode(geo), flush: true);
    return f.path;
  }

  Future<String?> _saveGpx(File csvFile) async {
    if (_track.isEmpty) return null;
    final stamp = DateTime.now().toUtc().toIso8601String();
    final b = StringBuffer();
    b.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    b.writeln('<gpx version="1.1" creator="MadePlus ShoeML" '
        'xmlns="http://www.topografix.com/GPX/1/1">');
    b.writeln('<trk>');
    b.writeln('<name>${_label}</name>');
    b.writeln('<trkseg>');
    for (int i = 0; i < _track.length; i++) {
      final p = _track[i];
      final t = (i < _trackTs.length)
          ? _trackTs[i].toUtc().toIso8601String()
          : stamp;
      b.writeln(
          '<trkpt lat="${p.latitude}" lon="${p.longitude}"><time>$t</time></trkpt>');
    }
    b.writeln('</trkseg>');
    b.writeln('</trk>');
    b.writeln('</gpx>');

    final dir = await _ensureDir(await _appDir(), "ShoeML/gpx");
    final name =
        csvFile.uri.pathSegments.last.replaceAll(".csv", ".gpx");
    final f = File("${dir.path}/$name");
    await f.writeAsString(b.toString(), flush: true);
    return f.path;
  }

  Future<String?> _saveKml(File csvFile) async {
    if (_track.isEmpty) return null;
    final dir = await _ensureDir(await _appDir(), "ShoeML/kml");
    final stamp = DateFormat("yyyyMMdd_HHmmss").format(DateTime.now());
    final safeLabel = _label.replaceAll(RegExp(r'\W+'), '_');
    final name = "track_${safeLabel}_$stamp.kml";
    final f = File("${dir.path}/$name");

    final b = StringBuffer();
    b.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    b.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
    b.writeln('<Document>');
    b.writeln('  <name>$safeLabel</name>');
    b.writeln('  <Placemark>');
    b.writeln('    <name>$safeLabel</name>');
    b.writeln('    <LineString>');
    b.writeln('      <coordinates>');
    for (int i = 0; i < _track.length; i++) {
      final p = _track[i];
      final t = (i < _trackTs.length)
          ? _trackTs[i].toUtc().toIso8601String()
          : DateTime.now().toUtc().toIso8601String();
      b.writeln(
          '        ${p.longitude},${p.latitude},0 <!-- $t -->');
    }
    b.writeln('      </coordinates>');
    b.writeln('    </LineString>');
    b.writeln('  </Placemark>');
    b.writeln('</Document>');
    b.writeln('</kml>');

    await f.writeAsString(b.toString(), flush: true);
    return f.path;
  }

  Future<Uint8List?> _captureMapPng(File csvFile) async {
    final ctx = _mapKey.currentContext;
    if (ctx == null) return null;
    final boundary =
        ctx.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final img = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return null;

    final dir = await _ensureDir(await _appDir(), "maps");
    final name =
        csvFile.uri.pathSegments.last.replaceAll(".csv", ".png");
    final f = File("${dir.path}/$name");
    await f.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return bytes.buffer.asUint8List();
  }

  Future<void> _showSummarySheet(
      File csv,
      Uint8List? mapPng,
      String? geoJsonPath,
      String? gpxPath,
      String? kmlPath) async {
    final distTxt = _formatDistance(_lastDistM);
    final durTxt = _formatDuration(_lastDur);
    final paceTxt = _formatPace(_lastDistM, _lastDur);
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Session summary",
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text("Primary label now: $_label"),
              Text("Distance: $distTxt"),
              Text("Duration: $durTxt"),
              Text("Pace: $paceTxt"),
              const SizedBox(height: 8),
              if (mapPng != null)
                SizedBox(
                  height: 150,
                  child: Image.memory(mapPng, fit: BoxFit.cover),
                ),
              const SizedBox(height: 8),
              Text("CSV: ${csv.path.split('/').last}",
                  style: Theme.of(ctx).textTheme.bodySmall),
              if (geoJsonPath != null)
                Text("GeoJSON: ${geoJsonPath.split('/').last}",
                    style: Theme.of(ctx).textTheme.bodySmall),
              if (gpxPath != null)
                Text("GPX: ${gpxPath.split('/').last}",
                    style: Theme.of(ctx).textTheme.bodySmall),
              if (kmlPath != null)
                Text("KML: ${kmlPath.split('/').last}",
                    style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 12),

              // ---- NEW: PDF buttons ----
             Row(
  children: [
    Expanded(
      child: FilledButton.icon(
        icon: const Icon(Icons.picture_as_pdf),
        label: const Text("Generate report (PDF)"),
        onPressed: () async {
          Navigator.of(ctx).pop();
          try {
            final pdfFile = await _generateSessionPdf(csv, mapPng);
            if (!mounted) return;

            // Let user choose Open / Download / Share
            await _showReportActionSheet(pdfFile);
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Failed to generate report: $e"),
              ),
            );
          }
        },
      ),
    ),
    const SizedBox(width: 8),
    Expanded(
      child: OutlinedButton.icon(
        icon: const Icon(Icons.compare_arrows),
        label: const Text("Compare with previous"),
        onPressed: () async {
          Navigator.of(ctx).pop();
          await _showCompareWithPreviousSheet(csv);
        },
      ),
    ),
  ],
),

            ],
          ),
        );
      },
    );
  }

  // Build a LatLngBounds from the route
  LatLngBounds _boundsFromTrack(List<LatLng> pts) {
    double minLat = pts.first.latitude;
    double maxLat = pts.first.latitude;
    double minLon = pts.first.longitude;
    double maxLon = pts.first.longitude;

    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    const minSpan = 0.001;
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

  /// Recompute steps, cadence and stride length purely in the app
  /// using the recorded pitch signal and GPS distance.
  void _fillStepsCadenceStrideFromPitch() {
    if (_buffer.length < 3) return;

    final int n = _buffer.length;
    final times = List<double>.filled(n, 0.0);
    final pitches = List<double>.filled(n, 0.0);

    for (int i = 0; i < n; i++) {
      final s = _buffer[i];
      times[i] = s.t;
      pitches[i] = s.pitch ?? 0.0;
    }

    // ----- 1) Smooth baseline for pitch -----
    const double alpha = 0.01; // low-pass factor
    final baseline = List<double>.filled(n, 0.0);
    baseline[0] = pitches[0];
    for (int i = 1; i < n; i++) {
      baseline[i] =
          baseline[i - 1] + alpha * (pitches[i] - baseline[i - 1]);
    }

    // ----- 2) Detect steps via upward zero-crossings of (pitch - baseline) -----
    const double ampThresh = 5.0; // degrees
    const double minStepDt = 0.30; // seconds
    final stepTimes = <double>[];

    double lastCentered = pitches[0] - baseline[0];
    double lastStepTime = -1.0;

    for (int i = 1; i < n; i++) {
      final centered = pitches[i] - baseline[i];
      final bool upwardCross = (lastCentered <= 0.0 && centered > 0.0);
      final double dtFromLast =
          lastStepTime < 0 ? 999.0 : (times[i] - lastStepTime);

      if (upwardCross &&
          centered.abs() >= ampThresh &&
          dtFromLast >= minStepDt) {
        stepTimes.add(times[i]);
        lastStepTime = times[i];
      }

      lastCentered = centered;
    }

    // ----- 3) Cumulative steps per sample -----
    final stepsPerSample = List<int>.filled(n, 0);
    int stepIdx = 0;
    int cumSteps = 0;
    for (int i = 0; i < n; i++) {
      final t = times[i];
      while (stepIdx < stepTimes.length && stepTimes[stepIdx] <= t) {
        cumSteps++;
        stepIdx++;
      }
      stepsPerSample[i] = cumSteps;
    }

    // ----- 4) Cadence per sample (trailing 10 s window) -----
    const double windowSec = 10.0;
    final cadencePerSample = List<double>.filled(n, 0.0);
    int left = 0;
    int right = 0;

    for (int i = 0; i < n; i++) {
      final t = times[i];
      final tMin = t - windowSec;

      while (left < stepTimes.length && stepTimes[left] < tMin) {
        left++;
      }
      while (right < stepTimes.length && stepTimes[right] <= t) {
        right++;
      }

      final count = right - left;
      if (count >= 2) {
        final firstT = stepTimes[left];
        final lastT = stepTimes[right - 1];
        final dur = lastT - firstT;
        if (dur > 0) {
          final freqHz = (count - 1) / dur;
          cadencePerSample[i] = freqHz * 60.0; // steps/min
        }
      }
    }

    // ----- 5) Average stride length for the whole session -----
    double strideM = 0.0;
    final int totalSteps =
        stepsPerSample.isNotEmpty ? stepsPerSample.last : 0;
    if (totalSteps > 0 && _lastDistM > 0) {
      strideM = _lastDistM / totalSteps;
    }

    // ----- 6) Write back into _buffer -----
    for (int i = 0; i < n; i++) {
      final s = _buffer[i];
      s.steps = stepsPerSample[i];
      s.cadence = cadencePerSample[i];
      s.strideM = strideM;
    }
  }

  // Helper to get valid track points
  List<LatLng> get _validTrack {
    return _track
        .where((p) =>
            !p.latitude.isNaN &&
            !p.latitude.isInfinite &&
            !p.longitude.isNaN &&
            !p.longitude.isInfinite &&
            p.latitude.abs() <= 90 &&
            p.longitude.abs() <= 180)
        .toList();
  }
  
    // Save a report PDF to a user-visible "Downloads" / exports folder
  Future<File> _saveReportToDownloads(File src) async {
    Directory targetDir;

    try {
      if (Platform.isAndroid) {
        // Try the public Downloads folder first
        Directory? dir;
        final dl = Directory('/storage/emulated/0/Download');
        if (dl.existsSync()) {
          dir = dl;
        } else {
          // Fallback: app-specific external storage
          dir = await getExternalStorageDirectory();
        }
        targetDir = dir ?? await _ensureDir(await _appDir(), "exports");
      } else if (Platform.isIOS) {
        // iOS: use an "exports" subfolder in app docs, visible via Files app
        targetDir = await _ensureDir(await _appDir(), "exports");
      } else {
        // Desktop platforms: use downloads directory if available
        final d = await getDownloadsDirectory();
        if (d != null) {
          targetDir = d;
        } else {
          targetDir = await _ensureDir(await _appDir(), "exports");
        }
      }

      final name = src.uri.pathSegments.last;
      final dest = File("${targetDir.path}/$name");
      return await src.copy(dest.path);
    } catch (_) {
      // Last-resort fallback: put it into app's exports folder
      final fallbackDir = await _ensureDir(await _appDir(), "exports");
      final name = src.uri.pathSegments.last;
      final dest = File("${fallbackDir.path}/$name");
      return await src.copy(dest.path);
    }
  }
    Future<void> _confirmDeleteReport(File f) async {
    final name = f.path.split('/').last;
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: const Text("Delete report?"),
              content: Text(
                "Do you want to permanently delete the report file:\n\n$name",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text("Cancel"),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text(
                    "Delete",
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;

    if (ok) {
      await _deleteReportFile(f);
    }
  }

  Future<void> _deleteReportFile(File f) async {
    try {
      final exists = await f.exists();
      if (exists) {
        await f.delete();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Deleted report: ${f.path.split('/').last}"),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to delete report: $e"),
        ),
      );
    }
  }


  // Open a report PDF in a system viewer / print dialog
  Future<void> _openReportPdf(File f) async {
    try {
      final bytes = await f.readAsBytes();
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytes,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to open PDF: $e")),
      );
    }
  }

  // Download (copy) the report to a user-visible folder and show where it went
  Future<void> _downloadReport(File f) async {
    try {
      final saved = await _saveReportToDownloads(f);
      if (!mounted) return;
      final filename = saved.path.split('/').last;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Saved $filename to:\n${saved.path}"),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save report: $e")),
      );
    }
  }

  // Bottom sheet with actions for a single report
  Future<void> _showReportActionSheet(File f) async {
    if (!mounted) return;
    final name = f.path.split('/').last;

    await showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text("Open / view"),
                subtitle: const Text("Preview, print or export"),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _openReportPdf(f);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text("Download to device"),
                subtitle: const Text("Copy into Downloads / exports folder"),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _downloadReport(f);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text("Share"),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await Share.shareXFiles(
                    [XFile(f.path)],
                    text: "MadePlus ShoeML report: $name",
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }


  /* ---------------------------------------------------------------------- */
  /*                     PDF & COMPARISON HELPERS (NEW)                     */
  /* ---------------------------------------------------------------------- */

  Future<_SessionSummary> _readSessionSummary(File f) async {
    final lines = await f.readAsLines();

    double? distanceM;
    Duration? duration;
    String? paceText;

    int idx = 0;
    for (; idx < lines.length; idx++) {
      final line = lines[idx];
      if (!line.startsWith('#')) break;
      if (line.startsWith('# distance_m=')) {
        distanceM = double.tryParse(line.split('=').last.trim());
      } else if (line.startsWith('# duration_s=')) {
        final s = int.tryParse(line.split('=').last.trim());
        if (s != null) duration = Duration(seconds: s);
      } else if (line.startsWith('# pace=')) {
        paceText = line.split('=').last.trim();
      }
    }

    if (idx >= lines.length) {
      return _SessionSummary(
        file: f,
        label: null,
        distanceM: distanceM,
        duration: duration,
        paceText: paceText,
        totalSteps: null,
        avgCadence: null,
        avgStride: null,
        avgTempC: null,
      );
    }

    final dataLines =
        lines.skip(idx + 1);

    int maxSteps = 0;
    int nCad = 0;
    double sumCad = 0;
    int nStride = 0;
    double sumStride = 0;
    int nTemp = 0;
    double sumTemp = 0;
    final Map<String, int> labelCounts = {};

    for (final row in dataLines) {
      if (row.trim().isEmpty) continue;
      final parts = row.split(',');
      if (parts.length < 10) continue;

      final tempStr = parts[4].trim();
      final stepsStr = parts[5].trim();
      final cadenceStr = parts[6].trim();
      final strideStr = parts[7].trim();
      final labelStr = parts[9].trim();

      if (tempStr.isNotEmpty) {
        final v = double.tryParse(tempStr);
        if (v != null) {
          sumTemp += v;
          nTemp++;
        }
      }
      if (stepsStr.isNotEmpty) {
        final v = int.tryParse(stepsStr);
        if (v != null && v > maxSteps) maxSteps = v;
      }
      if (cadenceStr.isNotEmpty) {
        final v = double.tryParse(cadenceStr);
        if (v != null) {
          sumCad += v;
          nCad++;
        }
      }
      if (strideStr.isNotEmpty) {
        final v = double.tryParse(strideStr);
        if (v != null) {
          sumStride += v;
          nStride++;
        }
      }
      if (labelStr.isNotEmpty) {
        labelCounts[labelStr] = (labelCounts[labelStr] ?? 0) + 1;
      }
    }

    final avgCad = nCad > 0 ? sumCad / nCad : null;
    final avgStride = nStride > 0 ? sumStride / nStride : null;
    final avgTemp = nTemp > 0 ? sumTemp / nTemp : null;

    String? mainLabel;
    if (labelCounts.isNotEmpty) {
      mainLabel = labelCounts.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
    }

    return _SessionSummary(
      file: f,
      label: mainLabel,
      distanceM: distanceM,
      duration: duration,
      paceText: paceText,
      totalSteps: maxSteps == 0 ? null : maxSteps,
      avgCadence: avgCad,
      avgStride: avgStride,
      avgTempC: avgTemp,
    );
  }

  Future<File> _generateSessionPdf(File csvFile, Uint8List? mapPng) async {
    final lines = await csvFile.readAsLines();

    double? distanceM;
    Duration? duration;
    String? paceText;

    int idx = 0;
    for (; idx < lines.length; idx++) {
      final line = lines[idx];
      if (!line.startsWith('#')) break;
      if (line.startsWith('# distance_m=')) {
        distanceM = double.tryParse(line.split('=').last.trim());
      } else if (line.startsWith('# duration_s=')) {
        final s = int.tryParse(line.split('=').last.trim());
        if (s != null) duration = Duration(seconds: s);
      } else if (line.startsWith('# pace=')) {
        paceText = line.split('=').last.trim();
      }
    }

    final dataLines = idx < lines.length
        ? lines.skip(idx + 1)
        : const Iterable<String>.empty();

    int maxSteps = 0;
    int nCad = 0;
    double sumCad = 0;
    int nStride = 0;
    double sumStride = 0;
    int nTemp = 0;
    double sumTemp = 0;
    final Map<String, int> labelCounts = {};

    for (final row in dataLines) {
      if (row.trim().isEmpty) continue;
      final parts = row.split(',');
      if (parts.length < 10) continue;

      final tempStr = parts[4].trim();
      final stepsStr = parts[5].trim();
      final cadenceStr = parts[6].trim();
      final strideStr = parts[7].trim();
      final labelStr = parts[9].trim();

      if (tempStr.isNotEmpty) {
        final v = double.tryParse(tempStr);
        if (v != null) {
          sumTemp += v;
          nTemp++;
        }
      }
      if (stepsStr.isNotEmpty) {
        final v = int.tryParse(stepsStr);
        if (v != null && v > maxSteps) maxSteps = v;
      }
      if (cadenceStr.isNotEmpty) {
        final v = double.tryParse(cadenceStr);
        if (v != null) {
          sumCad += v;
          nCad++;
        }
      }
      if (strideStr.isNotEmpty) {
        final v = double.tryParse(strideStr);
        if (v != null) {
          sumStride += v;
          nStride++;
        }
      }
      if (labelStr.isNotEmpty) {
        labelCounts[labelStr] = (labelCounts[labelStr] ?? 0) + 1;
      }
    }

    final avgCad = nCad > 0 ? sumCad / nCad : 0.0;
    final avgStride = nStride > 0 ? sumStride / nStride : 0.0;
    final avgTemp = nTemp > 0 ? sumTemp / nTemp : 0.0;
    final totalSteps = maxSteps;
    String? mainLabel;
    if (labelCounts.isNotEmpty) {
      mainLabel = labelCounts.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              'MadePlus ShoeML – Session Report',
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            csvFile.path.split('/').last,
            style: pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 12),
          pw.Text('Summary',
              style: pw.TextStyle(
                  fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Table.fromTextArray(
            headers: ['Metric', 'Value'],
            data: [
              ['Primary label', mainLabel ?? '-'],
              [
                'Distance',
                distanceM != null ? _formatDistance(distanceM) : '-'
              ],
              [
                'Duration',
                duration != null ? _formatDuration(duration) : '-'
              ],
              ['Pace', paceText ?? '-'],
              ['Total steps', totalSteps.toString()],
              [
                'Avg cadence',
                nCad > 0 ? '${avgCad.toStringAsFixed(1)} spm' : '-'
              ],
              [
                'Stride length',
                nStride > 0 ? '${avgStride.toStringAsFixed(2)} m' : '-'
              ],
              [
                'Avg temperature',
                nTemp > 0 ? '${avgTemp.toStringAsFixed(1)} °C' : '-'
              ],
            ],
          ),
          if (mapPng != null) ...[
            pw.SizedBox(height: 16),
            pw.Text('Route preview',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Center(
              child:
                  pw.Image(pw.MemoryImage(mapPng), height: 200),
            ),
          ],
          pw.SizedBox(height: 16),
          pw.Text('Label distribution',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          if (labelCounts.isNotEmpty)
            pw.Table.fromTextArray(
              headers: ['Label', 'Samples'],
              data: labelCounts.entries
                  .map((e) => [e.key, e.value.toString()])
                  .toList(),
            )
          else
            pw.Text('No label information found in CSV.'),
        ],
      ),
    );

    final reportsDir =
        await _ensureDir(await _appDir(), 'reports');
    final pdfName =
        csvFile.uri.pathSegments.last.replaceAll('.csv', '.pdf');
    final outFile = File('${reportsDir.path}/$pdfName');
    await outFile.writeAsBytes(await pdf.save());
    return outFile;
  }

  Future<void> _showCompareWithPreviousSheet(File currentCsv) async {
    final all = await _recentSessionCsvFiles(limit: 50);
    final others =
        all.where((f) => f.path != currentCsv.path).toList();

    if (others.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No other sessions to compare with."),
        ),
      );
      return;
    }

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text("Compare with previous session"),
                subtitle:
                    Text("Choose another CSV to build comparison PDF"),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: others.length,
                  itemBuilder: (context, index) {
                    final f = others[index];
                    final name = f.path.split('/').last;
                    return ListTile(
                      title: Text(name),
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        try {
                          final pdfFile =
                              await _generateComparisonPdf(
                                  currentCsv, f);
                          if (!mounted) return;
                          await Share.shareXFiles(
                            [XFile(pdfFile.path)],
                            text:
                                "MadePlus ShoeML comparison report: ${pdfFile.path.split('/').last}",
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context)
                              .showSnackBar(
                            SnackBar(
                              content: Text(
                                  "Failed to generate comparison: $e"),
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// List recent PDF reports (up to [limit]) from shoeml/reports
  Future<List<File>> _recentReportPdfFiles({int limit = 50}) async {
    final dir = await _ensureDir(await _appDir(), "reports");
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith(".pdf"))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    if (files.length > limit) {
      return files.sublist(0, limit);
    }
    return files;
  }

  /// Try to find the CSV session that corresponds to a given PDF report.
  /// Handles both "name.pdf" -> "name.csv" and "name_report.pdf" -> "name.csv".
  Future<File?> _csvForReport(File pdf) async {
    final sessionsDir =
        await _ensureDir(await _appDir(), "sessions");
    final pdfName = pdf.uri.pathSegments.last;

    // Guess 1: strip "_report.pdf" → .csv
    final guess1Name = pdfName.replaceAll("_report.pdf", ".csv");
    final guess1 = File("${sessionsDir.path}/$guess1Name");
    if (guess1.existsSync()) return guess1;

    // Guess 2: strip ".pdf" → .csv
    final guess2Name = pdfName.replaceAll(".pdf", ".csv");
    final guess2 = File("${sessionsDir.path}/$guess2Name");
    if (guess2.existsSync()) return guess2;

    return null;
  }

  /// Bottom sheet: list all PDF reports, allow share + compare.
    /// Bottom sheet: list all PDF reports, allow open / download / share + compare.
   Future<void> _showShareReportsPicker() async {
    final files = await _recentReportPdfFiles(limit: 50);
    if (files.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "No PDF reports found yet. Generate one from a session first.",
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text("Reports (PDF)"),
                subtitle: Text(
                  "Tap to view / download / share • use compare to analyze vs other sessions • use the bin icon to delete",
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final f = files[index];
                    final name = f.path.split('/').last;
                    return ListTile(
                      title: Text(name),
                      onTap: () async {
                        // Open actions: Open / Download / Share
                        Navigator.of(ctx).pop();
                        await _showReportActionSheet(f);
                      },
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.compare),
                            tooltip: "Compare this report",
                            onPressed: () async {
                              Navigator.of(ctx).pop();
                              final csv = await _csvForReport(f);

                              if (!mounted) return;
                              if (csv == null || !csv.existsSync()) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      "No matching CSV found for $name",
                                    ),
                                  ),
                                );
                                return;
                              }

                              await _showCompareWithPreviousSheet(csv);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: "Delete this report",
                            onPressed: () async {
                              // Close the list, then confirm + delete
                              Navigator.of(ctx).pop();
                              await _confirmDeleteReport(f);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }



  Future<File> _generateComparisonPdf(File a, File b) async {
    final sa = await _readSessionSummary(a);
    final sb = await _readSessionSummary(b);

    final pdf = pw.Document();

    pw.Widget tableFor(_SessionSummary s, String title) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title,
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Table.fromTextArray(
            headers: ['Metric', 'Value'],
            data: [
              ['File', s.file.path.split('/').last],
              ['Primary label', s.label ?? '-'],
              [
                'Distance',
                s.distanceM != null
                    ? _formatDistance(s.distanceM!)
                    : '-'
              ],
              [
                'Duration',
                s.duration != null
                    ? _formatDuration(s.duration!)
                    : '-'
              ],
              ['Pace', s.paceText ?? '-'],
              [
                'Total steps',
                s.totalSteps != null ? s.totalSteps.toString() : '-'
              ],
              [
                'Avg cadence',
                s.avgCadence != null
                    ? '${s.avgCadence!.toStringAsFixed(1)} spm'
                    : '-'
              ],
              [
                'Stride length',
                s.avgStride != null
                    ? '${s.avgStride!.toStringAsFixed(2)} m'
                    : '-'
              ],
              [
                'Avg temp',
                s.avgTempC != null
                    ? '${s.avgTempC!.toStringAsFixed(1)} °C'
                    : '-'
              ],
            ],
          ),
        ],
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              'MadePlus ShoeML – Session Comparison',
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: tableFor(sa, 'Session A')),
              pw.SizedBox(width: 16),
              pw.Expanded(child: tableFor(sb, 'Session B')),
            ],
          ),
        ],
      ),
    );

    final dir = await _ensureDir(await _appDir(), "reports");
    final pdfName =
        "compare_${a.uri.pathSegments.last.replaceAll('.csv', '')}_vs_${b.uri.pathSegments.last.replaceAll('.csv', '')}.pdf";
    final outFile = File("${dir.path}/$pdfName");
    await outFile.writeAsBytes(await pdf.save());
    return outFile;
  }
}

/// Single sample in the training buffer
class _RawSample {
  _RawSample(
    this.t,
    this.roll,
    this.pitch,
    this.yaw,
    this.tempC,
    this.cadence,
    this.strideM,
    this.dH, {
    this.steps,
    this.labelIdx,
  });

  double t;
  double? roll, pitch, yaw, tempC, cadence, strideM, dH;
  int? steps; // app-computed step count (cumulative)
  int? labelIdx; // index into _labels at the time of sampling
}

class _SessionSummary {
  _SessionSummary({
    required this.file,
    required this.label,
    required this.distanceM,
    required this.duration,
    required this.paceText,
    required this.totalSteps,
    required this.avgCadence,
    required this.avgStride,
    required this.avgTempC,
  });

  final File file;
  final String? label;
  final double? distanceM;
  final Duration? duration;
  final String? paceText;
  final int? totalSteps;
  final double? avgCadence;
  final double? avgStride;
  final double? avgTempC;
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
                "3) Graphs tab shows smooth lines for R/P/Y and temperature.\n"
                "4) Training tab: choose a label, Start → Stop (auto-saves CSV),\n"
                "   then Train & Save to create a model JSON.\n"
                "5) On the Training tab, use \"Active model for live classification\" to mark\n"
                "   which model JSON should be used for live predictions.\n"
                "6) Go back to Dashboard and tap \"Load active model\", then walk/run with\n"
                "   the shoe connected to see live predictions and confidence.\n\n"
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
/*                              SOFTMAX CLASSIFIER                            */
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
      final d = ByteData.sublistView(Uint8List.fromList(b))
          .getFloat32(0, Endian.little);
      if (d.isNaN || d.isInfinite) return null;
      if (d < -50 || d > 120) return null; // sanity
      return d;
    }
    if (b.length >= 2) {
      final s = ByteData.sublistView(Uint8List.fromList(b))
          .getInt16(0, Endian.little);
      return s / 100.0; // some firmwares send centi-degC
    }
  } catch (_) {}
  return null;
}

// ---------------------------------------------------------------------------
// Shared helper: ShoeML root dir + runtime model loader
// ---------------------------------------------------------------------------

const String kActiveModelPathKey = 'shoeml_active_model_path'; // NEW: list of active models
const String kActiveModelPathsKey = 'shoeml_active_model_paths';   // legacy single-model key
const String kLiveConfThresholdKey = 'shoeml_live_conf_threshold';
const String kEnabledLiveLabelsKey = 'shoeml_live_enabled_labels';



Future<Directory> shoeMlRootDir() async {
  final d = await getApplicationDocumentsDirectory();
  final dir = Directory("${d.path}/shoeml");
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

/// Runtime wrapper for a trained softmax model saved as JSON:
/// {
///   "labels": ["walking","running",...],
///   "W": [[...], [...], ...],
///   "b": [...]
/// }

/// Common interface for any activity model (single or ensemble).
abstract class ActivityModel {
  List<String> get labels;
  MapEntry<String, double> predictLabel(List<double> x);
}

class LoadedActivityModel implements ActivityModel {
  LoadedActivityModel({
    required this.labels,
    required this.W,
    required this.b,
  });

  final List<String> labels;
  final List<List<double>> W;
  final List<double> b;

  factory LoadedActivityModel.fromJson(Map<String, dynamic> j) {
    final rawLabels = (j["labels"] as List? ?? const []);
    final labels = rawLabels.map((e) => e.toString()).toList();

    final rawW = (j["W"] as List? ?? const []);
    final W = rawW
        .map<List<double>>(
          (row) => (row as List)
              .map<double>((v) => (v as num).toDouble())
              .toList(),
        )
        .toList();

    final rawB = (j["b"] as List? ?? const []);
    final b = rawB.map<double>((v) => (v as num).toDouble()).toList();

    return LoadedActivityModel(labels: labels, W: W, b: b);
  }

  /// Compute logits z = W x + b
  List<double> _z(List<double> x) {
    final C = W.length;
    if (C == 0) return const <double>[];
    final D = W[0].length;

    // Ensure x length matches D by padding/truncating
    final xx = x.length == D
        ? x
        : () {
            final v = List<double>.filled(D, 0.0);
            for (int i = 0; i < D && i < x.length; i++) {
              v[i] = x[i];
            }
            return v;
          }();

    final out = List<double>.filled(C, 0.0);
    for (int k = 0; k < C; k++) {
      double s = 0.0;
      final row = W[k];
      for (int j = 0; j < row.length && j < xx.length; j++) {
        s += row[j] * xx[j];
      }
      if (k < b.length) s += b[k];
      out[k] = s;
    }
    return out;
  }

  List<double> _softmax(List<double> z) {
    if (z.isEmpty) return const <double>[];
    final m = z.reduce(math.max);
    final exps = z.map((v) => math.exp(v - m)).toList();
    final sum = exps.fold<double>(0.0, (a, b) => a + b);
    if (sum == 0.0) {
      final p = 1.0 / exps.length;
      return List<double>.filled(exps.length, p);
    }
    return exps.map((v) => v / sum).toList();
  }

  /// New: return probability for each label
  Map<String, double> predictProbs(List<double> x) {
    final z = _z(x);
    if (z.isEmpty) return const <String, double>{};
    final p = _softmax(z);

    final out = <String, double>{};
    for (int i = 0; i < p.length && i < labels.length; i++) {
      out[labels[i]] = p[i];
    }
    return out;
  }

  /// Old API: best label + probability
  MapEntry<String, double> predictLabel(List<double> x) {
    final probs = predictProbs(x);
    if (probs.isEmpty) return const MapEntry<String, double>('-', 0.0);

    String bestLabel = probs.keys.first;
    double bestP = probs[bestLabel] ?? 0.0;

    probs.forEach((lbl, v) {
      if (v > bestP) {
        bestP = v;
        bestLabel = lbl;
      }
    });

    return MapEntry(bestLabel, bestP);
  }
}
/// Simple ensemble: uses multiple models and picks the label with the highest
/// confidence across all of them (mixture-of-experts style).
class EnsembleActivityModel implements ActivityModel {
  EnsembleActivityModel(this.models);

  final List<LoadedActivityModel> models;

  @override
  List<String> get labels {
    final set = <String>{};
    for (final m in models) {
      set.addAll(m.labels);
    }
    return set.toList();
  }

  @override
  MapEntry<String, double> predictLabel(List<double> x) {
    if (models.isEmpty) return const MapEntry('-', 0.0);

    String bestLabel = '-';
    double bestConf = -1.0;

    for (final m in models) {
      final pred = m.predictLabel(x);
      if (pred.value > bestConf) {
        bestConf = pred.value;
        bestLabel = pred.key;
      }
    }

    if (bestConf < 0) bestConf = 0.0;
    return MapEntry(bestLabel, bestConf);
  }
}


