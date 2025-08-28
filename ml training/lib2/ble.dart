import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class ShoeSample {
  final DateTime t;
  final double roll, pitch, yaw;
  final double cadence, strideM, dH;
  final int steps;
  final double? tempC;
  ShoeSample({
    required this.t,
    required this.roll,
    required this.pitch,
    required this.yaw,
    required this.cadence,
    required this.strideM,
    required this.dH,
    required this.steps,
    required this.tempC,
  });
}

class ShoeBle {
  // UUIDs (keep in sync with your firmware)
  final serviceUuid = Uuid.parse("0000feed-0000-1000-8000-00805f9b34fb");
  final rollUuid    = Uuid.parse("0000a001-0000-1000-8000-00805f9b34fb");
  final pitchUuid   = Uuid.parse("0000a002-0000-1000-8000-00805f9b34fb");
  final yawUuid     = Uuid.parse("0000a003-0000-1000-8000-00805f9b34fb");
  final tempUuid    = Uuid.parse("0000b001-0000-1000-8000-00805f9b34fb");
  final stepsUuid   = Uuid.parse("0000c001-0000-1000-8000-00805f9b34fb");
  final cadUuid     = Uuid.parse("0000c002-0000-1000-8000-00805f9b34fb");
  final strideUuid  = Uuid.parse("0000c003-0000-1000-8000-00805f9b34fb");
  final altdhUuid   = Uuid.parse("0000b002-0000-1000-8000-00805f9b34fb");
  final cmdUuid     = Uuid.parse("0000d001-0000-1000-8000-00805f9b34fb");

  final _ble = FlutterReactiveBle();

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _sRoll,_sPitch,_sYaw,_sTemp,_sSteps,_sCad,_sStride,_sDh;

  bool get connected => _connected;
  bool _connected = false;
  String? deviceId;
  QualifiedCharacteristic? _chCmd;

  // latest live values (used by UI & training windowing)
  double roll=0,pitch=0,yaw=0,cadence=0,strideM=0,dH=0;
  int steps=0;
  double? tempC;

  final _sampleCtrl = StreamController<ShoeSample>.broadcast();
  Stream<ShoeSample> get samples => _sampleCtrl.stream;

  void dispose() {
    _stopNotifications();
    _connSub?.cancel();
    _scanSub?.cancel();
    _sampleCtrl.close();
  }

  Future<void> scanAndConnect({String targetName = "MADEPLUS SMART SHOE"}) async {
    await _scanSub?.cancel();
    final c = Completer<DiscoveredDevice>();
    _scanSub = _ble.scanForDevices(withServices: [serviceUuid]).listen((d) {
      if (d.name == targetName) {
        c.complete(d);
        _scanSub?.cancel();
      }
    });
    final dev = await c.future.timeout(const Duration(seconds: 10));
    await connect(dev.id);
  }

  Future<void> connect(String id) async {
    deviceId = id;
    await _connSub?.cancel();
    _connSub = _ble.connectToDevice(id: id, connectionTimeout: const Duration(seconds: 10))
      .listen((u) async {
        switch (u.connectionState) {
          case DeviceConnectionState.connected:
            _connected = true;
            await _subscribeAll(id);
            break;
          case DeviceConnectionState.disconnected:
            _connected = false;
            _stopNotifications();
            break;
          default:
            break;
        }
      });
  }

  Future<void> disconnect() async {
    _stopNotifications();
    await _connSub?.cancel();
    _connected = false;
  }

  Future<void> _subscribeAll(String id) async {
    Future<void> sub(Uuid uuid, void Function(List<int>) onData) async {
      final ch = QualifiedCharacteristic(deviceId: id, serviceId: serviceUuid, characteristicId: uuid);
      final s = _ble.subscribeToCharacteristic(ch).listen(onData, onError: (_) {});
      if (uuid == rollUuid) _sRoll = s;
      if (uuid == pitchUuid) _sPitch = s;
      if (uuid == yawUuid) _sYaw = s;
      if (uuid == tempUuid) _sTemp = s;
      if (uuid == stepsUuid) _sSteps = s;
      if (uuid == cadUuid) _sCad = s;
      if (uuid == strideUuid) _sStride = s;
      if (uuid == altdhUuid) _sDh = s;
    }

    double f32(List<int> b) {
      if (b.length < 4) return double.nan;
      return ByteData.sublistView(Uint8List.fromList(b)).getFloat32(0, Endian.little);
    }
    int u32(List<int> b) {
      if (b.length < 4) return 0;
      return ByteData.sublistView(Uint8List.fromList(b)).getUint32(0, Endian.little);
    }

    await sub(rollUuid, (b){ final v=f32(b); if (v.isFinite) roll=v; _emit(); });
    await sub(pitchUuid,(b){ final v=f32(b); if (v.isFinite) pitch=v; _emit(); });
    await sub(yawUuid,  (b){ final v=f32(b); if (v.isFinite) yaw=v; _emit(); });
    await sub(tempUuid, (b){ final v=f32(b); if (v.isFinite) tempC=v; _emit(); });
    await sub(stepsUuid,(b){ steps=u32(b); _emit(); });
    await sub(cadUuid,  (b){ final v=f32(b); if (v.isFinite) cadence=v; _emit(); });
    await sub(strideUuid,(b){ final v=f32(b); if (v.isFinite) strideM=v; _emit(); });
    await sub(altdhUuid,(b){ final v=f32(b); if (v.isFinite) dH=v; _emit(); });

    _chCmd = QualifiedCharacteristic(deviceId: id, serviceId: serviceUuid, characteristicId: cmdUuid);
  }

  void _emit() {
    _sampleCtrl.add(ShoeSample(
      t: DateTime.now(),
      roll: roll, pitch: pitch, yaw: yaw,
      cadence: cadence, strideM: strideM, dH: dH,
      steps: steps, tempC: tempC,
    ));
  }

  void _stopNotifications() {
    _sRoll?.cancel(); _sPitch?.cancel(); _sYaw?.cancel(); _sTemp?.cancel();
    _sSteps?.cancel(); _sCad?.cancel(); _sStride?.cancel(); _sDh?.cancel();
    _sRoll=_sPitch=_sYaw=_sTemp=_sSteps=_sCad=_sStride=_sDh=null;
  }

  Future<void> sendCommand(String text) async {
    if (_chCmd == null) return;
    await _ble.writeCharacteristicWithoutResponse(_chCmd!, value: text.codeUnits);
  }
}
