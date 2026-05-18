import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

void main() => runApp(SmartShoeApp());

class SmartShoeApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Shoe Dashboard',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final String serverUrl = "http://192.168.1.181:5000/data";

  int steps = 0;
  double temp = 0, pressure = 0, roll = 0, pitch = 0, yaw = 0;

  List<FlSpot> stepData = [];
  List<FlSpot> tempData = [];
  List<FlSpot> pressureData = [];
  List<FlSpot> rollData = [], pitchData = [], yawData = [];

  int timeIndex = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    fetchData();
    timer = Timer.periodic(Duration(seconds: 1), (_) => fetchData());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void fetchData() async {
    try {
      final response = await http.get(Uri.parse(serverUrl));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          steps = data['steps'];
          temp = data['temperature'];
          pressure = data['pressure'];
          roll = data['roll'];
          pitch = data['pitch'];
          yaw = data['yaw'];

          timeIndex++;
          stepData.add(FlSpot(timeIndex.toDouble(), steps.toDouble()));
          tempData.add(FlSpot(timeIndex.toDouble(), temp));
          pressureData.add(FlSpot(timeIndex.toDouble(), pressure));
          rollData.add(FlSpot(timeIndex.toDouble(), roll));
          pitchData.add(FlSpot(timeIndex.toDouble(), pitch));
          yawData.add(FlSpot(timeIndex.toDouble(), yaw));

          if (stepData.length > 30) {
            stepData.removeAt(0);
            tempData.removeAt(0);
            pressureData.removeAt(0);
            rollData.removeAt(0);
            pitchData.removeAt(0);
            yawData.removeAt(0);
          }
        });
      }
    } catch (e) {
      print("Error fetching data: $e");
    }
  }

  Widget buildChart(String label, List<FlSpot> data, Color color) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(
              height: 150,
              child: LineChart(LineChartData(
                titlesData: FlTitlesData(show: false),
                gridData: FlGridData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: data,
                    isCurved: true,
                    color: color,
                    barWidth: 3,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  )
                ],
              )),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Smart Shoe Dashboard')),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Text("Steps: $steps", style: TextStyle(fontSize: 20)),
              Text("Temperature: ${temp.toStringAsFixed(2)} °C"),
              Text("Pressure: ${pressure.toStringAsFixed(2)} hPa"),
              Text("Roll: ${roll.toStringAsFixed(2)}°, Pitch: ${pitch.toStringAsFixed(2)}°, Yaw: ${yaw.toStringAsFixed(2)}°"),
              buildChart("Steps", stepData, Colors.orange),
              buildChart("Temperature (°C)", tempData, Colors.redAccent),
              buildChart("Pressure (hPa)", pressureData, Colors.blue),
              buildChart("Roll", rollData, Colors.purple),
              buildChart("Pitch", pitchData, Colors.green),
              buildChart("Yaw", yawData, Colors.teal),
            ],
          ),
        ),
      ),
    );
  }
}
