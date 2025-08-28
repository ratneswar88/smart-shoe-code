import 'dart:async';
import 'dart:math';
import 'package:app_settings/app_settings.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ble.dart';
import 'ml/features.dart';
import 'ml/classifier.dart';
import 'ml/model_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShoeMLApp());
}

class ShoeMLApp extends StatefulWidget {
  const ShoeMLApp({super.key});
  @override
  State<ShoeMLApp> createState() => _ShoeMLAppState();
}

class _ShoeMLAppState extends State<ShoeMLApp> {
  ThemeMode _mode = ThemeMode.light;
  void _toggle() => setState(()=>_mode = _mode==ThemeMode.light?ThemeMode.dark:ThemeMode.light);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartShoe ML Trainer',
      themeMode: _mode,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal), useMaterial3: true),
      darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark), useMaterial3: true),
      home: HomePage(onToggleTheme: _toggle),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onToggleTheme});
  final VoidCallback onToggleTheme;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ShoeBle _ble = ShoeBle();
  final _status = ValueNotifier<String>('Idle');
  final _bleStatus = ValueNotifier<BleStatus>(BleStatus.unknown);

  // live chart data
  static const int maxPts = 300;
  final List<FlSpot> _roll = [], _pitch = [], _yaw = [];
  double _t=0;

  // training/inference state
  final labels = <String>['walking','running','stairs_up','stairs_down','standing'];
  String curLabel = 'walking';
  final WindowedBuffer _winBuf = WindowedBuffer(windowMs: 2000, overlap: 0.5);
  final _collected = <String, List<FeatureVector>>{};
  bool collecting=false;
  bool training=false;
  String quant = 'fp32'; // metadata only

  // active model
  SoftmaxClassifier? _clf;
  List<String> _clfLabels = [];
  String? _activeModelFile;

  // anomalies
  final _cadHistory = <double>[];
  String _anomalyNote = '';

  int _tab=0;

  @override
  void initState() {
    super.initState();
    _listenBleStatus();
    _ble.samples.listen((s){
      _t += 0.1;
      void push(List<FlSpot> a,double v){ if (v.isFinite) { a.add(FlSpot(_t,v)); if (a.length>maxPts) a.removeAt(0); } }
      push(_roll, s.roll); push(_pitch, s.pitch); push(_yaw,s.yaw);

      // accumulate windows for training capture
      _winBuf.add(s);

      // simple anomaly on cadence z-score
      _cadHistory.add(s.cadence.isFinite? s.cadence : 0);
      if (_cadHistory.length>200) _cadHistory.removeAt(0);
      final m=_cadHistory.average; final sd=_std(_cadHistory);
      if (sd>0 && (s.cadence-m).abs()>3*sd) {
        _anomalyNote = 'Cadence anomaly!';
      } else if (_anomalyNote.isNotEmpty) {
        _anomalyNote='';
      }
      setState((){});
    });
  }

  double _std(List<double> a) {
    if (a.length<2) return 0;
    final m=a.average; double s=0; for(final v in a){final d=v-m; s+=d*d;} return sqrt(s/(a.length-1));
  }

  void _listenBleStatus() {
    _bleStatus.value = FlutterReactiveBle().status;
    FlutterReactiveBle().statusStream.listen((s){
      _bleStatus.value = s;
      if (s==BleStatus.poweredOff) _status.value = "Bluetooth is off — please enable it.";
    });
  }

  @override
  void dispose() {
    _ble.dispose();
    super.dispose();
  }

  // ---------- actions ----------
  Future<void> _ensurePerms() async {
    final req = await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.locationWhenInUse].request();
    if (req.values.any((s)=>s.isDenied || s.isPermanentlyDenied)) {
      _status.value = 'Permissions missing';
    }
  }

  Future<void> _scanConnect() async {
    await _ensurePerms();
    if (_bleStatus.value == BleStatus.poweredOff) {
      _status.value = 'Bluetooth is off — please enable it.'; return;
    }
    _status.value = 'Scanning…';
    try {
      await _ble.scanAndConnect();
      _status.value = 'Connected';
      setState((){});
    } catch (_) {
      _status.value = 'Scan/connect failed';
    }
  }

  Future<void> _disconnect() async {
    await _ble.disconnect();
    _status.value = 'Disconnected';
    setState((){});
  }

  // -------- training capture --------
  void _toggleCollect() {
    collecting = !collecting;
    setState((){});
    if (collecting) {
      _status.value = 'Collecting "$curLabel"…';
      _pumpCollect();
    } else {
      _status.value = 'Stopped collecting';
    }
  }

  void _pumpCollect() async {
    if (!collecting) return;
    final wins = _winBuf.takeWindows();
    if (wins.isNotEmpty) {
      final feats = wins.map(FeatureExtractor.fromWindow).toList();
      _collected.putIfAbsent(curLabel, ()=>[]);
      _collected[curLabel]!.addAll(feats);
      setState((){});
    }
    Future.delayed(const Duration(milliseconds: 200), _pumpCollect);
  }

  Future<void> _saveCsvSession() async {
    // save last 2 minutes of raw samples? We only kept features; so save per-label features as CSV
    final ts = DateFormat('MMddyy_HHmmss').format(DateTime.now());
    final name = '${curLabel}_$ts';
    final buf = StringBuffer();
    buf.writeln('label,' + List.generate(_collected.values.expand((e)=>e).firstOrNull?.x.length ?? 0, (i)=>'f$i').join(',') + ',len,steps_end,temp_last');
    _collected.forEach((lab, arr){
      for(final fv in arr){
        buf.writeln([
          lab,
          ...fv.x.map((v)=>v.toStringAsFixed(6)),
          fv.extras['len']?.toStringAsFixed(0) ?? '0',
          fv.extras['steps_end']?.toStringAsFixed(0) ?? '0',
          (fv.extras['temp_last']?.isFinite==true) ? (fv.extras['temp_last']!.toStringAsFixed(2)) : ''
        ].join(','));
      }
    });
    final path = await ModelStore.saveCsv(name, buf.toString());
    _status.value = 'Saved dataset CSV: $path';
  }

  Future<void> _trainAndSave() async {
    if (_collected.isEmpty) { _status.value='Nothing collected'; return; }
    training = true; setState((){});
    final allLabels = _collected.keys.toList()..sort();
    final X = <List<double>>[]; final y = <int>[];
    for (int k=0;k<allLabels.length;k++) {
      for (final fv in _collected[allLabels[k]]!) {
        X.add(fv.x); y.add(k);
      }
    }
    // shuffle
    final idx = List.generate(X.length, (i)=>i)..shuffle(Random(1));
    final Xs = [for(final i in idx) X[i]];
    final ys = [for(final i in idx) y[i]];

    // split train/val 80/20
    final nTr = (Xs.length*0.8).floor();
    final Xtr = Xs.sublist(0,nTr), ytr = ys.sublist(0,nTr);
    final Xval= Xs.sublist(nTr),   yval= ys.sublist(nTr);

    final clf = SoftmaxClassifier();
    clf.init(nIn: Xtr.first.length, labels: allLabels);
    clf.fit(Xtr, ytr, epochs: 35, lr: 0.05, l2: 1e-4, batch: 64);

    // metrics
    int correct=0;
    final cm = List.generate(allLabels.length, (_)=>List.filled(allLabels.length,0));
    for (int i=0;i<Xval.length;i++) {
      final pred = clf.predict(Xval[i]);
      cm[yval[i]][pred] += 1;
      if (pred==yval[i]) correct++;
    }
    final acc = Xval.isEmpty ? 1.0 : correct/Xval.length;

    final payload = {
      'createdAt': DateTime.now().toIso8601String(),
      'kind': 'softmax',
      'quant': quant,
      'labels': allLabels,
      'nIn': Xtr.first.length,
      'W': clf.W,
      'b': clf.b,
      'metrics': {'acc': acc, 'cm': cm},
      'windowMs': _winBuf.windowMs,
      'overlap': _winBuf.overlap,
      'features': 'mean,var,rms,energy x channels (roll,pitch,yaw,cad,stride,dH,temp)',
    };
    final path = await ModelStore.saveModelJson(baseName: 'model', payload: payload);
    _clf = clf; _clfLabels = allLabels; _activeModelFile = path.split('/').last;
    training = false; setState((){});
    _status.value = 'Trained acc=${acc.toStringAsFixed(2)}  Saved: $path';
  }

  Future<void> _loadLatestModel() async {
    final list = await ModelStore.listModels();
    if (list.isEmpty) { _status.value='No models'; return; }
    final m = list.first;
    final j = await ModelStore.loadModelJson(m.id);
    if (j==null) return;
    final clf = SoftmaxClassifier();
    clf.nIn = (j['nIn'] as num).toInt();
    clf.nClasses = (j['labels'] as List).length;
    clf.W = (j['W'] as List).map((e)=> (e as num).toDouble()).toList();
    clf.b = (j['b'] as List).map((e)=> (e as num).toDouble()).toList();
    _clf = clf; _clfLabels = (j['labels'] as List).map((e)=>e.toString()).toList();
    _activeModelFile = m.id;
    setState((){});
    _status.value = 'Loaded model: ${m.id}';
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pages = [
      _dashboard(cs),
      _graphs(cs),
      _trainTab(cs),
      _modelsTab(),
      _inferenceTab(cs),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartShoe ML Trainer'),
        actions: [
          IconButton(icon: const Icon(Icons.color_lens_outlined), onPressed: widget.onToggleTheme),
        ],
      ),
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i)=>setState(()=>_tab=i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.show_chart_outlined), label: 'Graphs'),
          NavigationDestination(icon: Icon(Icons.school_outlined), label: 'Train'),
          NavigationDestination(icon: Icon(Icons.storage_outlined), label: 'Models'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), label: 'Inference'),
        ],
      ),
    );
  }

  Widget _dashboard(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          ValueListenableBuilder(
            valueListenable: _status, builder: (_,v,__)=>
              Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600)))),
          ),
          const SizedBox(height: 8),
          Wrap(spacing:8, runSpacing:8, children: [
            ElevatedButton.icon(onPressed: _ble.connected? null : _scanConnect, icon: const Icon(Icons.bluetooth_searching), label: const Text('Scan & Connect')),
            ElevatedButton.icon(onPressed: _ble.connected? _disconnect : null, icon: const Icon(Icons.link_off), label: const Text('Disconnect')),
            ElevatedButton.icon(onPressed: ()=>AppSettings.openAppSettings(type: AppSettingsType.bluetooth), icon: const Icon(Icons.settings), label: const Text('Open Bluetooth')),
            ElevatedButton.icon(onPressed: ()=>_ble.sendCommand('notify_hz=10'), icon: const Icon(Icons.speed), label: const Text('Notify 10 Hz')),
            ElevatedButton.icon(onPressed: ()=>_ble.sendCommand('reset'), icon: const Icon(Icons.restart_alt), label: const Text('Reset Steps')),
          ]),
          const SizedBox(height: 12),
          _metricsGrid(cs),
        ],
      ),
    );
  }

  Widget _metricsGrid(ColorScheme cs) {
    Widget tile(Color bg, String title, String value, IconData icon) {
      return Container(
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(icon, size: 28, color: Colors.black.withOpacity(0.7)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(value, style: const TextStyle(fontSize: 16)),
          ])),
        ]),
      );
    }

    final tiles = [
      tile(cs.primaryContainer, "Steps", "${_ble.steps}", Icons.directions_walk),
      tile(cs.tertiaryContainer, "Cadence", "${_ble.cadence.toStringAsFixed(1)} spm", Icons.speed),
      tile(cs.secondaryContainer, "Stride", "${_ble.strideM.toStringAsFixed(3)} m", Icons.straighten),
      tile(cs.primaryContainer, "Δh", "${_ble.dH.toStringAsFixed(3)} m", Icons.landscape),
      tile(cs.secondaryContainer, "Ambient Temp (BLE)", (_ble.tempC?.isFinite==true) ? "${_ble.tempC!.toStringAsFixed(2)} °C" : "—", Icons.thermostat),
      tile(cs.primaryContainer, "R/P/Y", "${_ble.roll.toStringAsFixed(1)}/${_ble.pitch.toStringAsFixed(1)}/${_ble.yaw.toStringAsFixed(1)}°", Icons.rotate_90_degrees_cw),
    ];

    return GridView.count(
      crossAxisCount: 2, childAspectRatio: 2.6, shrinkWrap: true, crossAxisSpacing: 8, mainAxisSpacing: 8,
      physics: const NeverScrollableScrollPhysics(),
      children: tiles,
    );
  }

  Widget _graphs(ColorScheme cs) {
    Widget card(String title, List<FlSpot> pts) => Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height:8),
          SizedBox(
            height: 220,
            child: LineChart(LineChartData(
              backgroundColor: Colors.transparent,
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(show:true),
              borderData: FlBorderData(show:true),
              lineBarsData: [
                LineChartBarData(isCurved:true, spots: pts, dotData: FlDotData(show:false), barWidth: 2),
              ],
            )),
          ),
        ]),
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(children: [
        card("Roll (°)", _roll),
        const SizedBox(height: 12),
        card("Pitch (°)", _pitch),
        const SizedBox(height: 12),
        card("Yaw (°)", _yaw),
        if (_anomalyNote.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top:8), child: Text(_anomalyNote, style: TextStyle(color: Theme.of(context).colorScheme.error)))
      ]),
    );
  }

  Widget _trainTab(ColorScheme cs) {
    final countByLabel = { for (final L in labels) L : (_collected[L]?.length ?? 0) };
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final L in labels)
            ChoiceChip(label: Text(L), selected: curLabel==L, onSelected: (_){ setState(()=>curLabel=L); }),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          ElevatedButton.icon(onPressed: _toggleCollect, icon: Icon(collecting? Icons.stop:Icons.fiber_manual_record),
              label: Text(collecting? 'Stop collecting' : 'Collect "$curLabel"')),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: _saveCsvSession, icon: const Icon(Icons.save_alt), label: const Text('Save dataset CSV')),
        ]),
        const SizedBox(height: 8),
        DropdownButton<String>(
          value: quant,
          items: const [
            DropdownMenuItem(value:'fp32', child: Text('Quant: FP32')),
            DropdownMenuItem(value:'fp16', child: Text('Quant: FP16 (est.)')),
            DropdownMenuItem(value:'int8', child: Text('Quant: int8 (est.)')),
          ],
          onChanged: (v){ setState(()=>quant=v??'fp32'); },
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: training? null : _trainAndSave,
          icon: const Icon(Icons.school),
          label: Text(training? 'Training…' : 'Train & Save model'),
        ),
        const SizedBox(height: 12),
        Card(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Collected windows per label', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in countByLabel.entries)
                Chip(label: Text('${e.key}: ${e.value}')),
            ]),
            const SizedBox(height: 8),
            const Text('Windows: 2.0 s, 50% overlap. Features: mean/var/RMS/energy for roll,pitch,yaw,cad,stride,Δh,temp.'),
          ]),
        )),
      ]),
    );
  }

  Widget _modelsTab() {
    return FutureBuilder(
      future: ModelStore.listModels(),
      builder: (_, snap) {
        final list = snap.data ?? [];
        return Padding(
          padding: const EdgeInsets.all(12),
          child: ListView(children: [
            Row(children: [
              ElevatedButton.icon(onPressed: _loadLatestModel, icon: const Icon(Icons.download), label: const Text('Load latest')),
              const SizedBox(width: 8),
              if (_activeModelFile!=null) Chip(label: Text('Active: $_activeModelFile')),
            ]),
            const SizedBox(height: 8),
            for (final m in list)
              Card(child: ListTile(
                title: Text(m.id),
                subtitle: Text('labels=${m.labels.join(", ")}  acc=${(m.metrics['acc']??'—').toString()}'),
                trailing: Wrap(spacing: 6, children: [
                  IconButton(icon: const Icon(Icons.play_arrow), tooltip: 'Activate', onPressed: () async {
                    final j = await ModelStore.loadModelJson(m.id);
                    if (j==null) return;
                    final clf = SoftmaxClassifier();
                    clf.nIn = (j['nIn'] as num).toInt();
                    clf.nClasses = (j['labels'] as List).length;
                    clf.W = (j['W'] as List).map((e)=> (e as num).toDouble()).toList();
                    clf.b = (j['b'] as List).map((e)=> (e as num).toDouble()).toList();
                    _clf = clf; _clfLabels = (j['labels'] as List).map((e)=>e.toString()).toList();
                    setState(()=>_activeModelFile=m.id);
                  }),
                  IconButton(icon: const Icon(Icons.delete), onPressed: () async {
                    await ModelStore.deleteModel(m.id);
                    setState((){});
                  }),
                ]),
              )),
          ]),
        );
      },
    );
  }

  Widget _inferenceTab(ColorScheme cs) {
    final hasModel = _clf!=null;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ElevatedButton.icon(onPressed: _loadLatestModel, icon: const Icon(Icons.download), label: const Text('Load latest model')),
          const SizedBox(width: 8),
          if (_activeModelFile!=null) Chip(label: Text('Active: $_activeModelFile')),
        ]),
        const SizedBox(height: 8),
        if (!hasModel) const Text('No model loaded. Train or load one from the Models tab.'),
        if (hasModel) _LiveInferencePanel(clf: _clf!, labels: _clfLabels, stream: _ble.samples),
      ]),
    );
  }
}

class _LiveInferencePanel extends StatefulWidget {
  final SoftmaxClassifier clf;
  final List<String> labels;
  final Stream<ShoeSample> stream;
  const _LiveInferencePanel({required this.clf, required this.labels, required this.stream});
  @override
  State<_LiveInferencePanel> createState() => _LiveInferencePanelState();
}

class _LiveInferencePanelState extends State<_LiveInferencePanel> {
  final WindowedBuffer _wb = WindowedBuffer(windowMs: 2000, overlap: 0.5);
  String pred='—';
  double conf=0;
  final Map<String,int> counts={};

  @override
  void initState() {
    super.initState();
    widget.stream.listen((s){
      _wb.add(s);
      final ws=_wb.takeWindows();
      if (ws.isNotEmpty) {
        final fv = FeatureExtractor.fromWindow(ws.first);
        final p = widget.clf.predictProba(fv.x);
        int arg=0; double best=p[0];
        for (int k=1;k<p.length;k++) if (p[k]>best){best=p[k];arg=k;}
        pred = widget.labels[arg]; conf = best;
        counts[pred]=(counts[pred]??0)+1;
        setState((){});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Prediction: $pred  (${(conf*100).toStringAsFixed(1)}%)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        Wrap(spacing:8, runSpacing:8, children: [
          for (final L in widget.labels)
            Chip(label: Text('$L: ${counts[L]??0}')),
        ]),
      ]),
    ));
  }
}

extension _Avg on List<double> {
  double get average => isEmpty? 0 : (reduce((p,c)=>p+c)/length);
}
