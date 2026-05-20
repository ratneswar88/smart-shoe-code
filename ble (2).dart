
// lib/ble.dart — Auto‑reconnect + persistence for MADEPLUS ShoeML
// Drop‑in replacement for your project.
// - Persists last device id/name at: <app>/files/shoeml/last_device.json
// - Auto‑reconnects on disconnect with jittered exponential backoff
// - Periodically scans to find the device again if the id is stale
// - Exposes the same public signals your UI already uses (roll$/pitch$/...)
// - Keeps delegate methods scanOnce() and connect(String id) so your UI code
//   in DashboardPage continues to compile without changes.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:path_provider/path_provider.dart';

class ShoeBle {
  // ---------------- Streams ----------------
  final _connState = StreamController<DeviceConnectionState>.broadcast();
  Stream<DeviceConnectionState> get connection$ => _connState.stream;

  final _rssiCtrl = StreamController<int>.broadcast();
  Stream<int> get rssi$ => _rssiCtrl.stream;

  final _roll$    = StreamController<double>.broadcast();
  final _pitch$   = StreamController<double>.broadcast();
  final _yaw$     = StreamController<double>.broadcast();
  final _steps$   = StreamController<int>.broadcast();
  final _cadence$ = StreamController<double>.broadcast();
  final _stride$  = StreamController<double>.broadcast();
  final _dh$      = StreamController<double>.broadcast();

  Stream<double> get roll$    => _roll$.stream;
  Stream<double> get pitch$   => _pitch$.stream;
  Stream<double> get yaw$     => _yaw$.stream;
  Stream<int>    get steps$   => _steps$.stream;
  Stream<double> get cadence$ => _cadence$.stream;
  Stream<double> get stride$  => _stride$.stream;
  Stream<double> get dh$      => _dh$.stream;

  final _tempCtrl = StreamController<double?>.broadcast();
  Stream<double?> get temp$ => _tempCtrl.stream;

  // ---------------- Core ----------------
  final FlutterReactiveBle _ble;
  ShoeBle({LogLevel logLevel = LogLevel.verbose}) : _ble = FlutterReactiveBle(logLevel: logLevel) {
    // fire up a very light auto‑scan loop so "app comes to foreground with shoe back on"
    // causes reconnection even if UI never presses Scan.
    _startBackgroundScanner();
  }

  String? _deviceId;               // currently connected id
  String? _targetId;               // id we are trying to connect
  bool _isConnecting = false;
  bool _isConnected  = false;
  bool _disposed     = false;
  int  _epoch        = 0;          // invalidate old listeners after resubscribe

  // ---------------- Auto‑reconnect ----------------
  bool _autoReconnect = true;
  Timer? _reconnectTimer;
  Duration _backoff = const Duration(seconds: 2);
  static const Duration _backoffMax = Duration(seconds: 30);

  // Periodic auto‑scan helper
  Timer? _autoScanTimer;
  bool _scanBusy = false;

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

  // ---------------- Public API (compatible with your UI) ----------------

  /// One‑shot scan restricted to our service; returns the first hit (or null).
  Future<DiscoveredDevice?> scanOnce({Duration timeout = const Duration(seconds: 6)}) async {
    DiscoveredDevice? pick;
    final sub = _ble.scanForDevices(withServices: [serviceUuid]).listen((d) {
      pick ??= d;
    }, onError: (_) {}, cancelOnError: true);

    await Future.delayed(timeout);
    await sub.cancel();
    return pick;
  }

  /// Scan that *prefers* the last remembered id/name, else any device with our service.
  Future<DiscoveredDevice?> scanOncePreferLast({Duration timeout = const Duration(seconds: 6)}) async {
    await _loadLast();
    final hasName = _lastName != null && _lastName!.trim().isNotEmpty;
    final hasId   = _lastId   != null && _lastId!.trim().isNotEmpty;
    final wantSpecific = hasId || hasName;

    final stream = _ble.scanForDevices(withServices: wantSpecific ? const [] : [serviceUuid]);

    DiscoveredDevice? pick;
    final sub = stream.listen((d) {
      if (hasId && d.id == _lastId) { pick ??= d; return; }
      if (hasName && d.name.trim().isNotEmpty && d.name.trim() == _lastName!.trim()) { pick ??= d; return; }
      if (!wantSpecific) pick ??= d;
    }, onError: (_) {}, cancelOnError: true);

    await Future.delayed(timeout);
    await sub.cancel();
    return pick;
  }

  /// Connect by id and automatically subscribe to all notifications.
  Future<void> connect(String id, {bool subscribe = true}) async {
    if (_disposed) return;

    if (_isConnected && _deviceId == id) { _targetId = id; return; }
    if (_isConnecting && _targetId == id) return;

    _targetId = id;
    _isConnecting = true;

    // Cancel previous connection stream if it was for another id.
    if (_connSub != null && _deviceId != null && _deviceId != id) {
      try { await _connSub?.cancel(); } catch (_) {}
      _connSub = null;
      _isConnected = false;
      _deviceId = null;
    }

    final myEpoch = ++_epoch;

    _connSub = _ble
        .connectToDevice(id: id, connectionTimeout: const Duration(seconds: 8))
        .listen((u) async {
      if (_disposed || myEpoch != _epoch) return;

      _safeAdd(_connState, u.connectionState);

      if (u.connectionState == DeviceConnectionState.connected) {
        _deviceId = id;
        _isConnected = true;
        _isConnecting = false;
        _backoff = const Duration(seconds: 2);
        await _saveLast(id);

        if (subscribe) {
          await _subscribeAll(myEpoch);
        }
      } else if (u.connectionState == DeviceConnectionState.disconnected) {
        _isConnected = false;
        _isConnecting = false;
        await _teardownNotifies(cancelNative: false);
        _deviceId = null;
        _scheduleReconnect();
      }
    }, onError: (e, st) async {
      if (_disposed || myEpoch != _epoch) return;
      _isConnected = false;
      _isConnecting = false;
      _safeAdd(_connState, DeviceConnectionState.disconnected);
      await _teardownNotifies(cancelNative: false);
      _deviceId = null;
      _scheduleReconnect();
    }, cancelOnError: true);
  }

  /// Try reconnecting to the last saved device; if not found, do a service scan.
  Future<void> tryReconnectLast({Duration delay = const Duration(milliseconds: 300)}) async {
    if (_disposed) return;
    if (!_autoReconnect) return;

    if (delay > Duration.zero) await Future.delayed(delay);
    if (_isConnected || _isConnecting) return;

    await _loadLast();

    // Fast path by saved id
    if (_lastId != null && _lastId!.isNotEmpty) {
      try { await connect(_lastId!); return; } catch (_) { /* fall through */ }
    }

    // Fall back to scanning
    final hit = await scanOncePreferLast();
    if (hit != null) {
      await connect(hit.id);
    }
  }

  /// Explicit disconnect (also clears timers).
  Future<void> disconnect() async {
    _reconnectTimer?.cancel(); _reconnectTimer = null;
    _autoScanTimer?.cancel();  _autoScanTimer  = null;
    _epoch++; // invalidate callbacks
    await _teardownNotifies(cancelNative: _isConnected);
    try { await _connSub?.cancel(); } catch (_) {}
    _connSub = null;
    _isConnecting = false;
    _deviceId = null;
    _isConnected = false;
  }

  void enableAutoReconnect(bool on) {
    _autoReconnect = on;
    if (!on) {
      _reconnectTimer?.cancel(); _reconnectTimer = null;
    }
  }

  // ---------------- Internals ----------------

  void _safeAdd<T>(StreamController<T> c, T v) {
    if (!_disposed && !c.isClosed) {
      try { c.add(v); } catch (_) {}
    }
  }

  Future<void> _subscribeAll(int myEpoch) async {
    if (_disposed || _deviceId == null || myEpoch != _epoch) return;
    final id = _deviceId!;

    Future<StreamSubscription<List<int>>> sub(
      Uuid charId, void Function(List<int>) onData) async {
      final q = QualifiedCharacteristic(deviceId: id, serviceId: serviceUuid, characteristicId: charId);
      return _ble.subscribeToCharacteristic(q).listen(
        (bytes) { if (_disposed || myEpoch != _epoch) return; onData(bytes); },
        onError: (e, st) {}, cancelOnError: false);
    }

    _sRoll   = await sub(rollUuid,   (b) => _safeAdd(_roll$,    _f32(b)));
    _sPitch  = await sub(pitchUuid,  (b) => _safeAdd(_pitch$,   _f32(b)));
    _sYaw    = await sub(yawUuid,    (b) => _safeAdd(_yaw$,     _f32(b)));
    _sTemp   = await sub(tempUuid,   (b) { final v = _f32Nullable(b); _tempCtrl.add(v); });
    _sSteps  = await sub(stepsUuid,  (b) => _safeAdd(_steps$,   _i32(b)));
    _sCad    = await sub(cadenceUuid,(b) => _safeAdd(_cadence$, _f32(b)));
    _sStride = await sub(strideUuid, (b) => _safeAdd(_stride$,  _f32(b)));
    _sDh     = await sub(altdhUuid,  (b) => _safeAdd(_dh$,      _f32(b)));
  }

  Future<void> _teardownNotifies({required bool cancelNative}) async {
    Future<void> _cancel(StreamSubscription? s) async { try { await s?.cancel(); } catch (_) {} }
    if (cancelNative) {
      await _cancel(_sRoll);   await _cancel(_sPitch);  await _cancel(_sYaw);
      await _cancel(_sTemp);   await _cancel(_sSteps);  await _cancel(_sCad);
      await _cancel(_sStride); await _cancel(_sDh);
    }
    _sRoll = _sPitch = _sYaw = _sTemp = _sSteps = _sCad = _sStride = _sDh = null;
  }

  void _scheduleReconnect() {
    if (_disposed || !_autoReconnect || _isConnected || _isConnecting) return;
    if (_reconnectTimer != null) return;

    final jitter = Duration(milliseconds: math.Random().nextInt(300));
    final when   = _backoff + jitter;

    _reconnectTimer = Timer(when, () async {
      _reconnectTimer = null;
      if (_disposed || !_autoReconnect || _isConnected || _isConnecting) return;

      await _loadLast();

      if (_lastId != null && _lastId!.isNotEmpty) {
        try { await connect(_lastId!); return; } catch (_) {}
      }

      final hit = await scanOncePreferLast();
      if (hit != null) {
        await connect(hit.id);
        return;
      }

      final nextMs = (_backoff.inMilliseconds * 2).clamp(2000, _backoffMax.inMilliseconds);
      _backoff = Duration(milliseconds: nextMs);
      _scheduleReconnect();
    });
  }

  void _startBackgroundScanner() {
    // light periodic loop; if we are not connected and not connecting, try to reconnect
    _autoScanTimer?.cancel();
    _autoScanTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (_disposed || !_autoReconnect || _isConnected || _isConnecting || _scanBusy) return;
      _scanBusy = true;
      try {
        await tryReconnectLast(delay: Duration.zero);
      } finally {
        _scanBusy = false;
      }
    });
  }

  // ---------------- Decoders ----------------
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

  // ---------------- Persistence helpers ----------------
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
      _lastId = id; _lastName = name;
    } catch (_) {}
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

  Future<void> forgetLast() async {
    try {
      final f = File("${(await _cfgDir()).path}/last_device.json");
      if (await f.exists()) await f.delete();
    } catch (_) {}
    _lastId = _lastName = null;
  }

  // ---------------- Dispose ----------------
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel(); _reconnectTimer = null;
    _autoScanTimer?.cancel();  _autoScanTimer  = null;
    _epoch++;
    try { _connSub?.cancel(); } catch (_) {}
    _connSub = null;

    _sRoll = _sPitch = _sYaw = _sTemp = _sSteps = _sCad = _sStride = _sDh = null;

    try { _connState.close(); } catch (_) {}
    try { _rssiCtrl.close(); } catch (_) {}
    try { _roll$.close(); } catch (_) {}
    try { _pitch$.close(); } catch (_) {}
    try { _yaw$.close(); } catch (_) {}
    try { _steps$.close(); } catch (_) {}
    try { _cadence$.close(); } catch (_) {}
    try { _stride$.close(); } catch (_) {}
    try { _dh$.close(); } catch (_) {}
    try { _tempCtrl.close(); } catch (_) {}
  }
}
