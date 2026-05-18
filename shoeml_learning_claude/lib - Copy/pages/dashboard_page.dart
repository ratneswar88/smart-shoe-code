import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../ble.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.ble});
  final ShoeBle ble;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // Live values
  DeviceConnectionState conn = DeviceConnectionState.disconnected;
  String? _id;
  int? rssi;

  double roll = 0, pitch = 0, yaw = 0;
  double? tempC;
  int steps = 0;
  double cadence = 0, stride = 0, dh = 0;

  // Stream subs
  StreamSubscription? _sConn, _sRssi;
  StreamSubscription? _sRoll, _sPitch, _sYaw, _sTemp, _sSteps, _sCad, _sStride, _sDh;

  @override
  void initState() {
    super.initState();
    // Connection + device id
    _sConn = widget.ble.connection$.listen((s) {
      setState(() {
        conn = s;
        _id = widget.ble.device?.id;
      });
    });

    // RSSI (if your ble.dart provides rssi$)
    _sRssi = widget.ble.rssi$.listen((v) => setState(() => rssi = v));

    _sRoll   = widget.ble.roll$.listen((v) => setState(() => roll = v));
    _sPitch  = widget.ble.pitch$.listen((v) => setState(() => pitch = v));
    _sYaw    = widget.ble.yaw$.listen((v) => setState(() => yaw = v));
    _sTemp   = widget.ble.temp$.listen((v) => setState(() => tempC = v));
    _sSteps  = widget.ble.steps$.listen((v) => setState(() => steps = v));
    _sCad    = widget.ble.cadence$.listen((v) => setState(() => cadence = v));
    _sStride = widget.ble.stride$.listen((v) => setState(() => stride = v));
    _sDh     = widget.ble.dh$.listen((v) => setState(() => dh = v));
  }

  @override
  void dispose() {
    for (final s in [
      _sConn, _sRssi, _sRoll, _sPitch, _sYaw, _sTemp, _sSteps, _sCad, _sStride, _sDh
    ]) {
      s?.cancel();
    }
    super.dispose();
  }

  Future<void> _scanAndConnect() async {
    // Generic, works across our BLE wrappers
    final d = await widget.ble.scanOnce();
    if (d != null) {
      await widget.ble.connect(d.id);
    }
  }

  // ----------- UI helpers -----------

  Widget _statusRow({
    required DeviceConnectionState state,
    required String? id,
    required int? rssiDbm,
  }) {
    final isConnected = state == DeviceConnectionState.connected;
    final color = isConnected ? Colors.green : Colors.red;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(isConnected ? Icons.check_circle : Icons.cancel, color: color),
            const SizedBox(width: 8),
            Text(
              isConnected
                  ? "Connected"
                  : state == DeviceConnectionState.connecting
                      ? "Connecting..."
                      : state == DeviceConnectionState.disconnecting
                          ? "Disconnecting..."
                          : "Disconnected",
              style: TextStyle(fontWeight: FontWeight.w600, color: color),
            ),
            if (id != null) ...[
              const SizedBox(width: 12),
              Text(id, style: const TextStyle(color: Colors.black54)),
            ],
            const Spacer(),
            if (rssiDbm != null) ...[
              Chip(
                avatar: const Icon(Icons.network_cell, size: 16),
                label: Text("RSSI $rssiDbm dBm"),
              ),
              const SizedBox(width: 8),
            ],
            if (!isConnected)
              ElevatedButton.icon(
                onPressed: _scanAndConnect,
                icon: const Icon(Icons.search),
                label: const Text("Scan & Connect"),
              )
            else
              ElevatedButton.icon(
                onPressed: () => widget.ble.disconnect(),
                icon: const Icon(Icons.link_off),
                label: const Text("Disconnect"),
              ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon) {
    return SizedBox(
      width: 180,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.black54)),
                    const SizedBox(height: 4),
                    Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _statusRow(state: conn, id: _id, rssiDbm: rssi),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metric("Roll (°)",   roll.toStringAsFixed(1),  Icons.rotate_90_degrees_ccw),
              _metric("Pitch (°)",  pitch.toStringAsFixed(1), Icons.rotate_90_degrees_cw),
              _metric("Yaw (°)",    yaw.toStringAsFixed(1),   Icons.refresh),
              _metric("Temp (°C)",  tempC?.toStringAsFixed(1) ?? "—", Icons.thermostat),
              _metric("Steps",      steps.toString(),          Icons.directions_walk),
              _metric("Cadence",    "${cadence.toStringAsFixed(1)} spm", Icons.speed),
              _metric("Stride",     "${stride.toStringAsFixed(2)} m",    Icons.straighten),
              _metric("Δh",         "${dh.toStringAsFixed(2)} m",        Icons.landscape),
            ],
          ),
        ),
      ],
    );
  }
}
