// lib/pages/training_page.dart
//
// Improvements over previous version:
//  1. Incremental CSV write — IOSink opened on Start, one row written per
//     roll BLE event, flushed/closed on Stop.  RAM never holds more than
//     300 samples regardless of session length.
//  2. Multi-label training — "Train & Save" scans ALL saved CSVs, reads
//     the label column, builds a combined feature matrix, shuffles, and
//     trains a softmax across every label present (not just the one
//     selected in the UI).
//  3. Dataset summary card shows window counts per label so the user can
//     see what data they have before pressing Train.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../ble.dart';

class TrainingPage extends StatefulWidget {
  const TrainingPage({super.key, required this.ble});
  final ShoeBle ble;

  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  // ── Labels ─────────────────────────────────────────────────────────────
  static const _labels = [
    'walking', 'running', 'stairs_up', 'stairs_down', 'standing', 'sitting',
  ];
  String _label = 'walking';

  // ── Connection ──────────────────────────────────────────────────────────
  DeviceConnectionState _conn = DeviceConnectionState.disconnected;
  StreamSubscription<DeviceConnectionState>? _connSub;
  bool get _connected => _conn == DeviceConnectionState.connected;

  // ── BLE streams ─────────────────────────────────────────────────────────
  StreamSubscription? _sr, _sp, _sy, _st, _sc, _ss, _sdh;

  // Latest values — roll is the write clock, others are just cached.
  double  _latPitch = 0, _latYaw = 0, _latCadence = 0,
          _latStride = 0, _latDh = 0;
  double? _latTemp;

  // ── Collection state ────────────────────────────────────────────────────
  bool      _collecting  = false;
  DateTime? _tStart;
  double    _tRel        = 0;   // relative time, increments on each roll event
  int       _sampleCount = 0;   // display counter only

  // Incremental write — opened on Start, closed on Stop.
  IOSink? _sink;
  File?   _csvFile;

  // Rolling window for display only; never used for training.
  final List<_RawRow> _liveBuf = [];
  static const _liveBufMax = 300;

  // ── GPS / route ─────────────────────────────────────────────────────────
  final GlobalKey     _mapKey  = GlobalKey();
  final MapController _mapCtrl = MapController();
  List<LatLng>   _track   = [];
  List<DateTime> _trackTs = [];
  StreamSubscription<Position>? _posSub;
  double   _lastDistM = 0;
  Duration _lastDur   = Duration.zero;

  // ── Dataset summary ─────────────────────────────────────────────────────
  Map<String, int> _datasetCounts  = {};  // label -> window count
  bool             _datasetLoading = false;

  // Session manager
  List<_SessionInfo> _sessions        = [];
  bool               _sessionsLoading = false;

  // ── Training state ──────────────────────────────────────────────────────
  bool _training = false;
  final _modelNameCtrl = TextEditingController();

  // ── Lifecycle ───────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _bindBle();
    _connSub = widget.ble.connection$.listen((c) {
      if (!mounted) return;
      setState(() => _conn = c);
    });
    _refreshDataset();
    _loadSessions();
  }

  @override
  void dispose() {
    for (final s in [_sr, _sp, _sy, _st, _sc, _ss, _sdh]) s?.cancel();
    _connSub?.cancel();
    _posSub?.cancel();
    _sink?.close();
    _modelNameCtrl.dispose();
    super.dispose();
  }

  // ── BLE binding ─────────────────────────────────────────────────────────

  void _bindBle() {
    // Roll fires the write clock.  One CSV row is written per event.
    _sr = widget.ble.roll$.listen((roll) {
      if (!_collecting) return;
      _tRel += 0.1;
      final row = _RawRow(
        t: _tRel, roll: roll, pitch: _latPitch, yaw: _latYaw,
        tempC: _latTemp, cadence: _latCadence, strideM: _latStride,
        dh: _latDh, label: _label,
      );
      _sink?.writeln(row.toCsv());
      _liveBuf.add(row);
      if (_liveBuf.length > _liveBufMax) _liveBuf.removeAt(0);
      if (mounted) setState(() => _sampleCount++);
    });
    // All others just update the cache — no list growth.
    _sp  = widget.ble.pitch$.listen((v)   { _latPitch   = v; });
    _sy  = widget.ble.yaw$.listen((v)     { _latYaw     = v; });
    _st  = widget.ble.temp$.listen((v)    { _latTemp    = v; });
    _sc  = widget.ble.cadence$.listen((v) { _latCadence = v; });
    _ss  = widget.ble.stride$.listen((v)  { _latStride  = v; });
    _sdh = widget.ble.dh$.listen((v)      { _latDh      = v; });
  }

  // ── Collection control ──────────────────────────────────────────────────

  Future<void> _toggleCollect() async {
    if (!_collecting) {
      // START
      if (!_connected) { _snack('Connect to the shoe first.'); return; }
      final dir   = await _ensureDir(await _appDir(), 'sessions');
      final stamp = DateFormat('yyMMdd_HHmmss').format(DateTime.now());
      _csvFile    = File('${dir.path}/${_label}_$stamp.csv');
      _sink       = _csvFile!.openWrite();
      _sink!.writeln(_RawRow.csvHeader);
      setState(() {
        _collecting = true; _sampleCount = 0; _tRel = 0;
        _liveBuf.clear(); _track = []; _trackTs = [];
        _tStart = DateTime.now();
      });
      await _startGps();
    } else {
      // STOP
      await _stopGps();
      if (_sampleCount == 0) {
        await _sink?.close(); _sink = null; _csvFile = null;
        if (mounted) setState(() => _collecting = false);
        _snack('No sensor data received — nothing saved.');
        return;
      }
      await _sink?.flush();
      await _sink?.close();
      _sink = null;
      _lastDistM = _computeDistM();
      _lastDur   = _tStart != null
          ? DateTime.now().difference(_tStart!) : Duration.zero;
      await _fitRoute();
      final csv = _csvFile!; _csvFile = null;
      if (mounted) setState(() => _collecting = false);
      final png = await _captureMapPng();
      final geo = await _saveGeoJson(csv);
      final gpx = await _saveGpx(csv);
      final kml = await _saveKml(csv);
      await _showSummarySheet(csv, png, geo, gpx, kml);
      await _refreshDataset();
      await _loadSessions();
    }
  }

  // ── Dataset scan ────────────────────────────────────────────────────────

  Future<void> _refreshDataset() async {
    if (!mounted) return;
    setState(() => _datasetLoading = true);
    try {
      final dir   = await _ensureDir(await _appDir(), 'sessions');
      final files = dir.listSync().whereType<File>()
          .where((f) => f.path.endsWith('.csv')).toList();
      final counts = <String, int>{};
      for (final f in files) {
        try {
          final lines = await f.readAsLines();
          if (lines.length < 2) continue;
          // Count rows per label; estimate windows at 10 Hz BLE rate
          // (3 s window = 30 rows, 1.5 s hop = 15 rows).
          final rowsByLabel = <String, int>{};
          for (final l in lines.skip(1)) {
            if (l.trim().isEmpty) continue;
            final parts = l.split(',');
            if (parts.length < 9) continue;
            final lbl = parts[8].trim();
            if (lbl.isNotEmpty) rowsByLabel[lbl] = (rowsByLabel[lbl] ?? 0) + 1;
          }
          for (final e in rowsByLabel.entries) {
            final wins = math.max(0, (e.value - 30) ~/ 15 + 1);
            counts[e.key] = (counts[e.key] ?? 0) + wins;
          }
        } catch (_) {}
      }
      if (mounted) setState(() => _datasetCounts = counts);
    } finally {
      if (mounted) setState(() => _datasetLoading = false);
    }
  }

  // ── Multi-label training ────────────────────────────────────────────────


  // Session manager methods

  Future<void> _loadSessions() async {
    if (!mounted) return;
    setState(() => _sessionsLoading = true);
    try {
      final dir   = await _ensureDir(await _appDir(), 'sessions');
      final files = dir.listSync().whereType<File>()
          .where((f) => f.path.endsWith('.csv')).toList()
        ..sort((a, b) =>
            b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      final infos = <_SessionInfo>[];
      for (final f in files) {
        try {
          final name  = f.uri.pathSegments.last.replaceAll('.csv', '');
          final parts = name.split('_');
          int split = parts.length;
          for (int i = parts.length - 1; i >= 0; i--) {
            if (RegExp(r'^\d{6}$').hasMatch(parts[i])) split = i;
            else break;
          }
          final label   = parts.sublist(0, split).join('_');
          final samples = math.max(0, (await f.readAsLines()).length - 1);
          infos.add(_SessionInfo(
            file: f, label: label,
            dateStr: DateFormat('MMM d yyyy  HH:mm')
                         .format(f.lastModifiedSync()),
            sampleCount: samples,
          ));
        } catch (_) {}
      }
      if (mounted) setState(() => _sessions = infos);
    } finally {
      if (mounted) setState(() => _sessionsLoading = false);
    }
  }

  Future<void> _deleteSession(_SessionInfo info) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete session?'),
        content: Text(info.file.uri.pathSegments.last),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await info.file.delete();
      await _loadSessions();
      await _refreshDataset();
    } catch (e) { _snack('Delete failed: $e'); }
  }

  Future<void> _clearAllSessions() async {
    if (_sessions.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all sessions?'),
        content: Text('Deletes all ${_sessions.length} CSV files permanently.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete all')),
        ],
      ),
    );
    if (ok != true) return;
    for (final s in List<_SessionInfo>.from(_sessions)) {
      try { await s.file.delete(); } catch (_) {}
    }
    await _loadSessions();
    await _refreshDataset();
  }

  Future<void> _trainAndSave() async {
    if (_training) return;
    setState(() => _training = true);
    try {
      final dir   = await _ensureDir(await _appDir(), 'sessions');
      final files = dir.listSync().whereType<File>()
          .where((f) => f.path.endsWith('.csv')).toList();
      if (files.isEmpty) {
        _snack('No sessions found. Collect at least two labels first.');
        return;
      }

      final X           = <List<double>>[];
      final y           = <int>[];
      final foundLabels = <String>{};

      for (final f in files) {
        try {
          final rows = await _loadCsvRows(f);
          if (rows.length < 30) continue;
          for (final w in _windowRows(rows)) {
            final lbl = w.first.label;
            final idx = _labels.indexOf(lbl);
            if (idx < 0) continue;
            foundLabels.add(lbl);
            X.add(_features(w));
            y.add(idx);
          }
        } catch (_) {}
      }

      if (foundLabels.length < 2) {
        _snack(
          'Need sessions for ≥2 labels. '
          'Found: ${foundLabels.isEmpty ? "none" : foundLabels.join(", ")}.',
        );
        return;
      }

      // Shuffle then 80/20 split.
      final rng     = math.Random(42);
      final indices = List.generate(X.length, (i) => i)..shuffle(rng);
      final Xs      = [for (final i in indices) X[i]];
      final ys      = [for (final i in indices) y[i]];
      final m       = math.max(1, (Xs.length * 0.8).floor());

      // Random Forest: 50 trees, max depth 12, sqrt feature subsampling.
      final clf = RandomForestClassifier(nTrees: 50, maxDepth: 12);
      clf.fit(Xs.sublist(0, m), ys.sublist(0, m),
              numClasses: _labels.length);
      final acc = clf.accuracy(Xs.sublist(m), ys.sublist(m));

      final mDir  = await _ensureDir(await _appDir(), 'models');
      final stamp = DateFormat('yyMMdd_HHmmss').format(DateTime.now());
      final base  = _modelNameCtrl.text.trim().isEmpty
          ? (foundLabels.toList()..sort()).join('_')
          : _modelNameCtrl.text.trim();
      await File('${mDir.path}/${base}_$stamp.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            ...clf.toJson(),
            'labels':      _labels,
            'input_dim':   Xs.first.length,
            'num_classes': _labels.length,
            'trained_on':  (foundLabels.toList()..sort()),
            'windows':     Xs.length,
            'accuracy':    acc,
          }));

      // Build confusion matrix on test set.
      final testX   = Xs.sublist(m);
      final testY   = ys.sublist(m);
      final usedLbls = (foundLabels.toList()..sort());
      final idxMap   = { for (int i = 0; i < _labels.length; i++) i: _labels[i] };
      // matrix[actual][predicted] = count
      final matrix = List.generate(
          _labels.length, (_) => List.filled(_labels.length, 0));
      for (int i = 0; i < testX.length; i++) {
        final pred = clf.predict(testX[i]);
        matrix[testY[i]][pred]++;
      }

      if (mounted) {
        _snack('RF saved — ${(acc * 100).toStringAsFixed(1)}% acc · '
               '${Xs.length} windows · ${foundLabels.length} labels');
        await _showConfusionMatrix(matrix, idxMap, usedLbls, acc);
      }
    } finally {
      if (mounted) setState(() => _training = false);
    }
  }

  // ── Confusion matrix dialog ──────────────────────────────────────────────

  Future<void> _showConfusionMatrix(
    List<List<int>> matrix,
    Map<int, String> idxMap,
    List<String> usedLbls,
    double overallAcc,
  ) async {
    if (!mounted) return;

    // Per-class recall (true positives / actual count).
    final recalls = <String, double>{};
    for (int i = 0; i < _labels.length; i++) {
      final lbl   = _labels[i];
      if (!usedLbls.contains(lbl)) continue;
      final total = matrix[i].fold(0, (a, b) => a + b);
      recalls[lbl] = total > 0 ? matrix[i][i] / total : 0.0;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs     = Theme.of(ctx).colorScheme;
        final active = _labels.where((l) => usedLbls.contains(l)).toList();
        return AlertDialog(
          title: const Text('Training results'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Overall accuracy
                  Text('Overall test accuracy: '
                       '${(overallAcc * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),

                  // Per-class recall bars
                  Text('Per-class recall (test set):',
                      style: Theme.of(ctx).textTheme.labelMedium),
                  const SizedBox(height: 6),
                  ...active.map((lbl) {
                    final r   = recalls[lbl] ?? 0.0;
                    final bad = r < 0.6;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        SizedBox(
                          width: 90,
                          child: Text(lbl.replaceAll('_', ' '),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: bad ? cs.error : cs.onSurface)),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: r, minHeight: 10,
                              backgroundColor: cs.surfaceContainerHighest,
                              color: bad ? cs.error : cs.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 38,
                          child: Text('${(r * 100).toStringAsFixed(0)}%',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: bad ? cs.error : cs.onSurface)),
                        ),
                      ]),
                    );
                  }),
                  const SizedBox(height: 14),

                  // Confusion matrix grid
                  Text('Confusion matrix (rows=actual, cols=predicted):',
                      style: Theme.of(ctx).textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Text('Abbreviations: ' +
                       active.map((l) => '${l[0].toUpperCase()}${l[1]}='
                           '${l.replaceAll("_"," ")}').join(', '),
                      style: TextStyle(
                          fontSize: 10, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Table(
                      defaultColumnWidth: const FixedColumnWidth(32),
                      border: TableBorder.all(
                          color: cs.outline.withOpacity(0.3), width: 0.5),
                      children: [
                        // Header row
                        TableRow(children: [
                          const SizedBox(width: 32, height: 24),
                          ...active.map((l) => Center(
                            child: Text(
                              '${l[0].toUpperCase()}${l[1]}',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: cs.primary),
                            ),
                          )),
                        ]),
                        // Data rows
                        ...active.map((rowLbl) {
                          final ri = _labels.indexOf(rowLbl);
                          return TableRow(children: [
                            // Row label
                            Center(
                              child: Text(
                                '${rowLbl[0].toUpperCase()}${rowLbl[1]}',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: cs.primary),
                              ),
                            ),
                            // Counts
                            ...active.map((colLbl) {
                              final ci  = _labels.indexOf(colLbl);
                              final cnt = ri >= 0 && ci >= 0
                                  ? matrix[ri][ci] : 0;
                              final isDiag = rowLbl == colLbl;
                              return Container(
                                height: 24,
                                color: isDiag && cnt > 0
                                    ? cs.primaryContainer.withOpacity(0.5)
                                    : cnt > 0 && !isDiag
                                        ? cs.errorContainer.withOpacity(0.4)
                                        : null,
                                child: Center(
                                  child: Text('$cnt',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: isDiag
                                              ? FontWeight.w700
                                              : FontWeight.normal,
                                          color: isDiag
                                              ? cs.onPrimaryContainer
                                              : cnt > 0
                                                  ? cs.onErrorContainer
                                                  : cs.onSurfaceVariant)),
                                ),
                              );
                            }),
                          ]);
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Diagonal = correct. Off-diagonal = misclassified. '
                    'Red recall bar = below 60% — collect more data for that label.',
                    style: TextStyle(
                        fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // ── CSV / windowing helpers ──────────────────────────────────────────────

  Future<List<_RawRow>> _loadCsvRows(File f) async {
    final lines = await f.readAsLines();
    final out   = <_RawRow>[];
    for (final l in lines.skip(1)) {
      if (l.trim().isEmpty) continue;
      final r = _RawRow.fromCsv(l);
      if (r != null) out.add(r);
    }
    return out;
  }

  List<List<_RawRow>> _windowRows(List<_RawRow> rows,
      {int winN = 30, int hopN = 15}) {
    if (rows.length < winN) return [];
    final out = <List<_RawRow>>[];
    for (int i = 0; i + winN <= rows.length; i += hopN) {
      out.add(rows.sublist(i, i + winN));
    }
    return out;
  }

  List<double> _features(List<_RawRow> win) {
    List<double> col(double? Function(_RawRow) fn) =>
        win.map(fn).whereType<double>().toList();

    List<double> stats(List<double> x) {
      if (x.isEmpty) return [0.0, 0.0, 0.0];
      final n    = x.length;
      final mean = x.reduce((a, b) => a + b) / n;
      final vari = x.map((v) => (v - mean) * (v - mean))
                    .reduce((a, b) => a + b) / n;
      final rms  = math.sqrt(x.map((v) => v * v).reduce((a, b) => a + b) / n);
      return [mean, vari, rms];
    }

    // Jerk = first-order finite difference of angular channel.
    // Captures how abruptly the foot rotates — critical for separating
    // stairs (high jerk at each step edge) from walking (smooth).
    List<double> jerk(List<double> x) {
      if (x.length < 2) return stats([0.0]);
      final diffs = <double>[];
      for (int i = 1; i < x.length; i++) diffs.add(x[i] - x[i - 1]);
      return stats(diffs);
    }

    final rollV  = col((r) => r.roll);
    final pitchV = col((r) => r.pitch);
    final yawV   = col((r) => r.yaw);

    return [
      // ── Basic stats (18 values) ──────────────────────────────────────
      ...stats(rollV),
      ...stats(pitchV),
      ...stats(yawV),
      ...stats(col((r) => r.cadence)),
      ...stats(col((r) => r.strideM)),
      ...stats(col((r) => r.tempC)),
      // ── Jerk stats (9 values) ────────────────────────────────────────
      ...jerk(rollV),
      ...jerk(pitchV),
      ...jerk(yawV),
    ]; // total: 27 features
  }

  // ── GPS helpers ─────────────────────────────────────────────────────────

  Future<bool> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _snack('Enable GPS in system settings'); return false;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      _snack('Location permission denied'); return false;
    }
    return true;
  }

  Future<void> _startGps() async {
    if (!await _ensureLocationPermission()) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best);
      if (!pos.latitude.isFinite || !pos.longitude.isFinite) return;
      final pt = LatLng(pos.latitude, pos.longitude);
      if (mounted) setState(() { _track = [pt]; _trackTs = [DateTime.now()]; });
      try { _mapCtrl.move(pt, 16); } catch (_) {}
    } catch (_) {}
    await _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best, distanceFilter: 3),
    ).listen((pos) {
      if (!pos.latitude.isFinite || !pos.longitude.isFinite) return;
      final pt = LatLng(pos.latitude, pos.longitude);
      if (_track.isNotEmpty) {
        final d = Geolocator.distanceBetween(_track.last.latitude,
            _track.last.longitude, pt.latitude, pt.longitude);
        if (d > 1000 || (d < 8 && pos.speed.isFinite && pos.speed < 0.5)) return;
      }
      if (mounted) setState(() { _track.add(pt); _trackTs.add(DateTime.now()); });
      try { _mapCtrl.move(pt, _mapCtrl.camera.zoom); } catch (_) {}
    });
  }

  Future<void> _stopGps() async { await _posSub?.cancel(); _posSub = null; }

  double _computeDistM() {
    if (_track.length < 2) return 0;
    double d = 0;
    for (int i = 1; i < _track.length; i++) {
      d += Geolocator.distanceBetween(_track[i-1].latitude,
          _track[i-1].longitude, _track[i].latitude, _track[i].longitude);
    }
    return d;
  }

  Future<void> _fitRoute() async {
    if (_track.length < 2) return;
    await Future.delayed(const Duration(milliseconds: 100));
    double minLat = _track.first.latitude, maxLat = minLat;
    double minLon = _track.first.longitude, maxLon = minLon;
    for (final p in _track) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    const sp = 0.001;
    if ((maxLat - minLat).abs() < sp) { minLat -= sp/2; maxLat += sp/2; }
    if ((maxLon - minLon).abs() < sp) { minLon -= sp/2; maxLon += sp/2; }
    try {
      _mapCtrl.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds(LatLng(minLat, minLon), LatLng(maxLat, maxLon)),
        padding: const EdgeInsets.all(20)));
    } catch (_) {}
  }

  // ── Export helpers ───────────────────────────────────────────────────────

  Future<Uint8List?> _captureMapPng() async {
    try {
      final ctx = _mapKey.currentContext; if (ctx == null) return null;
      final b   = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (b == null) return null;
      final img = await b.toImage(pixelRatio: 3.0);
      final bd  = await img.toByteData(format: ui.ImageByteFormat.png);
      return bd?.buffer.asUint8List();
    } catch (_) { return null; }
  }

  String _stem(File f) =>
      f.uri.pathSegments.last.replaceAll(RegExp(r'\.csv$'), '');

  Future<File?> _saveGeoJson(File csv) async {
    try {
      if (_track.isEmpty) return null;
      final f = File('${csv.parent.path}/${_stem(csv)}.geojson');
      await f.writeAsString(jsonEncode({
        'type': 'FeatureCollection',
        'features': [{
          'type': 'Feature',
          'properties': {'label': _label, 'distance_m': _lastDistM},
          'geometry': {'type': 'LineString',
            'coordinates': _track.map((p) => [p.longitude, p.latitude]).toList()},
        }],
      }), flush: true);
      return f;
    } catch (_) { return null; }
  }

  Future<File?> _saveGpx(File csv) async {
    try {
      if (_track.isEmpty) return null;
      final sb = StringBuffer()
        ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
        ..writeln('<gpx version="1.1" creator="ShoeML">'
                  '<trk><n>$_label</n><trkseg>');
      for (int i = 0; i < _track.length; i++) {
        final p = _track[i];
        final t = i < _trackTs.length
            ? _trackTs[i].toUtc().toIso8601String()
            : DateTime.now().toUtc().toIso8601String();
        sb.writeln('<trkpt lat="${p.latitude}" lon="${p.longitude}">'
                   '<time>$t</time></trkpt>');
      }
      sb.writeln('</trkseg></trk></gpx>');
      final f = File('${csv.parent.path}/${_stem(csv)}.gpx');
      await f.writeAsString(sb.toString(), flush: true);
      return f;
    } catch (_) { return null; }
  }

  Future<File?> _saveKml(File csv) async {
    try {
      if (_track.isEmpty) return null;
      final safe = _label.replaceAll(RegExp(r'\W+'), '_');
      final sb = StringBuffer()
        ..writeln('<?xml version="1.0"?>')
        ..writeln('<kml xmlns="http://www.opengis.net/kml/2.2">'
                  '<Document><n>$safe</n><Placemark>'
                  '<LineString><coordinates>');
      for (final p in _track) sb.writeln('${p.longitude},${p.latitude},0');
      sb.writeln('</coordinates></LineString></Placemark></Document></kml>');
      final f = File('${csv.parent.path}/${_stem(csv)}.kml');
      await f.writeAsString(sb.toString(), flush: true);
      return f;
    } catch (_) { return null; }
  }

  // ── Utilities ────────────────────────────────────────────────────────────

  Future<Directory> _appDir() async {
    final d   = await getApplicationDocumentsDirectory();
    final dir = Directory('${d.path}/shoeml');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<Directory> _ensureDir(Directory base, String child) async {
    final d = Directory('${base.path}/$child');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  String _dist(double m) => m < 1000
      ? '${m.toStringAsFixed(1)} m' : '${(m/1000).toStringAsFixed(2)} km';
  String _dur(Duration d) => '${d.inMinutes}m ${d.inSeconds % 60}s';

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showSummarySheet(
      File csv, Uint8List? png, File? geo, File? gpx, File? kml) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Session saved',
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('$_label  ·  $_sampleCount samples  ·  '
                 '${_dist(_lastDistM)}  ·  ${_dur(_lastDur)}'),
            const SizedBox(height: 8),
            if (png != null)
              SizedBox(
                height: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(png, fit: BoxFit.cover,
                      width: double.infinity),
                ),
              ),
            const SizedBox(height: 8),
            Text(csv.path.split('/').last,
                style: Theme.of(ctx).textTheme.bodySmall),
            if (geo != null) Text('GeoJSON saved',
                style: Theme.of(ctx).textTheme.bodySmall),
            if (gpx != null) Text('GPX saved',
                style: Theme.of(ctx).textTheme.bodySmall),
            if (kml != null) Text('KML saved',
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.share),
                label: const Text('Share CSV'),
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await Share.shareXFiles([XFile(csv.path)],
                      text: 'ShoeML session');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(children: [
        _collectCard(cs),
        const SizedBox(height: 12),
        _datasetCard(cs),
        const SizedBox(height: 12),
        _trainCard(cs),
        const SizedBox(height: 12),
        _sessionManagerCard(cs),
        const SizedBox(height: 12),
        _shareCard(),
        const SizedBox(height: 12),
        _routeCard(cs),
      ]),
    );
  }

  Widget _collectCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Collect samples',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'Pick a label, tap Start. Stop saves the session to a CSV '
              'and adds it to the training pool. Collect at least one '
              'session per label you want to classify.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8, runSpacing: 6,
              children: _labels.map((lbl) => ChoiceChip(
                label: Text(lbl.replaceAll('_', ' ')),
                selected: _label == lbl,
                onSelected: _collecting ? null : (on) {
                  if (on) setState(() => _label = lbl);
                },
              )).toList(),
            ),
            const SizedBox(height: 12),
            Row(children: [
              FilledButton.icon(
                onPressed: _collecting
                    ? _toggleCollect
                    : (_connected ? _toggleCollect : null),
                icon: Icon(_collecting
                    ? Icons.stop : Icons.fiber_manual_record),
                label: Text(_collecting
                    ? 'Stop & Save' : 'Start  "$_label"'),
                style: _collecting
                    ? FilledButton.styleFrom(
                        backgroundColor: cs.error,
                        foregroundColor: cs.onError) : null,
              ),
              if (_collecting) ...[
                const SizedBox(width: 12),
                Text('$_sampleCount samples',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ]),
            if (!_connected && !_collecting)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Connect to the shoe to enable recording.',
                    style: TextStyle(color: cs.error, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _datasetCard(ColorScheme cs) {
    final total          = _datasetCounts.values.fold(0, (a, b) => a + b);
    final labelsWithData = _datasetCounts.keys
        .where((l) => (_datasetCounts[l] ?? 0) > 0).length;

    return Card(
      color: cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('Training dataset',
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              if (_datasetLoading)
                const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: _refreshDataset,
                  tooltip: 'Refresh',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ]),
            const SizedBox(height: 8),
            if (total == 0)
              Text('No sessions yet. Record at least one session per label.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))
            else ...[
              Text('$total windows  ·  $labelsWithData label(s)',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              ..._labels.map((lbl) {
                final count = _datasetCounts[lbl] ?? 0;
                final frac  = total > 0 ? count / total : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    SizedBox(
                      width: 108,
                      child: Text(lbl.replaceAll('_', ' '),
                          style: const TextStyle(fontSize: 12)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: frac, minHeight: 8,
                          backgroundColor: cs.surfaceContainerHighest,
                          color: count > 0 ? cs.primary : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 38,
                      child: Text(count > 0 ? '$count' : '—',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            color: count > 0
                                ? cs.onSurface : cs.onSurfaceVariant,
                          )),
                    ),
                  ]),
                );
              }),
              if (labelsWithData < 2)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '⚠  Need data for at least 2 labels before training.',
                    style: TextStyle(color: cs.error, fontSize: 12),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _trainCard(ColorScheme cs) {
    final labelsWithData = _datasetCounts.keys
        .where((l) => (_datasetCounts[l] ?? 0) > 0).length;
    final canTrain = labelsWithData >= 2 && !_training && !_collecting;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Train classifier',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'Reads all saved sessions, extracts 3 s windows (hop 1.5 s), '
              'shuffles, then trains across all labels present. '
              'Split: 80 % train / 20 % test.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Model name (optional)',
                hintText: 'e.g. outdoor_v2',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              FilledButton.icon(
                onPressed: canTrain ? _trainAndSave : null,
                icon: _training
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome),
                label: Text(_training ? 'Training…' : 'Train & Save'),
              ),
              if (!canTrain && !_training)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text(
                    labelsWithData < 2
                        ? 'Collect ≥2 labels first.'
                        : _collecting ? 'Stop recording first.' : '',
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _sessionManagerCard(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('Saved sessions',
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              if (_sessionsLoading)
                const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: _loadSessions,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Refresh',
                  ),
                  if (_sessions.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: _clearAllSessions,
                      icon: Icon(Icons.delete_sweep,
                          size: 16, color: cs.error),
                      label: Text('Clear all',
                          style: TextStyle(color: cs.error, fontSize: 12)),
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4)),
                    ),
                  ],
                ]),
            ]),
            const SizedBox(height: 8),
            if (_sessions.isEmpty && !_sessionsLoading)
              Text('No sessions yet.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))
            else
              ..._sessions.map((info) => Dismissible(
                    key: ValueKey(info.file.path),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      color: cs.errorContainer,
                      child: Icon(Icons.delete, color: cs.onErrorContainer),
                    ),
                    confirmDismiss: (_) async {
                      await _deleteSession(info);
                      return false;
                    },
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Chip(
                        label: Text(info.label.replaceAll('_', ' '),
                            style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      title: Text(info.dateStr,
                          style: const TextStyle(fontSize: 12)),
                      subtitle: Text('${info.sampleCount} samples',
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant)),
                      trailing: IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: cs.error, size: 18),
                        onPressed: () => _deleteSession(info),
                        tooltip: 'Delete',
                      ),
                    ),
                  )).toList(),
          ],
        ),
      ),
    );
  }

  Widget _shareCard() {
    return Card(
      child: ListTile(
        title: const Text('Share last CSV'),
        subtitle: const Text('Shares the most recently saved session.'),
        trailing: IconButton(
          icon: const Icon(Icons.share),
          onPressed: () async {
            final dir = await _ensureDir(await _appDir(), 'sessions');
            final files = dir.listSync().whereType<File>()
                .where((f) => f.path.endsWith('.csv')).toList()
              ..sort((a, b) =>
                  b.lastModifiedSync().compareTo(a.lastModifiedSync()));
            if (files.isEmpty) { _snack('No sessions yet.'); return; }
            await Share.shareXFiles([XFile(files.first.path)],
                text: 'ShoeML session');
          },
        ),
      ),
    );
  }

  Widget _routeCard(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Route preview',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: RepaintBoundary(
                key: _mapKey,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _track.isEmpty
                      ? Container(
                          color: cs.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.location_searching,
                                  size: 42, color: cs.onSurfaceVariant),
                              const SizedBox(height: 8),
                              Text('Start a recording to see GPS route.',
                                  style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 13)),
                            ],
                          ),
                        )
                      : FlutterMap(
                          mapController: _mapCtrl,
                          options: MapOptions(
                              initialCenter: _track.last,
                              initialZoom: 16),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.madeplus.shoeml',
                            ),
                            if (_track.length > 1)
                              PolylineLayer(polylines: [
                                Polyline(
                                  points: _track, strokeWidth: 4,
                                  color: cs.primary,
                                ),
                              ]),
                            MarkerLayer(markers: [
                              Marker(
                                  width: 30, height: 30,
                                  point: _track.first,
                                  child: const Icon(Icons.flag,
                                      color: Colors.green)),
                              Marker(
                                  width: 30, height: 30,
                                  point: _track.last,
                                  child: const Icon(Icons.place,
                                      color: Colors.red)),
                            ]),
                          ],
                        ),
                ),
              ),
            ),
            if (_lastDistM > 0 || _lastDur.inSeconds > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Last: ${_dist(_lastDistM)} · ${_dur(_lastDur)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class _RawRow {
  static const csvHeader =
      't,roll,pitch,yaw,tempC,cadence,strideM,deltaH,label';

  const _RawRow({
    required this.t, required this.roll, required this.pitch,
    required this.yaw, required this.tempC, required this.cadence,
    required this.strideM, required this.dh, required this.label,
  });

  final double  t, roll, pitch, yaw;
  final double? tempC, cadence, strideM, dh;
  final String  label;

  String toCsv() =>
      '${t.toStringAsFixed(2)},'
      '${roll.toStringAsFixed(4)},'
      '${pitch.toStringAsFixed(4)},'
      '${yaw.toStringAsFixed(4)},'
      '${tempC?.toStringAsFixed(2) ?? ''},'
      '${cadence?.toStringAsFixed(2) ?? ''},'
      '${strideM?.toStringAsFixed(3) ?? ''},'
      '${dh?.toStringAsFixed(3) ?? ''},'
      '$label';

  static _RawRow? fromCsv(String line) {
    try {
      final p = line.split(',');
      if (p.length < 9) return null;
      return _RawRow(
        t:       double.parse(p[0].trim()),
        roll:    double.tryParse(p[1].trim()) ?? 0.0,
        pitch:   double.tryParse(p[2].trim()) ?? 0.0,
        yaw:     double.tryParse(p[3].trim()) ?? 0.0,
        tempC:   double.tryParse(p[4].trim()),
        cadence: double.tryParse(p[5].trim()),
        strideM: double.tryParse(p[6].trim()),
        dh:      double.tryParse(p[7].trim()),
        label:   p[8].trim(),
      );
    } catch (_) { return null; }
  }
}

// ---------------------------------------------------------------------------
// Random Forest Classifier
// ---------------------------------------------------------------------------

class _DTNode {
  int? featureIdx; double? threshold;
  _DTNode? left, right; int? classLabel;
  bool get isLeaf => classLabel != null;
}

class _DecisionTree {
  _DTNode? _root;
  final int maxDepth, minSamples, maxFeatures;
  final math.Random _rng;
  _DecisionTree({required this.maxDepth, required this.minSamples,
      required this.maxFeatures, required math.Random rng}) : _rng = rng;

  void fit(List<List<double>> X, List<int> y) => _root = _build(X, y, 0);

  int predict(List<double> x) {
    var n = _root;
    while (n != null && !n.isLeaf)
      n = x[n.featureIdx!] <= n.threshold! ? n.left : n.right;
    return n?.classLabel ?? 0;
  }

  _DTNode _build(List<List<double>> X, List<int> y, int depth) {
    final node = _DTNode();
    if (y.toSet().length == 1 || depth >= maxDepth || y.length < minSamples) {
      node.classLabel = _majority(y); return node;
    }
    final feats = (List.generate(X.first.length, (i) => i)..shuffle(_rng))
        .take(math.min(maxFeatures, X.first.length)).toList();
    double bestG = double.infinity; int? bestFi; double? bestTh;
    for (final fi in feats) {
      final uniq = X.map((r) => r[fi]).toSet().toList()..sort();
      if (uniq.length < 2) continue;
      final step = math.max(1, (uniq.length - 1) ~/ 20);
      for (int i = 0; i < uniq.length - 1; i += step) {
        final th = (uniq[i] + uniq[i + 1]) / 2;
        final g  = _giniSplit(X, y, fi, th);
        if (g < bestG) { bestG = g; bestFi = fi; bestTh = th; }
      }
    }
    if (bestFi == null) { node.classLabel = _majority(y); return node; }
    node.featureIdx = bestFi; node.threshold = bestTh;
    final lX = <List<double>>[], lY = <int>[], rX = <List<double>>[], rY = <int>[];
    for (int i = 0; i < X.length; i++) {
      if (X[i][bestFi] <= bestTh!) { lX.add(X[i]); lY.add(y[i]); }
      else { rX.add(X[i]); rY.add(y[i]); }
    }
    if (lX.isEmpty || rX.isEmpty) { node.classLabel = _majority(y); return node; }
    node.left = _build(lX, lY, depth + 1);
    node.right = _build(rX, rY, depth + 1);
    return node;
  }

  double _giniSplit(List<List<double>> X, List<int> y, int fi, double th) {
    final lY = <int>[], rY = <int>[];
    for (int i = 0; i < X.length; i++)
      if (X[i][fi] <= th) lY.add(y[i]); else rY.add(y[i]);
    final n = y.length.toDouble();
    if (lY.isEmpty || rY.isEmpty) return double.infinity;
    return lY.length / n * _gini(lY) + rY.length / n * _gini(rY);
  }

  double _gini(List<int> y) {
    final c = <int, int>{};
    for (final v in y) c[v] = (c[v] ?? 0) + 1;
    final n = y.length.toDouble();
    return 1.0 - c.values.fold(0.0, (s, v) => s + (v / n) * (v / n));
  }

  int _majority(List<int> y) {
    final c = <int, int>{};
    for (final v in y) c[v] = (c[v] ?? 0) + 1;
    return c.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  List<Map<String, dynamic>> toNodeList() {
    final out = <Map<String, dynamic>>[]; _flatten(_root, out); return out;
  }

  int _flatten(_DTNode? n, List<Map<String, dynamic>> out) {
    if (n == null) return -1;
    final idx = out.length;
    if (n.isLeaf) { out.add({'cl': n.classLabel}); }
    else {
      out.add({'fi': n.featureIdx, 'th': n.threshold, 'l': -1, 'r': -1});
      out[idx]['l'] = _flatten(n.left, out);
      out[idx]['r'] = _flatten(n.right, out);
    }
    return idx;
  }
}

class RandomForestClassifier {
  final int nTrees, maxDepth, minSamples;
  final List<_DecisionTree> _trees = [];
  RandomForestClassifier({this.nTrees = 30, this.maxDepth = 8, this.minSamples = 4});

  void fit(List<List<double>> X, List<int> y, {required int numClasses}) {
    _trees.clear();
    final n = X.length, nF = X.first.length;
    final maxF = math.sqrt(nF.toDouble()).ceil();
    final rng  = math.Random(42);
    for (int t = 0; t < nTrees; t++) {
      final bX = <List<double>>[], bY = <int>[];
      for (int i = 0; i < n; i++) {
        final idx = rng.nextInt(n); bX.add(X[idx]); bY.add(y[idx]);
      }
      _trees.add(_DecisionTree(
        maxDepth: maxDepth, minSamples: minSamples, maxFeatures: maxF,
        rng: math.Random(rng.nextInt(1 << 30)),
      )..fit(bX, bY));
    }
  }

  int predict(List<double> x) {
    final votes = <int, int>{};
    for (final t in _trees) { final p = t.predict(x); votes[p] = (votes[p] ?? 0) + 1; }
    return votes.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  double accuracy(List<List<double>> X, List<int> y) {
    if (X.isEmpty) return 0;
    int ok = 0;
    for (int i = 0; i < X.length; i++) if (predict(X[i]) == y[i]) ok++;
    return ok / X.length;
  }

  Map<String, dynamic> toJson() => {
    'type': 'random_forest', 'n_trees': nTrees,
    'max_depth': maxDepth, 'min_samples': minSamples,
    'trees': _trees.map((t) => {'nodes': t.toNodeList()}).toList(),
  };
}

// ---------------------------------------------------------------------------
// Session info
// ---------------------------------------------------------------------------

class _SessionInfo {
  const _SessionInfo({required this.file, required this.label,
      required this.dateStr, required this.sampleCount});
  final File file; final String label, dateStr; final int sampleCount;
}
