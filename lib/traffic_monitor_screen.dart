import 'localization_service.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class TrafficMonitorScreen extends StatefulWidget {
  const TrafficMonitorScreen({super.key});
  @override
  State<TrafficMonitorScreen> createState() => _TrafficMonitorScreenState();
}

class _TrafficMonitorScreenState extends State<TrafficMonitorScreen> {
  bool _isLoading = true;
  String _range = '1h';
  Map<String, dynamic> _overview = {};
  List<dynamic> _stats = [];

  @override
  void initState() { super.initState(); _fetchData(); }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    try {
      final res = await http.get(Uri.parse('${AppConfig.baseUrl}/api/traffic_monitor_api?range=$_range'), headers: {'Cookie': 'PHPSESSID=${prefs.getString('phpsessid')}'});
      final data = jsonDecode(res.body);
      if (data['status'] == 'success') {
        setState(() { _overview = data['overview']; _stats = data['stats']; _isLoading = false; });
      }
    } catch (e) { setState(() => _isLoading = false); }
  }

  Widget _buildCard(String title, String val, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16), 
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28), const Spacer(),
          Text(val, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          Text(title, style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text(LocalizationService().currentLanguage == 'vi' ? 'Giám sát lưu lượng' : 'Traffic Monitor', style: TextStyle(fontWeight: FontWeight.bold))),
      body: _isLoading ? Center(child: CircularProgressIndicator()) : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Nút chọn khung thời gian
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: '1h', label: Text(LocalizationService().currentLanguage == 'vi' ? '1 Giờ' : '1 Hour')),
              ButtonSegment(value: '24h', label: Text(LocalizationService().currentLanguage == 'vi' ? '24 Giờ' : '24 Hours')),
              ButtonSegment(value: '7d', label: Text(LocalizationService().currentLanguage == 'vi' ? '7 Ngày' : '7 Days')),
            ],
            selected: {_range},
            onSelectionChanged: (newSelection) { setState(() => _range = newSelection.first); _fetchData(); },
          ),
          SizedBox(height: 20),

          // 4 Thẻ tổng quan
          GridView.count(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.4,
            children: [
              _buildCard(LocalizationService().currentLanguage == 'vi' ? 'Tổng Request' : 'Total Requests', _overview['total_requests'].toString(), Icons.speed, Colors.blue),
              _buildCard(LocalizationService().currentLanguage == 'vi' ? 'IP Duy nhất' : 'Unique IPs', _overview['unique_visitors'].toString(), Icons.public, Colors.green),
              _buildCard(LocalizationService().currentLanguage == 'vi' ? 'Độ trễ TB (ms)' : 'Avg Latency (ms)', _overview['avg_latency'].toString(), Icons.timer, Colors.orange),
              _buildCard(LocalizationService().currentLanguage == 'vi' ? 'Tỷ lệ lỗi' : 'Error Rate', '${_overview['error_rate']}%', Icons.warning, _overview['error_rate'] > 5 ? Colors.red : Colors.green),
            ],
          ),
          SizedBox(height: 30),

          // BIỂU ĐỒ CỘT THỦ CÔNG (Siêu nhẹ)
          Text(LocalizationService().currentLanguage == 'vi' ? 'BIỂU ĐỒ REQUESTS' : 'REQUESTS CHART', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          SizedBox(height: 10),
          Container(
            height: 200, padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface, 
              border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300), 
              borderRadius: BorderRadius.circular(16)
            ),
            child: _stats.isEmpty ? Center(child: Text(LocalizationService().currentLanguage == 'vi' ? 'Không có dữ liệu' : 'No data')) : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _stats.map((s) {
                final double maxReq = _stats.map<double>((e) => (e['requests'] as num).toDouble()).reduce(max);
                final double h = (s['requests'] / (maxReq == 0 ? 1 : maxReq)) * 140; // max height
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(height: h, margin: const EdgeInsets.symmetric(horizontal: 2), decoration: BoxDecoration(color: Colors.blue.shade400, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))),
                      SizedBox(height: 4),
                      Text(s['time'].toString().substring(0, min(5, s['time'].toString().length)), style: const TextStyle(fontSize: 8, color: Colors.grey), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                );
              }).toList(),
            ),
          )
        ],
      ),
    );
  }
}