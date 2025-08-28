// lib/model_store.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ModelStore {
  /// Subfolder inside the app's Documents directory
  static const String _modelsFolder = "models";

  /// Returns the models directory, creating it if needed.
  static Future<Directory> _modelsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory("${docs.path}/$_modelsFolder");
    if (!(await dir.exists())) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Produce a timestamp like 082525 (MMDDYY), matching your example.
  static String _stamp([DateTime? dt]) =>
      DateFormat("MMddyy").format(dt ?? DateTime.now());

  /// Save a JSON-encodable payload as a .json file with nameBase_YYMMDD pattern.
  /// Returns the written file.
  static Future<File> saveJson(
    String nameBase,
    Map<String, dynamic> payload, {
    DateTime? now,
  }) async {
    final dir = await _modelsDir();
    final filename = "${_sanitize(nameBase)}_${_stamp(now)}.json";
    final file = File("${dir.path}/$filename");
    final data = const JsonEncoder.withIndent("  ").convert(payload);
    await file.writeAsString(data);
    return file;
  }

  /// Save raw bytes as .bin with timestamped filename.
  static Future<File> saveBytes(
    String nameBase,
    Uint8List bytes, {
    String ext = "bin",
    DateTime? now,
  }) async {
    final dir = await _modelsDir();
    final filename = "${_sanitize(nameBase)}_${_stamp(now)}.$ext";
    final file = File("${dir.path}/$filename");
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// List saved model files (json/bin) newest first.
  static Future<List<File>> listModels() async {
    final dir = await _modelsDir();
    if (!(await dir.exists())) return <File>[];
    final entries = await dir.list().toList();
    final files = entries.whereType<File>().where((f) {
      final n = f.path.toLowerCase();
      return n.endsWith(".json") || n.endsWith(".bin");
    }).toList();
    files.sort((a, b) {
      final at = a.statSync().modified;
      final bt = b.statSync().modified;
      return bt.compareTo(at);
    });
    return files;
  }

  /// Delete a saved model file.
  static Future<void> delete(File f) async {
    if (await f.exists()) {
      await f.delete();
    }
  }

  /// Share a saved model file via OS share sheet.
  static Future<void> shareFile(File f, {String? text}) async {
    if (!(await f.exists())) return;
    final x = XFile(f.path);
    await Share.shareXFiles([x], text: text ?? "Trained model: ${_basename(f)}");
  }

  /// Copy to a public Downloads folder (Android only best-effort).
  /// Returns the destination file if copy succeeded.
  static Future<File?> copyToDownloads(File f) async {
    try {
      if (!Platform.isAndroid) return null;
      // Best-effort path; may need MANAGE_EXTERNAL_STORAGE / SAF for Android 11+.
      final dl = Directory("/storage/emulated/0/Download");
      if (!(await dl.exists())) return null;
      final dest = File("${dl.path}/${_basename(f)}");
      await f.copy(dest.path);
      return dest;
    } catch (_) {
      return null;
    }
  }

  // ---------- helpers ----------

  static String _basename(File f) => f.path.split(Platform.pathSeparator).last;

  static String _sanitize(String s) {
    final cleaned = s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), "_");
    return cleaned.replaceAll(RegExp(r'[^a-z0-9_\-]'), "");
  }
}
