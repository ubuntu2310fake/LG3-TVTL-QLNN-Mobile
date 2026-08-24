import 'localization_service.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});
  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  bool _isLoading = true;
  List _users = [];
  List _classes = [];

  @override
  void initState() { super.initState(); _fetchData(); }

  Future<void> _fetchData() async {
    final prefs = await SharedPreferences.getInstance();
    final res = await http.get(Uri.parse('${AppConfig.baseUrl}/api/manage_users_api'), headers: {'Cookie': 'PHPSESSID=${prefs.getString('phpsessid')}'});
    final data = jsonDecode(res.body);
    if (data['status'] == 'success') setState(() { _users = data['users']; _classes = data['classes']; _isLoading = false; });
  }

  void _assignClass(int userId, String userName, int? currentClassId) {
    int? selectedClass = currentClassId;
    showDialog(context: context, builder: (c) => AlertDialog(
      title: Text(LocalizationService().currentLanguage == 'vi' ? 'Phân công $userName' : 'Assign $userName'),
      content: DropdownButtonFormField<int>(
        initialValue: selectedClass,
        decoration: InputDecoration(border: OutlineInputBorder(), labelText: LocalizationService().currentLanguage == 'vi' ? 'Chọn Lớp Chủ Nhiệm' : 'Select Homeroom Class'),
        items: [
          DropdownMenuItem<int>(value: null, child: Text(LocalizationService().currentLanguage == 'vi' ? '-- Không đứng lớp --' : '-- No class --')),
          ..._classes.map<DropdownMenuItem<int>>((cl) => DropdownMenuItem(value: cl['id'], child: Text(cl['name'])))
        ],
        onChanged: (v) => selectedClass = v,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Hủy' : 'Cancel')),
        FilledButton(onPressed: () async {
          Navigator.pop(c);
          final prefs = await SharedPreferences.getInstance();
          final res = await http.post(Uri.parse('${AppConfig.baseUrl}/api/manage_users_api'), headers: {'Cookie': 'PHPSESSID=${prefs.getString('phpsessid')}'}, body: jsonEncode({'action': 'assign_homeroom', 'user_id': userId, 'class_id': selectedClass ?? ''}));
          final data = jsonDecode(res.body);
          if (data['status'] == 'success') {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${data['msg']}'), backgroundColor: Colors.green));
            _fetchData();
          }
        }, child: Text(LocalizationService().currentLanguage == 'vi' ? 'Lưu' : 'Save')),
      ],
    ));
  }

  void _showCreateUserDialog() {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String role = 'TEACHER';

    showDialog(context: context, builder: (c) => StatefulBuilder(
      builder: (context, setStateSB) => AlertDialog(
        title: Text(LocalizationService().currentLanguage == 'vi' ? 'Tạo Tài Khoản Mới' : 'Create New Account'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: userCtrl, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Tên đăng nhập (*)' : 'Username (*)', border: OutlineInputBorder())), SizedBox(height: 10),
              TextField(controller: nameCtrl, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Họ và tên (*)' : 'Full Name (*)', border: OutlineInputBorder())), SizedBox(height: 10),
              TextField(controller: passCtrl, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Mật khẩu (*)' : 'Password (*)', border: OutlineInputBorder()), obscureText: true), SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: role, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Quyền hạn' : 'Role / Permissions', border: OutlineInputBorder()),
                items: [DropdownMenuItem(value: 'TEACHER', child: Text(LocalizationService().currentLanguage == 'vi' ? 'Giáo Viên' : 'Teacher')), DropdownMenuItem(value: 'ADMIN', child: Text(LocalizationService().currentLanguage == 'vi' ? 'Quản Trị Viên' : 'Administrator'))],
                onChanged: (v) => setStateSB(() => role = v!),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Hủy' : 'Cancel')),
          FilledButton(onPressed: () async {
            if (userCtrl.text.isEmpty || passCtrl.text.isEmpty || nameCtrl.text.isEmpty) return;
            Navigator.pop(c);
            final prefs = await SharedPreferences.getInstance();
            final res = await http.post(Uri.parse('${AppConfig.baseUrl}/api/manage_users_api'), headers: {'Cookie': 'PHPSESSID=${prefs.getString('phpsessid')}'}, body: jsonEncode({'action': 'create', 'username': userCtrl.text, 'password': passCtrl.text, 'full_name': nameCtrl.text, 'role': role}));
            final data = jsonDecode(res.body);
            if (data['status'] == 'success') {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${data['msg']}'), backgroundColor: Colors.green));
              _fetchData();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ ${data['msg']}'), backgroundColor: Colors.red));
            }
          }, child: Text(LocalizationService().currentLanguage == 'vi' ? 'Tạo mới' : 'Create')),
        ],
      )
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(LocalizationService().currentLanguage == 'vi' ? 'Quản Lý Người Dùng' : 'Manage Users', style: TextStyle(fontWeight: FontWeight.bold))),
      // THÊM NÚT TẠO USER Ở ĐÂY
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateUserDialog,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(Icons.person_add, color: Colors.white),
      ),
      body: _isLoading ? Center(child: CircularProgressIndicator()) : ListView.builder(
        padding: const EdgeInsets.only(bottom: 80), // Cách nút dấu cộng
        itemCount: _users.length,
        itemBuilder: (c, i) {
          final u = _users[i];
          return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: ListTile(
            leading: CircleAvatar(
              backgroundColor: u['role'] == 'ADMIN' ? Colors.red.shade100 : Colors.blue.shade100,
              child: Icon(u['role'] == 'ADMIN' ? Icons.admin_panel_settings : Icons.school, color: u['role'] == 'ADMIN' ? Colors.red : Colors.blue),
            ),
            title: Text(u['full_name'] ?? '---', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(LocalizationService().currentLanguage == 'vi' ? "@${u['username']} - ${u['role']}\nLớp: ${u['class_name'] ?? 'Không'}" : "@${u['username']} - ${u['role']}\nClass: ${u['class_name'] ?? 'None'}"),
            isThreeLine: true,
            trailing: IconButton(icon: Icon(Icons.edit_note, color: Colors.blue), onPressed: () => _assignClass(u['id'], u['full_name'] ?? u['username'], u['homeroom_class_id'])),
          ));
        },
      ),
    );
  }
}