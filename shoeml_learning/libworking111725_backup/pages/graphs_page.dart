import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../ble.dart';

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
  // CRITICAL: Validate before adding to chart
  if (v.isNaN || v.isInfinite || t.isNaN || t.isInfinite) return;
  if (v.abs() > 1e10 || t.abs() > 1e10) return;
  
  s.add(FlSpot(t, v));
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
  // Filter out any invalid points before rendering
  final validPts = pts.where((p) => 
    !p.x.isNaN && !p.x.isInfinite && 
    !p.y.isNaN && !p.y.isInfinite
  ).toList();
  
  return Card(
    color: cs.surfaceContainerHigh,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: validPts.isEmpty
                ? Center(
                    child: Text('No data',
                        style: TextStyle(color: Colors.grey[600])))
                : LineChart(
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
                          spots: validPts,
                          isCurved: true,
                          barWidth: 2,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}
}
