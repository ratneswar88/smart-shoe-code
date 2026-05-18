import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../ble.dart';

// Graphs page — displays live roll/pitch/yaw, temperature, and real gait
// phase from the firmware's phase characteristic (0=STANCE, 1=SWING).
// Phase replaces the previous cadence-based approximation.

class GraphsPage extends StatefulWidget {
  const GraphsPage({super.key, required this.ble});
  final ShoeBle ble;

  @override
  State<GraphsPage> createState() => _GraphsPageState();
}

class _GraphsPageState extends State<GraphsPage> {
  // Chart data series
  final List<FlSpot> _r = [], _p = [], _y = [];
  final List<FlSpot> _temp  = [];
  final List<FlSpot> _phase = [];   // 0.0 = STANCE, 1.0 = SWING

  // Shared X-axis time counter.
  // Only the roll listener advances _t so all orientation series share the
  // same X coordinate.  Temperature and phase use wall-clock elapsed time.
  double    _t  = 0;
  DateTime? _t0;

  // Cached latest pitch/yaw — pushed alongside roll in the roll listener.
  double _latestPitch = 0;
  double _latestYaw   = 0;

  StreamSubscription? _sr, _sp, _sy;
  StreamSubscription<double?>? _sTemp;
  StreamSubscription<int>?     _sPhase;

  static const int _keep = 300;  // max data points kept per series

  void _push(List<FlSpot> s, double t, double v) {
    if (v.isNaN || v.isInfinite || t.isNaN || t.isInfinite) return;
    s.add(FlSpot(t, v));
    if (s.length > _keep) s.removeAt(0);
  }

  @override
  void initState() {
    super.initState();
    _t0 = DateTime.now();

    // Roll is the write clock for orientation charts.
    _sr = widget.ble.roll$.listen((v) {
      if (v.isNaN || v.isInfinite) return;
      setState(() {
        _t += 0.1;
        _push(_r, _t, v);
        _push(_p, _t, _latestPitch);
        _push(_y, _t, _latestYaw);
      });
    });

    // Pitch and yaw just cache; chart points written on next roll event.
    _sp = widget.ble.pitch$.listen((v) { if (!v.isNaN) _latestPitch = v; });
    _sy = widget.ble.yaw$.listen((v)   { if (!v.isNaN) _latestYaw   = v; });

    // Temperature uses wall-clock elapsed time (arrives at ~10 Hz but
    // independently of roll).
    _sTemp = widget.ble.temp$.listen((v) {
      if (v == null || v.isNaN || v.isInfinite) return;
      final elapsed =
          DateTime.now().difference(_t0!).inMilliseconds / 1000.0;
      // Convert °C from firmware to °F for display
      final vF = v * 9 / 5 + 32;
      setState(() => _push(_temp, elapsed, vF));
    });

    // Real gait phase from firmware (0=STANCE, 1=SWING).
    // Arrives at ~10 Hz on state transitions.
    _sPhase = widget.ble.phase$.listen((v) {
      final elapsed =
          DateTime.now().difference(_t0!).inMilliseconds / 1000.0;
      setState(() => _push(_phase, elapsed, v.toDouble()));
    });
  }

  @override
  void dispose() {
    for (final s in [_sr, _sp, _sy, _sTemp, _sPhase]) s?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(children: [
        _lineCard(cs, 'Roll (°)', _r),
        _lineCard(cs, 'Pitch (°)', _p),
        _lineCard(cs, 'Yaw (°)', _y),
        _lineCard(cs, 'Temperature (°F)', _temp),
        _phaseCard(cs),
      ]),
    );
  }

  Widget _lineCard(ColorScheme cs, String title, List<FlSpot> pts,
      {double? minY, double? maxY}) {
    final valid = pts
        .where((p) =>
            !p.x.isNaN && !p.x.isInfinite &&
            !p.y.isNaN && !p.y.isInfinite)
        .toList();
    final cur = valid.isEmpty ? null : valid.last.y;

    return Card(
      color: cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (cur != null)
                Text('Now: ${cur.toStringAsFixed(1)}',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withOpacity(0.7))),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: valid.isEmpty
                  ? Center(
                      child: Text('No data yet',
                          style: TextStyle(color: Colors.grey[600])))
                  : LineChart(LineChartData(
                      minY: minY,
                      maxY: maxY,
                      gridData: const FlGridData(show: true),
                      titlesData: const FlTitlesData(
                        leftTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: true,
                                reservedSize: 36)),
                        bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: true),
                      lineBarsData: [
                        LineChartBarData(
                          spots: valid,
                          isCurved: true,
                          barWidth: 2,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          color: cs.primary,
                        ),
                      ],
                    )),
            ),
          ],
        ),
      ),
    );
  }

  // Phase chart — step plot between 0 (STANCE) and 1 (SWING).
  // Uses minY/maxY -0.1/1.1 so the line isn't clipped at the border.
  Widget _phaseCard(ColorScheme cs) {
    final valid = _phase
        .where((p) =>
            !p.x.isNaN && !p.x.isInfinite &&
            !p.y.isNaN && !p.y.isInfinite)
        .toList();

    final currentPhase = valid.isEmpty
        ? null
        : valid.last.y == 1.0 ? 'SWING' : 'STANCE';

    return Card(
      color: cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('Gait phase (firmware)',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (currentPhase != null)
                Chip(
                  label: Text(currentPhase,
                      style: const TextStyle(fontSize: 12)),
                  backgroundColor: currentPhase == 'SWING'
                      ? cs.primaryContainer
                      : cs.secondaryContainer,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
            ]),
            const SizedBox(height: 4),
            Text('0 = STANCE  ·  1 = SWING  ·  direct from shoe firmware',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: valid.isEmpty
                  ? Center(
                      child: Text(
                        'Waiting for phase data…\n'
                        '(requires updated firmware with UUID c005)',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600],
                            fontSize: 12),
                      ))
                  : LineChart(LineChartData(
                      minY: -0.1,
                      maxY:  1.1,
                      gridData: FlGridData(
                        show: true,
                        getDrawingHorizontalLine: (v) => FlLine(
                          color: cs.outline.withOpacity(0.3),
                          strokeWidth: 1,
                        ),
                        horizontalInterval: 1,
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36,
                            getTitlesWidget: (v, _) {
                              if (v == 0) return const Text('ST', style: TextStyle(fontSize: 10));
                              if (v == 1) return const Text('SW', style: TextStyle(fontSize: 10));
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                        bottomTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: true),
                      lineBarsData: [
                        LineChartBarData(
                          spots: valid,
                          isCurved: false,   // step-like transitions
                          barWidth: 2,
                          isStrokeCapRound: false,
                          dotData: const FlDotData(show: false),
                          color: cs.tertiary,
                        ),
                      ],
                    )),
            ),
          ],
        ),
      ),
    );
  }
}