// MadePlus SHOEML — WITH AUTO-RECONNECT FIX AND DEBUG LOGS
// Copy this ENTIRE file to replace your main.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

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
import 'package:flutter/foundation.dart';
import 'dart:ui' as ui;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
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
      brightness: _mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
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
    _bootBle();
  }

  Future<void> _ensurePerms() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.storage,
    ].request();
  }

  Future<void> _bootBle() async {
    print("========== BOOT BLE START ==========");
    await _ensurePerms();

    if (Platform.isAndroid) {
      final svcOn = await Geolocator.isLocationServiceEnabled();
      if (!svcOn) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please turn ON Location services')),
          );
        }
        await Geolocator.openLocationSettings();
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    final ready = await _ble.waitUntilReady(timeout: const Duration(seconds: 10));
    if (!ready) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bluetooth not ready')),
        );
      }
      return;
    }

    _ble.enableAutoReconnect(true);
    await _ble.tryReconnectLast(delay: Duration.zero);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ble.startAutoScanner(period: const Duration(seconds: 8));
    });
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
        title: Row(children: [
          Image.asset("assets/madeplus_logo.png", height: 28,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          const SizedBox(width: 8),
          const Text("MADEPLUS SHOEML"),
        ]),
        actions: [
          IconButton(
            tooltip: "Theme & color",
            onPressed: widget.onPickColor,
            icon: const Icon(Icons.palette_outlined),
          ),
          IconButton(
            tooltip: "Bluetooth settings",
            onPressed: () => Geolocator.openAppSettings(),
            icon: const Icon(Icons.bluetooth),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: "Dashboard"),
          NavigationDestination(icon: Icon(Icons.show_chart), label: "Graphs"),
          NavigationDestination(icon: Icon(Icons.school_outlined), label: "Training"),
          NavigationDestination(icon: Icon(Icons.help_outline), label: "Tutorial"),
        ],
      ),
    );
  }
}

// Include the complete ShoeBle class from document 3 here
// (I'll include it in the artifact for you - it's the version with logging)
class ShoeBle {
  // ---------------- Streams ----------------
  final _connState = StreamController<DeviceConnectionState>.broadcast();
  Stream<DeviceConnectionState> get connection$ => _connState.stream;

  final _rssi = StreamController<int>.broadcast();
  Stream<int> get rssi$ => _rssi.stream;

  final roll$    = StreamController<double>.broadcast();
  final pitch$   = StreamController<double>.broadcast();
  final yaw$     = StreamController<double>.broadcast();
  final steps$   = StreamController<int>.broadcast();
  final cadence$ = StreamController<double>.broadcast();
  final stride$  = StreamController<double>.broadcast();
  final dh$      = StreamController<double>.broadcast();
  final _tempCtrl = StreamController<double?>.broadcast();
  Stream<double?> get temp$ => _tempCtrl.stream;

  // FIX: Debug log stream for on-screen display
  final _debugLog = StreamController<String>.broadcast();
  Stream<String> get debugLog$ => _debugLog.stream;
  final List<String> _logHistory = [];

  // ---------------- Core ----------------
  final _ble = FlutterReactiveBle(logLevel: LogLevel.verbose);

  String? _deviceId;
  String? _targetId;
  bool _isConnecting = false;
  bool _isConnected  = false;
  bool _disposed     = false;
  int  _epoch        = 0;

  // ---------------- Auto-reconnect ----------------
  bool _autoReconnect = true;
  Timer? _reconnectTimer;
  Duration _backoff = const Duration(seconds: 2);
  static const Duration _backoffMax = Duration(seconds: 30);
  bool get isAutoReconnectEnabled => _autoReconnect;

  // Periodic auto-scan / reconnect
  Timer? _autoScanTimer;
  bool _scanBusy = false;

  // Heartbeat-based disconnect detection
  Timer? _heartbeatTimer;
  DateTime? _lastDataTime;
  int _dataCount = 0;
  static const Duration _heartbeatInterval = Duration(seconds: 3);
  static const Duration _dataTimeout = Duration(seconds: 10);

  // ---------------- Persistence ----------------
  String? _lastId, _lastName;

  // ---------------- UUIDs ----------------
  final Uuid serviceUuid = Uuid.parse("0000feed-0000-1000-8000-00805f9b34fb");
  final Uuid rollUuid    = Uuid.parse("0000a001-0000-1000-8000-00805f9b34fb");
  final Uuid pitchUuid   = Uuid.parse("0000a002-0000-1000-8000-00805f9b34fb");
  final Uuid yawUuid     = Uuid.parse("0000a003-0000-1000-8000-00805f9b34fb");
  final Uuid tempUuid    = Uuid.parse("0000b001-0000-1000-8000-00805f9b34fb");
  final Uuid stepsUuid   = Uuid.parse("0000c001-0000-1000-8000-00805f9b34fb");
  final Uuid cadenceUuid = Uuid.parse("0000c002-0000-1000-8000-00805f9b34fb");
  final Uuid strideUuid  = Uuid.parse("0000c003-0000-1000-8000-00805f9b34fb");
  final Uuid altdhUuid   = Uuid.parse("0000c004-0000-1000-8000-00805f9b34fb");

  // ---------------- Subscriptions ----------------
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _sRoll, _sPitch, _sYaw, _sTemp, _sSteps, _sCad, _sStride, _sDh;

  // FIX: Enhanced logging function
  void _log(String msg) {
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    final logMsg = '[$timestamp] $msg';
    print(logMsg); // Console
    debugPrint(logMsg); // Flutter debug
    
    _logHistory.add(logMsg);
    if (_logHistory.length > 50) _logHistory.removeAt(0);
    
    if (!_debugLog.isClosed) {
      _debugLog.add(logMsg);
    }
  }

  List<String> getLogHistory() => List.from(_logHistory);

  // ---------------- Controls ----------------
  void enableAutoReconnect(bool on) {
    _autoReconnect = on;
    _log('Auto-reconnect ${on ? "ENABLED" : "DISABLED"}');
    if (!on) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    } else {
      if (!_isConnected && !_isConnecting) {
        _scheduleReconnect();
      }
    }
  }

  Stream<BleStatus> get bleStatus$ => _ble.statusStream;

  Future<bool> waitUntilReady({Duration timeout = const Duration(seconds: 8)}) async {
    BleStatus? latest;
    final sub = _ble.statusStream.listen((s) => latest = s);
    final start = DateTime.now();
    try {
      while (DateTime.now().difference(start) < timeout) {
        if (latest == BleStatus.ready) {
          _log('BLE adapter READY');
          return true;
        }
        await Future.delayed(const Duration(milliseconds: 150));
      }
      _log('BLE adapter timeout (status: $latest)');
      return latest == BleStatus.ready;
    } finally {
      await sub.cancel();
    }
  }

  Future<DiscoveredDevice?> scanOncePreferLast({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    await _loadLast();
    final hasName = _lastName != null && _lastName!.trim().isNotEmpty;
    final hasId   = _lastId   != null && _lastId!.trim().isNotEmpty;

    _log('Scanning (prefer: id=$_lastId, name=$_lastName)...');
    
    final List<DiscoveredDevice> hits = [];
    DiscoveredDevice? best;

    final sub = _ble.scanForDevices(
      withServices: const [],
      scanMode: ScanMode.lowLatency,
    ).listen((d) {
      hits.add(d);
      if (hasId && d.id == _lastId) {
        best = d; return;
      }
      if (hasName && d.name.trim().isNotEmpty && d.name.trim() == _lastName!.trim()) {
        best ??= d; return;
      }
    }, onError: (_) {}, cancelOnError: true);

    await Future.delayed(timeout);
    await sub.cancel();

    if (best != null) {
      _log('Found preferred device: ${best!.id}');
      return best;
    }

    final tokens = ['shoe', 'shoeml', 'made', 'madeplus', 'esp32'];
    DiscoveredDevice? nameHit;
    int bestRssi = -999;
    for (final d in hits) {
      final n = d.name.toLowerCase();
      if (tokens.any((t) => n.contains(t))) {
        if (d.rssi > bestRssi) { nameHit = d; bestRssi = d.rssi; }
      }
    }
    if (nameHit != null) {
      _log('Found by name: ${nameHit!.id} (${nameHit!.name})');
      return nameHit;
    }

    hits.sort((a,b) => b.rssi.compareTo(a.rssi));
    if (hits.isNotEmpty) {
      _log('Found strongest: ${hits.first.id} (RSSI: ${hits.first.rssi})');
    } else {
      _log('No devices found in scan');
    }
    return hits.isEmpty ? null : hits.first;
  }

  Future<void> connectAuto(String id, {String? hintName, bool subscribe = true}) async {
    await _saveLast(id, name: hintName);
    await connect(id, subscribe: subscribe);
  }

  Future<void> connectLast({bool subscribe = true}) async {
    await _loadLast();
    if (_lastId != null && _lastId!.isNotEmpty) {
      await connect(_lastId!, subscribe: subscribe);
    }
  }

  Future<void> forgetLast() async {
    try {
      final f = File("${(await _cfgDir()).path}/last_device.json");
      if (await f.exists()) await f.delete();
    } catch (_) {}
    _lastId = _lastName = null;
    _log('Forgot last device');
  }

  Stream<ConnectionStateUpdate> _connectStreamForId(String id) {
    if (Platform.isAndroid) {
      return _ble.connectToAdvertisingDevice(
        id: id,
        withServices: const [],
        prescanDuration: const Duration(seconds: 2),
        servicesWithCharacteristicsToDiscover: {
          serviceUuid: [rollUuid, pitchUuid, yawUuid, tempUuid, stepsUuid, cadenceUuid, strideUuid, altdhUuid],
        },
        connectionTimeout: const Duration(seconds: 12),
      );
    }
    return _ble.connectToDevice(id: id, connectionTimeout: const Duration(seconds: 12));
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _lastDataTime = DateTime.now();
    _dataCount = 0;
    
    _log('Heartbeat monitor STARTED');
    
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_disposed || !_isConnected) return;
      
      final now = DateTime.now();
      final timeSinceData = now.difference(_lastDataTime ?? now);
      
      _log('❤️ Heartbeat: ${timeSinceData.inSeconds}s since data (count: $_dataCount)');
      
      if (timeSinceData > _dataTimeout) {
        _log('💀 TIMEOUT! No data for ${timeSinceData.inSeconds}s');
        _handleDisconnect();
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _updateDataTimestamp() {
    _lastDataTime = DateTime.now();
    _dataCount++;
  }

  void _handleDisconnect() {
    if (!_isConnected && !_isConnecting) {
      _log('Disconnect ignored (already disconnected)');
      return;
    }
    
    _log('⚠️ HANDLING DISCONNECT');
    
    _isConnected = false;
    _isConnecting = false;
    _scanBusy = false;
    _deviceId = null;
    
    _stopHeartbeat();
    _safeAdd(_connState, DeviceConnectionState.disconnected);
    
    _teardownNotifies(cancelNative: false);
    
    if (_autoReconnect) {
      _log('Auto-reconnect enabled, scheduling...');
      _scheduleReconnect();
    } else {
      _log('Auto-reconnect disabled, staying disconnected');
    }
  }

  Future<void> connect(String id, {bool subscribe = true}) async {
    if (_disposed) return;

    if (_isConnected && _deviceId == id) {
      _targetId = id;
      _log('Already connected to $id');
      return;
    }
    if (_isConnecting && _targetId == id) {
      _log('Already connecting to $id');
      return;
    }

    _targetId = id;
    _isConnecting = true;
    _scanBusy = true;
    _log('🔗 Connecting to $id...');

    if (_connSub != null && _deviceId != null && _deviceId != id) {
      try { 
        await _connSub?.cancel(); 
      } catch (_) {}
      _connSub = null;
      _isConnected = false;
      _deviceId = null;
    }

    final myEpoch = ++_epoch;

    try {
      _connSub = _connectStreamForId(id).listen((u) async {
        if (_disposed || myEpoch != _epoch) return;

        _log('Connection event: ${u.connectionState}');
        _safeAdd(_connState, u.connectionState);

        if (u.connectionState == DeviceConnectionState.connected) {
          _deviceId = id;
          _isConnected = true;
          _isConnecting = false;
          _scanBusy = false;
          _backoff = const Duration(seconds: 2);
          await _saveLast(id);

          _log('✅ CONNECTED successfully!');
          _startHeartbeat();

          if (subscribe) {
            await Future.delayed(const Duration(milliseconds: 250));
            await _subscribeAll(myEpoch);
          }
        } else if (u.connectionState == DeviceConnectionState.disconnected) {
          _log('Disconnect event from stream');
          _handleDisconnect();
        }
      }, 
      onDone: () {
        _log('Connection stream COMPLETED');
        if (_disposed || myEpoch != _epoch) return;
        _handleDisconnect();
      },
      onError: (e, st) async {
        _log('Connection stream ERROR: $e');
        if (_disposed || myEpoch != _epoch) return;
        _handleDisconnect();
      }, 
      cancelOnError: true);
    } catch (e) {
      _log('Connect EXCEPTION: $e');
      _isConnecting = false;
      _scanBusy = false;
      
      if (_autoReconnect) {
        _scheduleReconnect();
      }
    }
  }

  Future<void> enableNotificationsNow() async {
    if (!_isConnected || _deviceId == null) return;
    _log('Enabling notifications now...');
    final myEpoch = ++_epoch;
    await _teardownNotifies(cancelNative: true);
    await _subscribeAll(myEpoch);
  }

  Future<void> disconnect() async {
    _log('🔌 Manual disconnect requested');
    
    _reconnectTimer?.cancel(); 
    _reconnectTimer = null;
    _stopHeartbeat();
    _epoch++;
    
    await _teardownNotifies(cancelNative: _isConnected);
    
    try { await _connSub?.cancel(); } catch (_) {}
    _connSub = null;
    
    _isConnecting = false;
    _scanBusy = false;
    _deviceId = null;
    _isConnected = false;
    
    _safeAdd(_connState, DeviceConnectionState.disconnected);
  }

  Future<void> tryReconnectLast({Duration delay = const Duration(milliseconds: 300)}) async {
    if (_disposed || !_autoReconnect) {
      _log('Reconnect skipped: disposed=$_disposed, auto=$_autoReconnect');
      return;
    }
    
    await _loadLast();
    
    if (delay > Duration.zero) await Future.delayed(delay);
    
    if (_isConnected || _isConnecting || _scanBusy) {
      _log('Reconnect blocked: conn=$_isConnected, connecting=$_isConnecting, busy=$_scanBusy');
      return;
    }

    _log('🔄 Attempting reconnect...');

    if (_lastId != null && _lastId!.isNotEmpty) {
      try {
        _log('Trying last device: $_lastId');
        await connect(_lastId!);
        return;
      } catch (e) {
        _log('Direct connect failed: $e');
      }
    }

    try {
      _log('Starting scan...');
      final found = await scanOncePreferLast(timeout: const Duration(seconds: 7));
      if (found != null) {
        _log('Found device, connecting...');
        await connectAuto(found.id, hintName: found.name.isNotEmpty ? found.name : null);
      } else {
        _log('❌ No devices found');
      }
    } catch (e) {
      _log('Scan failed: $e');
    }
  }

  Future<void> _subscribeAll(int myEpoch) async {
    if (_disposed || _deviceId == null || myEpoch != _epoch) return;
    final id = _deviceId!;

    Future<StreamSubscription<List<int>>> sub(
      Uuid charId, void Function(List<int>) onData) async {
      final q = QualifiedCharacteristic(
        deviceId: id, 
        serviceId: serviceUuid, 
        characteristicId: charId
      );
      return _ble.subscribeToCharacteristic(q).listen(
        (bytes) { 
          if (_disposed || myEpoch != _epoch) return;
          _updateDataTimestamp();
          onData(bytes); 
        },
        onError: (e, st) {
          _log('Characteristic error: $e');
        }, 
        cancelOnError: false
      );
    }

    try {
      _sRoll   = await sub(rollUuid,   (b) => _safeAdd(roll$,    _f32(b)));
      _sPitch  = await sub(pitchUuid,  (b) => _safeAdd(pitch$,   _f32(b)));
      _sYaw    = await sub(yawUuid,    (b) => _safeAdd(yaw$,     _f32(b)));
      _sTemp   = await sub(tempUuid,   (b) { 
        final v = _f32Nullable(b); 
        if (v != null) _tempCtrl.add(v); 
      });
      _sSteps  = await sub(stepsUuid,  (b) => _safeAdd(steps$,   _i32(b)));
      _sCad    = await sub(cadenceUuid,(b) => _safeAdd(cadence$, _f32(b)));
      _sStride = await sub(strideUuid, (b) => _safeAdd(stride$,  _f32(b)));
      _sDh     = await sub(altdhUuid,  (b) => _safeAdd(dh$,      _f32(b)));
      
      _log('✅ All characteristics subscribed');
    } catch (e) {
      _log('Subscribe error: $e');
    }
  }

  Future<void> _teardownNotifies({required bool cancelNative}) async {
    Future<void> _cancel(StreamSubscription? s) async { 
      try { await s?.cancel(); } catch (_) {} 
    }
    if (cancelNative) {
      await _cancel(_sRoll);   
      await _cancel(_sPitch);  
      await _cancel(_sYaw);
      await _cancel(_sTemp);   
      await _cancel(_sSteps);  
      await _cancel(_sCad);
      await _cancel(_sStride); 
      await _cancel(_sDh);
    }
    _sRoll = _sPitch = _sYaw = _sTemp = _sSteps = _sCad = _sStride = _sDh = null;
  }

  void _scheduleReconnect() {
    if (_disposed || !_autoReconnect) {
      _log('Reconnect scheduling skipped');
      return;
    }
    
    if (_isConnected || _isConnecting) {
      _log('Reconnect skip: already connected/connecting');
      return;
    }
    
    if (_reconnectTimer != null) {
      _log('Reconnect already scheduled');
      return;
    }

    final jitter = Duration(milliseconds: math.Random().nextInt(300));
    final when   = _backoff + jitter;

    _log('⏰ Scheduling reconnect in ${when.inSeconds}s');

    _reconnectTimer = Timer(when, () async {
      _reconnectTimer = null;
      
      if (_disposed || !_autoReconnect || _isConnected || _isConnecting) {
        return;
      }

      await tryReconnectLast(delay: Duration.zero);

      if (!_isConnected) {
        final nextMs = (_backoff.inMilliseconds * 2).clamp(2000, _backoffMax.inMilliseconds);
        _backoff = Duration(milliseconds: nextMs);
        _log('Backoff increased to ${_backoff.inSeconds}s');
        _scheduleReconnect();
      }
    });
  }

  void startAutoScanner({
    Duration period = const Duration(seconds: 10),
    Duration firstDelay = Duration.zero,
  }) {
    if (_disposed) return;
    
    stopAutoScanner();
    enableAutoReconnect(true);

    _log('Auto-scanner started (period: ${period.inSeconds}s)');

    Future.delayed(firstDelay, () {
      if (!_disposed && _autoReconnect && !_isConnected && !_isConnecting) {
        tryReconnectLast(delay: Duration.zero);
      }
    });

    _autoScanTimer = Timer.periodic(period, (_) {
      if (_disposed || !_autoReconnect) return;
      if (_isConnected || _isConnecting || _scanBusy) return;

      _log('⏰ Auto-scan triggered');
      tryReconnectLast(delay: Duration.zero);
    });
  }

  void stopAutoScanner() {
    try { 
      _autoScanTimer?.cancel(); 
    } catch (_) {}
    _autoScanTimer = null;
  }

  // ---------------- Helpers ----------------
  void _safeAdd<T>(StreamController<T> c, T v) {
    if (!_disposed && !c.isClosed) {
      try { c.add(v); } catch (_) {}
    }
  }

  double _f32(List<int> b) {
    if (b.length < 4) return double.nan;
    final bd = ByteData.sublistView(Uint8List.fromList(b));
    return bd.getFloat32(0, Endian.little);
  }

  double? _f32Nullable(List<int> b) {
    if (b.length < 4) return null;
    final bd = ByteData.sublistView(Uint8List.fromList(b));
    final v = bd.getFloat32(0, Endian.little);
    return (v.isNaN || v.isInfinite) ? null : v;
  }

  int _i32(List<int> b) {
    if (b.length < 4) return 0;
    final bd = ByteData.sublistView(Uint8List.fromList(b));
    return bd.getInt32(0, Endian.little);
  }

  // ---------------- Persistence ----------------
  Future<Directory> _cfgDir() async {
    final d = await getApplicationDocumentsDirectory();
    final dir = Directory("${d.path}/shoeml");
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<void> _saveLast(String id, {String? name}) async {
    try {
      final f = File("${(await _cfgDir()).path}/last_device.json");
      await f.writeAsString(jsonEncode({"id": id, "name": name}), flush: true);
      _lastId = id; 
      _lastName = name;
    } catch (e) {
      _log('Failed to save: $e');
    }
  }

  Future<void> _loadLast() async {
    try {
      final f = File("${(await _cfgDir()).path}/last_device.json");
      if (await f.exists()) {
        final m = jsonDecode(await f.readAsString()) as Map;
        _lastId = m["id"] as String?;
        _lastName = m["name"] as String?;
      }
    } catch (_) {}
  }

  // ---------------- Dispose ----------------
  void dispose() {
    _log('Disposing ShoeBle');
    _disposed = true;
    _reconnectTimer?.cancel(); 
    _reconnectTimer = null;
    _autoScanTimer?.cancel();  
    _autoScanTimer = null;
    _stopHeartbeat();
    _epoch++;
    
    try { _connSub?.cancel(); } catch (_) {}
    _connSub = null;

    _sRoll = _sPitch = _sYaw = _sTemp = _sSteps = _sCad = _sStride = _sDh = null;

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
    try { _debugLog.close(); } catch (_) {}
  }
}


/* -------------------------------------------------------------------------- */
/*                          DASHBOARD WITH DEBUG                              */
/* -------------------------------------------------------------------------- */

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
  int steps = 0, rssi = 0;
  bool _safeConnect = false; // Changed to false for easier testing
  DeviceConnectionState conn = DeviceConnectionState.disconnected;

  StreamSubscription? _s1, _s2, _s3, _s4, _s5, _s6, _s7, _s8, _s9, _s10;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    _s1 = widget.ble.connection$.listen((c) => setState(() => conn = c));
    _s2 = widget.ble.roll$.stream.listen((v) => setState(() => roll = v));
    _s3 = widget.ble.pitch$.stream.listen((v) => setState(() => pitch = v));
    _s4 = widget.ble.yaw$.stream.listen((v) => setState(() => yaw = v));
    _s5 = widget.ble.temp$.listen((v) => setState(() => tempC = v));
    _s6 = widget.ble.steps$.stream.listen((v) => setState(() => steps = v));
    _s7 = widget.ble.cadence$.stream.listen((v) => setState(() => cadence = v));
    _s8 = widget.ble.stride$.stream.listen((v) => setState(() => stride = v));
    _s9 = widget.ble.dh$.stream.listen((v) => setState(() => dh = v));
    _s10 = widget.ble.rssi$.listen((v) => setState(() => rssi = v));
  }

  @override
  void dispose() {
    for (final s in [_s1, _s2, _s3, _s4, _s5, _s6, _s7, _s8, _s9, _s10]) {
      s?.cancel();
    }
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
    final d = await widget.ble.scanOncePreferLast();
    if (!mounted) return;
    if (d == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No device found nearby.")),
      );
      return;
    }
    setState(() => _id = d.id);
    await widget.ble.connectAuto(d.id,
        hintName: d.name.isNotEmpty ? d.name : null,
        subscribe: !_safeConnect);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          // Connection Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bluetooth),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_connLabel(conn),
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(_id ?? "Not connected",
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                          avatar: const Icon(Icons.network_cell, size: 16),
                          label: Text("RSSI $rssi dBm")),
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

          // Metrics
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

          const SizedBox(height: 12),

          // ⭐ DEBUG LOG WIDGET - THIS IS THE KEY ADDITION ⭐
          _DebugLogWidget(ble: widget.ble),
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
                    Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                              DEBUG LOG WIDGET                              */
/* -------------------------------------------------------------------------- */

class _DebugLogWidget extends StatefulWidget {
  final ShoeBle ble;
  const _DebugLogWidget({required this.ble});

  @override
  State<_DebugLogWidget> createState() => _DebugLogWidgetState();
}

class _DebugLogWidgetState extends State<_DebugLogWidget> {
  final List<String> _logs = [];
  StreamSubscription? _sub;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Load existing logs
    _logs.addAll(widget.ble.getLogHistory());
    
    // Listen for new logs
    _sub = widget.ble.debugLog$.listen((log) {
      if (mounted) {
        setState(() {
          _logs.add(log);
          if (_logs.length > 50) _logs.removeAt(0);
        });
        // Auto-scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bug_report, size: 20),
                    const SizedBox(width: 8),
                    const Text('Debug Log', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(width: 8),
                    Chip(
                      label: Text('${_logs.length}'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      tooltip: 'Clear logs',
                      onPressed: () => setState(() => _logs.clear()),
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: 'Test reconnect',
                      onPressed: () {
                        widget.ble.disconnect();
                        Future.delayed(const Duration(milliseconds: 500), () {
                          widget.ble.connectLast();
                        });
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            height: 300,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.surface.withOpacity(0.5),
              border: Border(
                top: BorderSide(color: cs.outline.withOpacity(0.2)),
              ),
            ),
            child: _logs.isEmpty
                ? const Center(
                    child: Text('Waiting for logs...',
                        style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)))
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _logs.length,
                    itemBuilder: (_, i) {
                      final log = _logs[i];
                      Color? color;
                      IconData? icon;
                      
                      if (log.contains('❤️')) {
                        color = Colors.green;
                        icon = Icons.favorite;
                      } else if (log.contains('💀') || log.contains('⚠️')) {
                        color = Colors.red;
                        icon = Icons.warning;
                      } else if (log.contains('✅')) {
                        color = Colors.blue;
                        icon = Icons.check_circle;
                      } else if (log.contains('🔄') || log.contains('⏰')) {
                        color = Colors.orange;
                        icon = Icons.refresh;
                      } else if (log.contains('🔗')) {
                        color = Colors.purple;
                        icon = Icons.link;
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (icon != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 6, top: 2),
                                child: Icon(icon, size: 12, color: color),
                              ),
                            Expanded(
                              child: Text(
                                log,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'Courier',
                                  color: color ?? cs.onSurface.withOpacity(0.8),
                                  height: 1.3,
                                ),
                              ),
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
    s.add(FlSpot(t, v.toDouble()));
    if (s.length > keep) s.removeAt(0);
  }

  @override
  void initState() {
    super.initState();
    _sr = widget.ble.roll$.stream.listen((v) {
      setState(() {
        _t += 0.1;
        _push(_r, _t, v);
      });
    });
    _sp = widget.ble.pitch$.stream.listen((v) {
      setState(() {
        _t += 0.1;
        _push(_p, _t, v);
      });
    });
    _sy = widget.ble.yaw$.stream.listen((v) {
      setState(() {
        _t += 0.1;
        _push(_y, _t, v);
      });
    });
    _t0 ??= DateTime.now();
    _sTemp = widget.ble.temp$.listen((v) {
      if (v == null) return;
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
        ],
      ),
    );
  }

  Widget _lineCard(ColorScheme cs, String title, List<FlSpot> pts,
      {double? minY, double? maxY}) {
    return Card(
      color: cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              minY: minY,
              maxY: maxY,
              gridData: const FlGridData(show: true),
              titlesData: const FlTitlesData(
                leftTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: true)),
                bottomTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void dispose() {
    for (final s in [_sr, _sp, _sy, _st, _sc, _ss, _sdh]) {
      s?.cancel();
    }
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
    if (!mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Saved: ${file.path.split('/').last}")),
    );

    return file;
  }

  Future<void> _toggleCollect() async {
    setState(() => _collecting = !_collecting);
    if (_collecting) {
      _buffer.clear();
      _track = [];
      _trackTs = [];
      await _startLocation();
    } else {
      await _stopLocation();
      _lastDistM = _computeDistanceMeters();
      _lastDur   = _tStart != null ? DateTime.now().difference(_tStart!) : Duration.zero;
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
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

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            "Trained acc ${(acc * 100).toStringAsFixed(1)}% • Saved $name")));
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
                        onPressed: _toggleCollect,
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
                          FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialZoom: 16,
                              initialCenter: _track.isNotEmpty ? _track.last : const LatLng(0, 0),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.madeplus.shoeml',
                              ),
                              if (_track.length > 1)
                                PolylineLayer(polylines: [Polyline(points: _track, strokeWidth: 4)]),
                              if (_track.isNotEmpty)
                                MarkerLayer(markers: [
                                  Marker(width: 30, height: 30, point: _track.first, child: const Icon(Icons.flag,  color: Colors.green)),
                                  Marker(width: 30, height: 30, point: _track.last,  child: const Icon(Icons.place, color: Colors.red)),
                                ]),
                            ],
                          ),
                          Positioned(
                            right: 8, top: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
                              child: Text('Dist: ' + _formatDistance(_computeDistanceMeters()),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _track = [LatLng(pos.latitude, pos.longitude)];
        _trackTs = [DateTime.now()];
      });
    } catch (_) {}
    await _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 3,
      ),
    ).listen((pos) {
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
    if (_track.length < 2) return 0;
    const Distance d = Distance();
    double sum = 0;
    for (int i = 1; i < _track.length; i++) {
      sum += d.as(LengthUnit.Meter, _track[i - 1], _track[i]);
    }
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
    if (meters < 1 || dur.inSeconds == 0) return '—';
    final km = meters / 1000.0;
    final secPerKm = dur.inSeconds / km;
    final m = (secPerKm ~/ 60);
    final s = (secPerKm % 60).round();
    return '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')} / km';
  }

  Future<void> _fitRoute() async {
    if (_track.length < 2) return;
    double minLat = _track.first.latitude, maxLat = _track.first.latitude;
    double minLon = _track.first.longitude, maxLon = _track.first.longitude;
    for (final p in _track) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    final bounds = LatLngBounds(LatLng(minLat, minLon), LatLng(maxLat, maxLon));
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(24)),
    );
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<File?> _saveGeoJson(File csvFile) async {
    try {
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
      final name = "track_${_label.replaceAll(RegExp(r'\W+'), '_')}_$stamp.kml";
      final f = File('${dir.path}/$name');
      final b = StringBuffer();
      b.writeln('<?xml version="1.0" encoding="UTF-8"?>');
      b.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
      b.writeln('  <Document>');
      b.writeln('    <name>' + (_label) + '</name>');
      b.writeln('    <Placemark>');
      b.writeln('      <name>Route</name>');
      b.writeln('      <LineString>');
      b.writeln('        <tessellate>1</tessellate>');
      b.writeln('        <coordinates>');
      for (int i = 0; i < _track.length; i++) {
        final p = _track[i];
        final t = (i < _trackTs.length) ? _trackTs[i].toUtc().toIso8601String() : DateTime.now().toUtc().toIso8601String();
        b.writeln('          ${p.longitude},${p.latitude},0 <!-- ${t} -->');
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
    if (!mounted) return;
    await showModalBottomSheet(
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
    final mc = MapController();

    return SizedBox(
      height: 260,
      child: FlutterMap(
        mapController: mc,
        options: MapOptions(
          initialCenter: track.isNotEmpty ? track.first : const LatLng(20, 0),
          initialZoom: 14,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
          onMapReady: () {
            if (track.length >= 2) {
              final bounds = _boundsFromTrack(track);
              mc.fitCamera(
                CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(24)),
              );
            }
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c'],
            userAgentPackageName: 'shoeml_learning',
          ),
          if (track.isNotEmpty)
            PolylineLayer(
              polylines: [
                Polyline(points: track, strokeWidth: 4),
              ],
            ),
          if (track.isNotEmpty)
            MarkerLayer(
              markers: [
                Marker(
                  point: track.first,
                  width: 28, height: 28,
                  child: const Icon(Icons.flag, size: 24),
                ),
                Marker(
                  point: track.last,
                  width: 28, height: 28,
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
    double minLat = pts.first.latitude,  maxLat = pts.first.latitude;
    double minLon = pts.first.longitude, maxLon = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    return LatLngBounds(LatLng(minLat, minLon), LatLng(maxLat, maxLon));
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
