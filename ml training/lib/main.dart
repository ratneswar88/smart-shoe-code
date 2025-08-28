// MadePlus SHOEML — split tabs: Dashboard, Graphs, Training, Tutorial
// Requires: flutter_reactive_ble, permission_handler, app_settings, fl_chart,
//           path_provider, intl, share_plus

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShoeMLApp());
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
            onPressed: () =>
                AppSettings.openAppSettings(type: AppSettingsType.bluetooth),
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

class ShoeBle {
  final _ble = FlutterReactiveBle();

  // Update these to match your firmware UUIDs.
  final Uuid serviceUuid =
      Uuid.parse("0000feed-0000-1000-8000-00805f9b34fb");

  final Uuid rollUuid = Uuid.parse("0000a001-0000-1000-8000-00805f9b34fb");
  final Uuid pitchUuid = Uuid.parse("0000a002-0000-1000-8000-00805f9b34fb");
  final Uuid yawUuid = Uuid.parse("0000a003-0000-1000-8000-00805f9b34fb");
  final Uuid tempUuid = Uuid.parse("0000a004-0000-1000-8000-00805f9b34fb");

  final Uuid stepsUuid = Uuid.parse("0000c001-0000-1000-8000-00805f9b34fb");
  final Uuid cadenceUuid = Uuid.parse("0000c002-0000-1000-8000-00805f9b34fb");
  final Uuid strideUuid = Uuid.parse("0000c003-0000-1000-8000-00805f9b34fb");
  final Uuid altdhUuid = Uuid.parse("0000c004-0000-1000-8000-00805f9b34fb");

  // Streams
  final _connState = StreamController<DeviceConnectionState>.broadcast();
  Stream<DeviceConnectionState> get connection$ => _connState.stream;

  final _rssi = StreamController<int>.broadcast();
  Stream<int> get rssi$ => _rssi.stream;

  final roll$ = StreamController<double>.broadcast();
  final pitch$ = StreamController<double>.broadcast();
  final yaw$ = StreamController<double>.broadcast();
  final temp$ = StreamController<double?>.broadcast();

  final steps$ = StreamController<int>.broadcast();
  final cadence$ = StreamController<double>.broadcast();
  final stride$ = StreamController<double>.broadcast();
  final dh$ = StreamController<double>.broadcast();

  String? _deviceId;
  Timer? _rssiTimer;

  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _sRoll, _sPitch, _sYaw, _sTemp;
  StreamSubscription<List<int>>? _sSteps, _sCad, _sStride, _sDh;

  Future<DiscoveredDevice?> scanOnce(
      {Duration timeout = const Duration(seconds: 6)}) async {
    DiscoveredDevice? found;
    final sub =
        _ble.scanForDevices(withServices: [serviceUuid]).listen((d) {
      found ??= d; // first match
    });
    await Future.delayed(timeout);
    await sub.cancel();
    return found;
  }

  Future<void> connect(String id) async {
    await disconnect();

    _connSub = _ble.connectToDevice(id: id).listen((u) async {
      _connState.add(u.connectionState);
      if (u.connectionState == DeviceConnectionState.connected) {
        _deviceId = id;
        await _subscribeAll();
        _startRssi();
      } else if (u.connectionState ==
          DeviceConnectionState.disconnected) {
        _stopRssi();
        await _unsubscribeAll();
        _deviceId = null;
      }
    });
  }

  Future<void> disconnect() async {
    _stopRssi();
    await _unsubscribeAll();
    await _connSub?.cancel();
    _deviceId = null;
  }

  void dispose() {
    disconnect();
    _connState.close();
    _rssi.close();
    roll$.close();
    pitch$.close();
    yaw$.close();
    temp$.close();
    steps$.close();
    cadence$.close();
    stride$.close();
    dh$.close();
  }

  Future<void> _subscribeAll() async {
    if (_deviceId == null) return;
    final id = _deviceId!;

    Future<StreamSubscription<List<int>>> sub(
        Uuid c, void Function(List<int>) onData) async {
      final q = QualifiedCharacteristic(
        deviceId: id,
        serviceId: serviceUuid,
        characteristicId: c,
      );
      return _ble.subscribeToCharacteristic(q).listen(onData);
    }

    _sRoll = await sub(rollUuid, (b) => roll$.add(_f32(b)));
    _sPitch = await sub(pitchUuid, (b) => pitch$.add(_f32(b)));
    _sYaw = await sub(yawUuid, (b) => yaw$.add(_f32(b)));
    _sTemp = await sub(tempUuid, (b) => temp$.add(_f32Nullable(b)));

    _sSteps = await sub(stepsUuid, (b) => steps$.add(_i32(b)));
    _sCad = await sub(cadenceUuid, (b) => cadence$.add(_f32(b)));
    _sStride = await sub(strideUuid, (b) => stride$.add(_f32(b)));
    _sDh = await sub(altdhUuid, (b) => dh$.add(_f32(b)));
  }

  Future<void> _unsubscribeAll() async {
    await _sRoll?.cancel();
    await _sPitch?.cancel();
    await _sYaw?.cancel();
    await _sTemp?.cancel();
    await _sSteps?.cancel();
    await _sCad?.cancel();
    await _sStride?.cancel();
    await _sDh?.cancel();
  }

  void _startRssi() {
    _rssiTimer?.cancel();
    if (_deviceId == null) return;
    _rssiTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final r = await _ble.readRssi(deviceId: _deviceId!);
        _rssi.add(r);
      } catch (_) {}
    });
  }

  void _stopRssi() {
    _rssiTimer?.cancel();
    _rssiTimer = null;
  }
}

// BLE helpers for simple float/int payloads
double _f32(List<int> b) {
  if (b.length < 4) return double.nan;
  final bb = ByteData.sublistView(Uint8List.fromList(b));
  return bb.getFloat32(0, Endian.little);
}

double? _f32Nullable(List<int> b) {
  if (b.length < 4) return null;
  final v = _f32(b);
  if (v.isNaN) return null;
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
  DeviceConnectionState conn = DeviceConnectionState.disconnected;

  StreamSubscription? _s1, _s2, _s3, _s4, _s5, _s6, _s7, _s8, _s9, _s10;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    _s1 = widget.ble.connection$.listen((c) => setState(() => conn = c));
    _s2 = widget.ble.roll$.listen((v) => setState(() => roll = v));
    _s3 = widget.ble.pitch$.listen((v) => setState(() => pitch = v));
    _s4 = widget.ble.yaw$.listen((v) => setState(() => yaw = v));
    _s5 = widget.ble.temp$.listen((v) => setState(() => tempC = v));
    _s6 = widget.ble.steps$.listen((v) => setState(() => steps = v));
    _s7 = widget.ble.cadence$.listen((v) => setState(() => cadence = v));
    _s8 = widget.ble.stride$.listen((v) => setState(() => stride = v));
    _s9 = widget.ble.dh$.listen((v) => setState(() => dh = v));
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
            child: ListTile(
              leading: const Icon(Icons.bluetooth),
              title: Text(_connLabel(conn)),
              subtitle: Text(_id == null ? "Not connected" : _id!),
              trailing: Wrap(spacing: 8, children: [
                Chip(
                  label: Text("RSSI $rssi dBm"),
                  avatar: const Icon(Icons.network_cell, size: 16),
                ),
                ElevatedButton.icon(
                  onPressed: _scanAndConnect,
                  icon: const Icon(Icons.search),
                  label: const Text("Scan & Connect"),
                ),
                ElevatedButton.icon(
                  onPressed: () => widget.ble.disconnect(),
                  icon: const Icon(Icons.link_off),
                  label: const Text("Disconnect"),
                ),
              ]),
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
  final List<FlSpot> _stance = [], _swing = [];
  double _t = 0;

  StreamSubscription? _sr, _sp, _sy, _scad;

  void _push(List<FlSpot> s, double t, double v, {int keep = 300}) {
    s.add(FlSpot(t, v.toDouble()));
    if (s.length > keep) s.removeAt(0);
  }

  @override
  void initState() {
    super.initState();
    _sr = widget.ble.roll$.listen((v) {
      setState(() {
        _t += 0.1;
        _push(_r, _t, v);
      });
    });
    _sp = widget.ble.pitch$.listen((v) {
      setState(() {
        _t += 0.1;
        _push(_p, _t, v);
      });
    });
    _sy = widget.ble.yaw$.listen((v) {
      setState(() {
        _t += 0.1;
        _push(_y, _t, v);
      });
    });
    _scad = widget.ble.cadence$.listen((c) {
      // rough phase split: stance ~ 60% at walking, adjust with cadence
      final stancePct = (0.6 - (c - 100) * 0.0015).clamp(0.3, 0.8);
      setState(() {
        _push(_stance, _t, stancePct);
        _push(_swing, _t, 1.0 - stancePct);
      });
    });
  }

  @override
  void dispose() {
    for (final s in [_sr, _sp, _sy, _scad]) {
      s?.cancel();
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
          _lineCard(cs, "Gait: Stance (fraction)", _stance, minY: 0, maxY: 1),
          _lineCard(cs, "Gait: Swing (fraction)", _swing, minY: 0, maxY: 1),
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
    _sr = widget.ble.roll$.listen((v) {
      t += 0.1;
      _buffer.add(_RawSample(t, v, null, null, null, null, null, null));
    });
    _sp = widget.ble.pitch$.listen((v) {
      if (_buffer.isNotEmpty) _buffer.last.pitch = v;
    });
    _sy = widget.ble.yaw$.listen((v) {
      if (_buffer.isNotEmpty) _buffer.last.yaw = v;
    });
    _st = widget.ble.temp$.listen((v) {
      if (_buffer.isNotEmpty) _buffer.last.tempC = v;
    });
    _sc = widget.ble.cadence$.listen((v) {
      if (_buffer.isNotEmpty) _buffer.last.cadence = v;
    });
    _ss = widget.ble.stride$.listen((v) {
      if (_buffer.isNotEmpty) _buffer.last.strideM = v;
    });
    _sdh = widget.ble.dh$.listen((v) {
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

  Future<void> _saveCsv() async {
    final dir = await _ensureDir(await _appDir(), "sessions");
    final stamp = DateFormat("yyMMdd_HHmmss").format(DateTime.now());
    final file = File("${dir.path}/${_label}_$stamp.csv");

    const header = "t,roll,pitch,yaw,tempC,cadence,strideM,deltaH,label\n";
    final sb = StringBuffer(header);
    for (final s in _buffer) {
      sb.write("${s.t.toStringAsFixed(2)},${s.roll?.toStringAsFixed(4) ?? ""},"
          "${s.pitch?.toStringAsFixed(4) ?? ""},${s.yaw?.toStringAsFixed(4) ?? ""},"
          "${s.tempC?.toStringAsFixed(2) ?? ""},${s.cadence?.toStringAsFixed(2) ?? ""},"
          "${s.strideM?.toStringAsFixed(3) ?? ""},${s.dH?.toStringAsFixed(3) ?? ""},$_label\n");
    }
    await file.writeAsString(sb.toString(), flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Saved: ${file.path.split('/').last}")),
    );
  }

  Future<void> _toggleCollect() async {
    setState(() => _collecting = !_collecting);
    if (_collecting) {
      _buffer.clear();
    } else {
      await _saveCsv();
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
            child: ListTile(
              title: const Text("Collect samples"),
              subtitle: const Text(
                  "Pick a label, Start/Stop capture, CSV auto-saves on stop."),
              trailing: Wrap(spacing: 8, children: [
                DropdownButton<String>(
                  value: _label,
                  items: _labels
                      .map((e) =>
                          DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setState(() => _label = v ?? _label),
                ),
                FilledButton.icon(
                  onPressed: _toggleCollect,
                  icon: Icon(_collecting
                      ? Icons.stop
                      : Icons.fiber_manual_record),
                  label:
                      Text(_collecting ? "Stop & Save CSV" : "Start"),
                ),
              ]),
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
