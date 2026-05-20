// Smart Belt Flutter App
// Integrates both Posture Monitoring and Waist Circumference Tracking
// 
// Features:
// - Real-time posture visualization
// - Sitting time tracking
// - Waist circumference trending
// - BLE auto-reconnect (using your proven heartbeat method)
// - Data persistence and analytics
// - Alert configuration

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:math';

void main() {
  runApp(const SmartBeltApp());
}

class SmartBeltApp extends StatelessWidget {
  const SmartBeltApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Belt Monitor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

// ==================== BLE Service Manager ====================
class BLEService {
  // Service UUIDs
  static const String postureServiceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String waistServiceUuid = "5fafc201-1fb5-459e-8fcc-c5c9c331914b";
  
  // Posture characteristics
  static const String tiltAngleUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  static const String postureScoreUuid = "beb5483f-36e1-4688-b7f5-ea07361b26a8";
  static const String sittingTimeUuid = "beb54840-36e1-4688-b7f5-ea07361b26a8";
  static const String postureConfigUuid = "beb54841-36e1-4688-b7f5-ea07361b26a8";
  static const String postureCalibrateUuid = "beb54842-36e1-4688-b7f5-ea07361b26a8";
  
  // Waist characteristics
  static const String currentCircumUuid = "ceb5483e-36e1-4688-b7f5-ea07361b26a8";
  static const String dailyAvgUuid = "ceb5483f-36e1-4688-b7f5-ea07361b26a8";
  static const String weeklyTrendUuid = "ceb54840-36e1-4688-b7f5-ea07361b26a8";
  static const String waistCalibrationUuid = "ceb54841-36e1-4688-b7f5-ea07361b26a8";
  static const String rawDataUuid = "ceb54842-36e1-4688-b7f5-ea07361b26a8";

  BluetoothDevice? device;
  BluetoothCharacteristic? tiltAngleChar;
  BluetoothCharacteristic? postureScoreChar;
  BluetoothCharacteristic? sittingTimeChar;
  BluetoothCharacteristic? postureConfigChar;
  BluetoothCharacteristic? postureCalibrateChar;
  BluetoothCharacteristic? currentCircumChar;
  BluetoothCharacteristic? dailyAvgChar;
  BluetoothCharacteristic? weeklyTrendChar;
  BluetoothCharacteristic? waistCalibrationChar;

  Timer? heartbeatTimer;
  Timer? reconnectTimer;
  bool isConnected = false;
  DateTime? lastHeartbeat;

  final StreamController<double> tiltAngleController = StreamController<double>.broadcast();
  final StreamController<double> postureScoreController = StreamController<double>.broadcast();
  final StreamController<int> sittingTimeController = StreamController<int>.broadcast();
  final StreamController<double> waistCircumController = StreamController<double>.broadcast();
  final StreamController<ConnectionState> connectionStateController = 
      StreamController<ConnectionState>.broadcast();

  Future<void> connectToDevice(BluetoothDevice dev) async {
    device = dev;
    
    try {
      await device!.connect();
      isConnected = true;
      connectionStateController.add(ConnectionState.connected);
      
      // Discover services
      List<BluetoothService> services = await device!.discoverServices();
      
      // Find characteristics
      for (var service in services) {
        if (service.uuid.toString() == postureServiceUuid) {
          for (var characteristic in service.characteristics) {
            switch (characteristic.uuid.toString()) {
              case tiltAngleUuid:
                tiltAngleChar = characteristic;
                await characteristic.setNotifyValue(true);
                characteristic.value.listen((value) {
                  if (value.isNotEmpty) {
                    double tiltAngle = ByteData.sublistView(Uint8List.fromList(value))
                        .getFloat32(0, Endian.little);
                    tiltAngleController.add(tiltAngle);
                    updateHeartbeat();
                  }
                });
                break;
              case postureScoreUuid:
                postureScoreChar = characteristic;
                await characteristic.setNotifyValue(true);
                characteristic.value.listen((value) {
                  if (value.isNotEmpty) {
                    double score = ByteData.sublistView(Uint8List.fromList(value))
                        .getFloat32(0, Endian.little);
                    postureScoreController.add(score);
                  }
                });
                break;
              case sittingTimeUuid:
                sittingTimeChar = characteristic;
                break;
              case postureConfigUuid:
                postureConfigChar = characteristic;
                break;
              case postureCalibrateUuid:
                postureCalibrateChar = characteristic;
                break;
            }
          }
        } else if (service.uuid.toString() == waistServiceUuid) {
          for (var characteristic in service.characteristics) {
            switch (characteristic.uuid.toString()) {
              case currentCircumUuid:
                currentCircumChar = characteristic;
                await characteristic.setNotifyValue(true);
                characteristic.value.listen((value) {
                  if (value.isNotEmpty) {
                    double circumference = ByteData.sublistView(Uint8List.fromList(value))
                        .getFloat32(0, Endian.little);
                    waistCircumController.add(circumference);
                    updateHeartbeat();
                  }
                });
                break;
              case dailyAvgUuid:
                dailyAvgChar = characteristic;
                break;
              case weeklyTrendUuid:
                weeklyTrendChar = characteristic;
                break;
              case waistCalibrationUuid:
                waistCalibrationChar = characteristic;
                break;
            }
          }
        }
      }
      
      // Start heartbeat monitoring
      startHeartbeatMonitoring();
      
      print('Connected to Smart Belt');
    } catch (e) {
      print('Connection error: $e');
      isConnected = false;
      connectionStateController.add(ConnectionState.disconnected);
      startReconnectAttempts();
    }
  }

  void updateHeartbeat() {
    lastHeartbeat = DateTime.now();
  }

  void startHeartbeatMonitoring() {
    heartbeatTimer?.cancel();
    heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (lastHeartbeat == null) return;
      
      final timeSinceLastHeartbeat = DateTime.now().difference(lastHeartbeat!);
      
      if (timeSinceLastHeartbeat.inSeconds > 10) {
        print('Heartbeat timeout - connection lost');
        disconnect();
        startReconnectAttempts();
      }
    });
  }

  void startReconnectAttempts() {
    reconnectTimer?.cancel();
    reconnectTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (isConnected) {
        timer.cancel();
        return;
      }
      
      print('Attempting reconnection...');
      
      try {
        if (device != null) {
          await connectToDevice(device!);
          timer.cancel();
        }
      } catch (e) {
        print('Reconnect failed: $e');
      }
    });
  }

  Future<void> calibratePosture() async {
    if (postureCalibrateChar == null) return;
    
    try {
      await postureCalibrateChar!.write([0x01]);
      print('Posture calibration triggered');
    } catch (e) {
      print('Calibration error: $e');
    }
  }

  Future<void> calibrateWaist(double circumference) async {
    if (waistCalibrationChar == null) return;
    
    try {
      ByteData byteData = ByteData(4);
      byteData.setFloat32(0, circumference, Endian.little);
      await waistCalibrationChar!.write(byteData.buffer.asUint8List());
      print('Waist calibration: $circumference cm');
    } catch (e) {
      print('Waist calibration error: $e');
    }
  }

  Future<int> readSittingTime() async {
    if (sittingTimeChar == null) return 0;
    
    try {
      List<int> value = await sittingTimeChar!.read();
      if (value.length >= 4) {
        return ByteData.sublistView(Uint8List.fromList(value)).getUint32(0, Endian.little);
      }
    } catch (e) {
      print('Read sitting time error: $e');
    }
    return 0;
  }

  Future<double> readDailyAverage() async {
    if (dailyAvgChar == null) return 0.0;
    
    try {
      List<int> value = await dailyAvgChar!.read();
      if (value.length >= 4) {
        return ByteData.sublistView(Uint8List.fromList(value)).getFloat32(0, Endian.little);
      }
    } catch (e) {
      print('Read daily average error: $e');
    }
    return 0.0;
  }

  Future<List<double>> readWeeklyTrend() async {
    if (weeklyTrendChar == null) return [];
    
    try {
      List<int> value = await weeklyTrendChar!.read();
      List<double> trend = [];
      
      ByteData byteData = ByteData.sublistView(Uint8List.fromList(value));
      for (int i = 0; i < value.length / 4; i++) {
        trend.add(byteData.getFloat32(i * 4, Endian.little));
      }
      
      return trend;
    } catch (e) {
      print('Read weekly trend error: $e');
    }
    return [];
  }

  void disconnect() {
    heartbeatTimer?.cancel();
    reconnectTimer?.cancel();
    device?.disconnect();
    isConnected = false;
    connectionStateController.add(ConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    tiltAngleController.close();
    postureScoreController.close();
    sittingTimeController.close();
    waistCircumController.close();
    connectionStateController.close();
  }
}

enum ConnectionState {
  disconnected,
  connecting,
  connected,
}

// ==================== Data Models ====================
class PostureData {
  final DateTime timestamp;
  final double tiltAngle;
  final double postureScore;
  
  PostureData({
    required this.timestamp,
    required this.tiltAngle,
    required this.postureScore,
  });
  
  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'tiltAngle': tiltAngle,
    'postureScore': postureScore,
  };
  
  factory PostureData.fromJson(Map<String, dynamic> json) => PostureData(
    timestamp: DateTime.parse(json['timestamp']),
    tiltAngle: json['tiltAngle'],
    postureScore: json['postureScore'],
  );
}

class WaistData {
  final DateTime timestamp;
  final double circumference;
  
  WaistData({
    required this.timestamp,
    required this.circumference,
  });
  
  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'circumference': circumference,
  };
  
  factory WaistData.fromJson(Map<String, dynamic> json) => WaistData(
    timestamp: DateTime.parse(json['timestamp']),
    circumference: json['circumference'],
  );
}

// ==================== Home Screen ====================
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final BLEService bleService = BLEService();
  int _selectedIndex = 0;
  
  // Data storage
  List<PostureData> postureHistory = [];
  List<WaistData> waistHistory = [];
  
  // Current readings
  double currentTiltAngle = 0.0;
  double currentPostureScore = 100.0;
  double currentWaistCircum = 0.0;
  int totalSittingTime = 0;
  
  ConnectionState connectionState = ConnectionState.disconnected;

  @override
  void initState() {
    super.initState();
    initBLE();
    loadHistoricalData();
    
    // Listen to BLE streams
    bleService.tiltAngleController.stream.listen((angle) {
      setState(() {
        currentTiltAngle = angle;
      });
    });
    
    bleService.postureScoreController.stream.listen((score) {
      setState(() {
        currentPostureScore = score;
      });
      
      // Save to history every minute
      if (postureHistory.isEmpty || 
          DateTime.now().difference(postureHistory.last.timestamp).inSeconds > 60) {
        postureHistory.add(PostureData(
          timestamp: DateTime.now(),
          tiltAngle: currentTiltAngle,
          postureScore: score,
        ));
        savePostureHistory();
      }
    });
    
    bleService.waistCircumController.stream.listen((circumference) {
      setState(() {
        currentWaistCircum = circumference;
      });
      
      // Save to history every 5 minutes
      if (waistHistory.isEmpty || 
          DateTime.now().difference(waistHistory.last.timestamp).inMinutes >= 5) {
        waistHistory.add(WaistData(
          timestamp: DateTime.now(),
          circumference: circumference,
        ));
        saveWaistHistory();
      }
    });
    
    bleService.connectionStateController.stream.listen((state) {
      setState(() {
        connectionState = state;
      });
    });
    
    // Periodic sitting time update
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (bleService.isConnected) {
        int sittingTime = await bleService.readSittingTime();
        setState(() {
          totalSittingTime = sittingTime;
        });
      }
    });
  }

  Future<void> initBLE() async {
    FlutterBluePlus.setLogLevel(LogLevel.info);
    
    // Start scanning
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    
    // Listen to scan results
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult result in results) {
        if (result.device.name == 'SmartBelt-Posture' || 
            result.device.name == 'SmartBelt-Waist') {
          FlutterBluePlus.stopScan();
          setState(() {
            connectionState = ConnectionState.connecting;
          });
          bleService.connectToDevice(result.device);
          break;
        }
      }
    });
  }

  Future<void> loadHistoricalData() async {
    // Load from SharedPreferences
    SharedPreferences prefs = await SharedPreferences.getInstance();
    
    // Load posture history (last 24 hours)
    // Implementation depends on data persistence strategy
  }

  Future<void> savePostureHistory() async {
    // Save to SharedPreferences or local database
  }

  Future<void> saveWaistHistory() async {
    // Save to SharedPreferences or local database
  }

  @override
  void dispose() {
    bleService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Belt Monitor'),
        actions: [
          // Connection indicator
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Center(
              child: _buildConnectionIndicator(),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          PostureTab(
            tiltAngle: currentTiltAngle,
            postureScore: currentPostureScore,
            sittingTime: totalSittingTime,
            postureHistory: postureHistory,
            onCalibrate: () => bleService.calibratePosture(),
          ),
          WaistTab(
            currentCircumference: currentWaistCircum,
            waistHistory: waistHistory,
            onCalibrate: (double value) => bleService.calibrateWaist(value),
            bleService: bleService,
          ),
          AnalyticsTab(
            postureHistory: postureHistory,
            waistHistory: waistHistory,
          ),
          SettingsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.accessibility_new),
            label: 'Posture',
          ),
          NavigationDestination(
            icon: Icon(Icons.straighten),
            label: 'Waist',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics),
            label: 'Analytics',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionIndicator() {
    Color color;
    String text;
    
    switch (connectionState) {
      case ConnectionState.connected:
        color = Colors.green;
        text = 'Connected';
        break;
      case ConnectionState.connecting:
        color = Colors.orange;
        text = 'Connecting...';
        break;
      case ConnectionState.disconnected:
        color = Colors.red;
        text = 'Disconnected';
        break;
    }
    
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(fontSize: 12)),
      ],
    );
  }
}

// ==================== Posture Tab ====================
class PostureTab extends StatelessWidget {
  final double tiltAngle;
  final double postureScore;
  final int sittingTime;
  final List<PostureData> postureHistory;
  final VoidCallback onCalibrate;

  const PostureTab({
    Key? key,
    required this.tiltAngle,
    required this.postureScore,
    required this.sittingTime,
    required this.postureHistory,
    required this.onCalibrate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Real-time posture visualization
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text(
                    'Current Posture',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  
                  // Posture score circular indicator
                  SizedBox(
                    height: 200,
                    child: CustomPaint(
                      painter: PostureGaugePainter(
                        score: postureScore,
                        tiltAngle: tiltAngle,
                      ),
                      size: const Size(200, 200),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Tilt angle display
                  Text(
                    '${tiltAngle.toStringAsFixed(1)}°',
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _getPostureMessage(tiltAngle),
                    style: TextStyle(
                      fontSize: 18,
                      color: _getPostureColor(tiltAngle),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Sitting time tracker
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sitting Time Today',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: (sittingTime / 28800000).clamp(0.0, 1.0), // 8 hours max
                    minHeight: 10,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      sittingTime > 14400000 ? Colors.orange : Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatDuration(Duration(milliseconds: sittingTime)),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Posture history chart
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Posture Trend (Last 2 Hours)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: _buildPostureChart(),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Calibration button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onCalibrate,
              icon: const Icon(Icons.settings_backup_restore),
              label: const Text('Calibrate Good Posture'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostureChart() {
    if (postureHistory.isEmpty) {
      return const Center(child: Text('No data yet'));
    }
    
    // Get last 2 hours of data
    final twoHoursAgo = DateTime.now().subtract(const Duration(hours: 2));
    final recentData = postureHistory.where((d) => d.timestamp.isAfter(twoHoursAgo)).toList();
    
    if (recentData.isEmpty) {
      return const Center(child: Text('No recent data'));
    }
    
    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text('${value.toInt()}°', style: TextStyle(fontSize: 10));
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index >= 0 && index < recentData.length) {
                  return Text(
                    DateFormat('HH:mm').format(recentData[index].timestamp),
                    style: TextStyle(fontSize: 10),
                  );
                }
                return Text('');
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: recentData.asMap().entries.map((entry) {
              return FlSpot(entry.key.toDouble(), entry.value.tiltAngle);
            }).toList(),
            isCurved: true,
            color: Colors.blue,
            barWidth: 3,
            dotData: FlDotData(show: false),
          ),
        ],
        minY: 0,
        maxY: 40,
      ),
    );
  }

  String _getPostureMessage(double angle) {
    if (angle < 10) return 'Excellent posture!';
    if (angle < 20) return 'Good posture';
    if (angle < 30) return 'Mild slouching';
    return 'Severe slouching!';
  }

  Color _getPostureColor(double angle) {
    if (angle < 15) return Colors.green;
    if (angle < 25) return Colors.orange;
    return Colors.red;
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '${hours}h ${minutes}m';
  }
}

// ==================== Posture Gauge Painter ====================
class PostureGaugePainter extends CustomPainter {
  final double score;
  final double tiltAngle;

  PostureGaugePainter({
    required this.score,
    required this.tiltAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 10;
    
    // Background circle
    final bgPaint = Paint()
      ..color = Colors.grey[300]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20;
    
    canvas.drawCircle(center, radius, bgPaint);
    
    // Score arc
    final scorePaint = Paint()
      ..color = _getScoreColor(score)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round;
    
    final sweepAngle = (score / 100) * 2 * pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      sweepAngle,
      false,
      scorePaint,
    );
    
    // Draw spine representation
    _drawSpine(canvas, center, radius - 40, tiltAngle);
  }

  void _drawSpine(Canvas canvas, Offset center, double length, double angle) {
    final spinePaint = Paint()
      ..color = Colors.blueAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    
    // Convert tilt angle to radians
    final angleRad = angle * pi / 180;
    
    // Draw spine as curved line
    final path = Path();
    path.moveTo(center.dx, center.dy + length / 2);
    
    final controlPoint = Offset(
      center.dx + sin(angleRad) * length / 2,
      center.dy,
    );
    
    final endPoint = Offset(
      center.dx + sin(angleRad) * length,
      center.dy - length / 2,
    );
    
    path.quadraticBezierTo(
      controlPoint.dx,
      controlPoint.dy,
      endPoint.dx,
      endPoint.dy,
    );
    
    canvas.drawPath(path, spinePaint);
  }

  Color _getScoreColor(double score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.lightGreen;
    if (score >= 40) return Colors.orange;
    return Colors.red;
  }

  @override
  bool shouldRepaint(PostureGaugePainter oldDelegate) {
    return oldDelegate.score != score || oldDelegate.tiltAngle != tiltAngle;
  }
}

// ==================== Waist Tab ====================
class WaistTab extends StatelessWidget {
  final double currentCircumference;
  final List<WaistData> waistHistory;
  final Function(double) onCalibrate;
  final BLEService bleService;

  const WaistTab({
    Key? key,
    required this.currentCircumference,
    required this.waistHistory,
    required this.onCalibrate,
    required this.bleService,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current measurement
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Text(
                    'Current Waist',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${currentCircumference.toStringAsFixed(1)} cm',
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${(currentCircumference / 2.54).toStringAsFixed(1)} inches',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Weekly trend
          FutureBuilder<List<double>>(
            future: bleService.readWeeklyTrend(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const SizedBox.shrink();
              }
              
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '4-Week Trend',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 200,
                        child: _buildWeeklyTrendChart(snapshot.data!),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          
          const SizedBox(height: 16),
          
          // Historical chart
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Waist Measurements',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 250,
                    child: _buildWaistChart(),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Calibration
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showCalibrationDialog(context),
              icon: const Icon(Icons.straighten),
              label: const Text('Calibrate Waist Measurement'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaistChart() {
    if (waistHistory.isEmpty) {
      return const Center(child: Text('No data yet'));
    }
    
    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              getTitlesWidget: (value, meta) {
                return Text('${value.toInt()} cm', style: TextStyle(fontSize: 10));
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index >= 0 && index < waistHistory.length) {
                  return Text(
                    DateFormat('M/d').format(waistHistory[index].timestamp),
                    style: TextStyle(fontSize: 10),
                  );
                }
                return Text('');
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: waistHistory.asMap().entries.map((entry) {
              return FlSpot(entry.key.toDouble(), entry.value.circumference);
            }).toList(),
            isCurved: true,
            color: Colors.purple,
            barWidth: 3,
            dotData: FlDotData(show: true),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyTrendChart(List<double> weeklyData) {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: weeklyData.reduce(max) + 2,
        minY: weeklyData.reduce(min) - 2,
        barTouchData: BarTouchData(enabled: true),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                const weeks = ['Week 1', 'Week 2', 'Week 3', 'Week 4'];
                return Text(
                  weeks[value.toInt()],
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: weeklyData.asMap().entries.map((entry) {
          return BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                toY: entry.value,
                color: Colors.purple,
                width: 20,
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  void _showCalibrationDialog(BuildContext context) {
    final controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Calibrate Waist Measurement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Measure your waist with a tape measure and enter the value:'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Waist Circumference (cm)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = double.tryParse(controller.text);
              if (value != null && value >= 60 && value <= 150) {
                onCalibrate(value);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Calibration in progress...')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid value')),
                );
              }
            },
            child: const Text('Calibrate'),
          ),
        ],
      ),
    );
  }
}

// ==================== Analytics Tab ====================
class AnalyticsTab extends StatelessWidget {
  final List<PostureData> postureHistory;
  final List<WaistData> waistHistory;

  const AnalyticsTab({
    Key? key,
    required this.postureHistory,
    required this.waistHistory,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Analytics & Insights',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          
          // Posture statistics
          _buildStatisticsCard(
            'Posture Statistics',
            [
              _StatItem('Average Score', '${_calculateAveragePostureScore().toStringAsFixed(0)}/100'),
              _StatItem('Good Posture %', '${_calculateGoodPosturePercentage().toStringAsFixed(0)}%'),
              _StatItem('Total Sessions', '${postureHistory.length}'),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Waist statistics
          _buildStatisticsCard(
            'Waist Statistics',
            [
              _StatItem('Average', '${_calculateAverageWaist().toStringAsFixed(1)} cm'),
              _StatItem('Change', '${_calculateWaistChange().toStringAsFixed(1)} cm'),
              _StatItem('Total Measurements', '${waistHistory.length}'),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Insights
          const Text(
            'Insights',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          
          ..._generateInsights(),
        ],
      ),
    );
  }

  Widget _buildStatisticsCard(String title, List<_StatItem> items) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...items.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(item.label),
                  Text(
                    item.value,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  List<Widget> _generateInsights() {
    List<Widget> insights = [];
    
    // Posture insights
    if (postureHistory.isNotEmpty) {
      final avgScore = _calculateAveragePostureScore();
      if (avgScore < 60) {
        insights.add(_buildInsightCard(
          '⚠️ Posture Alert',
          'Your average posture score is below 60. Consider taking more breaks and adjusting your workspace ergonomics.',
          Colors.orange,
        ));
      } else if (avgScore >= 80) {
        insights.add(_buildInsightCard(
          '✓ Great Posture!',
          'You\'re maintaining excellent posture! Keep up the good work.',
          Colors.green,
        ));
      }
    }
    
    // Waist insights
    if (waistHistory.length >= 7) {
      final change = _calculateWaistChange();
      if (change.abs() > 2.0) {
        insights.add(_buildInsightCard(
          change > 0 ? '📈 Waist Increased' : '📉 Waist Decreased',
          'Your waist has ${change > 0 ? 'increased' : 'decreased'} by ${change.abs().toStringAsFixed(1)} cm over the past week.',
          change > 0 ? Colors.red : Colors.green,
        ));
      }
    }
    
    if (insights.isEmpty) {
      insights.add(_buildInsightCard(
        '📊 Keep Collecting Data',
        'Continue using the Smart Belt to unlock more insights about your posture and body metrics.',
        Colors.blue,
      ));
    }
    
    return insights;
  }

  Widget _buildInsightCard(String title, String description, Color color) {
    return Card(
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Text(description),
          ],
        ),
      ),
    );
  }

  double _calculateAveragePostureScore() {
    if (postureHistory.isEmpty) return 0.0;
    return postureHistory.map((d) => d.postureScore).reduce((a, b) => a + b) / postureHistory.length;
  }

  double _calculateGoodPosturePercentage() {
    if (postureHistory.isEmpty) return 0.0;
    int goodCount = postureHistory.where((d) => d.postureScore >= 70).length;
    return (goodCount / postureHistory.length) * 100;
  }

  double _calculateAverageWaist() {
    if (waistHistory.isEmpty) return 0.0;
    return waistHistory.map((d) => d.circumference).reduce((a, b) => a + b) / waistHistory.length;
  }

  double _calculateWaistChange() {
    if (waistHistory.length < 2) return 0.0;
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final recentData = waistHistory.where((d) => d.timestamp.isAfter(weekAgo)).toList();
    
    if (recentData.length < 2) return 0.0;
    
    return recentData.last.circumference - recentData.first.circumference;
  }
}

class _StatItem {
  final String label;
  final String value;
  
  _StatItem(this.label, this.value);
}

// ==================== Settings Tab ====================
class SettingsTab extends StatelessWidget {
  const SettingsTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Settings',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        
        ListTile(
          leading: const Icon(Icons.vibration),
          title: const Text('Haptic Feedback'),
          subtitle: const Text('Vibrate on posture alerts'),
          trailing: Switch(
            value: true,
            onChanged: (value) {},
          ),
        ),
        
        ListTile(
          leading: const Icon(Icons.notifications),
          title: const Text('Break Reminders'),
          subtitle: const Text('Remind me to take breaks'),
          trailing: Switch(
            value: true,
            onChanged: (value) {},
          ),
        ),
        
        const Divider(),
        
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('Data History'),
          subtitle: const Text('View and export your data'),
          onTap: () {},
        ),
        
        ListTile(
          leading: const Icon(Icons.info),
          title: const Text('About'),
          onTap: () {
            showAboutDialog(
              context: context,
              applicationName: 'Smart Belt Monitor',
              applicationVersion: '1.0.0',
              applicationLegalese: '© 2024',
            );
          },
        ),
      ],
    );
  }
}
