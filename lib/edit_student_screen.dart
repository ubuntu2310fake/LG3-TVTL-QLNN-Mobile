import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

class EditStudentScreen extends StatefulWidget {
  final String studentCode;
  const EditStudentScreen({super.key, required this.studentCode});
  @override
  State<EditStudentScreen> createState() => _EditStudentScreenState();
}

class _EditStudentScreenState extends State<EditStudentScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  Map _student = {};
  List _classes = [];
  
  final _nameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  
  int? _classId;
  String _userRole = 'STUDENT';
  int? _standingClassId;
  
  String? _currentImageUrl;
  File? _newImageFile;
  bool _deleteImage = false;

  @override
  void initState() { super.initState(); _fetchData(); }

  Future<void> _fetchData() async {
    final prefs = await SharedPreferences.getInstance();
    final res = await http.get(
      Uri.parse('https://qlnn.testifiyonline.xyz/api/edit_student_api?code=${widget.studentCode}'), 
      headers: {'Cookie': 'PHPSESSID=${prefs.getString('phpsessid')}'}
    );
    final data = jsonDecode(res.body);
    if (data['status'] == 'success') {
      setState(() {
        _student = data['student']; 
        _classes = data['classes'];
        _nameCtrl.text = _student['name']; 
        _dobCtrl.text = _student['dob'] ?? ''; 
        _classId = _student['class_id'];
        _currentImageUrl = _student['image_url'];
        _userRole = data['linked_user']?['role'] ?? 'STUDENT';
        _standingClassId = data['linked_user']?['homeroom_class_id'];
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 80);
    if (pickedFile != null) {
      setState(() { _newImageFile = File(pickedFile.path); _deleteImage = false; });
    }
  }

  Future<void> _handlePending(String action) async {
    final prefs = await SharedPreferences.getInstance();
    await http.post(
      Uri.parse('https://qlnn.testifiyonline.xyz/api/edit_student_api'), 
      headers: {'Cookie': 'PHPSESSID=${prefs.getString('phpsessid')}'}, 
      body: jsonEncode({'action': action, 'id': _student['id']})
    );
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Đã xử lý yêu cầu!'), backgroundColor: Colors.green));
    _fetchData(); // Tải lại data mới
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final prefs = await SharedPreferences.getInstance();
    
    var request = http.MultipartRequest('POST', Uri.parse('https://qlnn.testifiyonline.xyz/api/edit_student_api'));
    request.headers['Cookie'] = 'PHPSESSID=${prefs.getString('phpsessid')}';
    request.headers['X-Requested-With'] = 'XMLHttpRequest'; 
    
    request.fields['action'] = 'update_direct';
    request.fields['id'] = _student['id'].toString();
    request.fields['name'] = _nameCtrl.text;
    request.fields['dob'] = _dobCtrl.text;
    request.fields['class_id'] = _classId.toString();
    request.fields['user_role'] = _userRole;
    request.fields['standing_class_id'] = _standingClassId?.toString() ?? '';
    request.fields['delete_image'] = _deleteImage ? '1' : '0';

    if (_newImageFile != null) {
      request.files.add(await http.MultipartFile.fromPath('image', _newImageFile!.path));
    }

    try {
      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      var data = jsonDecode(responseData);
      
      if (data['status'] == 'success') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${data['msg']}'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Lỗi kết nối!'), backgroundColor: Colors.red));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    bool hasPending = _student['has_pending_changes'] == 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Hồ Sơ Học Sinh', style: TextStyle(fontWeight: FontWeight.bold))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- BOX XỬ LÝ YÊU CẦU THAY ĐỔI ---
            if (hasPending) 
              Container(
                padding: const EdgeInsets.all(16), margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: isDark ? Colors.orange.withOpacity(0.1) : Colors.orange.shade50, 
                  borderRadius: BorderRadius.circular(12), 
                  border: Border.all(color: isDark ? Colors.orange.withOpacity(0.3) : Colors.orange.shade300)
                ), 
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [Icon(Icons.warning_amber, color: Colors.orange), SizedBox(width: 8), Text("Yêu cầu thay đổi", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange))]),
                    const SizedBox(height: 10),
                    Text("Tên mới: ${_student['pending_name'] ?? '---'}\nNgày sinh mới: ${_student['pending_dob'] ?? '---'}"),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: ElevatedButton.icon(onPressed: () => _handlePending('approve_changes'), icon: const Icon(Icons.check), label: const Text('Duyệt'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white))),
                        const SizedBox(width: 10),
                        Expanded(child: OutlinedButton.icon(onPressed: () => _handlePending('reject_changes'), icon: const Icon(Icons.close), label: const Text('Từ chối'), style: OutlinedButton.styleFrom(foregroundColor: Colors.red))),
                      ],
                    )
                  ],
                )
              ),

            // --- KHU VỰC AVATAR ---
            Center(
              child: Stack(
                children: [
                  Container(
                    width: 120, height: 150,
                    decoration: BoxDecoration(
                      border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300), 
                      borderRadius: BorderRadius.circular(12),
                      image: DecorationImage(
                        fit: BoxFit.cover,
                        image: _newImageFile != null ? FileImage(_newImageFile!) as ImageProvider 
                             : (_currentImageUrl != null && !_deleteImage ? NetworkImage('https://qlnn.testifiyonline.xyz/$_currentImageUrl') 
                             : const NetworkImage('https://qlnn.testifiyonline.xyz/static/default.png')),
                      ),
                    ),
                  ),
                  Positioned(bottom: -10, right: -10, child: IconButton(icon: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.camera_alt, color: Colors.white, size: 18)), onPressed: _pickImage)),
                ],
              ),
            ),
            if ((_currentImageUrl != null || _newImageFile != null) && !_deleteImage)
              TextButton.icon(onPressed: () => setState(() { _deleteImage = true; _newImageFile = null; }), icon: const Icon(Icons.delete, color: Colors.red, size: 18), label: const Text('Xóa ảnh', style: TextStyle(color: Colors.red))),
            
            const SizedBox(height: 20),

            // --- THÔNG TIN CƠ BẢN ---
            TextField(controller: TextEditingController(text: _student['code']), decoration: InputDecoration(labelText: 'Mã HS (SBD)', border: const OutlineInputBorder(), filled: true, fillColor: isDark ? Colors.grey[800] : const Color(0xFFF5F5F5)), readOnly: true), const SizedBox(height: 15),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Họ và tên', border: OutlineInputBorder())), const SizedBox(height: 15),
            TextField(controller: _dobCtrl, decoration: const InputDecoration(labelText: 'Ngày sinh (DD/MM/YYYY)', border: OutlineInputBorder())), const SizedBox(height: 15),
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: 'Lớp học', border: OutlineInputBorder()),
              value: _classId, items: _classes.map<DropdownMenuItem<int>>((c) => DropdownMenuItem(value: c['id'], child: Text(c['name']))).toList(),
              onChanged: (v) => setState(() => _classId = v),
            ),
            
            const Divider(height: 40),
            
            // --- PHÂN QUYỀN (CHỈ CÓ NHƯ WEB) ---
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Quyền hạn (User)', border: OutlineInputBorder()),
              value: _userRole, 
              items: const [
                DropdownMenuItem(value: 'STUDENT', child: Text('Học sinh')),
                DropdownMenuItem(value: 'RED_FLAG', child: Text('Cờ đỏ / Lớp trưởng (Được chấm điểm)')),
              ],
              onChanged: (v) => setState(() { _userRole = v!; if (v != 'RED_FLAG') _standingClassId = null; }),
            ),
            const SizedBox(height: 15),
            
            if (_userRole == 'RED_FLAG')
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Đứng lớp (Chỉ dành cho Cờ đỏ)', border: OutlineInputBorder()),
                value: _standingClassId, 
                items: [const DropdownMenuItem<int>(value: null, child: Text('-- Không đứng lớp --'))]..addAll(_classes.map((c) => DropdownMenuItem<int>(value: c['id'], child: Text('Lớp ${c['name']}')))),
                onChanged: (v) => setState(() => _standingClassId = v),
              ),

            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _isSaving ? null : _save, 
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), backgroundColor: Colors.blue, foregroundColor: Colors.white), 
              child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('LƯU THAY ĐỔI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
            ),
          ],
        ),
      ),
    );
  }
}