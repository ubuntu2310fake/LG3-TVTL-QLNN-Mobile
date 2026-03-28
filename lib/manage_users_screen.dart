import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
    final res = await http.get(Uri.parse('https://qlnn.testifiyonline.xyz/api/manage_users_api'), headers: {'Cookie': 'PHPSESSID=${prefs.getString('phpsessid')}'});
    final data = jsonDecode(res.body);
    if (data['status'] == 'success') setState(() { _users = data['users']; _classes = data['classes']; _isLoading = false; });
  }

  void _assignClass(int userId, String userName, int? currentClassId) {
    int? selectedClass = currentClassId;
    showDialog(context: context, builder: (c) => AlertDialog(
      title: Text('Phân công $userName'),
      content: DropdownButtonFormField<int>(
        value: selectedClass,
        decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Chọn Lớp Chủ Nhiệm'),
        items: [
          const DropdownMenuItem<int>(value: null, child: Text('-- Không đứng lớp --')),
          ..._classes.map<DropdownMenuItem<int>>((cl) => DropdownMenuItem(value: cl['id'], child: Text(cl['name'])))
        ],
        onChanged: (v) => selectedClass = v,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Hủy')),
        FilledButton(onPressed: () async {
          Navigator.pop(c);
          final prefs = await SharedPreferences.getInstance();
          final res = await http.post(Uri.parse('https://qlnn.testifiyonline.xyz/api/manage_users_api'), headers: {'Cookie': 'PHPSESSID=${prefs.getString('phpsessid')}'}, body: jsonEncode({'action': 'assign_homeroom', 'user_id': userId, 'class_id': selectedClass ?? ''}));
          final data = jsonDecode(res.body);
          if (data['status'] == 'success') {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${data['msg']}'), backgroundColor: Colors.green));
            _fetchData();
          }
        }, child: const Text('Lưu')),
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
        title: const Text('Tạo Tài Khoản Mới'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: userCtrl, decoration: const InputDecoration(labelText: 'Tên đăng nhập (*)', border: OutlineInputBorder())), const SizedBox(height: 10),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Họ và tên (*)', border: OutlineInputBorder())), const SizedBox(height: 10),
              TextField(controller: passCtrl, decoration: const InputDecoration(labelText: 'Mật khẩu (*)', border: OutlineInputBorder()), obscureText: true), const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: role, decoration: const InputDecoration(labelText: 'Quyền hạn', border: OutlineInputBorder()),
                items: const [DropdownMenuItem(value: 'TEACHER', child: Text('Giáo Viên')), DropdownMenuItem(value: 'ADMIN', child: Text('Quản Trị Viên'))],
                onChanged: (v) => setStateSB(() => role = v!),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Hủy')),
          FilledButton(onPressed: () async {
            if (userCtrl.text.isEmpty || passCtrl.text.isEmpty || nameCtrl.text.isEmpty) return;
            Navigator.pop(c);
            final prefs = await SharedPreferences.getInstance();
            final res = await http.post(Uri.parse('https://qlnn.testifiyonline.xyz/api/manage_users_api'), headers: {'Cookie': 'PHPSESSID=${prefs.getString('phpsessid')}'}, body: jsonEncode({'action': 'create', 'username': userCtrl.text, 'password': passCtrl.text, 'full_name': nameCtrl.text, 'role': role}));
            final data = jsonDecode(res.body);
            if (data['status'] == 'success') {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${data['msg']}'), backgroundColor: Colors.green));
              _fetchData();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ ${data['msg']}'), backgroundColor: Colors.red));
            }
          }, child: const Text('Tạo mới')),
        ],
      )
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quản Lý Người Dùng', style: TextStyle(fontWeight: FontWeight.bold))),
      // THÊM NÚT TẠO USER Ở ĐÂY
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateUserDialog,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
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
            subtitle: Text("@${u['username']} - ${u['role']}\nLớp: ${u['class_name'] ?? 'Không'}"),
            isThreeLine: true,
            trailing: IconButton(icon: const Icon(Icons.edit_note, color: Colors.blue), onPressed: () => _assignClass(u['id'], u['full_name'] ?? u['username'], u['homeroom_class_id'])),
          ));
        },
      ),
    );
  }
}