import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'edit_student_screen.dart';

class ManageStudentsScreen extends StatefulWidget {
  const ManageStudentsScreen({super.key});
  @override
  State<ManageStudentsScreen> createState() => _ManageStudentsScreenState();
}

class _ManageStudentsScreenState extends State<ManageStudentsScreen> {
  bool _isLoading = true;
  List _students = [];
  List _classes = [];
  String _search = '';
  String _classId = '';
  
  int _currentPage = 1;
  int _totalPages = 1;

  @override
  void initState() { super.initState(); _fetchData(); }

  Future<void> _fetchData({int page = 1}) async {
    setState(() { _isLoading = true; _currentPage = page; });
    final prefs = await SharedPreferences.getInstance();
    
    final res = await http.get(
      Uri.parse('https://qlnn.testifiyonline.xyz/api/manage_students_api?search=$_search&class_id=$_classId&page=$_currentPage'), 
      headers: {'Cookie': 'PHPSESSID=${prefs.getString('phpsessid')}'}
    );
    
    final data = jsonDecode(res.body);
    if (data['status'] == 'success') {
      setState(() { 
        _students = data['students']; 
        _classes = data['classes']; 
        _totalPages = data['total_pages'] ?? 1; 
        _isLoading = false; 
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _quickApprove(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await http.post(
      Uri.parse('https://qlnn.testifiyonline.xyz/api/manage_students_api'), 
      headers: {'Cookie': 'PHPSESSID=${prefs.getString('phpsessid')}'}, 
      body: jsonEncode({'action': 'quick_approve', 'code': code})
    );
    _fetchData(page: _currentPage);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Danh Sách Học Sinh', style: TextStyle(fontWeight: FontWeight.bold))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(child: TextField(
                  decoration: InputDecoration(hintText: 'Tìm mã/tên...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), 
                  onChanged: (v) { _search = v; _fetchData(page: 1); }
                )),
                const SizedBox(width: 10),
                Expanded(child: DropdownButtonFormField<String>(
                  decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), contentPadding: const EdgeInsets.symmetric(horizontal: 10)),
                  value: _classId.isEmpty ? null : _classId, hint: const Text('Tất cả lớp'),
                  items: [const DropdownMenuItem(value: '', child: Text('Tất cả'))]..addAll(_classes.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['name'])))),
                  onChanged: (v) { setState(() => _classId = v!); _fetchData(page: 1); },
                )),
              ],
            ),
          ),
          Expanded(
            child: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
              itemCount: _students.length,
              itemBuilder: (c, i) {
                final s = _students[i];
                bool hasPending = s['has_pending_changes'] == 1;
                return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: s['image_url'] != null ? NetworkImage('https://qlnn.testifiyonline.xyz/${s['image_url']}') : null,
                    child: s['image_url'] == null ? const Icon(Icons.person) : null,
                  ),
                  title: Text(s['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  // --- BỔ SUNG HIỂN THỊ BADGE CỜ ĐỎ DƯỚI TÊN ---
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${s['code']} - Lớp: ${s['class_name']}"),
                      if (s['role'] == 'RED_FLAG')
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            border: Border.all(color: Colors.red.shade200),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.flag, color: Colors.red, size: 12),
                              const SizedBox(width: 4),
                              Text(
                                'Cờ đỏ ${s['homeroom_class_name'] ?? ''}', 
                                style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasPending) IconButton(icon: const Icon(Icons.check_circle, color: Colors.green), onPressed: () => _quickApprove(s['code']), tooltip: 'Duyệt thay đổi'),
                      const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                    ],
                  ),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditStudentScreen(studentCode: s['code']))).then((_) => _fetchData(page: _currentPage)),
                ));
              },
            ),
          ),
          
          if (!_isLoading && _totalPages > 1)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: isDark ? Theme.of(context).colorScheme.surface : Colors.white, border: Border(top: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left), 
                    onPressed: _currentPage > 1 ? () => _fetchData(page: _currentPage - 1) : null,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: isDark ? Colors.blue.withOpacity(0.2) : Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text('Trang $_currentPage / $_totalPages', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right), 
                    onPressed: _currentPage < _totalPages ? () => _fetchData(page: _currentPage + 1) : null,
                  ),
                ],
              ),
            )
        ],
      ),
    );
  }
}