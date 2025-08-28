import 'package:flutter/material.dart';

class ShoeSample {
  final DateTime t;
  final int steps;
  final double cadence;
  final double roll;
  final double pitch;
  final double yaw;
  final double? tempC;
  final double strideM;
  final double dH;
  ShoeSample({
    required this.t,
    required this.steps,
    required this.cadence,
    required this.roll,
    required this.pitch,
    required this.yaw,
    required this.tempC,
    required this.strideM,
    required this.dH,
  });
}

class ModelMeta {
  final String name;
  final DateTime savedAt;
  final List<String> labels;
  final int inputLen;
  final Map<String, dynamic> metrics; // accuracy, f1, etc
  final String path; // folder path
  ModelMeta({
    required this.name,
    required this.savedAt,
    required this.labels,
    required this.inputLen,
    required this.metrics,
    required this.path,
  });
}

class LabelSet {
  static const presets = <String>[
    "walking","running","stairs_up","stairs_down","standing"
  ];
}
