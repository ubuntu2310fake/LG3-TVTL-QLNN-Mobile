import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  bool _isLoading = true;
  String _week = '';
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      
      String url = 'https://qlnn.testifiyonline.xyz/api/teacher_dashboard_api';
      if (_week.isNotEmpty) url += '?week=$_week';

      final response = await http.get(Uri.parse(url), headers: {'Cookie': 'PHPSESSID=$sessionId'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() { 
          if (_week.isEmpty && data['current_week'] != null) {
            _week = data['current_week'].toString();
          }
          _data = data; 
          _isLoading = false; 
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteViolation(int id) async {
    if (!await _confirm('Bạn có chắc muốn xóa lỗi vi phạm này?')) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      await http.post(
        Uri.parse('https://qlnn.testifiyonline.xyz/api/teacher_dashboard_api'),
        headers: {'Cookie': 'PHPSESSID=$sessionId', 'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'delete_violation', 'id': id}),
      );
      _fetchData(); 
    } catch (e) {}
  }

  Future<bool> _confirm(String msg) async {
    return await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Xác nhận'), content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy')),
        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Đồng ý', style: TextStyle(color: Colors.red))),
      ],
    )) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_data['status'] == 'error') return Scaffold(appBar: AppBar(), body: Center(child: Text(_data['msg'])));
    if (_data['has_class'] == false) return Scaffold(appBar: AppBar(title: const Text('Lớp của tôi')), body: const Center(child: Text('Bạn chưa được phân công chủ nhiệm.')));

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lớp ${_data['class_info']['name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              Text('GV: ${_data['class_info']['teacher']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.grey)),
            ],
          ),
          bottom: TabBar(
            isScrollable: true,
            labelColor: Theme.of(context).colorScheme.primary, 
            unselectedLabelColor: Colors.grey, 
            indicatorColor: Theme.of(context).colorScheme.primary,
            tabs: const [
              Tab(icon: Icon(Icons.people), text: 'Học sinh'),
              Tab(icon: Icon(Icons.warning_amber), text: 'Vi phạm'),
              Tab(icon: Icon(Icons.grid_on), text: 'Điểm Sổ'),
              Tab(icon: Icon(Icons.psychology), text: 'Tâm lý'),
            ],
          ),
          actions: [
            Row(
              children: [
                const Text('Tuần ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    dropdownColor: Theme.of(context).colorScheme.surface,
                    iconEnabledColor: Theme.of(context).colorScheme.primary,
                    style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16),
                    value: _week,
                    items: List.generate(35, (i) => DropdownMenuItem(value: (i+1).toString(), child: Text('${i+1}'))),
                    onChanged: (v) { setState(() => _week = v!); _fetchData(); },
                  ),
                ),
              ],
            ),
            const SizedBox(width: 15), 
          ],
        ),
        body: TabBarView(
          children: [
            ListView.builder(
              padding: const EdgeInsets.all(12), itemCount: _data['students'].length,
              itemBuilder: (c, i) {
                var s = _data['students'][i];
                return Card(child: ListTile(leading: CircleAvatar(child: Text(s['name'][0])), title: Text(s['name'], style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(s['code']), trailing: s['has_exemption'] == 1 ? const Icon(Icons.shield, color: Colors.green) : null));
              },
            ),
            _data['violations'].isEmpty ? const Center(child: Text("Không có vi phạm tuần này!")) : ListView.builder(
              padding: const EdgeInsets.all(12), itemCount: _data['violations'].length,
              itemBuilder: (c, i) {
                var v = _data['violations'][i];
                return Card(
                  elevation: 0, shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.redAccent), borderRadius: BorderRadius.circular(8)),
                  child: ListTile(
                    title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(v['student_name'] ?? 'Tập thể', style: const TextStyle(fontWeight: FontWeight.bold)), Text("-${v['recorded_points']}", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))]),
                    subtitle: Text("${v['recorded_violation_name']}\n${v['date_created']} • ${v['reporter']}"), isThreeLine: true,
                    trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.grey), onPressed: () => _deleteViolation(v['id'])),
                  ),
                );
              },
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: isDark ? Colors.blue.withOpacity(0.1) : Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("TỔNG ĐIỂM TUẦN:", style: TextStyle(fontWeight: FontWeight.bold)), Text("${_data['matrix']['total']}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.blue))]),
                  ),
                  const SizedBox(height: 15),
                  ...(_data['matrix']['data'] as List).map((row) => Card(
                    child: Padding(padding: const EdgeInsets.all(12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [CircleAvatar(backgroundColor: Colors.blue, child: Text(row['day'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))), Text("Trừ: ${10 - row['total']}đ", style: const TextStyle(color: Colors.redAccent)), Text("Còn: ${row['total']}đ", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))])),
                  )),
                ],
              ),
            ),
            _data['psychology'].isEmpty ? const Center(child: Text("Tâm lý ổn định.")) : ListView.builder(
              padding: const EdgeInsets.all(12), itemCount: _data['psychology'].length,
              itemBuilder: (c, i) {
                var p = _data['psychology'][i]; bool isDanger = p['risk_level'] == 'DANGER';
                return Card(
                  color: isDanger ? (isDark ? Colors.red.withOpacity(0.1) : Colors.red.shade50) : (isDark ? Colors.orange.withOpacity(0.1) : Colors.orange.shade50), 
                  shape: RoundedRectangleBorder(side: BorderSide(color: isDanger ? Colors.red : Colors.orange), borderRadius: BorderRadius.circular(8)),
                  child: ExpansionTile(
                    title: Text("${p['student_name']} ${isDanger ? '🆘' : '⚠️'}", style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(p['question']),
                    children: [ Padding(padding: const EdgeInsets.all(16), child: Text("AI Tư vấn:\n${p['advice']}", style: const TextStyle(fontStyle: FontStyle.italic))) ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}