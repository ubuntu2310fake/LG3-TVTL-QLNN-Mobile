import 'localization_service.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'edit_student_screen.dart';
import 'widgets/liquid_glass_container.dart';
import 'config.dart';

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
    
    final res = await AppConfig.client.get(
      Uri.parse('${AppConfig.baseUrl}/api/manage_students_api?search=$_search&class_id=$_classId&page=$_currentPage'), 
      headers: {'Cookie': 'PHPSESSID=${prefs.getString('phpsessid')}'}
    );
    
    if (!mounted) return;

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
    await AppConfig.client.post(
      Uri.parse('${AppConfig.baseUrl}/api/manage_students_api'), 
      headers: {'Cookie': 'PHPSESSID=${prefs.getString('phpsessid')}'}, 
      body: jsonEncode({'action': 'quick_approve', 'code': code})
    );
    _fetchData(page: _currentPage);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(LocalizationService().currentLanguage == 'vi' ? 'Danh Sách Học Sinh' : 'Manage Students', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(Icons.qr_code_2),
            tooltip: LocalizationService().currentLanguage == 'vi' ? 'Tải mã QR (.zip)' : 'Tai ma QR (.zip)',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Đang tạo và tải file mã QR (.zip)...' : 'Generating and downloading QR code (.zip)...')));
            }
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(child: TextField(
                  decoration: InputDecoration(hintText: LocalizationService().currentLanguage == 'vi' ? 'Tìm mã/tên...' : 'Search code/name...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), 
                  onChanged: (v) { _search = v; _fetchData(page: 1); }
                )),
                SizedBox(width: 10),
                Expanded(child: DropdownButtonFormField<String>(
                  decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), contentPadding: const EdgeInsets.symmetric(horizontal: 10)),
                  initialValue: _classId.isEmpty ? null : _classId, hint: Text(LocalizationService().currentLanguage == 'vi' ? 'Tất cả lớp' : 'All classes'),
                  items: [DropdownMenuItem(value: '', child: Text(LocalizationService().currentLanguage == 'vi' ? 'Tất cả' : 'All')), ..._classes.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['name'])))],
                  onChanged: (v) { setState(() => _classId = v!); _fetchData(page: 1); },
                )),
              ],
            ),
          ),
          Expanded(
            child: _isLoading ? Center(child: CircularProgressIndicator()) : ListView.builder(
              itemCount: _students.length,
              itemBuilder: (c, i) {
                final s = _students[i];
                bool hasPending = s['has_pending_changes'] == 1;
                return LiquidGlassContainer(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: s['image_url'] != null ? NetworkImage('${AppConfig.baseUrl}/${s['image_url']}') : null,
                    child: s['image_url'] == null ? Icon(Icons.person) : null,
                  ),
                  title: Text(s['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  // --- BỔ SUNG HIỂN THỊ BADGE CỜ ĐỎ DƯỚI TÊN ---
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(LocalizationService().currentLanguage == 'vi' ? (s['thuylinh'] != null ? "STT ${s['thuylinh']} • ${s['code']} - Lớp: ${s['class_name']}" : "${s['code']} - Lớp: ${s['class_name']}") : (s['thuylinh'] != null ? "STT ${s['thuylinh']} • ${s['code']} - Class: ${s['class_name']}" : "${s['code']} - Class: ${s['class_name']}")),
                      if (s['dob'] != null && s['dob'].toString().isNotEmpty)
                        Text(LocalizationService().currentLanguage == 'vi' ? "Ngày sinh: ${s['dob']}" : "DOB: ${s['dob']}", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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
                              Icon(Icons.flag, color: Colors.red, size: 12),
                              SizedBox(width: 4),
                              Text(
                                LocalizationService().currentLanguage == 'vi' ? 'Cờ đỏ ${s["homeroom_class_name"] ?? ""}' : 'Red Flag ${s["homeroom_class_name"] ?? ""}',
                                style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)
                              ),
                            ],
                          ),
                        ),
                      if (hasPending)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.orange.shade200)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [Icon(Icons.pending_actions, size: 14, color: Colors.orange), SizedBox(width: 4), Text(LocalizationService().currentLanguage == 'vi' ? 'Yêu cầu thay đổi:' : 'Yeu cau thay doi:', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11))]),
                              if (s['pending_changes'] != null) Text(s['pending_changes'].toString(), style: const TextStyle(fontSize: 11)),
                              if (s['pending_changes'] == null) Text(LocalizationService().currentLanguage == 'vi' ? 'Cập nhật thông tin (Cũ -> Mới)' : 'Information update (Old -> New)', style: TextStyle(fontSize: 11)),
                            ],
                          )
                        )
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasPending) IconButton(icon: Icon(Icons.check_circle, color: Colors.green), onPressed: () => _quickApprove(s['code']), tooltip: LocalizationService().currentLanguage == 'vi' ? 'Duyệt thay đổi' : 'Duyet thay doi'),
                      Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
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
                    icon: Icon(Icons.chevron_left), 
                    onPressed: _currentPage > 1 ? () => _fetchData(page: _currentPage - 1) : null,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: isDark ? Colors.blue.withValues(alpha: 0.2) : Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text(LocalizationService().currentLanguage == 'vi' ? 'Trang $_currentPage / $_totalPages' : 'Page $_currentPage / $_totalPages', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  ),
                  IconButton(
                    icon: Icon(Icons.chevron_right), 
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