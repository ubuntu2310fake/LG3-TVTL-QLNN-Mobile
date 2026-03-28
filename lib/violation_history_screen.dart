import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ViolationHistoryScreen extends StatefulWidget {
  const ViolationHistoryScreen({super.key});
  @override
  State<ViolationHistoryScreen> createState() => _ViolationHistoryScreenState();
}

class _ViolationHistoryScreenState extends State<ViolationHistoryScreen> {
  bool _isLoading = true;
  List<dynamic> _gateLogs = [];
  List<dynamic> _classLogs = [];

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      final response = await http.get(
        Uri.parse('https://qlnn.testifiyonline.xyz/api/violation_history_api'),
        headers: {'Cookie': 'PHPSESSID=$sessionId'},
      );
      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        setState(() { _gateLogs = data['gate_logs']; _classLogs = data['class_logs']; _isLoading = false; });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildLogItem(dynamic log, bool isGate) {
    bool isDeleted = log['is_deleted'] == 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 0, margin: const EdgeInsets.only(bottom: 8),
      color: isDark ? Theme.of(context).colorScheme.surface : Colors.white,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isDeleted 
            ? (isDark ? Colors.grey.shade800 : Colors.grey.shade300) 
            : (isDark ? Colors.red.withOpacity(0.3) : Colors.red.shade200)
        ), 
        borderRadius: BorderRadius.circular(12)
      ),
      child: ListTile(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(isGate ? log['student_name'] : log['class_name'], style: TextStyle(fontWeight: FontWeight.bold, decoration: isDeleted ? TextDecoration.lineThrough : null, color: isDark ? Colors.white : Colors.black87))),
            Text("-${log['recorded_points']}", style: TextStyle(color: isDeleted ? Colors.grey : Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(log['recorded_violation_name'], style: TextStyle(color: isDark ? Colors.grey.shade300 : Colors.black87)),
            Text(isGate ? "Lớp: ${log['class_name']}" : "Tuần ${log['week_number']}", style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade500 : Colors.black54)),
            Text("TG: ${isGate ? log['date_created'] : log['submitted_at']} • Báo cáo: ${log['reporter_name']}", style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade600 : Colors.grey)),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isDeleted 
              ? (isDark ? Colors.grey.shade900 : Colors.grey.shade100) 
              : (isDark ? Colors.green.withOpacity(0.15) : Colors.green.shade50), 
            borderRadius: BorderRadius.circular(8)
          ),
          child: Text(isDeleted ? "Đã xóa" : "Hiệu lực", style: TextStyle(color: isDeleted ? Colors.grey : Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lịch sử vi phạm', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: TabBar(
            labelColor: Theme.of(context).colorScheme.primary, unselectedLabelColor: Colors.grey, indicatorColor: Theme.of(context).colorScheme.primary,
            tabs: const [Tab(icon: Icon(Icons.qr_code_scanner), text: 'Trực Cổng'), Tab(icon: Icon(Icons.fact_check), text: 'Chấm Lớp')],
          ),
        ),
        body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              children: [
                ListView.builder(padding: const EdgeInsets.all(12), itemCount: _gateLogs.length, itemBuilder: (c, i) => _buildLogItem(_gateLogs[i], true)),
                ListView.builder(padding: const EdgeInsets.all(12), itemCount: _classLogs.length, itemBuilder: (c, i) => _buildLogItem(_classLogs[i], false)),
              ],
            ),
      ),
    );
  }
}