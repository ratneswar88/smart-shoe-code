import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class ShoeBle {
  final flutter = FlutterReactiveBle();

  // UUIDs (kept same as your original)
  final Uuid serviceUuid = Uuid.parse("0000feed-0000-1000-8000-00805f9b34fb");
  final Uuid rollUuid   = Uuid.parse("0000a001-0000-1000-8000-00805f9b34fb");
  final Uuid pitchUuid  = Uuid.parse("0000a002-0000-1000-8000-00805f9b34fb");
  final Uuid yawUuid    = Uuid.parse("0000a003-0000-1000-8000-00805f9b34fb");
  final Uuid tempUuid   = Uuid.parse("0000b001-0000-1000-8000-00805f9b34fb");
  final Uuid stepsUuid  = Uuid.parse("0000c001-0000-1000-8000-00805f9b34fb");
  final Uuid cadUuid    = Uuid.parse("0000c002-0000-1000-8000-00805f9b34fb");
  final Uuid strideUuid = Uuid.parse("0000c003-0000-1000-8000-00805f9b34fb");
  final Uuid altdhUuid  = Uuid.parse("0000b002-0000-1000-8000-00805f9b34fb");
  final Uuid cmdUuid    = Uuid.parse("0000d001-0000-1000-8000-00805f9b34fb");

  DiscoveredDevice? device;
  QualifiedCharacteristic? chCmd;

  // Streams
  final _r$ = StreamController<double>.broadcast();
  final _p$ = StreamController<double>.broadcast();
  final _y$ = StreamController<double>.broadcast();
  final _temp$ = StreamController<double>.broadcast();
  final _steps$ = StreamController<int>.broadcast();
  final _cad$ = StreamController<double>.broadcast();
  final _stride$ = StreamController<double>.broadcast();
  final _dh$ = StreamController<double>.broadcast();
  final _rssi$ = StreamController<int>.broadcast();

  Stream<double> get roll$ => _r$.stream;
  Stream<double> get pitch$ => _p$.stream;
  Stream<double> get yaw$ => _y$.stream;
  Stream<double> get temp$ => _temp$.stream;
  Stream<int> get steps$ => _steps$.stream;
  Stream<double> get cadence$ => _cad$.stream;
  Stream<double> get stride$ => _stride$.stream;
  Stream<double> get dH$ => _dh$.stream;
  // Back-compat aliases expected by your pages:
  Stream<double> get dh$ => dH$;
  Stream<int> get rssi$ => _rssi$.stream;

  // Connection state
  final _connState$ = StreamController<DeviceConnectionState>.broadcast();
  Stream<DeviceConnectionState> get connectionState$ => _connState$.stream;
  // Back-compat alias:
  Stream<DeviceConnectionState> get connection$ => connectionState$;

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _s1,_s2,_s3,_s4,_s5,_s6,_s7,_s8;
  Timer? _rssiTimer;

  double _f32(List<int> b) {
    if (b.length < 4) return double.nan;
    return ByteData.sublistView(Uint8List.fromList(b)).getFloat32(0, Endian.little);
  }
  int _u32(List<int> b) {
    if (b.length < 4) return 0;
    return ByteData.sublistView(Uint8List.fromList(b)).getUint32(0, Endian.little);
  }

  Future<DiscoveredDevice?> scanOnce({Duration timeout = const Duration(seconds: 3)}) async {
    final c = Completer<DiscoveredDevice?>();
    await _scanSub?.cancel();
    _scanSub = flutter.scanForDevices(withServices: [serviceUuid]).listen((d) {
      if (d.name.isNotEmpty) {
        c.complete(d);
      }
    }, onError: (e) => c.complete(null));
    await Future.delayed(timeout);
    await _scanSub?.cancel();
    return c.isCompleted ? await c.future : null;
  }

  Future<void> startScanAndConnect() async {
    await _scanSub?.cancel();
    _scanSub = flutter.scanForDevices(withServices: [serviceUuid]).listen((d) async {
      if (d.name == "MADEPLUS SMART SHOE") {
        await _scanSub?.cancel();
        await connect(d.id);
      }
    }, onError: (e) {});
  }

  Future<void> connect(String id) async {
    await _connSub?.cancel();
    _connSub = flutter.connectToDevice(id: id, connectionTimeout: const Duration(seconds: 8)).listen((u) async {
      _connState$.add(u.connectionState);
      if (u.connectionState == DeviceConnectionState.connected) {
        await _subscribeAll(id);
        _startRssiPolling(id);
      } else if (u.connectionState == DeviceConnectionState.disconnected) {
        _disposeNotifs();
        _stopRssiPolling();
      }
    }, onError: (e) {
      _connState$.add(DeviceConnectionState.disconnected);
    });
  }

  Future<void> disconnect() async {
    await _connSub?.cancel();
    _connState$.add(DeviceConnectionState.disconnected);
    _disposeNotifs();
    _stopRssiPolling();
  }

  Future<void> _subscribeAll(String id) async {
    Future<void> sub(Uuid charUuid, void Function(List<int>) onData, void Function(StreamSubscription<List<int>>) keep) async {
      final ch = QualifiedCharacteristic(deviceId: id, serviceId: serviceUuid, characteristicId: charUuid);
      final s = flutter.subscribeToCharacteristic(ch).listen(onData, onError: (_){ });
      keep(s);
    }
    await sub(rollUuid,   (b)=>_r$.add(_f32(b)), (s)=>_s1=s);
    await sub(pitchUuid,  (b)=>_p$.add(_f32(b)), (s)=>_s2=s);
    await sub(yawUuid,    (b)=>_y$.add(_f32(b)), (s)=>_s3=s);
    await sub(tempUuid,   (b){ final v=_f32(b); if (v.isFinite) _temp$.add(v); }, (s)=>_s4=s);
    await sub(stepsUuid,  (b)=>_steps$.add(_u32(b)), (s)=>_s5=s);
    await sub(cadUuid,    (b)=>_cad$.add(_f32(b)), (s)=>_s6=s);
    await sub(strideUuid, (b)=>_stride$.add(_f32(b)), (s)=>_s7=s);
    await sub(altdhUuid,  (b)=>_dh$.add(_f32(b)), (s)=>_s8=s);

    final ch = QualifiedCharacteristic(deviceId: id, serviceId: serviceUuid, characteristicId: cmdUuid);
    chCmd = ch;
  }

  Future<void> sendCommand(String text) async {
    if (chCmd == null) return;
    try { await flutter.writeCharacteristicWithoutResponse(chCmd!, value: utf8.encode(text)); } catch (_) {}
  }

  void _disposeNotifs() {
    _s1?.cancel(); _s2?.cancel(); _s3?.cancel(); _s4?.cancel();
    _s5?.cancel(); _s6?.cancel(); _s7?.cancel(); _s8?.cancel();
    _s1=_s2=_s3=_s4=_s5=_s6=_s7=_s8=null;
  }

  void _startRssiPolling(String id) {
    _rssiTimer?.cancel();
    _rssiTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final sub = flutter.scanForDevices(withServices: [serviceUuid]).listen((d) {
          if (d.id == id) {
            _rssi$.add(d.rssi);
          }
        });
        await Future.delayed(const Duration(milliseconds: 900));
        await sub.cancel();
      } catch (_) {}
    });
  }

  void _stopRssiPolling() {
    _rssiTimer?.cancel();
    _rssiTimer = null;
  }

  Future<void> dispose() async {
    await _scanSub?.cancel();
    await _connSub?.cancel();
    _disposeNotifs();
    await _rssi$.close();
    await _r$.close();
    await _p$.close();
    await _y$.close();
    await _temp$.close();
    await _steps$.close();
    await _cad$.close();
    await _stride$.close();
    await _dh$.close();
    await _connState$.close();
  }
}