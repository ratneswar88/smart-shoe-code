import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Welcome / home page.
///
/// First launch:
/// - stays on this page
/// - user taps "Go to Dashboard"
///
/// Later launches:
/// - shows this page briefly
/// - starts reconnect flow
/// - then routes to dashboard
///
/// NOTE:
/// We intentionally KEEP the same constructor parameters your main.dart
/// already passes today, so you do NOT need to change main.dart again.
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

  // Kept for compatibility with current main.dart wiring
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

  bool _isLoading = true;
  bool _hasSeenWelcome = false;
  bool _navigated = false;
  Timer? _autoNavTimer;

  @override
  void initState() {
    super.initState();
    _bootstrap();
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
      });

      if (seen) {
        _startLaterLaunchFlow();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasSeenWelcome = false;
        _isLoading = false;
      });
    }
  }

  void _startLaterLaunchFlow() {
    _autoNavTimer?.cancel();
    _autoNavTimer = Timer(const Duration(milliseconds: 900), () async {
      await _autoContinueLaterLaunch();
    });
  }

  Future<void> _autoContinueLaterLaunch() async {
    if (!mounted) return;

    // Run reconnect flow before entering dashboard so live data is ready.
    if (widget.reconnectLastIfAny != null) {
      try {
        await widget.reconnectLastIfAny!.call();
      } catch (_) {
        // Keep navigation alive even if reconnect bootstrap fails.
      }
    }

    if (!mounted) return;
    await _goToDashboard(markSeen: false);
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
      // Keep UI alive even if some permissions are ignored on platform/version.
    }
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
    _autoNavTimer?.cancel();
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
                  if (_hasSeenWelcome) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Opening dashboard and reconnecting sensor...',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onPrimaryContainer.withOpacity(0.85),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
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
                label: const Text('Go to Dashboard'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ),

            const SizedBox(height: 10),

            Text(
              _hasSeenWelcome
                  ? 'Later launches briefly pass through this page, reconnect the sensor, then continue to the dashboard.'
                  : 'On your next launches, this welcome page will appear briefly, reconnect the sensor, and continue to the dashboard automatically.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
