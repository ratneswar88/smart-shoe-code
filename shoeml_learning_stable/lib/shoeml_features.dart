// lib/shoeml_features.dart
import 'dart:math' as math;

class RawSampleLite {
  RawSampleLite({
    required this.roll,
    required this.pitch,
    required this.yaw,
    this.cadence,
    this.strideM,
    this.tempC,
  });

  final double? roll;
  final double? pitch;
  final double? yaw;
  final double? cadence;
  final double? strideM;
  final double? tempC;
}

List<double> shoemlFeatures(List<RawSampleLite> w) {
  List<double> col(Iterable<double?> v) {
    final r = v.whereType<double>().toList();
    return r.isEmpty ? [0] : r;
  }

  final roll = col(w.map((e) => e.roll));
  final pitch = col(w.map((e) => e.pitch));
  final yaw = col(w.map((e) => e.yaw));
  final cadence = col(w.map((e) => e.cadence));
  final stride = col(w.map((e) => e.strideM));
  final temp = col(w.map((e) => e.tempC));

  List<double> stats(List<double> x) {
    final n = x.length;
    final mean = x.reduce((a, b) => a + b) / n;
    final varr =
        x.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / n;
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
