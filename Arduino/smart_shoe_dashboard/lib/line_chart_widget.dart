import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class LineChartWidget extends StatelessWidget {
  final List<FlSpot> data;
  final String title;
  final Color color;

  LineChartWidget({required this.data, required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 5,
      margin: EdgeInsets.all(10),
      child: Container(
        padding: EdgeInsets.all(12),
        height: 220,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Expanded(
              child: LineChart(
                LineChartData(
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(),
                    leftTitles: AxisTitles(),
                    rightTitles: AxisTitles(),
                    topTitles: AxisTitles(),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: data,
                      isCurved: true,
                      colors: [color],
                      dotData: FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        colors: [color.withOpacity(0.3)],
                      ),
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
