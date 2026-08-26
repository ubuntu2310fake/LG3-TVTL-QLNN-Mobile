import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';

Widget _buildChart(String type, String resultStr, bool isDark) {
    try {
      final Map<String, dynamic> data = jsonDecode(resultStr);
      if (data.isEmpty) return const SizedBox();

      final List<MapEntry<String, dynamic>> entries = data.entries.toList();
      double maxY = 0;
      for (var e in entries) {
        double val = (e.value as num).toDouble();
        if (val > maxY) maxY = val;
      }
      if (maxY < 5) maxY = 5;
      
      if (type.toUpperCase() == 'HOLLAND') {
        return Container(
          height: 250,
          margin: const EdgeInsets.only(top: 15, bottom: 5),
          child: RadarChart(
            RadarChartData(
              dataSets: [
                RadarDataSet(
                  fillColor: Colors.blueAccent.withValues(alpha: 0.2),
                  borderColor: Colors.blueAccent,
                  entryRadius: 3,
                  dataEntries: entries.map((e) => RadarEntry(value: (e.value as num).toDouble())).toList(),
                )
              ],
              radarBackgroundColor: Colors.transparent,
              borderData: FlBorderData(show: false),
              radarBorderData: const BorderSide(color: Colors.transparent),
              titlePositionPercentageOffset: 0.2,
              titleTextStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 11, fontWeight: FontWeight.bold),
              getTitle: (index, angle) {
                return RadarChartTitle(text: entries[index].key);
              },
              tickCount: 4,
              ticksTextStyle: const TextStyle(color: Colors.transparent, fontSize: 10),
              tickBorderData: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
              gridBorderData: BorderSide(color: Colors.grey.withValues(alpha: 0.3), width: 1),
            ),
          ),
        );
      }

      maxY += 2;
      return Container();
    } catch (e) {
      return Container();
    }
}
