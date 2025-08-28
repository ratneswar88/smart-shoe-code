import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

/// Very small trainer and data manager.
/// - Collects feature vectors while "collecting" is true
/// - On stop, marks datasetReady
/// - Train & Save writes a simple JSON model file under Documents/models/
class TrainerController with ChangeNotifier {
  final List<List<double>> _samples = [];
  final List<int> _labels = [];

  bool _collecting = false;
  bool _training = false;
  bool _datasetReady = false;

  String? currentLabel; // e.g., "walking"
  int minSamplesPerClass = 40;

  bool get collecting => _collecting;
  bool get training => _training;
  bool get datasetReady => _datasetReady;
  int get sampleCount => _samples.length;
  Set<int> get classesPresent => _labels.toSet();

  /// Call this from your BLE loop when collecting.
  void addSample(List<double> x, {required int label}) {
    if (!_collecting) return;
    _samples.add(x);
    _labels.add(label);
  }

  void startCollection({required String labelName, required int labelId}) {
    currentLabel = labelName;
    _collecting = true;
    _datasetReady = false;
    notifyListeners();
  }

  void stopCollection() {
    _collecting = false;
    _datasetReady = _samples.isNotEmpty;
    notifyListeners();
  }

  void clearAll() {
    _samples.clear();
    _labels.clear();
    _datasetReady = false;
    notifyListeners();
  }

  bool get canTrain {
    if (_collecting || _training || !_datasetReady) return false;
    if (_samples.isEmpty) return false;
    final counts = <int, int>{};
    for (final y in _labels) {
      counts[y] = (counts[y] ?? 0) + 1;
    }
    return counts.values.any((c) => c >= minSamplesPerClass);
  }

  /// Tiny “training”: compute per-feature mean and std as a baseline model.
  /// Replace with a real classifier if needed; save format stays JSON.
  Future<String> trainAndSave({String? customName}) async {
    if (!canTrain) return "Not enough data to train.";
    _training = true;
    notifyListeners();

    try {
      final featureCount = _samples.first.length;

      // Compute means and stds across the dataset
      final means = List<double>.filled(featureCount, 0);
      for (final x in _samples) {
        for (var i = 0; i < featureCount; i++) {
          means[i] += x[i];
        }
      }
      for (var i = 0; i < featureCount; i++) {
        means[i] /= _samples.length;
      }

      final stds = List<double>.filled(featureCount, 0);
      for (final x in _samples) {
        for (var i = 0; i < featureCount; i++) {
          final d = x[i] - means[i];
          stds[i] += d * d;
        }
      }
      for (var i = 0; i < featureCount; i++) {
        stds[i] = (stds[i] / _samples.length).clamp(1e-9, double.infinity).toDouble();
        stds[i] = stds[i] > 0 ? stds[i].sqrt() : 1e-9;
      }

      final model = <String, dynamic>{
        "type": "baseline_mean_std",
        "featureCount": featureCount,
        "means": means,
        "stds": stds,
        "labelHint": currentLabel ?? "session",
        "createdAt": DateTime.now().toIso8601String(),
      };

      final ts = DateFormat('MMddyy_HHmm').format(DateTime.now());
      final safeLabel = (customName ?? currentLabel ?? "session")
          .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final fileName = "${safeLabel}_$ts.json";

      final docs = await getApplicationDocumentsDirectory();
      final modelsDir = Directory("${docs.path}/models");
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }
      final f = File("${modelsDir.path}/$fileName");
      await f.writeAsString(jsonEncode(model));

      _training = false;
      notifyListeners();
      return "Saved model: ${f.path}";
    } catch (e) {
      _training = false;
      notifyListeners();
      return "Training failed: $e";
    }
  }
}

extension on double {
  double sqrt() => mathSqrt(this);
}

// local sqrt without importing dart:math everywhere
double mathSqrt(double x) {
  // Newton’s method (enough for stats)
  if (x <= 0) return 0;
  double r = x;
  for (int i = 0; i < 8; i++) {
    r = 0.5 * (r + x / r);
  }
  return r;
}
