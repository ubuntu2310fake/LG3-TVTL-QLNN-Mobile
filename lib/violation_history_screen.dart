import 'localization_service.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/liquid_glass_container.dart';
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
        title: Text(LocalizationService().currentLanguage == 'vi' ? 'Xác nhận Xóa' : 'Confirm Deletion'),
        content: Text(LocalizationService().currentLanguage == 'vi' ? 'Bạn có chắc chắn muốn xóa bản ghi này không?' : 'Are you sure you want to delete this record?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Khoan đã' : 'Wait')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(LocalizationService().currentLanguage == 'vi' ? 'Xóa' : 'Delete')
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == "vi" ? "❌ Lỗi: ${data['msg']}" : "❌ Error: ${data['msg']}"), backgroundColor: Colors.red));
          _fetchHistory();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == "vi" ? "❌ Lỗi: ${data['msg']}" : "❌ Error: ${data['msg']}"), backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == "vi" ? "❌ Lỗi kết nối" : "❌ Connection error"), backgroundColor: Colors.red));
    }
  }

  Future<void> _showEditDialog(dynamic log) async {
    TextEditingController pointsCtrl = TextEditingController(text: log['recorded_points']?.toString() ?? '');
    TextEditingController noteCtrl = TextEditingController(text: log['note']?.toString() ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(LocalizationService().currentLanguage == 'vi' ? 'Sửa lỗi vi phạm' : 'Edit Violation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pointsCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Điểm trừ (Số)' : 'Deduction points (Number)', border: OutlineInputBorder()),
            ),
            SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Ghi chú thêm' : 'Additional notes', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Huỷ' : 'Cancel')),
          ElevatedButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              final sessionId = prefs.getString('phpsessid') ?? '';
              await http.post(
                Uri.parse('${AppConfig.baseUrl}/api/violation_history_api'),
                headers: {'Cookie': 'PHPSESSID=$sessionId', 'Content-Type': 'application/json'},
                body: jsonEncode({
                  'action': 'edit',
                  'edit_id': log['id'],
                  'points': pointsCtrl.text,
                  'note': noteCtrl.text
                }),
              );
              if (mounted) Navigator.pop(ctx);
              _fetchHistory();
            },
            child: Text(LocalizationService().currentLanguage == 'vi' ? 'Lưu' : 'Save')
          )
        ]
      )
    );
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
            icon: Icon(Icons.chevron_left),
            onPressed: currentPage > 1 ? () {
              setState(() { if (isGate) {
                _pageGate--;
              } else {
                _pageClass--;
              } });
              _fetchHistory();
            } : null,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade800 : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(LocalizationService().currentLanguage == 'vi' ? 'Trang $currentPage / $totalPages' : 'Page $currentPage / $totalPages', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.blue.shade800)),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right),
            onPressed: currentPage < totalPages ? () {
              setState(() { if (isGate) {
                _pageGate++;
              } else {
                _pageClass++;
              } });
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
    String titleName = isGate ? (log['student_name'] ?? log['class_name'] ?? (LocalizationService().currentLanguage == 'vi' ? 'Không rõ' : 'Unknown')) : (log['class_name'] ?? (LocalizationService().currentLanguage == 'vi' ? 'Không rõ' : 'Unknown'));

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
          SizedBox(height: 4),
          Text(LocalizationService().currentLanguage == 'vi' ? (log['recorded_violation_name'] ?? '') : (log['violation_name_en'] ?? log['recorded_violation_name'] ?? ''), style: TextStyle(color: isDark ? Colors.grey.shade300 : Colors.black87)),
          // FIX 3: Thêm ghi chú hiển thị nếu có
          if (isGate && log['note'] != null && log['note'].toString().trim().isNotEmpty)
             Text(LocalizationService().currentLanguage == "vi" ? "Ghi chú: \"${log['note']}\"" : "Note: \"${log['note']}\"", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.orange)),
          Text(isGate ? (LocalizationService().currentLanguage == "vi" ? "Lớp: ${log['class_name'] ?? ''} ${log['student_code'] != null ? '(${log['student_code']})' : ''}" : "Class: ${log['class_name'] ?? ''} ${log['student_code'] != null ? '(${log['student_code']})' : ''}") : (LocalizationService().currentLanguage == "vi" ? "Tuần ${log['week_number'] ?? ''}" : "Week ${log['week_number'] ?? ''}"), style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade500 : Colors.black54)),
          Text(LocalizationService().currentLanguage == "vi" ? "TG: ${isGate ? log['date_created'] : log['submitted_at']} • Báo cáo: ${log['reporter_name'] ?? 'Hệ thống'}" : "Time: ${isGate ? log['date_created'] : log['submitted_at']} • Reporter: ${log['reporter_name'] ?? 'System'}", style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade600 : Colors.grey)),
        ],
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isDeleted 
            ? (isDark ? Colors.grey.shade900 : Colors.grey.shade100) 
            : (isDark ? Colors.green.withValues(alpha: 0.15) : Colors.green.shade50), 
          borderRadius: BorderRadius.circular(8)
        ),
        child: Text(isDeleted ? (LocalizationService().currentLanguage == "vi" ? "Đã xóa" : "Deleted") : (LocalizationService().currentLanguage == "vi" ? "Hiệu lực" : "Valid"), style: TextStyle(color: isDeleted ? Colors.grey : Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
      onTap: (_userRole == 'ADMIN' && !isDeleted && isGate && log['id'] != null) ? () => _showEditDialog(log) : null,
    );

    Widget itemContent = LiquidGlassContainer(
      margin: const EdgeInsets.only(bottom: 8),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isDeleted 
            ? (isDark ? Colors.grey.shade800 : Colors.grey.shade300) 
            : (isDark ? Colors.red.withValues(alpha: 0.3) : Colors.red.shade200)
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
          child: Icon(Icons.delete, color: Colors.white),
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
          title: Text(LocalizationService().currentLanguage == 'vi' ? 'Lịch sử vi phạm' : 'Violation History', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: TabBar(
            labelColor: Theme.of(context).colorScheme.primary, unselectedLabelColor: Colors.grey, indicatorColor: Theme.of(context).colorScheme.primary,
            tabs: [Tab(icon: Icon(Icons.qr_code_scanner), text: LocalizationService().currentLanguage == 'vi' ? 'Trực Cổng' : 'Gate Check'), Tab(icon: Icon(Icons.fact_check), text: LocalizationService().currentLanguage == 'vi' ? 'Chấm Lớp' : 'Class Check')],
          ),
        ),
        body: _isLoading 
          ? Center(child: CircularProgressIndicator())
          : TabBarView(
              children: [
                RefreshIndicator(
                  onRefresh: _fetchHistory,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (_userRole == 'ADMIN') 
                        Padding(padding: EdgeInsets.only(bottom: 10), child: Text(LocalizationService().currentLanguage == 'vi' ? '💡 Gợi ý: Admin có thể chạm vào để Sửa, hoặc vuốt sang trái để Xóa lỗi trực cổng.' : '💡 Tip: Admin can tap to Edit, or swipe left to Delete gate violation.', style: TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic, fontSize: 13))),
                      ..._gateLogs.map((log) => _buildLogItem(log, true)),
                      _buildPaginationControls(true),
                    ],
                  ),
                ),
                RefreshIndicator(
                  onRefresh: _fetchHistory,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      ..._classLogs.map((log) => _buildLogItem(log, false)),
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