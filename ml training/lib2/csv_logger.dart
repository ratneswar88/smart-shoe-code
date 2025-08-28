import 'dart:async';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'ml_train.dart';

class CsvLogger {
  IOSink? _sink;
  Timer? _timer;
  String? filePath;

  bool get isLogging => _sink != null;

  Future<void> start() async {
    if (_sink != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final f = File('${dir.path}/shoeml_stream_$ts.csv');
    filePath = f.path;
    _sink = f.openWrite(mode: FileMode.writeOnlyAppend);
    _sink!.writeln('time,roll,pitch,yaw,cadence,strideM,deltaH,label');
    _timer = Timer.periodic(const Duration(seconds: 2), (_){ _sink?.flush(); });
  }

  void logSample(Sample s, String label){
    if (_sink == null) return;
    final t = s.t.toStringAsFixed(3);
    _sink!.writeln('$t,${s.roll.toStringAsFixed(3)},${s.pitch.toStringAsFixed(3)},${s.yaw.toStringAsFixed(3)},${s.cadence.toStringAsFixed(2)},${s.strideM.toStringAsFixed(3)},${s.dH.toStringAsFixed(3)},$label');
  }

  Future<void> stop() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    _timer?.cancel();
    _timer = null;
  }
}
