// lib/models_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'model_store.dart';

class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});
  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  List<File> _files = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    final files = await ModelStore.listModels();
    if (!mounted) return;
    setState(() {
      _files = files;
      _busy = false;
    });
  }

  String _fmtSize(int bytes) {
    const units = ["B", "KB", "MB", "GB"];
    double s = bytes.toDouble();
    int i = 0;
    while (s > 1024 && i < units.length - 1) {
      s /= 1024;
      i++;
    }
    return "${s.toStringAsFixed(s < 10 ? 2 : 1)} ${units[i]}";
    }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Trained Models"),
        actions: [
          IconButton(
            tooltip: "Refresh",
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? const Center(child: Text("No models saved yet. Train a model to see it here."))
              : ListView.separated(
                  itemCount: _files.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final f = _files[i];
                    final st = f.statSync();
                    final mtime = DateFormat("yyyy-MM-dd HH:mm").format(st.modified);
                    final size = _fmtSize(st.size);
                    final name = f.path.split(Platform.pathSeparator).last;
                    return ListTile(
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text("$mtime  •  $size"),
                      leading: const Icon(Icons.dataset),
                      trailing: Wrap(
                        spacing: 6,
                        children: [
                          IconButton(
                            tooltip: "Share / Export",
                            icon: const Icon(Icons.ios_share),
                            onPressed: () async {
                              await ModelStore.shareFile(f, text: "Trained model: $name");
                            },
                          ),
                          IconButton(
                            tooltip: "Delete",
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text("Delete this model?"),
                                  content: Text(name),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete")),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                await ModelStore.delete(f);
                                _refresh();
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
      floatingActionButton: _files.isEmpty
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.download),
              label: const Text("Copy last to Downloads"),
              onPressed: () async {
                final last = _files.first;
                final copied = await ModelStore.copyToDownloads(last);
                final snack = copied == null
                    ? const SnackBar(content: Text("Couldn’t copy. Use Share instead."))
                    : SnackBar(content: Text("Copied to Downloads: ${copied.path.split('/').last}"));
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(snack);
              },
            ),
    );
  }
}
