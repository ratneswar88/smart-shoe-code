// ============================================================================
// lib/main.dart — MADEPLUS ShoeML
// App entry point, global theme manager, and bottom-nav shell.
//
// Project structure expected:
//   lib/
//     main.dart                  ← this file
//     ble.dart                   ← ShoeBle (BLE layer + auto-reconnect)
//     connect_home_page.dart     ← scan/connect landing page
//     pages/
//       dashboard_page.dart      ← live metrics + activity classifier
//       graphs_page.dart         ← real-time R/P/Y charts
//       training_page.dart       ← data collection + on-device training
//       tutorials_page.dart      ← usage guide
//
// ⚠️  Known compatibility notes (fix in the page files, not here):
//   • dashboard_page.dart references `widget.ble.device?.id` but ShoeBle
//     in ble.dart does not expose a `device` getter. Either:
//       (a) add `DiscoveredDevice? get device => _device;` to ShoeBle, or
//       (b) remove the reference in dashboard_page.dart and derive the id
//           from the connection stream instead.
//   • ble.dart exposes `rssi$` as `Stream<int>` but ConnectHomePage
//     expects `Stream<int?>`. This is handled below with `.map<int?>((v)=>v)`.
//   • ble.dart uses `tryReconnectLast()` while ConnectHomePage's constructor
//     parameter is called `reconnectLastIfAny`. A lambda bridges the two.
// ============================================================================

import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ble.dart';
import 'connect_home_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/graphs_page.dart';
import 'pages/training_page.dart';
import 'pages/tutorials_page.dart';

// ─── Entry point ─────────────────────────────────────────────────────────────

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Surface framework errors to the console rather than crashing.
  FlutterError.onError = FlutterError.presentError;

  // Swallow uncaught async errors so the process stays alive.
  PlatformDispatcher.instance.onError = (_, __) => true;

  runZonedGuarded(
    () => runApp(const ShoeMLApp()),
    (_, __) {/* errors already swallowed by the handler above */},
  );
}

// ─── Root application widget ─────────────────────────────────────────────────

class ShoeMLApp extends StatefulWidget {
  const ShoeMLApp({super.key});

  @override
  State<ShoeMLApp> createState() => _ShoeMLAppState();
}

class _ShoeMLAppState extends State<ShoeMLApp> {
  // Singleton BLE instance shared across all pages.
  final ShoeBle _ble = ShoeBle();

  // Theme state.
  Color _seed = const Color(0xFF00639A);
  ThemeMode _themeMode = ThemeMode.system;

  static const List<Color> _colorPresets = [
    Color(0xFF00639A), // MADEPLUS blue (default)
    Color(0xFF00796B), // teal
    Color(0xFF7B1FA2), // purple
    Color(0xFF2E7D32), // green
    Color(0xFFEF6C00), // orange
    Color(0xFFAD1457), // pink
  ];

  // ── Theme picker dialog ───────────────────────────────────────────────────

  Future<void> _showThemePicker(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Color'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _colorPresets.map((color) {
                final selected = color == _seed;
                return InkWell(
                  onTap: () {
                    setState(() => _seed = color);
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? Colors.white : Colors.black12,
                        width: selected ? 3 : 1,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _themeMode = ThemeMode.light);
              Navigator.pop(context);
            },
            child: const Text('Light'),
          ),
          TextButton(
            onPressed: () {
              setState(() => _themeMode = ThemeMode.dark);
              Navigator.pop(context);
            },
            child: const Text('Dark'),
          ),
          TextButton(
            onPressed: () {
              setState(() => _themeMode = ThemeMode.system);
              Navigator.pop(context);
            },
            child: const Text('System'),
          ),
        ],
      ),
    );
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _ble.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final lightTheme = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: _seed,
      brightness: Brightness.light,
    );
    final darkTheme = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: _seed,
      brightness: Brightness.dark,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MADEPLUS ShoeML',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _themeMode,
      home: ConnectHomePage(
        // ── BLE stream adapters ──────────────────────────────────────────
        // ble.dart's rssi$ is Stream<int>; ConnectHomePage wants Stream<int?>.
        connection$: _ble.connection$,
        rssi$: _ble.rssi$.map<int?>((v) => v),

        // ble.dart's method is tryReconnectLast(); the param is reconnectLastIfAny.
        scanOnce: _ble.scanOnce,
        connect: _ble.connect,
        disconnect: _ble.disconnect,
        reconnectLastIfAny: () => _ble.tryReconnectLast(),

        dashboardBuilder: (_) => HomeShell(
          ble: _ble,
          onPickColor: () => _showThemePicker(context),
        ),
      ),
    );
  }
}

// ─── Bottom-navigation shell ──────────────────────────────────────────────────

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.ble,
    required this.onPickColor,
  });

  final ShoeBle ble;
  final VoidCallback onPickColor;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  // Request BLE + location permissions once on first launch.
  Future<void> _requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.storage,
    ].request();
  }

  @override
  Widget build(BuildContext context) {
    // Pages are kept alive by IndexedStack; no rebuilds on tab switch.
    final pages = <Widget>[
      DashboardPage(ble: widget.ble),
      GraphsPage(ble: widget.ble),
      TrainingPage(ble: widget.ble),
      const TutorialPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/madeplus_logo.png',
              height: 28,
              // Silently hide if asset is missing during development.
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
            const SizedBox(width: 8),
            const Text('SMARTSHOE'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Theme & colour',
            icon: const Icon(Icons.palette_outlined),
            onPressed: widget.onPickColor,
          ),
          IconButton(
            tooltip: 'Bluetooth settings',
            icon: const Icon(Icons.bluetooth),
            onPressed: _openBluetoothSettings,
          ),
        ],
      ),
      // IndexedStack keeps all pages in memory (preserves scroll position,
      // live subscriptions, and chart history across tab switches).
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart),
            selectedIcon: Icon(Icons.show_chart),
            label: 'Graphs',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: 'Training',
          ),
          NavigationDestination(
            icon: Icon(Icons.help_outline),
            selectedIcon: Icon(Icons.help),
            label: 'Tutorial',
          ),
        ],
      ),
    );
  }

  Future<void> _openBluetoothSettings() async {
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.bluetooth);
    } catch (_) {
      // Fallback to general settings on platforms that don't support
      // the Bluetooth deep-link (e.g. some Android versions).
      await AppSettings.openAppSettings();
    }
  }
}
