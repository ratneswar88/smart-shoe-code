import 'dart:math';
import '../ble.dart';

class WindowedBuffer {
  final int windowMs;
  final double overlap;
  final List<ShoeSample> _buf = [];
  WindowedBuffer({this.windowMs = 2000, this.overlap = 0.5});

  void add(ShoeSample s) => _buf.add(s);

  /// Return one ready window (if available) and advance by hop = window*(1-overlap).
  List<List<ShoeSample>> takeWindows() {
    if (_buf.isEmpty) return [];
    final t0 = _buf.first.t;
    int? end;
    for (int i = 0; i < _buf.length; i++) {
      if (_buf[i].t.difference(t0).inMilliseconds >= windowMs) {
        end = i;
        break;
      }
    }
    if (end == null) return [];
    final win = _buf.sublist(0, end);
    final hop = max(1, (end * (1.0 - overlap)).floor());
    _buf.removeRange(0, hop);
    return [win];
  }
}

class FeatureVector {
  final List<double> x;
  final Map<String, double> extras;
  FeatureVector(this.x, this.extras);
}

class FeatureExtractor {
  /// Compute mean/var/RMS/energy for channels:
  /// roll, pitch, yaw, cadence, strideM, dH, temp (if present)
  static FeatureVector fromWindow(List<ShoeSample> w) {
    // Collects a numeric series from samples, skipping nulls/NaNs.
    List<double> arr(double? Function(ShoeSample) sel) {
      final out = <double>[];
      for (final s in w) {
        final v = sel(s);
        if (v != null && v.isFinite) out.add(v);
      }
      return out;
    }

    double mean(List<double> a) =>
        a.isEmpty ? 0.0 : a.reduce((p, c) => p + c) / a.length;

    double var_(List<double> a) {
      if (a.length < 2) return 0.0;
      final m = mean(a);
      double s = 0.0;
      for (final v in a) {
        final d = v - m;
        s += d * d;
      }
      return s / (a.length - 1);
    }

    double rms(List<double> a) {
      if (a.isEmpty) return 0.0;
      double s = 0.0;
      for (final v in a) {
        s += v * v;
      }
      return sqrt(s / a.length);
    }

    double energy(List<double> a) {
      double s = 0.0;
      for (final v in a) {
        s += v * v;
      }
      return s;
    }

    final r  = arr((s) => s.roll);
    final p  = arr((s) => s.pitch);
    final y  = arr((s) => s.yaw);
    final c  = arr((s) => s.cadence);
    final st = arr((s) => s.strideM);
    final dh = arr((s) => s.dH);
    final tc = arr((s) => s.tempC); // may be empty if device doesn't send temp

    final feats = <double>[];
    void addAllFor(List<double> a) {
      feats.addAll([mean(a), var_(a), rms(a), energy(a)]);
    }

    addAllFor(r);
    addAllFor(p);
    addAllFor(y);
    addAllFor(c);
    addAllFor(st);
    addAllFor(dh);
    if (tc.isNotEmpty) {
      addAllFor(tc);
    } else {
      feats.addAll([0, 0, 0, 0]); // placeholder for temp features
    }

    final extras = <String, double>{
      'len': w.length.toDouble(),
      'steps_end': w.isNotEmpty ? w.last.steps.toDouble() : 0.0,
      'temp_last': (tc.isNotEmpty ? tc.last : double.nan),
    };

    return FeatureVector(feats, extras);
  }
}
