import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Home / welcome page.
///
/// Behavior:
/// - First launch:
///   * stay on this page
///   * user can tap "Go to Dashboard"
/// - Later launches:
///   * stay on this page while sensor is disconnected
///   * start reconnect in the background
///   * automatically go to dashboard ONLY when connection stream reports
///     DeviceConnectionState.connected
///   * user can still manually open the dashboard any time
///
/// NOTE:
/// We intentionally keep the same constructor parameters your current main.dart
/// already passes, so you do NOT need to change main.dart again.
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
  final Future<bool> Function()? reconnectLastIfAny;
  final WidgetBuilder dashboardBuilder;

  final String appTitle;
  final String heroTitle;

  @override
  State<ConnectHomePage> createState() => _ConnectHomePageState();
}

class _ConnectHomePageState extends State<ConnectHomePage> {
  static const String _prefsSeenWelcome = 'shoeml_seen_welcome';

  StreamSubscription<DeviceConnectionState>? _connSub;

  bool _isLoading = true;
  bool _hasSeenWelcome = false;
  bool _navigated = false;
  bool _isConnected = false;
  bool _isTryingReconnect = false;

  String _statusText = 'Checking sensor status...';

  @override
  void initState() {
    super.initState();
    _bindConnectionStream();
    _bootstrap();
  }

  void _bindConnectionStream() {
    _connSub = widget.connection$.listen((state) {
      if (!mounted) return;

      final connected = state == DeviceConnectionState.connected;

      setState(() {
        _isConnected = connected;

        switch (state) {
          case DeviceConnectionState.connected:
            _statusText = 'Sensor connected. Opening dashboard...';
            break;
          case DeviceConnectionState.connecting:
            _statusText = 'Connecting to sensor...';
            break;
          case DeviceConnectionState.disconnecting:
            _statusText = 'Disconnecting from sensor...';
            break;
          case DeviceConnectionState.disconnected:
            _statusText = _hasSeenWelcome
                ? 'Sensor disconnected. Waiting until it reconnects...'
                : 'Welcome. Tap below to enter the dashboard.';
            break;
        }
      });

      if (connected) {
        _goToDashboard(markSeen: false);
      }
    });
  }

  Future<void> _bootstrap() async {
    await _ensurePerms();

    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool(_prefsSeenWelcome) ?? false;

      if (!mounted) return;
      setState(() {
        _hasSeenWelcome = seen;
        _isLoading = false;
        _statusText = seen
            ? 'Sensor disconnected. Waiting until it reconnects...'
            : 'Welcome. Tap below to enter the dashboard.';
      });

      if (seen) {
        _startReconnectInBackground();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasSeenWelcome = false;
        _isLoading = false;
        _statusText = 'Welcome. Tap below to enter the dashboard.';
      });
    }
  }

  Future<void> _startReconnectInBackground() async {
    if (_isTryingReconnect) return;

    setState(() {
      _isTryingReconnect = true;
      _statusText = 'Trying to reconnect sensor...';
    });

    try {
      if (widget.reconnectLastIfAny != null) {
        final ok = await widget.reconnectLastIfAny!.call();

        if (!mounted) return;
        setState(() {
          _isTryingReconnect = false;
          if (!ok && !_isConnected) {
            _statusText =
                'Sensor disconnected. Waiting until it reconnects...';
          }
        });
      } else {
        if (!mounted) return;
        setState(() {
          _isTryingReconnect = false;
          _statusText =
              'Reconnect function not available. Open dashboard manually.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isTryingReconnect = false;
        _statusText = 'Reconnect failed. Waiting for sensor to reconnect...';
      });
    }
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
    } catch (_) {}
  }

  Future<void> _goToDashboard({required bool markSeen}) async {
    if (_navigated || !mounted) return;
    _navigated = true;

    if (markSeen) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_prefsSeenWelcome, true);
      } catch (_) {}
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: widget.dashboardBuilder,
      ),
    );
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.appTitle),
          centerTitle: true,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final waitingForReconnect = _hasSeenWelcome && !_isConnected;

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
                    'Real-time sensor analytics, live activity classification, and on-device training for your smart shoe platform.',
                    style: TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _statusText,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onPrimaryContainer.withOpacity(0.9),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            _featureCard(
              icon: Icons.analytics_outlined,
              title: 'MADE PLUS Smart Shoe Analytics',
              subtitle:
                  'Review motion, gait, cadence, stride, and elevation insights from your wearable.',
            ),
            _featureCard(
              icon: Icons.directions_walk,
              title: 'Live Activity Classification',
              subtitle:
                  'Monitor walking, running, stairs, and other activities in real time.',
            ),
            _featureCard(
              icon: Icons.memory_outlined,
              title: 'On-Device Training',
              subtitle:
                  'Collect labeled sessions and build personalized activity models.',
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _goToDashboard(markSeen: true),
                icon: const Icon(Icons.dashboard_outlined),
                label: Text(
                  waitingForReconnect
                      ? 'Go to Dashboard Anyway'
                      : 'Go to Dashboard',
                ),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ),

            const SizedBox(height: 10),

            Text(
              _hasSeenWelcome
                  ? 'When the sensor is disconnected, the app stays on this home page and keeps trying to reconnect. You can still open the dashboard manually at any time.'
                  : 'First launch stays on this welcome page. After that, the app will wait here for sensor reconnect, but you can still open the dashboard manually whenever you want.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
