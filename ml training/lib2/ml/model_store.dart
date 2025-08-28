import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

class SavedModelMeta {
  final String id; // filename
  final DateTime createdAt;
  final List<String> labels;
  final int nIn;
  final String kind; // 'softmax' or 'multilabel'
  final String quant; // 'fp32' | 'fp16' | 'int8' (metadata only)
  final Map<String, dynamic> metrics;
  SavedModelMeta(this.id, this.createdAt, this.labels, this.nIn, this.kind, this.quant, this.metrics);
}

class ModelStore {
  static Future<Directory> _appDir() async => await getApplicationDocumentsDirectory();

  static Future<Directory> modelsDir() async {
    final d = Directory('${(await _appDir()).path}/models');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<Directory> datasetsDir() async {
    final d = Directory('${(await _appDir()).path}/datasets');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<String> saveCsv(String baseName, String csv) async {
    final ts = DateFormat('MMddyy_HHmmss').format(DateTime.now());
    final f = File('${(await datasetsDir()).path}/${baseName}_$ts.csv');
    await f.writeAsString(csv);
    return f.path;
    // Android users can later copy from this app folder with a file manager.
  }

  static Future<String> saveModelJson({
    required String baseName,
    required Map<String, dynamic> payload,
  }) async {
    final ts = DateFormat('MMddyy_HHmmss').format(DateTime.now());
    final f = File('${(await modelsDir()).path}/${baseName}_$ts.json');
    await f.writeAsString(jsonEncode(payload));
    return f.path;
  }

  static Future<List<SavedModelMeta>> listModels() async {
    final d = await modelsDir();
    final out = <SavedModelMeta>[];
    await for (final e in d.list()) {
      if (e is File && e.path.endsWith('.json')) {
        try {
          final j = jsonDecode(await e.readAsString());
          out.add(SavedModelMeta(
            e.uri.pathSegments.last,
            DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
            (j['labels'] as List).map((x)=>x.toString()).toList(),
            (j['nIn'] as num).toInt(),
            j['kind'] ?? 'softmax',
            j['quant'] ?? 'fp32',
            (j['metrics'] as Map?)?.cast<String,dynamic>() ?? {},
          ));
        } catch (_) {}
      }
    }
    out.sort((a,b)=>b.createdAt.compareTo(a.createdAt));
    return out;
  }

  static Future<Map<String, dynamic>?> loadModelJson(String filename) async {
    final f = File('${(await modelsDir()).path}/$filename');
    if (!await f.exists()) return null;
    return jsonDecode(await f.readAsString());
  }

  static Future<void> deleteModel(String filename) async {
    final f = File('${(await modelsDir()).path}/$filename');
    if (await f.exists()) await f.delete();
  }
}
