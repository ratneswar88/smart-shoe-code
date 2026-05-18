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
    if (state == AppLifecycleState.detached) {
      unawaited(_ble.shutdownForAppClose());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_ble.shutdownForAppClose());
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

  // Analytics state
  double _tA=0,_baseline=0,_lastCentered=0,_lastStepT=-1,_lastStride=0;
  bool _baselineInit=false;
  int _cumSteps=0;
  final List<double> _stepTimes=[];
  DateTime? _lastPitchTs;

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
    _sPitch =await sub(pitchUuid, (b){final v=_f32(b);_pitch$.add(v);_pitchAnalytic(v);});
    _sYaw   =await sub(yawUuid,   (b)=>_yaw$.add(_f32(b)));
    _sTemp  =await sub(tempUuid,  (b)=>_tempCtrl.add(_f32N(b)));
    _sSteps =await sub(stepsUuid, (b)=>_steps$.add(_i32(b)));
    _sCad   =await sub(cadenceUuid,(b)=>_cadence$.add(_f32(b)));
    _sStride=await sub(strideUuid,(b)=>_stride$.add(_f32(b)));
    _sDh    =await sub(altdhUuid, (b)=>_dh$.add(_f32(b)));
  }

  Future<void> _unsub() async {
    for(final s in [_sRoll,_sPitch,_sYaw,_sTemp,_sSteps,_sCad,_sStride,_sDh]){
      try{ await s?.cancel(); } catch(_){}
    }
    _sRoll=_sPitch=_sYaw=_sTemp=_sSteps=_sCad=_sStride=_sDh=null;
  }

  void _resetAnalytics(){
    _tA=0;_baseline=0;_lastCentered=0;_lastStepT=-1;_lastStride=0;
    _baselineInit=false;_cumSteps=0;_stepTimes.clear();_lastPitchTs=null;
    if(!_stepsACtrl.isClosed)   _stepsACtrl.add(0);
    if(!_cadenceACtrl.isClosed) _cadenceACtrl.add(0);
    if(!_strideACtrl.isClosed)  _strideACtrl.add(0);
  }

  void _pitchAnalytic(double deg){
    final now=DateTime.now();
    double dt=0.1;
    if(_lastPitchTs!=null) dt=now.difference(_lastPitchTs!).inMilliseconds/1000.0.clamp(0.01,0.5);
    _lastPitchTs=now; _tA+=dt;
    if(!_baselineInit){_baseline=deg;_baselineInit=true;}
    else {_baseline+=0.01*(deg-_baseline);}
    final c=deg-_baseline;
    if(_lastCentered<=0&&c>0&&c.abs()>=5&&(_lastStepT<0?999:_tA-_lastStepT)>=0.3){
      _lastStepT=_tA;_cumSteps++;_stepTimes.add(_tA);
      while(_stepTimes.isNotEmpty&&_stepTimes.first<_tA-10) _stepTimes.removeAt(0);
    }
    _lastCentered=c;
    if(!_stepsACtrl.isClosed) _stepsACtrl.add(_cumSteps);
    double cad=0;
    if(_stepTimes.length>=2){
      final dur=_stepTimes.last-_stepTimes.first;
      if(dur>0) cad=(_stepTimes.length-1)/dur*60;
    }
    if(!_cadenceACtrl.isClosed) _cadenceACtrl.add(cad);
    if(cad>0) _lastStride=(0.48*cad/60).clamp(0.3,1.8);
    if(!_strideACtrl.isClosed) _strideACtrl.add(_lastStride);
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
int _i32(List<int> b){
  if(b.length<4) return 0;
  return ByteData.sublistView(Uint8List.fromList(b)).getInt32(0,Endian.little);
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
  final String path; final LoadedActivityModel model;
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

  final List<_RawSample> _liveBuf=[];
  final List<_LiveModelEntry> _liveModels=[];
  String? _liveActivity; double? _liveConf;
  bool _modelLoading=false; double _tLive=0;
  double _liveConfThreshold=0.6;
  Set<String> _enabledLiveLabels={};

  @override
  void initState(){
    super.initState();
    _loadConfThreshold(); _loadEnabledLiveLabels(); _bind();
  }

  void _bind(){
    _s1=widget.ble.connection$.listen((c){
      setState((){conn=c; if(c==DeviceConnectionState.connected) _id=widget.ble._deviceId;});
    });
    _s2=widget.ble.roll$.listen((v){ if(v.isNaN||v.isInfinite) return; setState(()=>roll=v); _onLiveRoll(v); });
    _s3=widget.ble.pitch$.listen((v){ if(v.isNaN||v.isInfinite) return; setState(()=>pitch=v); if(_liveBuf.isNotEmpty) _liveBuf.last.pitch=v; });
    _s4=widget.ble.yaw$.listen((v){ if(v.isNaN||v.isInfinite) return; setState(()=>yaw=v); if(_liveBuf.isNotEmpty) _liveBuf.last.yaw=v; });
    _s5=widget.ble.temp$.listen((v){ setState(()=>tempC=v); if(v!=null&&_liveBuf.isNotEmpty) _liveBuf.last.tempC=v; });
    _s6=widget.ble.stepsAnalytic$.listen((v)=>setState(()=>steps=v));
    _s7=widget.ble.cadenceAnalytic$.listen((v){ setState(()=>cadence=v); if(_liveBuf.isNotEmpty) _liveBuf.last.cadence=v; });
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
    String? best; double bestC=-1;
    for(final e in _liveModels){
      final p=e.model.predictLabel(feat);
      if((_enabledLiveLabels.isEmpty||_enabledLiveLabels.contains(p.key))&&p.value>bestC){
        bestC=p.value; best=p.key;
      }
    }
    if(!mounted) return;
    setState((){
      if(best!=null&&bestC>=_liveConfThreshold){ _liveActivity=best; _liveConf=bestC; }
      else { _liveActivity=null; _liveConf=null; }
    });
  }

  List<double> _features(List<_RawSample> w){
    List<double> col(List<double?> v){ final r=v.whereType<double>().toList(); return r.isEmpty?[0.0]:r; }
    List<double> stats(List<double> x){ final n=x.length,mean=x.reduce((a,b)=>a+b)/n; return [mean,x.map((v)=>(v-mean)*(v-mean)).reduce((a,b)=>a+b)/n,math.sqrt(x.map((v)=>v*v).reduce((a,b)=>a+b)/n)]; }
    return <double>[]
      ..addAll(stats(col(w.map((e)=>e.roll).toList())))..addAll(stats(col(w.map((e)=>e.pitch).toList())))
      ..addAll(stats(col(w.map((e)=>e.yaw).toList())))..addAll(stats(col(w.map((e)=>e.cadence).toList())))
      ..addAll(stats(col(w.map((e)=>e.strideM).toList())))..addAll(stats(col(w.map((e)=>e.tempC).toList())));
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
        try{ final d=jsonDecode(await f.readAsString()); if(d is Map<String,dynamic>) loaded.add(_LiveModelEntry(path:path,model:LoadedActivityModel.fromJson(d))); } catch(_){}
      }
      if(loaded.isEmpty){ if(mounted) _snack('Model files not found. Re-select on Training tab.'); return; }
      if(mounted) setState((){_liveModels..clear()..addAll(loaded);_liveBuf.clear();_tLive=0;_liveActivity=null;_liveConf=null;});
      if(mounted) _snack('Loaded ${loaded.length} model(s): ${loaded.map((e)=>e.shortName).join(', ')}');
    } catch(e){ if(mounted) _snack('Failed: $e'); }
    finally{ if(mounted) setState(()=>_modelLoading=false); }
  }

  void _snack(String msg){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(msg))); }

  Future<void> _scanAndConnect() async {
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
        _metric(cs,'Temp (°C)',   tempC?.toStringAsFixed(1)??'—',   Icons.thermostat),
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
      Text('Show prediction only if confidence >= ${(_liveConfThreshold*100).toStringAsFixed(0)}%',style:Theme.of(context).textTheme.bodySmall),
      Slider(value:_liveConfThreshold,min:0.3,max:0.99,divisions:14,label:'${(_liveConfThreshold*100).toStringAsFixed(0)}%',
          onChanged:(v)=>setState(()=>_liveConfThreshold=v),onChangeEnd:_saveConfThreshold),
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
      Row(children:[
        FilledButton.icon(onPressed:_modelLoading?null:_loadActiveModel,icon:const Icon(Icons.auto_awesome),
            label:Text(has?'Reload active models':'Load active models')),
        const SizedBox(width:16),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Prediction: ${_liveActivity??'-'}',style:const TextStyle(fontSize:14,fontWeight:FontWeight.w600)),
          if(_liveConf!=null) Text('Confidence: ${(_liveConf!*100).toStringAsFixed(1)}%',
              style:Theme.of(context).textTheme.bodySmall?.copyWith(color:cs.primary)),
        ])),
      ]),
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
    _sr=widget.ble.roll$.listen((v){ if(v.isNaN||v.isInfinite) return; setState((){_t+=0.1;_push(_r,_t,v);}); });
    _sp=widget.ble.pitch$.listen((v){ if(v.isNaN||v.isInfinite) return; setState((){_t+=0.1;_push(_p,_t,v);}); });
    _sy=widget.ble.yaw$.listen((v){ if(v.isNaN||v.isInfinite) return; setState((){_t+=0.1;_push(_y,_t,v);}); });
    _t0=DateTime.now();
    _sTemp=widget.ble.temp$.listen((v){ if(v==null||v.isNaN||v.isInfinite) return;
      final t=DateTime.now().difference(_t0!).inMilliseconds/1000.0; setState(()=>_push(_temp,t,v)); });
  }

  @override void dispose(){
    for(final s in [_sr,_sp,_sy,_sTemp]){ try{ s?.cancel(); } catch(_){} } super.dispose();
  }

  @override Widget build(BuildContext context){
    final cs=Theme.of(context).colorScheme;
    return Padding(padding:const EdgeInsets.all(12),child:ListView(children:[
      _card(cs,'Roll (°)',_r),_card(cs,'Pitch (°)',_p),_card(cs,'Yaw (°)',_y),_card(cs,'Temp (°C)',_temp),
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
        ['Avg temperature',s.avgTempC!=null?'${s.avgTempC!.toStringAsFixed(1)} °C':'-'],
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
      // Active model card
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Active model for live classification',style:Theme.of(context).textTheme.titleMedium),const SizedBox(height:6),
        Text('Select models here. Go to Dashboard → "Load active models" to start live prediction.',style:Theme.of(context).textTheme.bodySmall),const SizedBox(height:12),
        if(_loadingModels) const Center(child:CircularProgressIndicator())
        else if(_modelFiles.isEmpty) Text('No models yet. Train & Save first.',style:Theme.of(context).textTheme.bodySmall)
        else Column(children:_modelFiles.map((f){
          final name=f.path.split('/').last; final isActive=_activeModelPaths.contains(f.path);
          return ListTile(dense:true,contentPadding:EdgeInsets.zero,
            leading:Checkbox(value:isActive,onChanged:(_)=>_toggleActive(f)),
            title:Text(name,maxLines:1,overflow:TextOverflow.ellipsis),
            subtitle:isActive?Text('Active',style:TextStyle(color:cs.primary,fontWeight:FontWeight.w600)):null,
            trailing:IconButton(icon:const Icon(Icons.delete_outline),color:cs.error,onPressed:()=>_deleteModel(f)),
            onTap:()=>_toggleActive(f));
        }).toList()),
        const SizedBox(height:8),
        Text(_activeModelPaths.isEmpty?'Active: none':'Active: ${_activeModelPaths.map((p)=>p.split('/').last).join(', ')}',style:Theme.of(context).textTheme.bodySmall),
      ]))),
      const SizedBox(height:12),
      // Share card
      Card(child:ListTile(
        title:const Text('Share session CSV'),
        subtitle:const Text('Share most recent CSV file'),
        trailing:IconButton(icon:const Icon(Icons.share),onPressed:() async {
          final dir=await _ensureDir(await _appDir(),'sessions');
          final files=dir.listSync().whereType<File>().where((f)=>f.path.endsWith('.csv')).toList()..sort((a,b)=>b.lastModifiedSync().compareTo(a.lastModifiedSync()));
          if(files.isEmpty){ _snack('No sessions yet.'); return; }
          await Share.shareXFiles([XFile(files.first.path)],text:'MadePlus ShoeML session');
        }),
      )),
    ]));
  }
}

/* ========================================================================= */
/*  TUTORIAL PAGE                                                             */
/* ========================================================================= */

class TutorialPage extends StatelessWidget {
  const TutorialPage({super.key});
  @override Widget build(BuildContext context){
    final cs=Theme.of(context).colorScheme;
    return Padding(padding:const EdgeInsets.all(12),child:ListView(children:[
      Card(color:cs.surfaceContainerHigh,child:const Padding(padding:EdgeInsets.all(16),child:Text(
        'Tutorial\n\n'
        '1) Tap Scan & Connect on Dashboard to connect to the shoe.\n'
        '2) Watch live metrics (RSSI, roll/pitch/yaw, temp, steps).\n'
        '3) Graphs tab shows real-time charts for R/P/Y and temperature.\n'
        '4) Training tab: choose a label, Start → Stop (CSV auto-saves).\n'
        '5) Tap Train & Save to create a model JSON file.\n'
        '6) Check the model checkbox to mark it as active.\n'
        '7) Dashboard → "Load active models" → walk/run to see live predictions.\n\n'
        'Tip: use the Palette icon in the app bar to change theme/color.',
      ))),
    ]));
  }
}
