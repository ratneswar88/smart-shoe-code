import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'models.dart';

Future<Directory> appDocsDir() => getApplicationDocumentsDirectory();

Future<Directory> recordsDir() async {
  final dir = await appDocsDir();
  final rec = Directory('${dir.path}/records');
  if (!await rec.exists()) await rec.create(recursive: true);
  return rec;
}

Future<Directory> modelsDir() async {
  final dir = await appDocsDir();
  final md = Directory('${dir.path}/models');
  if (!await md.exists()) await md.create(recursive: true);
  return md;
}

String tsFile() => DateFormat('MMddyy_HHmmss').format(DateTime.now());

Future<File> saveCsv(String label, List<ShoeSample> samples) async {
  final rec = await recordsDir();
  final file = File('${rec.path}/${label}_${tsFile()}.csv');
  final sink = file.openWrite();
  sink.writeln("time,steps,cadence,roll,pitch,yaw,tempC,strideM,deltaH,label");
  for (final s in samples) {
    final time = DateFormat("HH:mm:ss.SSS").format(s.t);
    final temp = (s.tempC?.isFinite == true) ? s.tempC!.toStringAsFixed(2) : "";
    sink.writeln([
      time,
      s.steps,
      s.cadence.toStringAsFixed(2),
      s.roll.toStringAsFixed(2),
      s.pitch.toStringAsFixed(2),
      s.yaw.toStringAsFixed(2),
      temp,
      s.strideM.toStringAsFixed(3),
      s.dH.toStringAsFixed(3),
      label,
    ].join(","));
  }
  await sink.flush();
  await sink.close();
  return file;
}
