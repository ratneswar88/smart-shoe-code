import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../ble.dart';

import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui; // for ImageByteFormat when capturing PNG

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
    "sitting",
  ];
  String _label = "walking";

  final _modelNameCtrl = TextEditingController();
  bool _collecting = false;

  final GlobalKey _mapKey = GlobalKey();
  List<LatLng> _track = [];
  StreamSubscription<Position>? _posSub;

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
    _posSub?.cancel();
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

  Future<File> _saveCsv() async {
    final dir = await _ensureDir(await _appDir(), "sessions");
    final stamp = DateFormat("yyMMdd_HHmmss").format(DateTime.now());
    final file = File("${dir.path}/${_label}_$stamp.csv");

    const header = "t,roll,pitch,yaw,tempC,cadence,strideM,deltaH,label\n";
    final sb = StringBuffer(header);

    for (final s in _buffer) {
      sb.write(
        "${s.t.toStringAsFixed(2)},"
        "${s.roll?.toStringAsFixed(4) ?? ""},"
        "${s.pitch?.toStringAsFixed(4) ?? ""},"
        "${s.yaw?.toStringAsFixed(4) ?? ""},"
        "${s.tempC?.toStringAsFixed(2) ?? ""},"
        "${s.cadence?.toStringAsFixed(2) ?? ""},"
        "${s.strideM?.toStringAsFixed(3) ?? ""},"
        "${s.dH?.toStringAsFixed(3) ?? ""},"
        "$_label\n",
      );
    }

    await file.writeAsString(sb.toString());
    return file;
  }

  Future<void> _toggleCollect() async {
    setState(() => _collecting = !_collecting);

    if (_collecting) {
      // start collecting + GPS
      _buffer.clear();
      _track.clear();
      await _startLocation();
    } else {
      // stop, save CSV + map PNG + GeoJSON
      final csvFile = await _saveCsv();
      await _stopLocation();
      await _captureMapPng(csvFile);
      await _saveGeoJson(csvFile);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session saved.")),
      );
    }
  }

  Future<void> _trainAndSave() async {
    // Build windows from buffer
    final wins = _windows(_buffer, winSec: 3.0, hopSec: 1.5);
    if (wins.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No data to train.")),
      );
      return;
    }

    final feats = wins.map(_features).toList();
    final labelIdx = _labels.indexOf(_label);
    final labels = List<int>.filled(feats.length, labelIdx);

    final n = feats.length;
    final m = math.max(1, math.min(n - 1, (n * 0.8).floor()));

    final Xtr = feats.sublist(0, m);
    final ytr = labels.sublist(0, m);
    final Xte = feats.sublist(m);
    final yte = labels.sublist(m);

    final clf = SoftmaxClassifier()
      ..init(numClasses: _labels.length, inDim: Xtr.first.length)
      ..fit(Xtr, ytr, epochs: 50, lr: 0.05, l2: 1e-4, batch: 64);

    final acc = clf.accuracy(Xte, yte);

    final dir = await _ensureDir(await _appDir(), "models");
    final stamp = DateFormat("yyMMdd_HHmmss").format(DateTime.now());
    final baseName =
        _modelNameCtrl.text.trim().isEmpty ? _label : _modelNameCtrl.text.trim();
    final file = File("${dir.path}/${baseName}_$stamp.json");

    final modelJson = {
      "labels": _labels,
      "input_dim": Xtr.first.length,
      "num_classes": _labels.length,
      "W": clf.W,
      "b": clf.b,
      "accuracy": acc,
    };

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(modelJson),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Model saved (${(acc * 100).toStringAsFixed(1)}% acc)",
        ),
      ),
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
    if (dt <= 0) return [];
    final win = (winSec / dt).round();
    final hop = (hopSec / dt).round();
    if (win <= 1 || hop <= 0) return [];

    final out = <List<_RawSample>>[];
    for (int i = 0; i + win <= buf.length; i += hop) {
      out.add(buf.sublist(i, i + win));
    }
    return out;
  }

  List<double> _features(List<_RawSample> win) {
    final roll = win.map((e) => e.roll ?? 0.0).toList();
    final pitch = win.map((e) => e.pitch ?? 0.0).toList();
    final yaw = win.map((e) => e.yaw ?? 0.0).toList();
    final temp = win.map((e) => e.tempC ?? 0.0).toList();
    final cadence = win.map((e) => e.cadence ?? 0.0).toList();
    final stride = win.map((e) => e.strideM ?? 0.0).toList();

    List<double> stats(List<double> x) {
      final n = x.length;
      if (n == 0) return [0.0, 0.0, 0.0];
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
    // Ensure device location service is ON
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enable location (GPS) in system settings'),
          ),
        );
      }
      return false;
    }

    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.deniedForever ||
        p == LocationPermission.denied) {
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

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      // Guard against NaN/Infinity values
      if (!pos.latitude.isFinite || !pos.longitude.isFinite) {
        return;
      }

      setState(() {
        _track = [LatLng(pos.latitude, pos.longitude)];
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
      });
    });
  }

  Future<void> _stopLocation() async {
    await _posSub?.cancel();
    _posSub = null;
  }

  Future<File?> _saveGeoJson(File csvFile) async {
    try {
      if (_track.isEmpty) return null;
      final dir = csvFile.parent;
      final name =
          csvFile.uri.pathSegments.last.replaceAll('.csv', '.geojson');
      final coords =
          _track.map((p) => [p.longitude, p.latitude]).toList();

      final fc = {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "properties": {
              "source": "shoeml",
              "label": _label,
            },
            "geometry": {
              "type": "LineString",
              "coordinates": coords,
            },
          }
        ],
      };

      final f = File("${dir.path}/$name");
      await f.writeAsString(
        const JsonEncoder.withIndent('  ').convert(fc),
      );
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

      final ui.Image image =
          await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final dir = csvFile.parent;
      final name =
          csvFile.uri.pathSegments.last.replaceAll('.csv', '_map.png');
      final f = File("${dir.path}/$name");
      await f.writeAsBytes(
        byteData.buffer.asUint8List(),
      );
      return f;
    } catch (_) {
      return null;
    }
  }

  Widget _buildRouteMap() {
    // If we have no GPS points yet, show a placeholder instead of map
    if (_track.isEmpty) {
      return Container(
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        child: const Text(
          'No route yet.\nTap "Start" to begin capturing GPS.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return FlutterMap(
      options: MapOptions(
        initialZoom: 16,
        initialCenter: _track.last,
      ),
      children: [
        const TileLayer(
          urlTemplate:
              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.shoeml',
        ),
        PolylineLayer(
          polylines: [
            Polyline(points: _track, strokeWidth: 4),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              width: 30,
              height: 30,
              point: _track.first,
              child: const Icon(Icons.flag),
            ),
            Marker(
              width: 30,
              height: 30,
              point: _track.last,
              child: const Icon(Icons.place),
            ),
          ],
        ),
      ],
    );
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
                "Pick a label, Start/Stop capture, CSV auto-saves on stop.",
              ),
              trailing: Wrap(
                spacing: 8,
                children: [
                  DropdownButton<String>(
                    value: _label,
                    items: _labels
                        .map(
                          (e) => DropdownMenuItem(
                            value: e,
                            child: Text(e),
                          ),
                        )
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _label = v ?? _label),
                  ),
                  FilledButton.icon(
                    onPressed: _toggleCollect,
                    icon: Icon(
                      _collecting
                          ? Icons.stop
                          : Icons.fiber_manual_record,
                    ),
                    label: Text(
                      _collecting
                          ? "Stop & Save CSV"
                          : "Start",
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
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Train & Save Model",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
                    "Windows: 3s / hop 1.5s • Features: "
                    "mean/var/RMS + cadence/stride/temp",
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _trainAndSave,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text("Train & Save"),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text("Share last CSV"),
              subtitle: const Text(
                "Open Files → Android/data/<pkg>/files/shoeml/sessions",
              ),
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
                    ..sort(
                      (a, b) => b
                          .lastModifiedSync()
                          .compareTo(a.lastModifiedSync()),
                    );
                  if (files.isEmpty) return;
                  await Share.shareXFiles(
                    [XFile(files.first.path)],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Training Route Preview",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 220,
                    child: RepaintBoundary(
                      key: _mapKey,
                      child: _buildRouteMap(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RawSample {
  _RawSample(
    this.t,
    this.roll,
    this.pitch,
    this.yaw,
    this.tempC,
    this.cadence,
    this.strideM,
    this.dH,
  );

  double t;
  double? roll, pitch, yaw, tempC, cadence, strideM, dH;
}

// ---- Softmax classifier for on-device training ----
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
      (_) => List.generate(
        D,
        (_) => (rnd.nextDouble() - 0.5) * 0.01,
      ),
    );
    b = List.filled(C, 0.0);
  }

  List<double> _softmax(List<double> z) {
    final m = z.reduce(math.max);
    final exps = z.map((v) => math.exp(v - m)).toList();
    final s = exps.reduce((a, b) => a + b);
    return exps.map((v) => v / s).toList();
  }

  List<double> _predictProba(List<double> x) {
    final z = List<double>.generate(
      C,
      (k) {
        double s = b[k];
        for (int j = 0; j < D; j++) {
          s += W[k][j] * x[j];
        }
        return s;
      },
    );
    return _softmax(z);
  }

  int predict(List<double> x) {
    final p = _predictProba(x);
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

  void fit(
    List<List<double>> X,
    List<int> y, {
    int epochs = 50,
    double lr = 0.05,
    double l2 = 1e-4,
    int batch = 64,
  }) {
    final n = X.length;
    if (n == 0) return;

    for (int ep = 0; ep < epochs; ep++) {
      for (int i0 = 0; i0 < n; i0 += batch) {
        final i1 = math.min(n, i0 + batch);
        final m = i1 - i0;
        if (m <= 0) continue;

        final dW = List.generate(
          C,
          (_) => List.filled(D, 0.0),
        );
        final db = List.filled(C, 0.0);

        for (int i = i0; i < i1; i++) {
          final xi = X[i];
          final yi = y[i];
          final p = _predictProba(xi);

          for (int k = 0; k < C; k++) {
            final grad = p[k] - (k == yi ? 1.0 : 0.0);
            db[k] += grad;
            for (int j = 0; j < D; j++) {
              dW[k][j] += grad * xi[j];
            }
          }
        }

        for (int k = 0; k < C; k++) {
          for (int j = 0; j < D; j++) {
            dW[k][j] = dW[k][j] / m + l2 * W[k][j];
            W[k][j] -= lr * dW[k][j];
          }
          db[k] /= m;
          b[k] -= lr * db[k];
        }
      }
    }
  }

  double accuracy(List<List<double>> X, List<int> y) {
    if (X.isEmpty) return 0.0;
    int correct = 0;
    for (int i = 0; i < X.length; i++) {
      if (predict(X[i]) == y[i]) correct++;
    }
    return correct / X.length;
  }
}
