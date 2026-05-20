// MadePlus SHOEML — Dashboard, Graphs, Training, Tutorial
// All pages are inlined here. Delete any separate dashboard_page.dart,
// graphs_page.dart, and training_page.dart from lib/pages/ to avoid
// duplicate-definition build errors — this file supersedes them.
//
// Imports required in pubspec.yaml:
//   flutter_reactive_ble, permission_handler, app_settings, fl_chart,
//   path_provider, intl, share_plus, geolocator, flutter_map,
//   latlong2, pdf, printing, shared_preferences

import 'dart:async';
import 'package:archive/archive_io.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_settings/app_settings.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connect_home_page.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = FlutterError.presentError;
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('[App] Uncaught error: $error');
    return true;
  };
  runZonedGuarded(() => runApp(const ShoeMLApp()), (e, st) => debugPrint('[Zone] $e'));
}

// ---------------------------------------------------------------------------
// App root
// ---------------------------------------------------------------------------

class ShoeMLApp extends StatefulWidget {
  const ShoeMLApp({super.key});
  @override
  State<ShoeMLApp> createState() => _ShoeMLAppState();
}

class _ShoeMLAppState extends State<ShoeMLApp> with WidgetsBindingObserver {
  // BLE singleton — DECLARED FIRST, before build()
  final ShoeBle _ble = ShoeBle();
  Color _seed = const Color(0xFF00639A);
  ThemeMode _mode = ThemeMode.system;

 @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Screen unlocked / app foregrounded — re-enable reconnect and
        // restore the BLE session if it dropped while backgrounded.
        unawaited(_ble.onAppResumed());
        break;
      case AppLifecycleState.detached:
        // App terminated by OS — full clean shutdown.
        unawaited(_ble.shutdownForAppClose());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // inactive = screen dim / notification shade / incoming call.
        // paused  = app backgrounded.
        // BLE connections survive both on Android; do nothing here.
        // The auto-reconnect timer handles any drops without help.
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ble.dispose();
    super.dispose();
  }

  Future<void> _pickColor(BuildContext context) async {
    final presets = [
      const Color(0xFF00639A), const Color(0xFF00796B), const Color(0xFF7B1FA2),
      const Color(0xFF2E7D32), const Color(0xFFEF6C00), const Color(0xFFAD1457),
    ];
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Pick theme color'),
        content: Wrap(spacing: 10, runSpacing: 10, children: presets.map((c) => InkWell(
          onTap: () { setState(() => _seed = c); Navigator.pop(context); },
          child: Container(width: 36, height: 36,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.black12))),
        )).toList()),
        actions: [
          TextButton(onPressed: () => setState(() => _mode = ThemeMode.light),  child: const Text('Light')),
          TextButton(onPressed: () => setState(() => _mode = ThemeMode.dark),   child: const Text('Dark')),
          TextButton(onPressed: () => setState(() => _mode = ThemeMode.system), child: const Text('System')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: _seed,
      brightness: _mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
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
        bleStatus$: _ble.adapterStatus$,
        dashboardBuilder: (_) => HomeShell(ble: _ble, onPickColor: () => _pickColor(context)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Home shell
// ---------------------------------------------------------------------------

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.ble, required this.onPickColor});
  final ShoeBle ble;
  final VoidCallback onPickColor;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  @override
  void initState() { super.initState(); _ensurePerms(); }

  Future<void> _ensurePerms() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect,
           Permission.locationWhenInUse, Permission.storage].request();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(ble: widget.ble),
      GraphsPage(ble: widget.ble),
      TrainingPage(ble: widget.ble),
      const ReplayPage(),
      const TutorialPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Image.asset('assets/madeplus_logo.png', height: 28,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          const SizedBox(width: 8),
          const Text('SMARTSHOE'),
        ]),
        actions: [
          IconButton(tooltip: 'Theme', onPressed: widget.onPickColor, icon: const Icon(Icons.palette_outlined)),
          IconButton(tooltip: 'Bluetooth settings',
            onPressed: () async {
              try { await AppSettings.openAppSettings(type: AppSettingsType.bluetooth); }
              catch (_) { await AppSettings.openAppSettings(); }
            },
            icon: const Icon(Icons.bluetooth)),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.show_chart),         label: 'Graphs'),
          NavigationDestination(icon: Icon(Icons.school_outlined),    label: 'Training'),
          NavigationDestination(icon: Icon(Icons.replay_outlined),    label: 'Replay'),
          NavigationDestination(icon: Icon(Icons.help_outline),       label: 'Tutorial'),
        ],
      ),
    );
  }
}

/* ========================================================================= */
/*                                    BLE                                     */
/* ========================================================================= */

class ShoeBle {
  // Public streams
  final _connState   = StreamController<DeviceConnectionState>.broadcast();
  final _rssiCtrl    = StreamController<int?>.broadcast();
  final _roll$       = StreamController<double>.broadcast();
  final _pitch$      = StreamController<double>.broadcast();
  final _yaw$        = StreamController<double>.broadcast();
  final _steps$      = StreamController<int>.broadcast();
  final _cadence$    = StreamController<double>.broadcast();
  final _stride$     = StreamController<double>.broadcast();
  final _dh$         = StreamController<double>.broadcast();
  final _tempCtrl    = StreamController<double?>.broadcast();
  final _stepsACtrl  = StreamController<int>.broadcast();
  final _cadenceACtrl= StreamController<double>.broadcast();
  final _strideACtrl = StreamController<double>.broadcast();

  Stream<DeviceConnectionState> get connection$    => _connState.stream;
  Stream<int?>   get rssi$                         => _rssiCtrl.stream;
  Stream<double> get roll$                         => _roll$.stream;
  Stream<double> get pitch$                        => _pitch$.stream;
  Stream<double> get yaw$                          => _yaw$.stream;
  Stream<int>    get steps$                        => _steps$.stream;
  Stream<double> get cadence$                      => _cadence$.stream;
  Stream<double> get stride$                       => _stride$.stream;
  Stream<double> get dh$                           => _dh$.stream;
  Stream<double?> get temp$                        => _tempCtrl.stream;
  Stream<int>    get stepsAnalytic$                => _stepsACtrl.stream;
  Stream<double> get cadenceAnalytic$              => _cadenceACtrl.stream;
  Stream<double> get strideAnalytic$               => _strideACtrl.stream;

  // Internal
  final _ble = FlutterReactiveBle();
  String? _deviceId;
  bool _shouldReconnect = false;
  Timer? _reconnectTimer, _rssiTimer;
  static const String _prefsKey = 'shoeml_last_device_id';

  final Uuid serviceUuid = Uuid.parse('0000feed-0000-1000-8000-00805f9b34fb');
  final Uuid rollUuid    = Uuid.parse('0000a001-0000-1000-8000-00805f9b34fb');
  final Uuid pitchUuid   = Uuid.parse('0000a002-0000-1000-8000-00805f9b34fb');
  final Uuid yawUuid     = Uuid.parse('0000a003-0000-1000-8000-00805f9b34fb');
  final Uuid tempUuid    = Uuid.parse('0000b001-0000-1000-8000-00805f9b34fb');
  final Uuid stepsUuid   = Uuid.parse('0000c001-0000-1000-8000-00805f9b34fb');
  final Uuid cadenceUuid = Uuid.parse('0000c002-0000-1000-8000-00805f9b34fb');
  final Uuid strideUuid  = Uuid.parse('0000c003-0000-1000-8000-00805f9b34fb');
  final Uuid altdhUuid   = Uuid.parse('0000b002-0000-1000-8000-00805f9b34fb');

  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _sRoll,_sPitch,_sYaw,_sTemp,_sSteps,_sCad,_sStride,_sDh;
  
  DeviceConnectionState _currentConn = DeviceConnectionState.disconnected;
  DeviceConnectionState get currentConnectionState => _currentConn;
  /// True when the BLE connection is fully established and notifying.
  bool get isConnected => _currentConn == DeviceConnectionState.connected;
  // Public getter — avoids accessing private _deviceId from outside ShoeBle
  String? get connectedId => _deviceId;

  /// Adapter state stream — poweredOn, poweredOff, unauthorized, etc.
  Stream<BleStatus> get adapterStatus$ => _ble.statusStream;

  // Analytics state
  // Firmware-derived step tracking — replaces pitch analytic detector.
  int    _cumSteps    = 0;   // last received firmware count
  int    _baseSteps   = 0;   // firmware count at session start
  int    _sessionSteps = 0;  // current session-relative count

  /// Session-relative step count — 0 at connect, increments with each step.
  /// Use this to seed the dashboard display on subscribe.
  int get currentSessionSteps => _sessionSteps;
  double _lastStepWall = -1; // wall-clock seconds of last firmware step event
  Timer? _cadenceDecayTimer;
  double _lastCadence = 0;
  double _lastEmittedCadence = 0;
  final List<double> _stepWallTimes = []; // wall-clock timestamps for cadence
  // Legacy fields kept only for _resetAnalytics signature compatibility
  double _tA=0,_baseline=0,_lastCentered=0,_lastStepT=-1,_lastStride=0;
  bool _baselineInit=false; DateTime? _lastPitchTs;

  // ── API ──────────────────────────────────────────────────────────────────

  Future<DiscoveredDevice?> scanOnce({Duration timeout=const Duration(seconds:6)}) async {
    DiscoveredDevice? found;
    final sub=_ble.scanForDevices(withServices:[serviceUuid]).listen((d)=>found??=d,onError:(_){});
    await Future.delayed(timeout);
    await sub.cancel();
    return found;
  }

  Future<void> connect(String id) async {
    await disconnect(clearLastDevice:false);
    _shouldReconnect=true; _deviceId=id;
    await _saveId(id); _resetAnalytics();
    await _attempt(id);
  }

  Future<void> _attempt(String id) async {
    if(!_shouldReconnect) return;
    await _connSub?.cancel();
    _connSub=_ble.connectToDevice(id:id).listen((u) async {
	_currentConn = u.connectionState;
      if(!_connState.isClosed) _connState.add(u.connectionState);
      if(u.connectionState==DeviceConnectionState.connected){
        _reconnectTimer?.cancel();
        try{ await _ble.discoverAllServices(id); } catch(_){}
        await _subscribeAll();
        await _readRssi(); _startRssi();
      }
      if(u.connectionState==DeviceConnectionState.disconnected){
        _stopRssi(); await _unsub();
        if(_shouldReconnect&&_deviceId!=null) _scheduleReconnect();
      }
    }, onError:(Object e,StackTrace _) async {
      debugPrint('[BLE] $e');
	  _currentConn = DeviceConnectionState.disconnected;
      if(!_connState.isClosed) _connState.add(DeviceConnectionState.disconnected);
      _stopRssi(); await _unsub();
      if(_shouldReconnect&&_deviceId!=null) _scheduleReconnect();
    });
  }

  void _scheduleReconnect(){
    _reconnectTimer?.cancel();
    _reconnectTimer=Timer(const Duration(seconds:3),(){
      if(_shouldReconnect&&_deviceId!=null) _attempt(_deviceId!);
    });
  }
  Future<DiscoveredDevice?> scanOncePreferLast({
  Duration timeout = const Duration(seconds: 6),
}) async {
  final prefs = await SharedPreferences.getInstance();
  final lastId = prefs.getString(_prefsKey);

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

  Future<void> disconnect({bool clearLastDevice=true}) async {
    _shouldReconnect=false; _reconnectTimer?.cancel();
    _stopRssi(); await _unsub();
	_currentConn = DeviceConnectionState.disconnected;
    try{ await _connSub?.cancel(); } catch(_){}
    _connSub=null; _deviceId=null; _resetAnalytics();
    if(!_connState.isClosed) _connState.add(DeviceConnectionState.disconnected);
    if(clearLastDevice) await _clearId();
  }

 Future<bool> reconnectLastIfAny() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_prefsKey);

    if (savedId == null || savedId.isEmpty) {
      return false;
    }

    // 1) Fast path: try saved id directly first
    debugPrint('[BLE] Fast reconnect via saved id: $savedId');
    await connect(savedId);

    final fastOk = await _waitForFirstRollPacket(
      timeout: const Duration(seconds: 4),
    );

    if (fastOk) {
      debugPrint('[BLE] Fast reconnect succeeded');
      return true;
    }

    // 2) If no real sensor data came, reset and do a fresh scan fallback
    debugPrint('[BLE] Fast reconnect had no data, trying scan fallback...');
    await disconnect(clearLastDevice: false);

    final hit = await scanOncePreferLast(
      timeout: const Duration(seconds: 4),
    );

    if (hit == null) {
      return false;
    }

    debugPrint('[BLE] Scan reconnect target: ${hit.id}');
    await connect(hit.id);

    final scanOk = await _waitForFirstRollPacket(
      timeout: const Duration(seconds: 6),
    );

    if (!scanOk) {
      await disconnect(clearLastDevice: false);
      return false;
    }

    return true;
  } catch (e) {
    debugPrint('[BLE] reconnectLastIfAny failed: $e');
    return false;
  }
}

  Future<void> _saveId(String id) async {
    try{ (await SharedPreferences.getInstance()).setString(_prefsKey,id); } catch(_){}
  }
  Future<void> _clearId() async {
    try{ (await SharedPreferences.getInstance()).remove(_prefsKey); } catch(_){}
  }

  Future<void> _subscribeAll() async {
    if(_deviceId==null) return;
    final id=_deviceId!;
    Future<StreamSubscription<List<int>>> sub(Uuid c,void Function(List<int>) f) async {
      final q=QualifiedCharacteristic(deviceId:id,serviceId:serviceUuid,characteristicId:c);
      return _ble.subscribeToCharacteristic(q).listen(f,onError:(_){});
    }
    _sRoll  =await sub(rollUuid,  (b){final v=_f32(b);_roll$.add(v);});
    _sPitch =await sub(pitchUuid, (b){final v=_f32(b);_pitch$.add(v);});
    _sYaw   =await sub(yawUuid,   (b)=>_yaw$.add(_f32(b)));
    _sTemp  =await sub(tempUuid,  (b)=>_tempCtrl.add(_f32N(b)));
    // Steps: emit raw firmware count to steps$ for logging.
    // Cadence fires only on genuine increments (prevents 600 spm).
    // Dashboard computes session-relative offset itself via steps$.
    _sSteps =await sub(stepsUuid, (b){
      final cnt=_i32(b);
      _steps$.add(cnt);
      if(_cumSteps < 0){
        // First packet — record baseline, fire no step event.
        _cumSteps = cnt;
        _baseSteps = cnt;
        _sessionSteps = 0;
      } else if(cnt > _cumSteps){
        _sessionSteps = cnt - _baseSteps;
        _onFirmwareStep();
        _cumSteps = cnt;
      }
      // Always emit session-relative count so dashboard stays current.
      _stepsACtrl.add(_sessionSteps);
    });
    // Cadence from firmware is still forwarded to cadence$ for BLE logging.
    // Dashboard cadence display uses cadenceAnalytic$ fed by _onFirmwareStep.
    _sCad   =await sub(cadenceUuid,(b)=>_cadence$.add(_f32(b)));
    // Stride: firmware ZUPT integration → both display streams.
    _sStride=await sub(strideUuid,(b){
      final v=_f32(b);
      _stride$.add(v);
      _strideACtrl.add(v);           // dashboard listens to strideAnalytic$
    });
    _sDh    =await sub(altdhUuid, (b)=>_dh$.add(_f32(b)));
  }

  Future<void> _unsub() async {
    for(final s in [_sRoll,_sPitch,_sYaw,_sTemp,_sSteps,_sCad,_sStride,_sDh]){
      try{ await s?.cancel(); } catch(_){}
    }
    _sRoll=_sPitch=_sYaw=_sTemp=_sSteps=_sCad=_sStride=_sDh=null;
  }

  void _resetAnalytics(){
    _cadenceDecayTimer?.cancel(); _cadenceDecayTimer=null;
    _cumSteps=-1; _baseSteps=0; _sessionSteps=0; _cumPitchSteps=0; _lastStepWall=-1; _lastCadence=0; _lastEmittedCadence=0; _stepWallTimes.clear();
    // Legacy fields
    _tA=0;_baseline=0;_lastCentered=0;_lastStepT=-1;_lastStride=0;
    _baselineInit=false; _lastPitchTs=null;
    if(!_stepsACtrl.isClosed)   _stepsACtrl.add(0);
    if(!_cadenceACtrl.isClosed) _cadenceACtrl.add(0);
    if(!_strideACtrl.isClosed)  _strideACtrl.add(0);
  }

  void _pitchAnalytic(double deg){
    final now=DateTime.now();
    double dt=0.1;
    if(_lastPitchTs!=null) dt=now.difference(_lastPitchTs!).inMilliseconds/1000.0;
    _lastPitchTs=now; _tA+=dt;
    if(!_baselineInit){_baseline=deg;_baselineInit=true;}
    else{_baseline+=0.01*(deg-_baseline);}
    final c=deg-_baseline;
    if(_lastCentered<=0&&c>0&&c.abs()>=5&&(_lastStepT<0?999:_tA-_lastStepT)>=0.3){
      _lastStepT=_tA;_cumPitchSteps++;
      final cad=_stepWallTimes.length>=2
          ?(_stepWallTimes.length-1)/(_stepWallTimes.last-_stepWallTimes.first)*60
          :0.0;
      if(!_stepsACtrl.isClosed) _stepsACtrl.add(_cumPitchSteps);
    }
    _lastCentered=c;
  }

  int _cumPitchSteps=0;

  /// Called on every firmware step notification.
  /// Computes cadence from wall-clock inter-step intervals over a 10 s window
  /// and schedules a 2 s decay timer to zero cadence when steps stop.
  void _onFirmwareStep(){
    final nowSec = DateTime.now().millisecondsSinceEpoch / 1000.0;
    _stepWallTimes.add(nowSec);
    // Keep only the last 10 s of step timestamps.
    while(_stepWallTimes.isNotEmpty && _stepWallTimes.first < nowSec - 10.0)
      _stepWallTimes.removeAt(0);
    // Cadence from wall-clock timing — immune to BLE notify rate jitter.
    double cad = 0;
    if(_stepWallTimes.length >= 2){
      final dur = _stepWallTimes.last - _stepWallTimes.first;
      if(dur > 0) cad = (_stepWallTimes.length - 1) / dur * 60;
    }
    // EMA smoothing — α=0.3 keeps display stable across step-to-step
    // variance without lag on genuine cadence changes.
    // Light EMA on Dart side — firmware already applies α=0.25.
    // This second pass removes BLE packet jitter only.
    const double alpha = 0.5;
    _lastCadence = (_lastCadence == 0)
        ? cad
        : _lastCadence + alpha * (cad - _lastCadence);
    _lastStepWall = nowSec;
    // Dead-band: only emit if cadence changed by more than 0.5 spm.
    // Prevents tiny floating-point differences triggering a redraw.
    final emitCad = (_lastCadence - _lastEmittedCadence).abs() >= 0.5;
    if(emitCad && !_cadenceACtrl.isClosed){
      _lastEmittedCadence = _lastCadence;
      _cadenceACtrl.add(double.parse(_lastCadence.toStringAsFixed(1)));
    }
    // Decay to zero after 3 s — long enough for slow walking (~60 spm
    // = one step per second, so pairs can be 2 s apart).
    _cadenceDecayTimer?.cancel();
    _cadenceDecayTimer = Timer(const Duration(seconds: 3), (){
      _lastCadence = 0; _lastEmittedCadence = 0;
      if(!_cadenceACtrl.isClosed) _cadenceACtrl.add(0);
    });
  }

  Future<void> _readRssi() async {
    final id=_deviceId; if(id==null) return;
    try{ if(!_rssiCtrl.isClosed) _rssiCtrl.add(await _ble.readRssi(id)); }
    catch(_){ if(!_rssiCtrl.isClosed) _rssiCtrl.add(null); }
  }
  void _startRssi(){
    _stopRssi();
    _rssiTimer=Timer.periodic(const Duration(seconds:2),(_)=>_readRssi());
  }
  void _stopRssi(){
    _rssiTimer?.cancel(); _rssiTimer=null;
    if(!_rssiCtrl.isClosed) _rssiCtrl.add(null);
  }
  Future<bool> _waitForFirstRollPacket({
  Duration timeout = const Duration(seconds: 12),
}) async {
  try {
    await roll$.first.timeout(timeout);
    return true;
  } catch (_) {
    return false;
  }
}
/// Called by the lifecycle observer when the app returns to the foreground.
  /// Re-enables auto-reconnect and attempts to restore the last BLE session
  /// if the connection was lost while the screen was off.
  Future<void> onAppResumed() async {
    if (isConnected) return;  // nothing to do
    _shouldReconnect = true;
    await reconnectLastIfAny();
  }

Future<void> shutdownForAppClose() async {
  _shouldReconnect = false;
  _reconnectTimer?.cancel();
  _stopRssi();

  try {
    await _unsub();
  } catch (_) {}

  try {
    await _connSub?.cancel();
  } catch (_) {}

  _connSub = null;
  _currentConn = DeviceConnectionState.disconnected;
  _deviceId = null;
}

  void dispose() {
  _cadenceDecayTimer?.cancel();
  _shouldReconnect = false;
  _reconnectTimer?.cancel();
  _stopRssi();

  unawaited(_unsub());
  try {
    _connSub?.cancel();
  } catch (_) {}

  _connSub = null;
  _currentConn = DeviceConnectionState.disconnected;
  _deviceId = null;

  for (final c in [
    _connState,
    _rssiCtrl,
    _roll$,
    _pitch$,
    _yaw$,
    _steps$,
    _cadence$,
    _stride$,
    _dh$,
    _tempCtrl,
    _stepsACtrl,
    _cadenceACtrl,
    _strideACtrl,
  ]) {
    try {
      c.close();
    } catch (_) {}
  }
}
}

double _f32(List<int> b){
  if(b.length<4) return 0.0;
  final v=ByteData.sublistView(Uint8List.fromList(b)).getFloat32(0,Endian.little);
  return (v.isNaN||v.isInfinite)?0.0:v;
}
double? _f32N(List<int> b){
  if(b.length<4) return null;
  final v=ByteData.sublistView(Uint8List.fromList(b)).getFloat32(0,Endian.little);
  return (v.isNaN||v.isInfinite)?null:v;
}
// Firmware sends stepCount as uint32_t — use getUint32 to avoid sign-flip above 2^31
int _i32(List<int> b){
  if(b.length<4) return 0;
  return ByteData.sublistView(Uint8List.fromList(b)).getUint32(0,Endian.little);
}

/* ========================================================================= */
/*  SHARED PREFS KEYS & ROOT DIR                                             */
/* ========================================================================= */

const String kActiveModelPathKey   = 'shoeml_active_model_path';
const String kActiveModelPathsKey  = 'shoeml_active_model_paths';
const String kLiveConfThresholdKey = 'shoeml_live_conf_threshold';
const String kEnabledLiveLabelsKey = 'shoeml_live_enabled_labels';

Future<Directory> shoeMlRootDir() async {
  final d=await getApplicationDocumentsDirectory();
  final dir=Directory('${d.path}/shoeml');
  if(!dir.existsSync()) dir.createSync(recursive:true);
  return dir;
}

/* ========================================================================= */
/*  MODEL CLASSES                                                             */
/* ========================================================================= */

abstract class ActivityModel {
  List<String> get labels;
  MapEntry<String,double> predictLabel(List<double> x);
}

class LoadedActivityModel implements ActivityModel {
  LoadedActivityModel({required this.labels,required this.W,required this.b});
  @override final List<String> labels;
  final List<List<double>> W;
  final List<double> b;

  factory LoadedActivityModel.fromJson(Map<String,dynamic> j){
    final labels=(j['labels'] as List? ?? []).map((e)=>'$e').toList();
    final W=(j['W'] as List? ?? []).map<List<double>>((row)=>(row as List).map<double>((v)=>(v as num).toDouble()).toList()).toList();
    final b=(j['b'] as List? ?? []).map<double>((v)=>(v as num).toDouble()).toList();
    return LoadedActivityModel(labels:labels,W:W,b:b);
  }

  List<double> _z(List<double> x){
    final C=W.length; if(C==0) return const[];
    final D=W[0].length;
    final xx=x.length==D?x:(){final v=List<double>.filled(D,0.0);for(int i=0;i<D&&i<x.length;i++)v[i]=x[i];return v;}();
    final out=List<double>.filled(C,0.0);
    for(int k=0;k<C;k++){
      double s=k<b.length?b[k]:0.0;
      for(int j=0;j<W[k].length&&j<xx.length;j++) s+=W[k][j]*xx[j];
      out[k]=s;
    }
    return out;
  }

  List<double> _softmax(List<double> z){
    if(z.isEmpty) return const[];
    final m=z.reduce(math.max);
    final e=z.map((v)=>math.exp(v-m)).toList();
    final s=e.fold<double>(0,(a,b)=>a+b);
    if(s==0) return List.filled(e.length,1.0/e.length);
    return e.map((v)=>v/s).toList();
  }

  Map<String,double> predictProbs(List<double> x){
    final p=_softmax(_z(x)); if(p.isEmpty) return const{};
    final out=<String,double>{};
    for(int i=0;i<p.length&&i<labels.length;i++) out[labels[i]]=p[i];
    return out;
  }

  @override
  MapEntry<String,double> predictLabel(List<double> x){
    final probs=predictProbs(x); if(probs.isEmpty) return const MapEntry('-',0.0);
    var best=probs.entries.first;
    for(final e in probs.entries){ if(e.value>best.value) best=e; }
    return MapEntry(best.key,best.value);
  }
}


// RF model loaded from JSON — reconstructs trees from node lists.
class RFActivityModel implements ActivityModel {
  RFActivityModel({
    required this.labels,
    required List<List<Map<String,dynamic>>> trees,
    Set<String>? trainedOn,
  }) : _trees = trees,
       // If not provided, assume all labels were trained on (legacy models).
       trainedOn = trainedOn ?? labels.toSet();

  @override final List<String> labels;
  /// The subset of labels this model was actually trained on.
  /// Used to filter votes so single-label models don't cancel each other.
  final Set<String> trainedOn;
  final List<List<Map<String, dynamic>>> _trees;

  factory RFActivityModel.fromJson(Map<String, dynamic> j) {
    final labels    = (j['labels'] as List? ?? []).map((e) => '$e').toList();
    final trainedOn = (j['trained_on'] as List? ?? labels)
        .map((e) => '$e').toSet();
    final trees = (j['trees'] as List? ?? [])
        .map<List<Map<String, dynamic>>>((t) =>
            (t['nodes'] as List)
                .map<Map<String, dynamic>>((n) =>
                    Map<String, dynamic>.from(n as Map))
                .toList())
        .toList();
    return RFActivityModel(labels: labels, trees: trees, trainedOn: trainedOn);
  }

  int _walkTree(List<Map<String, dynamic>> nodes, List<double> x) {
    int idx = 0;
    while (idx >= 0 && idx < nodes.length) {
      final n = nodes[idx];
      if (n.containsKey('cl')) return (n['cl'] as num).toInt();
      final fi = (n['fi'] as num).toInt();
      final th = (n['th'] as num).toDouble();
      idx = x.length > fi && x[fi] <= th
          ? (n['l'] as num).toInt()
          : (n['r'] as num).toInt();
    }
    return 0;
  }

  /// Returns votes only for labels this model was trained on (label→fraction).
  /// Suppressing untrained labels prevents single-label models from
  /// permanently splitting votes 50/50 against each other.
  Map<String, double> predictAllVotes(List<double> x) {
    if (_trees.isEmpty) return {};
    final votes = <int, int>{};
    for (final t in _trees) {
      final p = _walkTree(t, x);
      votes[p] = (votes[p] ?? 0) + 1;
    }
    // Only expose votes for labels present in trainedOn.
    final raw = <String, double>{};
    for (int i = 0; i < labels.length; i++) {
      if (trainedOn.contains(labels[i])) {
        raw[labels[i]] = (votes[i] ?? 0) / _trees.length;
      }
    }
    // Re-normalise within the trained subset so fractions sum to 1.0.
    final sum = raw.values.fold(0.0, (a, b) => a + b);
    if (sum <= 0) return raw;
    return { for (final e in raw.entries) e.key: e.value / sum };
  }

  @override
  MapEntry<String, double> predictLabel(List<double> x) {
    if (_trees.isEmpty) return const MapEntry('-', 0.0);
    final all  = predictAllVotes(x);
    if (all.isEmpty) return const MapEntry('-', 0.0);
    final best = all.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return MapEntry(best.key, best.value);
  }
}

// Metadata parsed from a model JSON for the browser card.
class _ModelInfo {
  _ModelInfo({
    required this.file, required this.name, required this.type,
    required this.accuracy, required this.trainedOn,
    required this.windows, required this.inputDim, required this.date,
  });
  final File         file;
  final String       name, type;
  final double?      accuracy;
  final List<String> trainedOn;
  final int          windows, inputDim;
  final DateTime     date;

  static _ModelInfo fromFile(File f) {
    try {
      final j       = jsonDecode(f.readAsStringSync()) as Map<String,dynamic>;
      final trained = (j['trained_on'] as List? ?? j['labels'] as List? ?? [])
          .map((e) => '$e').toList();
      return _ModelInfo(
        file:      f,
        name:      f.uri.pathSegments.last,
        type:      (j['type'] as String? ?? 'softmax'),
        accuracy:  (j['accuracy'] as num?)?.toDouble(),
        trainedOn: trained,
        windows:   (j['windows'] as num? ?? 0).toInt(),
        inputDim:  (j['input_dim'] as num? ?? 0).toInt(),
        date:      f.lastModifiedSync(),
      );
    } catch (_) {
      return _ModelInfo(
        file: f, name: f.uri.pathSegments.last,
        type: 'unknown', accuracy: null, trainedOn: [],
        windows: 0, inputDim: 0, date: f.lastModifiedSync(),
      );
    }
  }
}

class EnsembleActivityModel implements ActivityModel {
  EnsembleActivityModel(this.models);
  final List<LoadedActivityModel> models;
  @override List<String> get labels=>{for(final m in models)...m.labels}.toList();
  @override MapEntry<String,double> predictLabel(List<double> x){
    if(models.isEmpty) return const MapEntry('-',0.0);
    var best=const MapEntry('-',-1.0);
    for(final m in models){ final p=m.predictLabel(x); if(p.value>best.value) best=p; }
    return MapEntry(best.key,best.value.clamp(0.0,1.0));
  }
}

/* ========================================================================= */
/*  DATA TYPES                                                                */
/* ========================================================================= */

class _RawSample {
  _RawSample(this.t,this.roll,this.pitch,this.yaw,this.tempC,this.cadence,this.strideM,this.dH,{this.steps,this.labelIdx});
  double t;
  double? roll,pitch,yaw,tempC,cadence,strideM,dH;
  int? steps,labelIdx;
}

class _SessionSummary {
  _SessionSummary({required this.file,required this.label,required this.distanceM,
    required this.duration,required this.paceText,required this.totalSteps,
    required this.avgCadence,required this.avgStride,required this.avgTempC});
  final File file;
  final String? label,paceText;
  final double? distanceM,avgCadence,avgStride,avgTempC;
  final Duration? duration;
  final int? totalSteps;
}

/* ========================================================================= */
/*  SOFTMAX CLASSIFIER                                                        */
/* ========================================================================= */

class SoftmaxClassifier {
  late int C,D;
  late List<List<double>> W;
  late List<double> b;

  void init({required int numClasses,required int inDim}){
    C=numClasses; D=inDim;
    final rnd=math.Random(42);
    W=List.generate(C,(_)=>List.generate(D,(_)=>(rnd.nextDouble()-0.5)*0.01));
    b=List.filled(C,0.0);
  }

  List<double> _sm(List<double> z){
    final m=z.reduce(math.max);
    final e=z.map((v)=>math.exp(v-m)).toList();
    final s=e.fold<double>(0,(a,b)=>a+b);
    return s==0?e:e.map((v)=>v/s).toList();
  }

  List<double> _proba(List<double> x){
    final z=List<double>.generate(C,(k){
      double s=b[k];
      for(int j=0;j<D;j++) s+=W[k][j]*x[j];
      return s;
    });
    return _sm(z);
  }

  int predict(List<double> x){
    final p=_proba(x); int arg=0;
    for(int i=1;i<p.length;i++) if(p[i]>p[arg]) arg=i;
    return arg;
  }

  void fit(List<List<double>> X,List<int> y,{int epochs=50,double lr=0.05,double l2=1e-4,int batch=64}){
    final n=X.length; if(n==0) return;
    for(int ep=0;ep<epochs;ep++){
      for(int i0=0;i0<n;i0+=batch){
        final i1=math.min(n,i0+batch); final m=i1-i0; if(m<=0) continue;
        final dW=List.generate(C,(_)=>List.filled(D,0.0));
        final db=List.filled(C,0.0);
        for(int i=i0;i<i1;i++){
          final p=_proba(X[i]);
          for(int k=0;k<C;k++){
            final g=p[k]-(k==y[i]?1.0:0.0); db[k]+=g;
            for(int j=0;j<D;j++) dW[k][j]+=g*X[i][j];
          }
        }
        for(int k=0;k<C;k++){
          for(int j=0;j<D;j++) W[k][j]-=lr*(dW[k][j]/m+l2*W[k][j]);
          b[k]-=lr*(db[k]/m);
        }
      }
    }
  }

  double accuracy(List<List<double>> X,List<int> y){
    if(X.isEmpty) return 0.0;
    int ok=0; for(int i=0;i<X.length;i++) if(predict(X[i])==y[i]) ok++;
    return ok/X.length;
  }
}

/* ========================================================================= */
/*  DASHBOARD PAGE                                                            */
/* ========================================================================= */

class _LiveModelEntry {
  _LiveModelEntry({required this.path,required this.model});
  final String path; final ActivityModel model;
  String get shortName=>path.split(Platform.pathSeparator).last;
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key,required this.ble});
  final ShoeBle ble;
  @override State<DashboardPage> createState()=>_DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String? _id;
  double roll=0,pitch=0,yaw=0,cadence=0,stride=0,dh=0;
  double? tempC; int steps=0; int? rssi;
  DeviceConnectionState conn=DeviceConnectionState.disconnected;
  StreamSubscription? _s1,_s2,_s3,_s4,_s5,_s6,_s7,_s8,_s9,_s10;

  // Dart-side provisional step display:
  // shows immediate step changes from live pitch motion while waiting for
  // firmware step updates, then firmware values take back over as source of truth.
  int _firmwareSteps = 0;
  int _provisionalSteps = 0;
  double _stepPitchBaseline = 0.0;
  bool _stepPitchBaselineInit = false;
  double _lastPitchCentered = 0.0;
  DateTime? _lastUiStepTs;

  final List<_RawSample> _liveBuf=[];
  final List<_LiveModelEntry> _liveModels=[];
  String? _liveActivity;
  Map<String, double> _liveVotes = {};  // per-class vote fractions from RF
  bool   _isStill   = false;  // true when RMS jerk is below threshold
  double _totalJerk  = 0.0;   // live RMS jerk magnitude (rad/sample)
  double? _liveConf;
  bool _modelLoading=false; double _tLive=0;
  double _liveConfThreshold=0.6;
  // RMS jerk threshold below which foot is considered still.
  // Tunable via slider in the classifier card.
  double _jerkThreshold=0.08;
  Set<String> _enabledLiveLabels={};

  @override
  void initState(){
    super.initState();
    conn = widget.ble.currentConnectionState;
    _id = widget.ble.connectedId;  // use public getter, not private _deviceId
    steps = widget.ble.currentSessionSteps;
    _firmwareSteps = steps;
    _provisionalSteps = steps;
    _loadConfThreshold();
    _loadEnabledLiveLabels();
    _bind();
  }

  void _bind(){
    _s1=widget.ble.connection$.listen((c){
      setState((){conn=c; if(c==DeviceConnectionState.connected) _id=widget.ble.connectedId;});
    });
    _s2=widget.ble.roll$.listen((v){ if(v.isNaN||v.isInfinite) return; setState(()=>roll=v); _onLiveRoll(v); });
    _s3=widget.ble.pitch$.listen((v){
      if(v.isNaN||v.isInfinite) return;
      setState(()=>pitch=v);
      _maybeProvisionalStepFromPitch(v);
      if(_liveBuf.isNotEmpty) _liveBuf.last.pitch=v;
    });
    _s4=widget.ble.yaw$.listen((v){ if(v.isNaN||v.isInfinite) return; setState(()=>yaw=v); if(_liveBuf.isNotEmpty) _liveBuf.last.yaw=v; });
    _s5=widget.ble.temp$.listen((v){ setState(()=>tempC=v); if(v!=null&&_liveBuf.isNotEmpty) _liveBuf.last.tempC=v; });
    _s6=widget.ble.stepsAnalytic$.listen((v){
      _firmwareSteps = v;
      if (v >= _provisionalSteps) {
        _provisionalSteps = v;
      }
      setState(()=>steps = _provisionalSteps);
    });
    _s7=widget.ble.cadenceAnalytic$.listen((v){
      if((v-cadence).abs() >= 0.5) setState(()=>cadence=v);
      if(_liveBuf.isNotEmpty) _liveBuf.last.cadence=v;
    });
    _s8=widget.ble.strideAnalytic$.listen((v){ setState(()=>stride=v); if(_liveBuf.isNotEmpty) _liveBuf.last.strideM=v; });
    _s9=widget.ble.dh$.listen((v)=>setState(()=>dh=v));
    _s10=widget.ble.rssi$.listen((v)=>setState(()=>rssi=v));
  }

  @override
  void dispose(){
    for(final s in [_s1,_s2,_s3,_s4,_s5,_s6,_s7,_s8,_s9,_s10]){ try{ s?.cancel(); } catch(_){} }
    super.dispose();
  }

  void _onLiveRoll(double v){
    if(_liveModels.isEmpty) return;
    _tLive+=0.1;
    _liveBuf.add(_RawSample(_tLive,v,null,null,null,null,null,null));
    while(_liveBuf.length>2&&_liveBuf.last.t-_liveBuf.first.t>20) _liveBuf.removeAt(0);
    _classify();
  }

  void _classify(){
    if(_liveModels.isEmpty||_liveBuf.length<5) return;
    final dt=(_liveBuf.last.t-_liveBuf.first.t)/(_liveBuf.length-1);
    if(!dt.isFinite||dt<=0) return;
    final win=(3.0/dt).round().clamp(1,_liveBuf.length);
    if(_liveBuf.length<win) return;
    final feat=_features(_liveBuf.sublist(_liveBuf.length-win));

    // ── Zero-motion gate (RMS jerk) ─────────────────────────────────────
    // Compute RMS of first-order angular differences across the window.
    // This is the same jerk signal the RF trains on — if it's below the
    // threshold the foot is genuinely still and locomotion labels are
    // suppressed, preventing the 50/50 sitting/walking split.
    const _locomotionLabels = {'walking', 'running', 'stairs_up', 'stairs_down'};
    final winSlice = _liveBuf.sublist(_liveBuf.length - win);

    double _rmsJerk(List<double?> vals) {
      final v = vals.whereType<double>().toList();
      if (v.length < 2) return 0.0;
      double sumSq = 0;
      for (int i = 1; i < v.length; i++) {
        final d = v[i] - v[i-1]; sumSq += d * d;
      }
      return math.sqrt(sumSq / (v.length - 1));
    }

    final jerkRoll  = _rmsJerk(winSlice.map((s) => s.roll).toList());
    final jerkPitch = _rmsJerk(winSlice.map((s) => s.pitch).toList());
    final jerkYaw   = _rmsJerk(winSlice.map((s) => s.yaw).toList());
    final totalJerk = math.sqrt(jerkRoll*jerkRoll + jerkPitch*jerkPitch + jerkYaw*jerkYaw);
    final isStill   = totalJerk < _jerkThreshold;

    // Accumulate votes across all loaded models.
    // RF models contribute fractional votes per class; softmax models
    // contribute 1.0 to their winning label (winner-takes-all).
    final accumulated = <String, double>{};
    String? best; double bestC = -1;

    for(final e in _liveModels){
      if(e.model is RFActivityModel){
        final rf = e.model as RFActivityModel;
        final allV = rf.predictAllVotes(feat);
        for(final kv in allV.entries){
          if(_enabledLiveLabels.isEmpty || _enabledLiveLabels.contains(kv.key)){
            accumulated[kv.key] = (accumulated[kv.key] ?? 0) + kv.value;
          }
        }
      } else {
        final p = e.model.predictLabel(feat);
        if(_enabledLiveLabels.isEmpty || _enabledLiveLabels.contains(p.key)){
          accumulated[p.key] = (accumulated[p.key] ?? 0) + p.value;
        }
      }
    }

    // Normalize so all bars sum to 1.0.
    final total = accumulated.values.fold(0.0, (a, b) => a + b);
    final normed = total > 0
        ? { for(final e in accumulated.entries) e.key: e.value / total }
        : <String, double>{};

    // Apply stillness gate: zero out votes for incompatible label groups.
    final gated = <String, double>{};
    for(final kv in normed.entries){
      if(isStill && _locomotionLabels.contains(kv.key)) continue;
      gated[kv.key] = kv.value;
    }
    // Re-normalize gated votes.
    final gatedTotal = gated.values.fold(0.0, (a, b) => a + b);
    final gatedNormed = gatedTotal > 0
        ? { for(final e in gated.entries) e.key: e.value / gatedTotal }
        : normed; // fallback to ungated if all labels were suppressed

    for(final kv in gatedNormed.entries){
      if(kv.value > bestC){ bestC = kv.value; best = kv.key; }
    }

    if(!mounted) return;
    setState((){
      _isStill   = isStill;
      _totalJerk = totalJerk;
      _liveVotes = gatedNormed;
      if(best!=null&&bestC>=_liveConfThreshold){ _liveActivity=best; _liveConf=bestC; }
      else { _liveActivity=null; _liveConf=null; }
    });
  }

  List<double> _features(List<_RawSample> w){
    List<double> col(List<double?> v){ final r=v.whereType<double>().toList(); return r.isEmpty?[0.0]:r; }
    List<double> stats(List<double> x){
      if(x.isEmpty) return [0.0,0.0,0.0];
      final n=x.length; final mean=x.reduce((a,b)=>a+b)/n;
      return [mean, x.map((v)=>(v-mean)*(v-mean)).reduce((a,b)=>a+b)/n,
              math.sqrt(x.map((v)=>v*v).reduce((a,b)=>a+b)/n)];
    }
    // Jerk: finite differences of angular channels — helps separate stairs
    // (high jerk at step edges) from walking (smooth rotation).
    List<double> jerk(List<double> x){
      if(x.length<2) return [0.0,0.0,0.0];
      final d=<double>[]; for(int i=1;i<x.length;i++) d.add(x[i]-x[i-1]);
      return stats(d);
    }
    final rv=col(w.map((e)=>e.roll).toList());
    final pv=col(w.map((e)=>e.pitch).toList());
    final yv=col(w.map((e)=>e.yaw).toList());
    return <double>[]
      // Basic stats (18)
      ..addAll(stats(rv))..addAll(stats(pv))..addAll(stats(yv))
      ..addAll(stats(col(w.map((e)=>e.cadence).toList())))
      ..addAll(stats(col(w.map((e)=>e.strideM).toList())))
      ..addAll(stats(col(w.map((e)=>e.tempC).toList())))
      // Jerk stats (9)
      ..addAll(jerk(rv))..addAll(jerk(pv))..addAll(jerk(yv));
    // total: 27 features — must match training_page._features
  }

  Future<void> _loadEnabledLiveLabels() async {
    try{ final l=(await SharedPreferences.getInstance()).getStringList(kEnabledLiveLabelsKey); if(l!=null&&mounted) setState(()=>_enabledLiveLabels=l.toSet()); } catch(_){}
  }
  Future<void> _saveEnabledLiveLabels() async {
    try{ (await SharedPreferences.getInstance()).setStringList(kEnabledLiveLabelsKey,_enabledLiveLabels.toList()); } catch(_){}
  }
  void _toggleLabel(String lbl){
    setState((){
      if(_enabledLiveLabels.isEmpty) _enabledLiveLabels={for(final e in _liveModels)...e.model.labels};
      if(_enabledLiveLabels.contains(lbl)) _enabledLiveLabels.remove(lbl); else _enabledLiveLabels.add(lbl);
    });
    _saveEnabledLiveLabels();
  }
  Future<void> _loadConfThreshold() async {
    try{ final v=(await SharedPreferences.getInstance()).getDouble(kLiveConfThresholdKey); if(v!=null&&mounted) setState(()=>_liveConfThreshold=v.clamp(0,1)); } catch(_){}
  }
  Future<void> _saveConfThreshold(double v) async {
    try{ (await SharedPreferences.getInstance()).setDouble(kLiveConfThresholdKey,v.clamp(0,1)); } catch(_){}
  }

  Future<void> _loadActiveModel() async {
    if(_modelLoading) return; setState(()=>_modelLoading=true);
    try{
      final prefs=await SharedPreferences.getInstance();
      List<String> paths=prefs.getStringList(kActiveModelPathsKey)??[];
      final leg=prefs.getString(kActiveModelPathKey);
      if(paths.isEmpty&&leg!=null&&leg.isNotEmpty) paths=[leg];
      if(paths.isEmpty){ if(mounted) _snack('No active models set. Go to Training tab.'); return; }
      final loaded=<_LiveModelEntry>[];
      for(final path in paths){
        final f=File(path); if(!await f.exists()) continue;
        try{
          final d=jsonDecode(await f.readAsString());
          if(d is Map<String,dynamic>){
            final ActivityModel mdl = (d['type'] == 'random_forest')
                ? RFActivityModel.fromJson(d)
                : LoadedActivityModel.fromJson(d);
            loaded.add(_LiveModelEntry(path:path, model:mdl));
          }
        } catch(_){}
      }
      if(loaded.isEmpty){ if(mounted) _snack('Model files not found. Re-select on Training tab.'); return; }
      if(mounted) setState((){_liveModels..clear()..addAll(loaded);_liveBuf.clear();_tLive=0;_liveActivity=null;_liveConf=null;});
      if(mounted) _snack('Loaded ${loaded.length} model(s): ${loaded.map((e)=>e.shortName).join(', ')}');
    } catch(e){ if(mounted) _snack('Failed: $e'); }
    finally{ if(mounted) setState(()=>_modelLoading=false); }
  }

  void _snack(String msg){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(msg))); }

  Future<void> _scanAndConnect() async {
    // Check BLE adapter state before scanning.
    final status = await widget.ble.adapterStatus$.first
        .timeout(const Duration(seconds: 2),
            onTimeout: () => BleStatus.unknown);
    if (!mounted) return;
    if (status == BleStatus.poweredOff) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Bluetooth is off — turn it on and try again.'),
        duration: Duration(seconds: 3),
      ));
      return;
    }
    if (status == BleStatus.unauthorized) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Bluetooth permission denied — check app settings.'),
        duration: Duration(seconds: 3),
      ));
      return;
    }
    final d=await widget.ble.scanOnce(); if(!mounted) return;
    if(d==null){ _snack('No device found.'); return; }
    setState(()=>_id=d.id); await widget.ble.connect(d.id);
  }

  String _connLabel(DeviceConnectionState s)=>switch(s){
    DeviceConnectionState.connecting=>'Connecting...',
    DeviceConnectionState.connected=>'Connected',
    DeviceConnectionState.disconnecting=>'Disconnecting...',
    _=>'Disconnected',
  };

  @override
  Widget build(BuildContext context){
    final cs=Theme.of(context).colorScheme;
    return Padding(padding:const EdgeInsets.all(12),child:ListView(children:[
      _connCard(),
      const SizedBox(height:8),
      Wrap(spacing:8,runSpacing:8,children:[
        _metric(cs,'Roll (°)',    roll.toStringAsFixed(1),          Icons.rotate_90_degrees_ccw),
        _metric(cs,'Pitch (°)',   pitch.toStringAsFixed(1),         Icons.rotate_90_degrees_cw),
        _metric(cs,'Yaw (°)',     yaw.toStringAsFixed(1),           Icons.refresh),
        _metric(cs,'Temp (°F)',   tempC != null ? (tempC! * 9 / 5 + 32).toStringAsFixed(1) : '—', Icons.thermostat),
        _metric(cs,'Steps',       steps.toString(),                 Icons.directions_walk),
        _metric(cs,'Cadence',     '${cadence.toStringAsFixed(1)} spm',Icons.speed),
        _metric(cs,'Stride',      '${stride.toStringAsFixed(2)} m', Icons.straighten),
        _metric(cs,'Elevation Δh','${dh.toStringAsFixed(2)} m',     Icons.landscape),
      ]),
      const SizedBox(height:16),
      _classifierCard(cs),
      const SizedBox(height:16),
      Card(color:cs.surfaceContainerHigh,child:const Padding(padding:EdgeInsets.all(16),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('MADEPLUS',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
          SizedBox(height:6),Text('Smart shoe analytics, live activity classification, and on-device training.'),
        ]))),
    ]));
  }

  Widget _connCard(){
    return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[
        const Icon(Icons.bluetooth),const SizedBox(width:12),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(_connLabel(conn),style:const TextStyle(fontWeight:FontWeight.w600)),
          Text(_id??'Not connected',style:Theme.of(context).textTheme.bodySmall,overflow:TextOverflow.ellipsis),
        ])),
      ]),
      const SizedBox(height:12),
      Wrap(spacing:8,runSpacing:8,children:[
        Chip(avatar:const Icon(Icons.network_cell,size:16),label:Text('RSSI ${rssi??'—'} dBm')),
        ElevatedButton.icon(onPressed:_scanAndConnect,icon:const Icon(Icons.search),label:const Text('Scan & Connect')),
        OutlinedButton.icon(onPressed:()=>widget.ble.disconnect(),icon:const Icon(Icons.link_off),label:const Text('Disconnect')),
      ]),
    ])));
  }

  Widget _metric(ColorScheme cs,String title,String value,IconData icon){
    return SizedBox(width:240,child:Card(color:cs.surfaceContainerHighest,child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[
      Icon(icon),const SizedBox(width:10),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(title,style:const TextStyle(fontSize:13,fontWeight:FontWeight.w500)),
        const SizedBox(height:2),
        Text(value,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      ])),
    ]))));
  }

  void _maybeProvisionalStepFromPitch(double deg){
    // Light high-pass baseline + rising zero-cross with debounce.
    // This is only for immediate UI feedback; firmware steps still override.
    final now = DateTime.now();
    if(!_stepPitchBaselineInit){
      _stepPitchBaseline = deg;
      _stepPitchBaselineInit = true;
      _lastPitchCentered = 0.0;
      return;
    }

    _stepPitchBaseline += 0.01 * (deg - _stepPitchBaseline);
    final centered = deg - _stepPitchBaseline;
    final dtMs = _lastUiStepTs == null
        ? 999999
        : now.difference(_lastUiStepTs!).inMilliseconds;

    final risingCross = _lastPitchCentered <= 0 && centered > 0;
    final enoughAmp = centered.abs() >= 4.0;
    final debounceOk = dtMs >= 350;

    if(risingCross && enoughAmp && debounceOk){
      _provisionalSteps += 1;
      _lastUiStepTs = now;
      if(_provisionalSteps < _firmwareSteps){
        _provisionalSteps = _firmwareSteps;
      }
      if(mounted){
        setState(()=>steps = _provisionalSteps);
      }
    }

    _lastPitchCentered = centered;
  }

  Widget _classifierCard(ColorScheme cs){
    final has=_liveModels.isNotEmpty;
    return Card(color:cs.surfaceContainerHigh,child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Live activity classifier',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
      const SizedBox(height:6),
      Text(has?'Using ${_liveModels.length} model(s). Each ~3 s window classified; highest-confidence label shown.'
              :'Train a model on Training tab, mark it as active, then tap "Load active models".',
          style:Theme.of(context).textTheme.bodySmall),
      const SizedBox(height:4),
      Text('Loaded: ${has?_liveModels.map((e)=>e.shortName).join(', '):'none'}',
          style:Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle:FontStyle.italic)),
      const SizedBox(height:10),
      Text('Min confidence: ${(_liveConfThreshold*100).toStringAsFixed(0)}%',style:Theme.of(context).textTheme.bodySmall),
      Slider(value:_liveConfThreshold,min:0.3,max:0.99,divisions:14,label:'${(_liveConfThreshold*100).toStringAsFixed(0)}%',
          onChanged:(v)=>setState(()=>_liveConfThreshold=v),onChangeEnd:_saveConfThreshold),
      // Zero-motion jerk threshold + live readout
      Row(children:[
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Still threshold (RMS jerk): ${_jerkThreshold.toStringAsFixed(3)}',
              style:Theme.of(context).textTheme.bodySmall),
          const SizedBox(height:2),
          Row(children:[
            Text('Live jerk: ',style:Theme.of(context).textTheme.bodySmall),
            Text(_totalJerk.toStringAsFixed(3),
                style:TextStyle(
                  fontSize:12,fontWeight:FontWeight.w700,
                  color:_isStill?cs.secondary:cs.primary)),
            const SizedBox(width:6),
            Text(_isStill?'← STILL (gate active)':'← motion detected',
                style:TextStyle(fontSize:11,
                    color:_isStill?cs.secondary:cs.onSurfaceVariant,
                    fontStyle:FontStyle.italic)),
          ]),
        ])),
        if(_isStill) Chip(label:const Text('STILL'),
            backgroundColor:cs.secondaryContainer,
            padding:EdgeInsets.zero,visualDensity:VisualDensity.compact),
      ]),
      Slider(value:_jerkThreshold,min:0.01,max:0.30,divisions:29,
          label:_jerkThreshold.toStringAsFixed(3),
          onChanged:(v)=>setState(()=>_jerkThreshold=v)),
      if(has)...[
        const SizedBox(height:6),
        Text('Enabled labels:',style:Theme.of(context).textTheme.bodySmall),
        const SizedBox(height:4),
        Wrap(spacing:6,runSpacing:4,children:[
          ...({for(final e in _liveModels)...e.model.labels}.toList()..sort()).map((lbl){
            final en=_enabledLiveLabels.isEmpty||_enabledLiveLabels.contains(lbl);
            return FilterChip(label:Text(lbl),selected:en,onSelected:(_)=>_toggleLabel(lbl),
                selectedColor:cs.primaryContainer,checkmarkColor:cs.onPrimaryContainer);
          }).toList(),
        ]),
      ],
      const SizedBox(height:10),
      // Warning: detect models with non-overlapping trainedOn sets
      if(has&&_liveModels.length>1)...[(){
        // Collect all RF trainedOn sets
        final rfModels=_liveModels
            .where((e)=>e.model is RFActivityModel)
            .map((e)=>(e.model as RFActivityModel).trainedOn).toList();
        if(rfModels.length<2) return const SizedBox.shrink();
        // Find any label covered by one model but not all — indicates
        // single-label models that should be replaced with one combined model.
        final allLbls=rfModels.expand((s)=>s).toSet();
        final disjoint=allLbls.any((l)=>rfModels.any((s)=>!s.contains(l)));
        if(!disjoint) return const SizedBox.shrink();
        return Container(
          margin:const EdgeInsets.only(bottom:10),
          padding:const EdgeInsets.all(10),
          decoration:BoxDecoration(
            color:cs.errorContainer,
            borderRadius:BorderRadius.circular(8)),
          child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Icon(Icons.warning_amber_rounded,
                color:cs.onErrorContainer,size:18),
            const SizedBox(width:8),
            Expanded(child:Text(
              'These models were each trained on a single label. '
              'Their votes cancel each other out (50/50 split). '
              'Fix: collect sessions for all labels, then train ONE '
              'combined model from the Training tab.',
              style:TextStyle(fontSize:12,color:cs.onErrorContainer))),
          ]),
        );
      }()],
      FilledButton.icon(
        onPressed:_modelLoading?null:_loadActiveModel,
        icon:const Icon(Icons.auto_awesome),
        label:Text(has?'Reload active models':'Load active models')),
      const SizedBox(height:12),
      // ── Per-class vote bars ────────────────────────────────────────
      if(has&&_liveVotes.isNotEmpty)...[
        Text('Live classification',
            style:Theme.of(context).textTheme.labelMedium),
        const SizedBox(height:6),
        ...(_liveVotes.entries.toList()
              ..sort((a,b)=>b.value.compareTo(a.value)))
            .map((kv){
          final isWinner = kv.key==_liveActivity;
          final pct = (kv.value*100);
          return Padding(
            padding:const EdgeInsets.only(bottom:5),
            child:Row(children:[
              SizedBox(width:90,
                child:Text(kv.key.replaceAll('_',' '),
                    maxLines:1,overflow:TextOverflow.ellipsis,
                    style:TextStyle(fontSize:12,
                        fontWeight:isWinner?FontWeight.w700:FontWeight.normal,
                        color:isWinner?cs.primary:cs.onSurface))),
              Expanded(
                child:ClipRRect(
                  borderRadius:BorderRadius.circular(4),
                  child:LinearProgressIndicator(
                    value:kv.value,minHeight:10,
                    backgroundColor:cs.surfaceContainerHighest,
                    color:isWinner?cs.primary:cs.secondary))),
              const SizedBox(width:6),
              SizedBox(width:36,
                child:Text('${pct.toStringAsFixed(0)}%',
                    textAlign:TextAlign.right,
                    style:TextStyle(fontSize:11,
                        fontWeight:isWinner?FontWeight.w700:FontWeight.normal,
                        color:isWinner?cs.primary:cs.onSurfaceVariant))),
            ]));
        }).toList(),
      ] else if(has)
        Text('Waiting for data window…',
            style:Theme.of(context).textTheme.bodySmall),
    ])));
  }
}

/* ========================================================================= */
/*  GRAPHS PAGE                                                               */
/* ========================================================================= */

class GraphsPage extends StatefulWidget {
  const GraphsPage({super.key,required this.ble});
  final ShoeBle ble;
  @override State<GraphsPage> createState()=>_GraphsPageState();
}

class _GraphsPageState extends State<GraphsPage> {
  final List<FlSpot> _r=[],_p=[],_y=[],_temp=[];
  double _t=0; DateTime? _t0;
  StreamSubscription? _sr,_sp,_sy; StreamSubscription<double?>? _sTemp;

  void _push(List<FlSpot> s,double t,double v,{int keep=300}){
    if(v.isNaN||v.isInfinite||t.isNaN||t.isInfinite) return;
    s.add(FlSpot(t,v)); if(s.length>keep) s.removeAt(0);
  }

  @override void initState(){
    super.initState();
    // Only the roll listener advances the shared time counter.
    // Pitch, yaw, and temp listeners reuse the current _t so all series
    // share the same X axis.  Each series arrives from independent BLE
    // notifications so they would otherwise triple-advance _t.
    _sr=widget.ble.roll$.listen((v){ if(v.isNaN||v.isInfinite) return; setState((){_t+=0.1;_push(_r,_t,v);}); });
    _sp=widget.ble.pitch$.listen((v){ if(v.isNaN||v.isInfinite) return; setState((){_push(_p,_t,v);}); });
    _sy=widget.ble.yaw$.listen((v){ if(v.isNaN||v.isInfinite) return; setState((){_push(_y,_t,v);}); });
    _t0=DateTime.now();
    _sTemp=widget.ble.temp$.listen((v){ if(v==null||v.isNaN||v.isInfinite) return;
      final t=DateTime.now().difference(_t0!).inMilliseconds/1000.0;
      final vF=v*9/5+32; // convert °C from firmware to °F
      setState(()=>_push(_temp,t,vF)); });
  }

  @override void dispose(){
    for(final s in [_sr,_sp,_sy,_sTemp]){ try{ s?.cancel(); } catch(_){} } super.dispose();
  }

  @override Widget build(BuildContext context){
    final cs=Theme.of(context).colorScheme;
    return Padding(padding:const EdgeInsets.all(12),child:ListView(children:[
      _card(cs,'Roll (°)',_r),_card(cs,'Pitch (°)',_p),_card(cs,'Yaw (°)',_y),_card(cs,'Temp (°F)',_temp),
    ]));
  }

  Widget _card(ColorScheme cs,String title,List<FlSpot> pts,{double? minY,double? maxY}){
    final valid=pts.where((p)=>!p.x.isNaN&&!p.x.isInfinite&&!p.y.isNaN&&!p.y.isInfinite).toList();
    final cur=valid.isEmpty?null:valid.last.y;
    final mn=valid.isEmpty?null:valid.map((p)=>p.y).reduce(math.min);
    final mx=valid.isEmpty?null:valid.map((p)=>p.y).reduce(math.max);
    return Card(color:cs.surfaceContainerHigh,child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[
        Text(title,style:const TextStyle(fontSize:14,fontWeight:FontWeight.w600)),const Spacer(),
        if(cur!=null) Text('Now: ${cur.toStringAsFixed(1)}',style:TextStyle(fontSize:12,color:cs.onSurface.withOpacity(0.7))),
      ]),
      const SizedBox(height:8),
      SizedBox(height:180,width:double.infinity,child:valid.isEmpty
          ?Center(child:Text('No data',style:TextStyle(color:Colors.grey[600])))
          :LineChart(LineChartData(minY:minY,maxY:maxY,
              gridData:const FlGridData(show:true),
              titlesData:const FlTitlesData(
                leftTitles:AxisTitles(sideTitles:SideTitles(showTitles:false)),
                bottomTitles:AxisTitles(sideTitles:SideTitles(showTitles:false)),
                topTitles:AxisTitles(sideTitles:SideTitles(showTitles:false)),
                rightTitles:AxisTitles(sideTitles:SideTitles(showTitles:false))),
              borderData:FlBorderData(show:true),
              lineBarsData:[LineChartBarData(spots:valid,isCurved:true,barWidth:2,isStrokeCapRound:true,dotData:const FlDotData(show:false))]))),
      if(mn!=null&&mx!=null)...[const SizedBox(height:4),Text('Range: ${mn.toStringAsFixed(1)} – ${mx.toStringAsFixed(1)}',style:TextStyle(fontSize:11,color:cs.onSurface.withOpacity(0.6)))],
    ])));
  }
}

/* ========================================================================= */
/*  TRAINING PAGE                                                             */
/* ========================================================================= */

class TrainingPage extends StatefulWidget {
  const TrainingPage({super.key,required this.ble});
  final ShoeBle ble;
  @override State<TrainingPage> createState()=>_TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  final _labels=['walking','running','stairs_up','stairs_down','standing','sitting'];
  String _label='walking';
  final _modelNameCtrl=TextEditingController();

  bool _collecting=false;
  DeviceConnectionState _conn=DeviceConnectionState.disconnected;
  StreamSubscription<DeviceConnectionState>? _connSub;

  final List<_RawSample> _buffer=[]; double _tTrain=0;
  StreamSubscription<double>? _sr,_sp,_sy,_sc,_ss,_sdh;
  StreamSubscription<double?>? _st;

  final _mapKey=GlobalKey(); final _mapCtrl=MapController();
  List<LatLng> _track=[]; List<DateTime> _trackTs=[];
  StreamSubscription<Position>? _posSub;
  DateTime? _tStart; double _lastDistM=0; Duration _lastDur=Duration.zero;

  List<File> _modelFiles=[]; Set<String> _activeModelPaths={}; bool _loadingModels=false;

  @override
void initState() {
  super.initState();
  _conn = widget.ble.currentConnectionState;
  _connSub = widget.ble.connection$.listen((s) {
    if (mounted) setState(() => _conn = s);
  });
  _bind();
  _loadModels();
}
  void _bind(){
    _sr=widget.ble.roll$.listen((v){ if(!_collecting) return; _tTrain+=0.1; _buffer.add(_RawSample(_tTrain,v,null,null,null,null,null,null,labelIdx:_labels.indexOf(_label))); });
    _sp=widget.ble.pitch$.listen((v){ if(!_collecting||_buffer.isEmpty) return; _buffer.last.pitch=v; });
    _sy=widget.ble.yaw$.listen((v){ if(!_collecting||_buffer.isEmpty) return; _buffer.last.yaw=v; });
    _st=widget.ble.temp$.listen((v){ if(!_collecting||_buffer.isEmpty) return; _buffer.last.tempC=v; });
    _sc=widget.ble.cadence$.listen((v){ if(!_collecting||_buffer.isEmpty) return; _buffer.last.cadence=v; });
    _ss=widget.ble.stride$.listen((v){ if(!_collecting||_buffer.isEmpty) return; _buffer.last.strideM=v; });
    _sdh=widget.ble.dh$.listen((v){ if(!_collecting||_buffer.isEmpty) return; _buffer.last.dH=v; });
  }

  @override void dispose(){
    for(final s in [_sr,_sp,_sy,_st,_sc,_ss,_sdh]){ try{ s?.cancel(); } catch(_){} }
    _posSub?.cancel(); _connSub?.cancel(); _modelNameCtrl.dispose(); super.dispose();
  }

  Future<Directory> _appDir() async {
    final d=await getApplicationDocumentsDirectory();
    final dir=Directory('${d.path}/shoeml'); if(!dir.existsSync()) dir.createSync(recursive:true);
    return dir;
  }
  Future<Directory> _ensureDir(Directory base,String child) async {
    final d=Directory('${base.path}/$child'); if(!d.existsSync()) d.createSync(recursive:true); return d;
  }

  void _snack(String msg){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(msg))); }

  // ── Collect ──────────────────────────────────────────────────────────────

  Future<void> _toggle() async {
    if(!_collecting&&_conn!=DeviceConnectionState.connected){ _snack('Connect to shoe first.'); return; }
    setState(()=>_collecting=!_collecting);
    if(_collecting){
      _buffer.clear(); _tTrain=0; _track=[]; _trackTs=[]; _tStart=DateTime.now(); await _startGps();
    } else {
      await _stopGps();
      if(_buffer.isEmpty){ _snack('No samples received — nothing saved.'); return; }
      _lastDistM=_distM(); _lastDur=_tStart!=null?DateTime.now().difference(_tStart!):Duration.zero;
      _fillStepsCadenceStride();
      await _fitRoute();
      final f=await _saveCsv(); if(f==null) return;
      final png=await _capturePng(f);
      final geo=await _saveGeoJson(f); final gpx=await _saveGpx(f); final kml=await _saveKml(f);
      await _showSummary(f,png,geo,gpx,kml);
    }
  }

  // ── CSV ───────────────────────────────────────────────────────────────────

  Future<File?> _saveCsv() async {
    final dir=await _ensureDir(await _appDir(),'sessions');
    final stamp=DateFormat('yyMMdd_HHmmss').format(DateTime.now());
    final file=File('${dir.path}/${_label}_$stamp.csv');
    final sb=StringBuffer()
      ..write('# distance_m=${_lastDistM.toStringAsFixed(1)}\n')
      ..write('# duration_s=${_lastDur.inSeconds}\n')
      ..write('# pace=${_pace(_lastDistM,_lastDur)}\n')
      ..write('t,roll,pitch,yaw,tempC,steps,cadence,strideM,deltaH,label\n');
    for(final s in _buffer){
      final lbl=(s.labelIdx!=null&&s.labelIdx!>=0&&s.labelIdx!<_labels.length)?_labels[s.labelIdx!]:_label;
      sb.write('${s.t.toStringAsFixed(3)},${s.roll?.toStringAsFixed(3)??''},${s.pitch?.toStringAsFixed(3)??''},${s.yaw?.toStringAsFixed(3)??''},${s.tempC?.toStringAsFixed(2)??''},${s.steps?.toString()??''},${s.cadence?.toStringAsFixed(1)??''},${s.strideM?.toStringAsFixed(3)??''},${s.dH?.toStringAsFixed(3)??''},$lbl\n');
    }
    await file.writeAsString(sb.toString(),flush:true);
    _snack('Saved: ${file.path.split('/').last}');
    return file;
  }

  // ── Train ─────────────────────────────────────────────────────────────────

  Future<void> _train() async {
    final wins=_windows(_buffer); if(wins.isEmpty){ _snack('No data.'); return; }
    final feats=wins.map(_featWin).toList();
    final winLabels=wins.map((w){ final counts=List<int>.filled(_labels.length,0); for(final s in w){ final i=s.labelIdx??_labels.indexOf(_label); if(i>=0&&i<counts.length) counts[i]++; } int best=0; for(int i=1;i<counts.length;i++) if(counts[i]>counts[best]) best=i; return best; }).toList();
    final present=winLabels.toSet().toList()..sort();
    final remap=<int,int>{for(int i=0;i<present.length;i++) present[i]:i};
    final usedLabels=present.map((i)=>_labels[i]).toList();
    final allY=winLabels.map((o)=>remap[o]!).toList();
    final n=feats.length; if(n<2){ _snack('Need at least 2 windows.'); return; }
    final nTr=(0.8*n).floor().clamp(1,n-1);
    final clf=SoftmaxClassifier()..init(numClasses:usedLabels.length,inDim:feats.first.length)
        ..fit(feats.sublist(0,nTr),allY.sublist(0,nTr),lr:0.01,epochs:200);
    final acc=clf.accuracy(feats.sublist(nTr),allY.sublist(nTr));
    final dir=await _ensureDir(await _appDir(),'models');
    final base=_modelNameCtrl.text.trim().isEmpty?'model':_modelNameCtrl.text.trim();
    final stamp=DateFormat('yyMMdd_HHmmss').format(DateTime.now());
    final file=File('${dir.path}/${base}_$stamp.json');
    await file.writeAsString(jsonEncode({'labels':usedLabels,'W':clf.W,'b':clf.b}));
    try{
      final prefs=await SharedPreferences.getInstance();
      final cur=prefs.getStringList(kActiveModelPathsKey)??[];
      if(!cur.contains(file.path)) cur.add(file.path);
      await prefs.setStringList(kActiveModelPathsKey,cur);
      await prefs.setString(kActiveModelPathKey,file.path);
    } catch(_){}
    await _loadModels();
    _snack('Trained on ${usedLabels.join(', ')} • acc ${(acc*100).toStringAsFixed(1)}% • ${file.path.split('/').last}');
  }

  List<List<_RawSample>> _windows(List<_RawSample> buf,{double winSec=3,double hopSec=1.5}){
    if(buf.length<2) return [];
    final dt=(buf.last.t-buf.first.t)/(buf.length-1); if(dt<=0) return [];
    final win=(winSec/dt).round().clamp(1,buf.length); final hop=(hopSec/dt).round().clamp(1,buf.length);
    final out=<List<_RawSample>>[]; for(int i=0;i+win<=buf.length;i+=hop) out.add(buf.sublist(i,i+win)); return out;
  }

  List<double> _featWin(List<_RawSample> w){
    List<double> col(List<double?> v){ final r=v.whereType<double>().toList(); return r.isEmpty?[0.0]:r; }
    List<double> stats(List<double> x){ final n=x.length,mean=x.reduce((a,b)=>a+b)/n; return [mean,x.map((v)=>(v-mean)*(v-mean)).reduce((a,b)=>a+b)/n,math.sqrt(x.map((v)=>v*v).reduce((a,b)=>a+b)/n)]; }
    return <double>[]..addAll(stats(col(w.map((e)=>e.roll).toList())))..addAll(stats(col(w.map((e)=>e.pitch).toList())))
      ..addAll(stats(col(w.map((e)=>e.yaw).toList())))..addAll(stats(col(w.map((e)=>e.cadence).toList())))
      ..addAll(stats(col(w.map((e)=>e.strideM).toList())))..addAll(stats(col(w.map((e)=>e.tempC).toList())));
  }

  // ── Model management ──────────────────────────────────────────────────────

  Future<void> _loadModels() async {
    if(mounted) setState(()=>_loadingModels=true);
    try{
      final root=await shoeMlRootDir(); final dir=Directory('${root.path}/models');
      List<File> models=[];
      if(dir.existsSync()) models=dir.listSync().whereType<File>().where((f)=>f.path.toLowerCase().endsWith('.json')).toList()..sort((a,b)=>b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      final prefs=await SharedPreferences.getInstance();
      final paths=<String>{...prefs.getStringList(kActiveModelPathsKey)??[]};
      final leg=prefs.getString(kActiveModelPathKey); if(leg!=null&&leg.isNotEmpty) paths.add(leg);
      if(mounted) setState((){_modelFiles=models;_activeModelPaths=paths;});
    } catch(_){ if(mounted) setState((){_modelFiles=[];_activeModelPaths={};});
    } finally{ if(mounted) setState(()=>_loadingModels=false); }
  }

  Future<void> _toggleActive(File f) async {
    final prefs=await SharedPreferences.getInstance();
    final paths=Set<String>.from(_activeModelPaths);
    if(paths.contains(f.path)) paths.remove(f.path); else paths.add(f.path);
    await prefs.setStringList(kActiveModelPathsKey,paths.toList());
    if(paths.isNotEmpty) await prefs.setString(kActiveModelPathKey,paths.first);
    else await prefs.remove(kActiveModelPathKey);
    if(mounted) setState(()=>_activeModelPaths=paths);
  }

  Future<void> _deleteModel(File f) async {
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Delete model?'),content:Text('Delete: ${f.path.split('/').last}'),
      actions:[TextButton(onPressed:()=>Navigator.of(ctx).pop(false),child:const Text('Cancel')),
               TextButton(onPressed:()=>Navigator.of(ctx).pop(true),child:const Text('Delete'))],
    ))??false;
    if(!ok) return;
    try{
      if(await f.exists()) await f.delete();
      final prefs=await SharedPreferences.getInstance();
      final newActive=Set<String>.from(_activeModelPaths)..remove(f.path);
      await prefs.setStringList(kActiveModelPathsKey,newActive.toList());
      if(mounted) setState((){_modelFiles=List.from(_modelFiles)..removeWhere((m)=>m.path==f.path);_activeModelPaths=newActive;});
    } catch(e){ _snack('Failed: $e'); }
  }

  // ── Export ZIP ───────────────────────────────────────────────────────────

  Future<void> _exportZip() async {
    try {
      _snack('Building ZIP…');
      final root     = await _appDir();
      final sessDir  = Directory('${root.path}/sessions');
      final modDir   = Directory('${root.path}/models');
      final encoder  = ZipFileEncoder();
      final stamp    = DateFormat('yyMMdd_HHmmss').format(DateTime.now());
      final zipPath  = '${root.path}/shoeml_export_$stamp.zip';
      encoder.create(zipPath);

      // Add all session CSVs
      if (sessDir.existsSync()) {
        for (final f in sessDir.listSync().whereType<File>()) {
          encoder.addFile(f, 'sessions/${f.uri.pathSegments.last}');
        }
      }
      // Add all model JSONs
      if (modDir.existsSync()) {
        for (final f in modDir.listSync().whereType<File>()) {
          encoder.addFile(f, 'models/${f.uri.pathSegments.last}');
        }
      }
      encoder.close();

      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(zipPath)],
        subject: 'ShoeML export $stamp',
        text: 'MadePlus ShoeML sessions + models',
      );
    } catch (e) {
      _snack('Export failed: $e');
    }
  }

  // ── GPS ───────────────────────────────────────────────────────────────────

  Future<void> _startGps() async {
    var p=await Geolocator.checkPermission();
    if(p==LocationPermission.denied) p=await Geolocator.requestPermission();
    if(p==LocationPermission.denied||p==LocationPermission.deniedForever){ _snack('Location denied'); return; }
    _tStart=DateTime.now();
    try{
      final pos=await Geolocator.getCurrentPosition(desiredAccuracy:LocationAccuracy.best);
      if(!pos.latitude.isFinite||!pos.longitude.isFinite) return;
      final first=LatLng(pos.latitude,pos.longitude);
      setState((){_track=[first];_trackTs=[DateTime.now()];});
      try{ _mapCtrl.move(first,16); } catch(_){}
    } catch(_){}
    await _posSub?.cancel();
    _posSub=Geolocator.getPositionStream(locationSettings:const LocationSettings(accuracy:LocationAccuracy.best,distanceFilter:3)).listen((pos){
      if(!pos.latitude.isFinite||!pos.longitude.isFinite) return;
      final pt=LatLng(pos.latitude,pos.longitude);
      if(_track.isNotEmpty){
        final dist=Geolocator.distanceBetween(_track.last.latitude,_track.last.longitude,pt.latitude,pt.longitude);
        if(dist>1000||(dist<8&&(!pos.speed.isFinite||pos.speed<0.5))) return;
      }
      setState((){_track.add(pt);_trackTs.add(DateTime.now());});
      try{ _mapCtrl.move(pt,_mapCtrl.camera.zoom); } catch(_){}
    });
  }

  Future<void> _stopGps() async { await _posSub?.cancel(); _posSub=null; }

  double _distM(){
    if(_track.length<2) return 0;
    double d=0; for(int i=1;i<_track.length;i++) d+=Geolocator.distanceBetween(_track[i-1].latitude,_track[i-1].longitude,_track[i].latitude,_track[i].longitude);
    return d;
  }

  String _dist(double m)=>m<1000?'${m.toStringAsFixed(1)} m':'${(m/1000).toStringAsFixed(2)} km';
  String _dur(Duration d)=>'${d.inMinutes}m ${d.inSeconds%60}s';
  String _pace(double m,Duration d){ if(m<=0||d.inSeconds<=0) return '-'; final s=d.inSeconds/(m/1000); return '${s~/60}m ${(s%60).round().toString().padLeft(2,'0')}s /km'; }

  Future<void> _fitRoute() async {
    if(_track.length<2) return;
    await Future.delayed(const Duration(milliseconds:100));
    double minLat=_track.first.latitude,maxLat=minLat,minLon=_track.first.longitude,maxLon=minLon;
    for(final p in _track){ if(p.latitude<minLat) minLat=p.latitude; if(p.latitude>maxLat) maxLat=p.latitude; if(p.longitude<minLon) minLon=p.longitude; if(p.longitude>maxLon) maxLon=p.longitude; }
    const sp=0.001;
    if((maxLat-minLat).abs()<sp){minLat-=sp/2;maxLat+=sp/2;} if((maxLon-minLon).abs()<sp){minLon-=sp/2;maxLon+=sp/2;}
    _mapCtrl.fitCamera(CameraFit.bounds(bounds:LatLngBounds(LatLng(minLat,minLon),LatLng(maxLat,maxLon)),padding:const EdgeInsets.all(20)));
  }

  List<LatLng> get _validTrack=>_track.where((p)=>!p.latitude.isNaN&&!p.latitude.isInfinite&&!p.longitude.isNaN&&!p.longitude.isInfinite&&p.latitude.abs()<=90&&p.longitude.abs()<=180).toList();

  void _fillStepsCadenceStride(){
    final n=_buffer.length; if(n<3) return;
    final times=List.generate(n,(i)=>_buffer[i].t); final pitches=List.generate(n,(i)=>_buffer[i].pitch??0.0);
    final baseline=List<double>.filled(n,0.0); baseline[0]=pitches[0];
    for(int i=1;i<n;i++) baseline[i]=baseline[i-1]+0.01*(pitches[i]-baseline[i-1]);
    final stepT=<double>[]; double lastC=pitches[0]-baseline[0],lastST=-1.0;
    for(int i=1;i<n;i++){
      final c=pitches[i]-baseline[i],dtL=lastST<0?999.0:times[i]-lastST;
      if(lastC<=0&&c>0&&c.abs()>=5&&dtL>=0.3){ stepT.add(times[i]); lastST=times[i]; } lastC=c;
    }
    final stpS=List<int>.filled(n,0); int si=0,cum=0;
    for(int i=0;i<n;i++){ while(si<stepT.length&&stepT[si]<=times[i]){ cum++;si++; } stpS[i]=cum; }
    final cadS=List<double>.filled(n,0.0); int l=0,r=0;
    for(int i=0;i<n;i++){
      while(l<stepT.length&&stepT[l]<times[i]-10) l++;
      while(r<stepT.length&&stepT[r]<=times[i]) r++;
      final cnt=r-l; if(cnt>=2){ final dur=stepT[r-1]-stepT[l]; if(dur>0) cadS[i]=(cnt-1)/dur*60; }
    }
    final totalSteps=stpS.isNotEmpty?stpS.last:0;
    final strideM=(totalSteps>0&&_lastDistM>0)?_lastDistM/totalSteps:0.0;
    for(int i=0;i<n;i++){ _buffer[i].steps=stpS[i]; _buffer[i].cadence=cadS[i]; _buffer[i].strideM=strideM; }
  }

  // ── Export helpers ────────────────────────────────────────────────────────

  Future<Uint8List?> _capturePng(File csv) async {
    final ctx=_mapKey.currentContext; if(ctx==null) return null;
    final b=ctx.findRenderObject() as RenderRepaintBoundary?; if(b==null) return null;
    final img=await b.toImage(pixelRatio:3); final bytes=await img.toByteData(format:ui.ImageByteFormat.png); if(bytes==null) return null;
    final dir=await _ensureDir(await _appDir(),'maps');
    await File('${dir.path}/${csv.uri.pathSegments.last.replaceAll('.csv','.png')}').writeAsBytes(bytes.buffer.asUint8List(),flush:true);
    return bytes.buffer.asUint8List();
  }

  Future<String?> _saveGeoJson(File csv) async {
    if(_track.isEmpty) return null;
    final geo={'type':'FeatureCollection','features':[{'type':'Feature','properties':{'label':_label,'distance_m':_lastDistM,'duration_s':_lastDur.inSeconds},'geometry':{'type':'LineString','coordinates':_track.map((p)=>[p.longitude,p.latitude]).toList()}}]};
    final dir=await _ensureDir(await _appDir(),'geojson');
    final f=File('${dir.path}/${csv.uri.pathSegments.last.replaceAll('.csv','.geojson')}');
    await f.writeAsString(jsonEncode(geo),flush:true); return f.path;
  }

  Future<String?> _saveGpx(File csv) async {
    if(_track.isEmpty) return null;
    final b=StringBuffer()..writeln('<?xml version="1.0" encoding="UTF-8"?>')..writeln('<gpx version="1.1" creator="MadePlus ShoeML"><trk><n>$_label</n><trkseg>');
    for(int i=0;i<_track.length;i++){ final p=_track[i]; final t=i<_trackTs.length?_trackTs[i].toUtc().toIso8601String():DateTime.now().toUtc().toIso8601String(); b.writeln('<trkpt lat="${p.latitude}" lon="${p.longitude}"><time>$t</time></trkpt>'); }
    b.writeln('</trkseg></trk></gpx>');
    final dir=await _ensureDir(await _appDir(),'gpx');
    final f=File('${dir.path}/${csv.uri.pathSegments.last.replaceAll('.csv','.gpx')}');
    await f.writeAsString(b.toString(),flush:true); return f.path;
  }

  Future<String?> _saveKml(File csv) async {
    if(_track.isEmpty) return null;
    final safe=_label.replaceAll(RegExp(r'\W+'),'_');
    final b=StringBuffer()..writeln('<?xml version="1.0"?><kml xmlns="http://www.opengis.net/kml/2.2"><Document><n>$safe</n><Placemark><LineString><coordinates>');
    for(final p in _track) b.writeln('${p.longitude},${p.latitude},0');
    b.writeln('</coordinates></LineString></Placemark></Document></kml>');
    final dir=await _ensureDir(await _appDir(),'kml');
    final f=File('${dir.path}/${csv.uri.pathSegments.last.replaceAll('.csv','.kml')}');
    await f.writeAsString(b.toString(),flush:true); return f.path;
  }

  Future<_SessionSummary> _readSummary(File f) async {
    final lines=await f.readAsLines();
    double? distM; Duration? dur; String? pace; int idx=0;
    for(;idx<lines.length;idx++){
      if(!lines[idx].startsWith('#')) break;
      if(lines[idx].startsWith('# distance_m=')) distM=double.tryParse(lines[idx].split('=').last.trim());
      else if(lines[idx].startsWith('# duration_s=')){ final s=int.tryParse(lines[idx].split('=').last.trim()); if(s!=null) dur=Duration(seconds:s); }
      else if(lines[idx].startsWith('# pace=')) pace=lines[idx].split('=').last.trim();
    }
    int maxSteps=0,nC=0,nSt=0,nTp=0; double sumC=0,sumSt=0,sumTp=0; final lblCounts=<String,int>{};
    for(final row in lines.skip(idx+1)){
      if(row.trim().isEmpty) continue; final p=row.split(','); if(p.length<10) continue;
      final v5=int.tryParse(p[5].trim()); if(v5!=null&&v5>maxSteps) maxSteps=v5;
      final v6=double.tryParse(p[6].trim()); if(v6!=null){sumC+=v6;nC++;}
      final v7=double.tryParse(p[7].trim()); if(v7!=null){sumSt+=v7;nSt++;}
      final v4=double.tryParse(p[4].trim()); if(v4!=null){sumTp+=v4;nTp++;}
      final lbl=p[9].trim(); if(lbl.isNotEmpty) lblCounts[lbl]=(lblCounts[lbl]??0)+1;
    }
    return _SessionSummary(file:f,label:lblCounts.isEmpty?null:lblCounts.entries.reduce((a,b)=>a.value>=b.value?a:b).key,
        distanceM:distM,duration:dur,paceText:pace,totalSteps:maxSteps==0?null:maxSteps,
        avgCadence:nC>0?sumC/nC:null,avgStride:nSt>0?sumSt/nSt:null,avgTempC:nTp>0?sumTp/nTp:null);
  }

  Future<File> _genPdf(File csv,Uint8List? mapPng) async {
    final s=await _readSummary(csv);
    final pdf=pw.Document();
    pdf.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a4,build:(ctx)=>[
      pw.Header(level:0,child:pw.Text('MadePlus ShoeML – Session Report',style:pw.TextStyle(fontSize:20,fontWeight:pw.FontWeight.bold))),
      pw.Text(csv.path.split('/').last,style:pw.TextStyle(fontSize:10)),pw.SizedBox(height:12),
      pw.Text('Summary',style:pw.TextStyle(fontSize:16,fontWeight:pw.FontWeight.bold)),pw.SizedBox(height:8),
      pw.Table.fromTextArray(headers:['Metric','Value'],data:[
        ['Primary label',s.label??'-'],
        ['Distance',s.distanceM!=null?_dist(s.distanceM!):'-'],
        ['Duration',s.duration!=null?_dur(s.duration!):'-'],
        ['Pace',s.paceText??'-'],
        ['Total steps',s.totalSteps?.toString()??'-'],
        ['Avg cadence',s.avgCadence!=null?'${s.avgCadence!.toStringAsFixed(1)} spm':'-'],
        ['Stride length',s.avgStride!=null?'${s.avgStride!.toStringAsFixed(2)} m':'-'],
        ['Avg temperature',s.avgTempC!=null?'${(s.avgTempC! * 9 / 5 + 32).toStringAsFixed(1)} °F':'-'],
      ]),
      if(mapPng!=null)...[pw.SizedBox(height:16),pw.Text('Route preview',style:pw.TextStyle(fontSize:14,fontWeight:pw.FontWeight.bold)),pw.SizedBox(height:8),pw.Center(child:pw.Image(pw.MemoryImage(mapPng),height:200))],
    ]));
    final dir=await _ensureDir(await _appDir(),'reports');
    final out=File('${dir.path}/${csv.uri.pathSegments.last.replaceAll('.csv','.pdf')}');
    await out.writeAsBytes(await pdf.save()); return out;
  }

  Future<void> _showSummary(File csv,Uint8List? png,String? geo,String? gpx,String? kml) async {
    if(!mounted) return;
    await showModalBottomSheet<void>(context:context,builder:(ctx)=>Padding(padding:const EdgeInsets.all(12),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('Session summary',style:Theme.of(ctx).textTheme.titleMedium),const SizedBox(height:8),
      Text('Label: $_label'), Text('Distance: ${_dist(_lastDistM)}'), Text('Duration: ${_dur(_lastDur)}'), Text('Pace: ${_pace(_lastDistM,_lastDur)}'),
      const SizedBox(height:8),
      if(png!=null) SizedBox(height:150,child:Image.memory(png,fit:BoxFit.cover)),
      const SizedBox(height:8),
      Text('CSV: ${csv.path.split('/').last}',style:Theme.of(ctx).textTheme.bodySmall),
      if(geo!=null) Text('GeoJSON saved',style:Theme.of(ctx).textTheme.bodySmall),
      if(gpx!=null) Text('GPX saved',style:Theme.of(ctx).textTheme.bodySmall),
      if(kml!=null) Text('KML saved',style:Theme.of(ctx).textTheme.bodySmall),
      const SizedBox(height:12),
      Row(children:[
        Expanded(child:FilledButton.icon(icon:const Icon(Icons.picture_as_pdf),label:const Text('Generate PDF'),
          onPressed:() async { Navigator.of(ctx).pop(); try{ final pf=await _genPdf(csv,png); if(!mounted) return; await Share.shareXFiles([XFile(pf.path)],text:'ShoeML report'); } catch(e){ _snack('Failed: $e'); } })),
        const SizedBox(width:8),
        Expanded(child:OutlinedButton.icon(icon:const Icon(Icons.share),label:const Text('Share CSV'),
          onPressed:() async { Navigator.of(ctx).pop(); await Share.shareXFiles([XFile(csv.path)],text:'ShoeML session'); })),
      ]),
    ])));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override Widget build(BuildContext context){
    final cs=Theme.of(context).colorScheme;
    final canStart=_conn==DeviceConnectionState.connected;
    return Padding(padding:const EdgeInsets.all(12),child:ListView(children:[
      // Collect card
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Collect samples',style:Theme.of(context).textTheme.titleMedium),const SizedBox(height:6),
        const Text('Tap a label, then Start/Stop. CSV auto-saves on stop.'),const SizedBox(height:12),
        Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Expanded(child:Wrap(spacing:8,runSpacing:4,children:_labels.map((lbl)=>ChoiceChip(label:Text(lbl.replaceAll('_',' ')),selected:_label==lbl,onSelected:(on){ if(on) setState(()=>_label=lbl); })).toList())),
          const SizedBox(width:12),
          FilledButton.icon(onPressed:_collecting?_toggle:(canStart?_toggle:null),icon:Icon(_collecting?Icons.stop:Icons.fiber_manual_record),label:Text(_collecting?'Stop & Save':'Start')),
        ]),
        const SizedBox(height:8),
        Text(_collecting?'Recording…':'Last: ${_dist(_lastDistM)} in ${_lastDur.inSeconds}s',style:Theme.of(context).textTheme.bodySmall),
      ]))),
      const SizedBox(height:12),
      // Route map
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Route',style:TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:8),
        SizedBox(height:220,child:RepaintBoundary(key:_mapKey,child:Builder(builder:(context){
          final valid=_validTrack;
          if(valid.isEmpty) return Container(color:Colors.grey[200],child:Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(Icons.location_searching,size:48,color:Colors.grey[400]),const SizedBox(height:8),Text('Waiting for GPS...',style:TextStyle(color:Colors.grey[600]))])));
          return Stack(children:[
            FlutterMap(mapController:_mapCtrl,options:MapOptions(initialZoom:16,initialCenter:valid.last),children:[
              TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'com.madeplus.shoeml'),
              if(valid.length>1) PolylineLayer(polylines:[Polyline(points:valid,strokeWidth:4)]),
              if(valid.isNotEmpty) MarkerLayer(markers:[
                Marker(width:30,height:30,point:valid.first,child:const Icon(Icons.flag,color:Colors.green)),
                Marker(width:30,height:30,point:valid.last,child:const Icon(Icons.place,color:Colors.red)),
              ]),
            ]),
            Positioned(right:8,top:8,child:Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),decoration:BoxDecoration(color:Colors.black54,borderRadius:BorderRadius.circular(16)),child:Text('${_dist(_lastDistM)}',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w600)))),
          ]);
        }))),
        const SizedBox(height:8),
        Text('Distance: ${_dist(_lastDistM)} • Duration: ${_dur(_lastDur)} • Pace: ${_pace(_lastDistM,_lastDur)}',style:Theme.of(context).textTheme.bodySmall),
      ]))),
      const SizedBox(height:12),
      // Train card
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Train classifier',style:Theme.of(context).textTheme.titleMedium),const SizedBox(height:6),
        const Text('Softmax classifier on collected buffer. Windows labeled by majority vote. 80/20 split.'),const SizedBox(height:12),
        TextField(controller:_modelNameCtrl,decoration:const InputDecoration(labelText:'Model name',hintText:'e.g. walk_run_v1')),const SizedBox(height:12),
        FilledButton.icon(onPressed:_buffer.length<10?null:_train,icon:const Icon(Icons.play_arrow),label:const Text('Train & Save')),
      ]))),
      const SizedBox(height:12),
      // ── Model browser ──────────────────────────────────────────────
      Card(color:cs.surfaceContainerHigh,child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[
          Text('Model browser',style:Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          IconButton(icon:const Icon(Icons.refresh,size:18),padding:EdgeInsets.zero,
              constraints:const BoxConstraints(),onPressed:_loadModels),
        ]),
        const SizedBox(height:4),
        Text('Check a model to mark it active. Dashboard → Load active models to run inference.',
            style:Theme.of(context).textTheme.bodySmall),
        const SizedBox(height:10),
        if(_loadingModels) const Center(child:CircularProgressIndicator())
        else if(_modelFiles.isEmpty)
          Text('No models yet — train one from the Training tab.',
              style:TextStyle(color:cs.onSurfaceVariant,fontSize:13))
        else Column(children:_modelFiles.map((f){
          final info=_ModelInfo.fromFile(f);
          final isActive=_activeModelPaths.contains(f.path);
          final accStr=info.accuracy!=null
              ?'${(info.accuracy!*100).toStringAsFixed(1)}% acc':'? acc';
          final typeStr=info.type=='random_forest'?'RF':'Softmax';
          final dateStr=DateFormat('MMM d  HH:mm').format(info.date);
          return Card(
            margin:const EdgeInsets.only(bottom:8),
            color:isActive?cs.primaryContainer:cs.surfaceContainerHighest,
            child:Padding(padding:const EdgeInsets.symmetric(horizontal:10,vertical:8),
              child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Checkbox(value:isActive,onChanged:(_)=>_toggleActive(f),
                    materialTapTargetSize:MaterialTapTargetSize.shrinkWrap),
                const SizedBox(width:4),
                Expanded(child:InkWell(onTap:()=>_toggleActive(f),child:Column(
                  crossAxisAlignment:CrossAxisAlignment.start,
                  children:[
                    Text(info.name,maxLines:2,overflow:TextOverflow.ellipsis,
                        style:TextStyle(fontSize:12,fontWeight:FontWeight.w600,
                            color:isActive?cs.onPrimaryContainer:cs.onSurface)),
                    const SizedBox(height:4),
                    // Labels row
                    Wrap(spacing:4,runSpacing:4,children:[
                      ...info.trainedOn.map((l)=>Chip(
                          label:Text(l.replaceAll('_',' '),
                              style:const TextStyle(fontSize:10)),
                          padding:EdgeInsets.zero,
                          visualDensity:VisualDensity.compact,
                          backgroundColor:isActive
                              ?cs.primary.withOpacity(0.15)
                              :cs.surfaceContainerHigh)),
                    ]),
                    const SizedBox(height:4),
                    // Stats row
                    Text('$typeStr  •  $accStr  •  ${info.windows} windows  •  $dateStr',
                        style:TextStyle(fontSize:10,
                            color:isActive?cs.onPrimaryContainer:cs.onSurfaceVariant)),
                    if(info.inputDim>0&&info.inputDim!=27)
                      Text('⚠ Input dim ${info.inputDim} — retrain for jerk features (27).',
                          style:TextStyle(fontSize:10,color:cs.error)),
                  ],
                ))),
                IconButton(
                  icon:const Icon(Icons.delete_outline,size:18),
                  color:cs.error,padding:EdgeInsets.zero,
                  constraints:const BoxConstraints(),
                  onPressed:()=>_deleteModel(f)),
              ]),
            ),
          );
        }).toList()),
        if(_activeModelPaths.isNotEmpty) Padding(
          padding:const EdgeInsets.only(top:4),
          child:Text('Active: ${_activeModelPaths.map((p)=>p.split('/').last).join(', ')}',
              style:Theme.of(context).textTheme.bodySmall?.copyWith(color:cs.primary))),
      ]))),
      const SizedBox(height:12),
      // ── Export ZIP ───────────────────────────────────────────────────
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,
        children:[
          Text('Export data',style:Theme.of(context).textTheme.titleMedium),
          const SizedBox(height:4),
          Text('Packages all session CSVs and model JSONs into a ZIP for PC analysis or backup.',
              style:Theme.of(context).textTheme.bodySmall),
          const SizedBox(height:10),
          Row(children:[
            Expanded(child:FilledButton.icon(
              icon:const Icon(Icons.archive_outlined),
              label:const Text('Export all as ZIP'),
              onPressed:_exportZip)),
            const SizedBox(width:10),
            Expanded(child:OutlinedButton.icon(
              icon:const Icon(Icons.share),
              label:const Text('Share last CSV'),
              onPressed:() async {
                final dir=await _ensureDir(await _appDir(),'sessions');
                final files=dir.listSync().whereType<File>()
                    .where((f)=>f.path.endsWith('.csv')).toList()
                  ..sort((a,b)=>b.lastModifiedSync().compareTo(a.lastModifiedSync()));
                if(files.isEmpty){ _snack('No sessions yet.'); return; }
                await Share.shareXFiles([XFile(files.first.path)],
                    text:'MadePlus ShoeML session');
              })),
          ]),
        ],
      ))),
    ]));
  }
}

/* ========================================================================= */
/*  TUTORIAL PAGE                                                             */
/* ========================================================================= */

class TutorialPage extends StatelessWidget {
  const TutorialPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final h   = Theme.of(context).textTheme.titleSmall!
        .copyWith(fontWeight: FontWeight.w700);
    final body = Theme.of(context).textTheme.bodyMedium!;

    Widget section(String title, String emoji, List<Widget> children) =>
        Card(
          color: cs.surfaceContainerHigh,
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Text(title, style: h),
                ]),
                const SizedBox(height: 10),
                ...children,
              ],
            ),
          ),
        );

    Widget step(String num, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius: 11,
              backgroundColor: cs.primaryContainer,
              child: Text(num,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.onPrimaryContainer)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: body)),
          ]),
        );

    Widget tip(String text) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.lightbulb_outline, size: 15, color: cs.primary),
            const SizedBox(width: 6),
            Expanded(
                child: Text(text,
                    style: body.copyWith(
                        fontStyle: FontStyle.italic,
                        color: cs.onSurfaceVariant))),
          ]),
        );

    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(children: [

        // ── Connect ──────────────────────────────────────────────────────────
        section('Connect to the shoe', '🦶', [
          step('1', 'Power on the shoe. The blue LED will pulse while advertising.'),
          step('2', 'Open the Dashboard tab and tap Scan & Connect.'),
          step('3', 'Once connected the LED goes solid and RSSI appears in the header.'),
          step('4', 'The app saves the last device and reconnects automatically on next launch.'),
          tip('If Bluetooth is off a banner appears at the top — tap Turn On to go directly to settings.'),
        ]),

        // ── Live metrics ─────────────────────────────────────────────────────
        section('Live metrics', '📊', [
          step('1', 'Dashboard shows roll, pitch, yaw (°), temperature (°F), step count, cadence (spm), stride length (m), and elevation Δh (m).'),
          step('2', 'Graphs tab shows time-series charts for all three angles, temperature, and real gait phase (STANCE / SWING) direct from the firmware.'),
          tip('Roll/pitch/yaw come from a complementary filter running at 200 Hz on the ESP32-S3. Gait phase uses the ZUPT stride detector — no approximation.'),
        ]),

        // ── Collect training data ─────────────────────────────────────────────
        section('Collect training data', '🎙️', [
          step('1', 'Go to the Training tab. Pick a label (walking, running, stairs up/down, standing, sitting).'),
          step('2', 'Tap Start — the app opens a CSV file and streams one row per BLE event directly to disk. RAM usage stays flat regardless of session length.'),
          step('3', 'Perform the activity naturally for at least 3–4 minutes. GPS route is recorded alongside the sensor data.'),
          step('4', 'Tap Stop & Save. A summary sheet shows distance, duration, and a map snapshot. GeoJSON, GPX, and KML files are saved alongside the CSV.'),
          step('5', 'Repeat for every label you want to classify. The dataset card shows window counts per label — aim for balanced counts across labels.'),
          tip('Collect in the same shoe and conditions you plan to use. Treadmill and outdoor walking produce different cadence and stride distributions.'),
        ]),

        // ── Train a model ────────────────────────────────────────────────────
        section('Train a combined model', '🌲', [
          step('1', 'After collecting sessions for at least two labels, tap Train & Save.'),
          step('2', 'The trainer reads ALL saved CSVs, extracts 3-second windows (1.5 s hop), and trains a Random Forest with 50 trees and max depth 12.'),
          step('3', 'Features: mean, variance, and RMS of roll, pitch, yaw, cadence, stride, and temperature — plus jerk (first-order angular differences) for each axis. 27 features total.'),
          step('4', 'After training a confusion matrix appears. Rows = actual label, columns = predicted. Diagonal = correct. Off-diagonal = misclassified.'),
          step('5', 'Any label with recall below 60% (shown in red) needs more data. Collect more sessions for that label and retrain.'),
          tip('Always train ONE model covering all your labels together. Two separate single-label models will split votes 50/50 — the app warns you if this happens.'),
          tip('The model JSON stores the trained_on field. The model browser shows accuracy, labels, window count, and a warning if the model was trained with an older feature set.'),
        ]),

        // ── Live classification ───────────────────────────────────────────────
        section('Live classification', '🔍', [
          step('1', 'In the model browser (Training tab), check the model you want to use as active.'),
          step('2', 'Go to Dashboard and tap Load active models.'),
          step('3', 'Walk, run, or climb stairs — the classifier card shows a bar for every label with its vote fraction (e.g. walking 86%, standing 14%).'),
          step('4', 'Min confidence slider: the winning label is only shown if it reaches this threshold. Default 60%. Lower it if the display is too quiet; raise it if it shows wrong labels.'),
          step('5', 'Still threshold (RMS jerk) controls the zero-motion gate. When the live jerk value is below the threshold, locomotion labels (walking, running, stairs) are suppressed and only sitting/standing can win.'),
          step('6', 'Watch the Live jerk readout while sitting still, then while walking slowly. Set the threshold just above your sitting jerk and just below your slowest walking jerk.'),
          tip('Typical sitting jerk: 0.01–0.04. Typical walking jerk: 0.15–0.40. Default threshold 0.08 works for most people but tune it to your shoe and gait.'),
        ]),

        // ── Replay ───────────────────────────────────────────────────────────
        section('Session replay', '▶️', [
          step('1', 'Go to the Replay tab and tap Load CSV.'),
          step('2', 'Pick any saved session file. The full header row and sample count are shown.'),
          step('3', 'Use the speed selector (0.5×, 1×, 2×, 5×) and tap Play.'),
          step('4', 'The replay feeds each row into the dashboard metric stream at the recorded rate — roll, pitch, yaw, cadence, stride, and temp all animate as if live.'),
          step('5', 'If a model is loaded in the classifier, live classification runs on the replayed data — useful for checking where the model makes mistakes on a known recording.'),
          tip('Pause at any point and scrub back using the progress slider to re-examine a specific moment.'),
        ]),

        // ── Export ───────────────────────────────────────────────────────────
        section('Export and backup', '📦', [
          step('1', 'Training tab → Export all as ZIP bundles every session CSV and model JSON into a single timestamped archive.'),
          step('2', 'Share it to Google Drive, email, or a PC for analysis in Python / scikit-learn.'),
          step('3', 'The ZIP folder structure is sessions/ and models/ — matches the on-device layout.'),
          tip('Session CSVs store raw °C from the firmware. The app converts to °F for display only — your data stays in SI units for PC analysis.'),
        ]),

        // ── Tips ─────────────────────────────────────────────────────────────
        section('General tips', '💡', [
          tip('Tap the Palette icon in the app bar to change theme colour.'),
          tip('The app auto-reconnects on foreground — no need to re-scan after unlocking the screen.'),
          tip('The firmware runs a 5-second watchdog. If the IMU or baro I2C bus locks up, the ESP32-S3 reboots automatically.'),
          tip('Baro readings update at 10 Hz using a non-blocking state machine — no delay() calls steal time from the 200 Hz IMU loop.'),
        ]),
      ]),
    );
  }
}

/* ========================================================================= */
/*  REPLAY PAGE                                                               */
/* ========================================================================= */

// Lightweight CSV row for replay — mirrors _RawRow in training_page.dart.
class _ReplayCsvRow {
  const _ReplayCsvRow({
    required this.t, required this.roll, required this.pitch,
    required this.yaw, this.tempC, this.cadence, this.strideM,
    this.dh, required this.label,
  });
  final double  t, roll, pitch, yaw;
  final double? tempC, cadence, strideM, dh;
  final String  label;

  static _ReplayCsvRow? fromCsv(String line) {
    try {
      final p = line.split(',');
      if (p.length < 9) return null;
      return _ReplayCsvRow(
        t:       double.parse(p[0].trim()),
        roll:    double.tryParse(p[1].trim()) ?? 0,
        pitch:   double.tryParse(p[2].trim()) ?? 0,
        yaw:     double.tryParse(p[3].trim()) ?? 0,
        tempC:   double.tryParse(p[4].trim()),
        cadence: double.tryParse(p[5].trim()),
        strideM: double.tryParse(p[6].trim()),
        dh:      double.tryParse(p[7].trim()),
        label:   p[8].trim(),
      );
    } catch (_) { return null; }
  }
}

class ReplayPage extends StatefulWidget {
  const ReplayPage({super.key});
  @override State<ReplayPage> createState() => _ReplayPageState();
}

class _ReplayPageState extends State<ReplayPage> {
  // ── File state ──────────────────────────────────────────────────────────
  File?         _file;
  String        _fileName   = '';
  List<_ReplayCsvRow> _rows       = [];
  String        _statusMsg  = 'No file loaded.';

  // ── Playback state ──────────────────────────────────────────────────────
  bool   _playing    = false;
  int    _cursor     = 0;   // current row index
  double _speed      = 1.0; // playback speed multiplier
  Timer? _timer;

  // ── Live metrics (replayed) ─────────────────────────────────────────────
  double  roll = 0, pitch = 0, yaw = 0;
  double? tempF;
  double  cadence = 0, stride = 0, dh = 0;

  // Progress as 0.0–1.0
  double get _progress =>
      _rows.isEmpty ? 0.0 : _cursor / (_rows.length - 1).clamp(1, 999999);

  static const _speeds = [0.5, 1.0, 2.0, 5.0];

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ── File loading ────────────────────────────────────────────────────────

  Future<void> _loadFile() async {
    _timer?.cancel();
    setState(() {
      _playing = false; _cursor = 0; _rows = [];
      _statusMsg = 'Loading…';
    });
    try {
      // Let user pick from the sessions directory
      final dir = await shoeMlRootDir();
      final sessDir = Directory('${dir.path}/sessions');
      if (!sessDir.existsSync()) {
        setState(() => _statusMsg = 'No sessions folder found. Record a session first.');
        return;
      }
      final files = sessDir.listSync().whereType<File>()
          .where((f) => f.path.endsWith('.csv')).toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      if (files.isEmpty) {
        setState(() => _statusMsg = 'No CSV files found. Record a session first.');
        return;
      }
      if (!mounted) return;

      // Show a picker dialog
      final picked = await showDialog<File>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pick a session'),
          content: SizedBox(
            width: 340,
            child: ListView(
              shrinkWrap: true,
              children: files.map((f) {
                final name = f.uri.pathSegments.last;
                final date = DateFormat('MMM d  HH:mm').format(f.lastModifiedSync());
                return ListTile(
                  dense: true,
                  title: Text(name, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(date, style: const TextStyle(fontSize: 11)),
                  onTap: () => Navigator.pop(ctx, f),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (picked == null) {
        setState(() => _statusMsg = 'No file selected.');
        return;
      }
      final lines = await picked.readAsLines();
      final rows  = <_ReplayCsvRow>[];
      for (final l in lines.skip(1)) {
        if (l.trim().isEmpty) continue;
        final r = _ReplayCsvRow.fromCsv(l);
        if (r != null) rows.add(r);
      }
      if (rows.isEmpty) {
        setState(() => _statusMsg = 'File has no valid data rows.');
        return;
      }
      setState(() {
        _file     = picked;
        _fileName = picked.uri.pathSegments.last;
        _rows     = rows;
        _cursor   = 0;
        _statusMsg = '${rows.length} samples  ·  '
            '${_dur(Duration(milliseconds: (rows.last.t * 1000).toInt()))}';
        _applyRow(rows.first);
      });
    } catch (e) {
      setState(() => _statusMsg = 'Error: $e');
    }
  }

  // ── Playback ────────────────────────────────────────────────────────────

  void _play() {
    if (_rows.isEmpty || _cursor >= _rows.length - 1) return;
    setState(() => _playing = true);
    _tick();
  }

  void _pause() {
    _timer?.cancel();
    setState(() => _playing = false);
  }

  void _stop() {
    _timer?.cancel();
    setState(() { _playing = false; _cursor = 0; });
    if (_rows.isNotEmpty) _applyRow(_rows.first);
  }

  void _tick() {
    _timer?.cancel();
    if (!_playing || _cursor >= _rows.length - 1) {
      if (mounted) setState(() => _playing = false);
      return;
    }
    // Compute delay from the timestamps of the next two rows.
    final cur  = _rows[_cursor];
    final next = _rows[_cursor + 1];
    final dtMs = ((next.t - cur.t) * 1000 / _speed).clamp(4.0, 2000.0);

    _timer = Timer(Duration(milliseconds: dtMs.toInt()), () {
      if (!mounted || !_playing) return;
      setState(() {
        _cursor++;
        _applyRow(_rows[_cursor]);
      });
      if (_cursor < _rows.length - 1) _tick();
      else setState(() => _playing = false);
    });
  }

  void _applyRow(_ReplayCsvRow r) {
    roll    = r.roll;
    pitch   = r.pitch;
    yaw     = r.yaw;
    tempF   = r.tempC != null ? r.tempC! * 9 / 5 + 32 : null;
    cadence = r.cadence ?? 0;
    stride  = r.strideM ?? 0;
    dh      = r.dh ?? 0;
  }

  void _scrub(double v) {
    _timer?.cancel();
    final idx = (v * (_rows.length - 1)).round().clamp(0, _rows.length - 1);
    setState(() { _cursor = idx; _applyRow(_rows[idx]); });
    if (_playing) _tick();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  String _dur(Duration d) =>
      '${d.inMinutes}m ${(d.inSeconds % 60).toString().padLeft(2,'0')}s';

  String _ts(int idx) {
    if (_rows.isEmpty) return '0:00';
    final t = Duration(milliseconds: (_rows[idx].t * 1000).toInt());
    return '${t.inMinutes}:${(t.inSeconds % 60).toString().padLeft(2,'0')}';
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final hasFile = _rows.isNotEmpty;

    return ListView(padding: const EdgeInsets.all(12), children: [
      // ── File picker card ────────────────────────────────────────────────
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Session replay',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Load a recorded CSV and play it back at variable speed. '
                'Metrics animate as if live — if a classifier model is loaded '
                'on the Dashboard it will run on the replayed data.',
              ),
              const SizedBox(height: 12),
              Row(children: [
                FilledButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Load CSV'),
                  onPressed: _loadFile,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hasFile ? _fileName : _statusMsg,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ]),
              if (hasFile) ...[
                const SizedBox(height: 6),
                Text(_statusMsg,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ],
          ),
        ),
      ),

      const SizedBox(height: 12),

      // ── Transport controls ──────────────────────────────────────────────
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              // Progress slider
              Row(children: [
                SizedBox(
                    width: 36,
                    child: Text(_rows.isEmpty ? '0:00' : _ts(_cursor),
                        style: const TextStyle(fontSize: 11))),
                Expanded(
                  child: Slider(
                    value: _progress,
                    onChanged: hasFile ? _scrub : null,
                  ),
                ),
                SizedBox(
                    width: 36,
                    child: Text(_rows.isEmpty ? '0:00' : _ts(_rows.length - 1),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 11))),
              ]),
              // Playback buttons
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                // Stop
                IconButton(
                  icon: const Icon(Icons.stop),
                  onPressed: hasFile ? _stop : null,
                  tooltip: 'Stop',
                ),
                // Play / Pause
                FilledButton(
                  onPressed: hasFile
                      ? (_playing ? _pause : _play)
                      : null,
                  child: Icon(_playing ? Icons.pause : Icons.play_arrow),
                ),
                const SizedBox(width: 16),
                // Speed selector
                DropdownButton<double>(
                  value: _speed,
                  items: _speeds.map((s) => DropdownMenuItem(
                      value: s,
                      child: Text('${s}×',
                          style: const TextStyle(fontSize: 13)))).toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _speed = v);
                    if (_playing) { _timer?.cancel(); _tick(); }
                  },
                ),
              ]),
            ],
          ),
        ),
      ),

      const SizedBox(height: 12),

      // ── Live metric tiles ───────────────────────────────────────────────
      if (hasFile)
        Card(
          color: cs.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('Metrics at ${_ts(_cursor)}',
                      style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  if (_playing)
                    Chip(
                      label: const Text('PLAYING'),
                      backgroundColor: cs.primaryContainer,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    )
                  else
                    Chip(
                      label: const Text('PAUSED'),
                      backgroundColor: cs.surfaceContainerHighest,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                ]),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    _tile(cs, 'Roll',    '${roll.toStringAsFixed(1)}°',
                        Icons.rotate_90_degrees_ccw),
                    _tile(cs, 'Pitch',   '${pitch.toStringAsFixed(1)}°',
                        Icons.rotate_90_degrees_cw),
                    _tile(cs, 'Yaw',     '${yaw.toStringAsFixed(1)}°',
                        Icons.refresh),
                    _tile(cs, 'Temp',
                        tempF != null ? '${tempF!.toStringAsFixed(1)} °F' : '—',
                        Icons.thermostat),
                    _tile(cs, 'Cadence', '${cadence.toStringAsFixed(1)} spm',
                        Icons.speed),
                    _tile(cs, 'Stride',  '${stride.toStringAsFixed(2)} m',
                        Icons.straighten),
                    _tile(cs, 'Elev Δh', '${dh.toStringAsFixed(2)} m',
                        Icons.landscape),
                  ],
                ),
                const SizedBox(height: 8),
                // Label from CSV
                if (_rows.isNotEmpty)
                  Row(children: [
                    const Icon(Icons.label_outline, size: 16),
                    const SizedBox(width: 6),
                    Text('Recorded label: ',
                        style: Theme.of(context).textTheme.bodySmall),
                    Chip(
                      label: Text(
                        _rows[_cursor].label.replaceAll('_', ' '),
                        style: const TextStyle(fontSize: 12),
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      backgroundColor: cs.secondaryContainer,
                    ),
                  ]),
              ],
            ),
          ),
        ),
    ]);
  }

  Widget _tile(ColorScheme cs, String label, String value, IconData icon) =>
      SizedBox(
        width: 150,
        child: Card(
          color: cs.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w500)),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              )),
            ]),
          ),
        ),
      );
}
