import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class ViolationHistoryScreen extends StatefulWidget {
  const ViolationHistoryScreen({super.key});
  @override
  State<ViolationHistoryScreen> createState() => _ViolationHistoryScreenState();
}

class _ViolationHistoryScreenState extends State<ViolationHistoryScreen> {
  bool _isLoading = true;
  List<dynamic> _gateLogs = [];
  List<dynamic> _classLogs = [];
  
  int _pageGate = 1;
  int _pageClass = 1;
  int _totalPagesGate = 1;
  int _totalPagesClass = 1;
  String _userRole = '';

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      
      final String url = '${AppConfig.baseUrl}/api/violation_history_api?page_gate=$_pageGate&page_class=$_pageClass';

      final response = await http.get(
        Uri.parse(url),
        headers: {'Cookie': 'PHPSESSID=$sessionId'},
      );
      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        if (mounted) {
          setState(() { 
            _gateLogs = data['gate_logs']; 
            _classLogs = data['class_logs'];
            _totalPagesGate = data['total_pages_gate'] ?? 1;
            _totalPagesClass = data['total_pages_class'] ?? 1;
            _userRole = data['role'] ?? '';
            _isLoading = false; 
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteLog(int id) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận Xóa'),
        content: const Text('Bạn có chắc chắn muốn xóa bản ghi này không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Khoan đã')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Xóa')
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/violation_history_api'),
        headers: {'Cookie': 'PHPSESSID=$sessionId', 'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'delete', 'delete_id': id}),
      );
      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Đã xóa bản ghi!'), backgroundColor: Colors.green));
          _fetchHistory();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Lỗi: ${data['msg']}'), backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Lỗi kết nối'), backgroundColor: Colors.red));
    }
  }

  Widget _buildPaginationControls(bool isGate) {
    int currentPage = isGate ? _pageGate : _pageClass;
    int totalPages = (isGate ? _totalPagesGate : _totalPagesClass).clamp(1, 9999);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: currentPage > 1 ? () {
              setState(() { if (isGate) _pageGate--; else _pageClass--; });
              _fetchHistory();
            } : null,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade800 : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('Trang $currentPage / $totalPages', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.blue.shade800)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: currentPage < totalPages ? () {
              setState(() { if (isGate) _pageGate++; else _pageClass++; });
              _fetchHistory();
            } : null,
          ),
        ],
      ),
    );
  }

  Widget _buildLogItem(dynamic log, bool isGate) {
    // FIX 1: Ép kiểu is_deleted an toàn hơn
    bool isDeleted = log['is_deleted'] == 1 || log['is_deleted'] == '1';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // FIX 2: Xử lý fallback chống crash nếu student_name hoặc class_name bị null
    String titleName = isGate ? (log['student_name'] ?? log['class_name'] ?? 'Không rõ') : (log['class_name'] ?? 'Không rõ');

    Widget cardListTile = ListTile(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(titleName, style: TextStyle(fontWeight: FontWeight.bold, decoration: isDeleted ? TextDecoration.lineThrough : null, color: isDark ? Colors.white : Colors.black87))),
          Text("-${log['recorded_points'] ?? 0}", style: TextStyle(color: isDeleted ? Colors.grey : Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(log['recorded_violation_name'] ?? '', style: TextStyle(color: isDark ? Colors.grey.shade300 : Colors.black87)),
          // FIX 3: Thêm ghi chú hiển thị nếu có
          if (isGate && log['note'] != null && log['note'].toString().trim().isNotEmpty)
             Text('Ghi chú: "${log['note']}"', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.orange)),
          Text(isGate ? "Lớp: ${log['class_name'] ?? ''} ${log['student_code'] != null ? '(${log['student_code']})' : ''}" : "Tuần ${log['week_number'] ?? ''}", style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade500 : Colors.black54)),
          Text("TG: ${isGate ? log['date_created'] : log['submitted_at']} • Báo cáo: ${log['reporter_name'] ?? 'Hệ thống'}", style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade600 : Colors.grey)),
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
    );

    Widget itemContent = Card(
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
      child: cardListTile,
    );

    if (_userRole == 'ADMIN' && !isDeleted && isGate && log['id'] != null) {
      return Dismissible(
        key: Key(log['id'].toString()),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        confirmDismiss: (direction) async {
          await _deleteLog(log['id']);
          return false; // Fake dismiss, list update will remove it from UI/gray it out
        },
        child: itemContent,
      );
    }

    return itemContent;
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
                RefreshIndicator(
                  onRefresh: _fetchHistory,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (_userRole == 'ADMIN') 
                        Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('💡 Gợi ý: Admin có thể vuốt sang trái để Xóa lỗi trực cổng.', style: TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic, fontSize: 13))),
                      ..._gateLogs.map((log) => _buildLogItem(log, true)).toList(),
                      _buildPaginationControls(true),
                    ],
                  ),
                ),
                RefreshIndicator(
                  onRefresh: _fetchHistory,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      ..._classLogs.map((log) => _buildLogItem(log, false)).toList(),
                      _buildPaginationControls(false),
                    ],
                  ),
                ),
              ],
            ),
      ),
    );
  }
}