import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

/// A BLE-first landing page for the Smart Shoe app.
///
/// This page:
/// - shows connection status + RSSI
/// - provides Scan & Connect / Disconnect
/// - auto-navigates to the dashboard when connected
/// - optionally tries reconnectLastIfAny() on startup
///
/// IMPORTANT:
/// This file is designed to work with your EXISTING ShoeBle class from main.dart
/// by passing callbacks/streams into the constructor.
/// That avoids circular imports and lets the same BLE instance be reused across
/// the landing page and dashboard.
class ConnectHomePage extends StatefulWidget {
  const ConnectHomePage({
    super.key,
    required this.connection$,
    required this.rssi$,
    required this.scanOnce,
    required this.connect,
    required this.disconnect,
    required this.dashboardBuilder,
    this.reconnectLastIfAny,
    this.appTitle = 'MADE PLUS',
    this.heroTitle = 'MADE PLUS Smart Shoe',
  });

  final Stream<DeviceConnectionState> connection$;
  final Stream<int?> rssi$;
  final Future<DiscoveredDevice?> Function() scanOnce;
  final Future<void> Function(String id) connect;
  final Future<void> Function() disconnect;
  final Future<void> Function()? reconnectLastIfAny;
  final WidgetBuilder dashboardBuilder;

  final String appTitle;
  final String heroTitle;

  @override
  State<ConnectHomePage> createState() => _ConnectHomePageState();
}

class _ConnectHomePageState extends State<ConnectHomePage> {
  StreamSubscription<DeviceConnectionState>? _connSub;
  StreamSubscription<int?>? _rssiSub;

  bool _isConnected = false;
  bool _isBusy = false;
  bool _navigated = false;

  int? _rssi;
  String _deviceName = 'MADEPLUS SMART SHOE';
  String? _deviceId;

  @override
  void initState() {
    super.initState();
    _bindStreams();
    _startup();
  }

  Future<void> _startup() async {
    await _ensurePerms();

    if (widget.reconnectLastIfAny != null) {
      try {
        await widget.reconnectLastIfAny!.call();
      } catch (_) {
        // keep UI alive even if reconnect bootstrap fails
      }
    }
  }

  void _bindStreams() {
    _connSub = widget.connection$.listen((state) {
      if (!mounted) return;

      final connected = state == DeviceConnectionState.connected;

      setState(() {
        _isConnected = connected;
        if (!connected) {
          _navigated = false;
        }
      });

      if (connected) {
        _goToDashboard();
      }
    });

    _rssiSub = widget.rssi$.listen((value) {
      if (!mounted) return;
      setState(() => _rssi = value);
    });
  }

  Future<void> _ensurePerms() async {
    final req = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.storage,
    ];

    try {
      await req.request();
    } catch (_) {
      // keep going; user may already have permissions or platform may ignore some
    }
  }

  void _goToDashboard() {
    if (_navigated || !_isConnected || !mounted) return;
    _navigated = true;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: widget.dashboardBuilder,
      ),
    );
  }

  Future<void> _scanAndConnect() async {
    setState(() => _isBusy = true);

    try {
      await _ensurePerms();

      final d = await widget.scanOnce();
      if (!mounted) return;

      if (d == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No device advertising the Smart Shoe service.'),
          ),
        );
        return;
      }

      setState(() {
        _deviceId = d.id;
        _deviceName = d.name.trim().isNotEmpty ? d.name.trim() : 'MADEPLUS SMART SHOE';
      });

      await widget.connect(d.id);
      // navigation happens from the connection stream once it becomes connected
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _disconnect() async {
    try {
      await widget.disconnect();

      if (!mounted) return;
      setState(() {
        _isConnected = false;
        _rssi = null;
        _navigated = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sensor disconnected')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Disconnect failed: $e')),
      );
    }
  }

  Widget _featureCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: CircleAvatar(
          radius: 22,
          child: Icon(icon),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _rssiSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectedText = _isConnected ? 'Connected' : 'Disconnected';
    final rssiText = _rssi == null ? '-- dBm' : '$_rssi dBm';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.appTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primaryContainer,
                    Theme.of(context).colorScheme.secondaryContainer,
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.heroTitle,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Real-time sensor connectivity, analytics, live activity classification, and on-device training.',
                    style: TextStyle(fontSize: 15),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isConnected
                              ? Icons.bluetooth_connected
                              : Icons.bluetooth_disabled,
                          size: 30,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _deviceName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text('Sensor status: $connectedText'),
                              Text('RSSI: $rssiText'),
                              if (_deviceId != null && _deviceId!.isNotEmpty)
                                Text(
                                  _deviceId!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isBusy ? null : _scanAndConnect,
                            icon: _isBusy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.search),
                            label: Text(
                              _isBusy ? 'Scanning...' : 'Scan & Connect',
                            ),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isConnected ? _disconnect : null,
                            icon: const Icon(Icons.link_off),
                            label: const Text('Disconnect'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),

            _featureCard(
              icon: Icons.analytics_outlined,
              title: 'MADE PLUS Smart Shoe Analytics',
              subtitle: 'Review sensor-driven motion and gait insights from your wearable.',
            ),
            _featureCard(
              icon: Icons.directions_walk,
              title: 'Live Activity Classification',
              subtitle: 'Detect and monitor walking, running, stairs, and more in real time.',
            ),
            _featureCard(
              icon: Icons.memory_outlined,
              title: 'On-Device Training',
              subtitle: 'Capture labeled motion data and support personalized model training.',
            ),
          ],
        ),
      ),
    );
  }
}
