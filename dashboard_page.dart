// lib/pages/dashboard_page.dart
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
  // Connection state
  DeviceConnectionState _conn = DeviceConnectionState.disconnected;
  String? _connectedId; // ← replaces widget.ble.device?.id (which doesn't exist)
  int? _rssi;

  // Sensor values
  double roll = 0, pitch = 0, yaw = 0;
  double? tempC;
  int steps = 0;
  double cadence = 0, stride = 0, dh = 0;

  // Stream subscriptions
  StreamSubscription? _sConn, _sRssi;
  StreamSubscription? _sRoll, _sPitch, _sYaw, _sTemp, _sSteps, _sCad, _sStride, _sDh;

  @override
  void initState() {
    super.initState();

    // Connection — use ble.connectedId instead of ble.device?.id
    _sConn = widget.ble.connection$.listen((s) {
      if (!mounted) return;
      setState(() {
        _conn = s;
        _connectedId = widget.ble.connectedId; // safe getter added to ShoeBle
      });
    });

    _sRssi   = widget.ble.rssi$.listen((v)    => _set(() => _rssi    = v));
    _sRoll   = widget.ble.roll$.listen((v)     => _set(() => roll     = v));
    _sPitch  = widget.ble.pitch$.listen((v)    => _set(() => pitch    = v));
    _sYaw    = widget.ble.yaw$.listen((v)      => _set(() => yaw      = v));
    _sTemp   = widget.ble.temp$.listen((v)     => _set(() => tempC    = v));
    _sSteps  = widget.ble.steps$.listen((v)    => _set(() => steps    = v));
    _sCad    = widget.ble.cadence$.listen((v)  => _set(() => cadence  = v));
    _sStride = widget.ble.stride$.listen((v)   => _set(() => stride   = v));
    _sDh     = widget.ble.dh$.listen((v)       => _set(() => dh       = v));
  }

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  @override
  void dispose() {
    for (final s in [
      _sConn, _sRssi, _sRoll, _sPitch, _sYaw,
      _sTemp, _sSteps, _sCad, _sStride, _sDh,
    ]) {
      s?.cancel();
    }
    super.dispose();
  }

  // ── BLE actions ─────────────────────────────────────────────────────────────

  Future<void> _scanAndConnect() async {
    final d = await widget.ble.scanOnce();
    if (d != null && mounted) {
      await widget.ble.connect(d.id);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No device found. Is the shoe powered on?')),
      );
    }
  }

  // ── UI helpers ───────────────────────────────────────────────────────────────

  String get _connLabel {
    switch (_conn) {
      case DeviceConnectionState.connecting:    return 'Connecting…';
      case DeviceConnectionState.connected:     return 'Connected';
      case DeviceConnectionState.disconnecting: return 'Disconnecting…';
      case DeviceConnectionState.disconnected:  return 'Disconnected';
    }
  }

  bool get _isConnected => _conn == DeviceConnectionState.connected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _connectionCard(cs),
        const SizedBox(height: 12),
        _metricsGrid(cs),
      ],
    );
  }

  // ── Connection card ──────────────────────────────────────────────────────────

  Widget _connectionCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: _isConnected ? cs.primary : cs.error,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _connLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _isConnected ? cs.primary : cs.error,
                        ),
                      ),
                      if (_connectedId != null)
                        Text(
                          _connectedId!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (_rssi != null)
                  Chip(
                    avatar: const Icon(Icons.network_cell, size: 16),
                    label: Text('$_rssi dBm'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isConnected ? null : _scanAndConnect,
                    icon: const Icon(Icons.search),
                    label: const Text('Scan & Connect'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isConnected ? () => widget.ble.disconnect() : null,
                    icon: const Icon(Icons.link_off),
                    label: const Text('Disconnect'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Metrics grid ─────────────────────────────────────────────────────────────

  Widget _metricsGrid(ColorScheme cs) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _metric(cs, 'Roll',     '${roll.toStringAsFixed(1)}°',           Icons.rotate_90_degrees_ccw),
        _metric(cs, 'Pitch',    '${pitch.toStringAsFixed(1)}°',          Icons.rotate_90_degrees_cw),
        _metric(cs, 'Yaw',      '${yaw.toStringAsFixed(1)}°',            Icons.refresh),
        _metric(cs, 'Temp',     tempC != null ? '${tempC!.toStringAsFixed(1)} °C' : '—', Icons.thermostat),
        _metric(cs, 'Steps',    '$steps',                                 Icons.directions_walk),
        _metric(cs, 'Cadence',  '${cadence.toStringAsFixed(1)} spm',     Icons.speed),
        _metric(cs, 'Stride',   '${stride.toStringAsFixed(2)} m',        Icons.straighten),
        _metric(cs, 'Elev Δh',  '${dh.toStringAsFixed(2)} m',           Icons.landscape),
      ],
    );
  }

  Widget _metric(ColorScheme cs, String label, String value, IconData icon) {
    return SizedBox(
      width: 200,
      child: Card(
        color: cs.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(value,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
