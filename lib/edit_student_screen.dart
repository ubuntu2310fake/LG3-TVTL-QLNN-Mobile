import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'localization_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'config.dart';

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
  final _sttCtrl = TextEditingController();
  
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
    final res = await AppConfig.client.get(
      Uri.parse('${AppConfig.baseUrl}/api/edit_student_api?code=${widget.studentCode}'), 
      headers: {'Cookie': 'PHPSESSID=${prefs.getString('phpsessid')}'}
    );
    final data = jsonDecode(res.body);
    if (data['status'] == 'success') {
      setState(() {
        _student = data['student']; 
        _classes = data['classes'];
        _nameCtrl.text = _student['name']; 
        _dobCtrl.text = _student['dob'] ?? ''; 
        _sttCtrl.text = _student['thuylinh']?.toString() ?? '';
        _classId = _student['class_id'];
        _currentImageUrl = _student['image_url'];
        
        // --- ÉP KIỂU AN TOÀN CHO DỮ LIỆU TỪ PHP ---
        _userRole = data['linked_user']?['role'] ?? 'STUDENT';
        var rawStandingId = data['linked_user']?['homeroom_class_id'];
        _standingClassId = rawStandingId != null ? int.tryParse(rawStandingId.toString()) : null;
        
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
    await AppConfig.client.post(
      Uri.parse('${AppConfig.baseUrl}/api/edit_student_api'), 
      headers: {'Cookie': 'PHPSESSID=${prefs.getString('phpsessid')}'}, 
      body: jsonEncode({'action': action, 'id': _student['id']})
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? '✅ Đã xử lý yêu cầu!' : '✅ Request processed!'), backgroundColor: Colors.green));
    _fetchData(); // Tải lại data mới
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final prefs = await SharedPreferences.getInstance();
    
    var request = http.MultipartRequest('POST', Uri.parse('${AppConfig.baseUrl}/api/edit_student_api'));
    request.headers['Cookie'] = 'PHPSESSID=${prefs.getString('phpsessid')}';
    request.headers['X-Requested-With'] = 'XMLHttpRequest'; 
    
    request.fields['action'] = 'update_direct';
    request.fields['id'] = _student['id'].toString();
    request.fields['name'] = _nameCtrl.text;
    request.fields['dob'] = _dobCtrl.text;
    request.fields['thuylinh'] = _sttCtrl.text;
    request.fields['class_id'] = _classId.toString();
    request.fields['user_role'] = _userRole;
    request.fields['standing_class_id'] = _standingClassId?.toString() ?? '';
    request.fields['delete_image'] = _deleteImage ? '1' : '0';

    if (_newImageFile != null) {
      request.files.add(await http.MultipartFile.fromPath('image', _newImageFile!.path));
    }

    try {
      var response = await AppConfig.client.send(request);
      var responseData = await response.stream.bytesToString();
      var data = jsonDecode(responseData);
      
      if (data['status'] == 'success') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? '✅ ${data['msg']}' : '✅ ${data['msg']}'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? '❌ Lỗi kết nối!' : '❌ Connection error!'), backgroundColor: Colors.red));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Scaffold(body: Center(child: CircularProgressIndicator()));
    bool hasPending = _student['has_pending_changes'] == 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text(LocalizationService().currentLanguage == 'vi' ? 'Hồ Sơ Học Sinh' : 'Student Profile', style: TextStyle(fontWeight: FontWeight.bold))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasPending) 
              Container(
                padding: const EdgeInsets.all(16), margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: isDark ? Colors.orange.withValues(alpha: 0.1) : Colors.orange.shade50, 
                  borderRadius: BorderRadius.circular(12), 
                  border: Border.all(color: isDark ? Colors.orange.withValues(alpha: 0.3) : Colors.orange.shade300)
                ), 
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [Icon(Icons.warning_amber, color: Colors.orange), SizedBox(width: 8), Text(LocalizationService().currentLanguage == 'vi' ? "Yêu cầu thay đổi" : "Change Request", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange))]),
                    SizedBox(height: 10),
                    Text(LocalizationService().currentLanguage == 'vi' ? "Tên mới: ${_student['pending_name'] ?? '---'}\nNgày sinh mới: ${_student['pending_dob'] ?? '---'}" : "New name: ${_student['pending_name'] ?? '---'}\nNew DOB: ${_student['pending_dob'] ?? '---'}"),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: ElevatedButton.icon(onPressed: () => _handlePending('approve_changes'), icon: Icon(Icons.check), label: Text(LocalizationService().currentLanguage == 'vi' ? 'Duyệt' : 'Approve'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white))),
                        SizedBox(width: 10),
                        Expanded(child: OutlinedButton.icon(onPressed: () => _handlePending('reject_changes'), icon: Icon(Icons.close), label: Text(LocalizationService().currentLanguage == 'vi' ? 'Từ chối' : 'Reject'), style: OutlinedButton.styleFrom(foregroundColor: Colors.red))),
                      ],
                    )
                  ],
                )
              ),

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
                             : (_currentImageUrl != null && !_deleteImage ? NetworkImage('${AppConfig.baseUrl}/$_currentImageUrl') 
                             : const NetworkImage('${AppConfig.baseUrl}/static/default.png')),
                      ),
                    ),
                  ),
                  Positioned(bottom: -10, right: -10, child: IconButton(icon: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.camera_alt, color: Colors.white, size: 18)), onPressed: _pickImage)),
                ],
              ),
            ),
            if ((_currentImageUrl != null || _newImageFile != null) && !_deleteImage)
              TextButton.icon(onPressed: () => setState(() { _deleteImage = true; _newImageFile = null; }), icon: Icon(Icons.delete, color: Colors.red, size: 18), label: Text(LocalizationService().currentLanguage == 'vi' ? 'Xóa ảnh' : 'Delete Image', style: TextStyle(color: Colors.red))),
            
            SizedBox(height: 20),

            TextField(controller: TextEditingController(text: _student['code']), decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Mã HS (SBD)' : 'Student Code (ID)', border: OutlineInputBorder(), filled: true, fillColor: isDark ? Colors.grey[800] : Color(0xFFF5F5F5)), readOnly: true), SizedBox(height: 15),
            TextField(controller: _sttCtrl, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'STT trong lớp (Tùy chọn)' : 'Class Order (Optional)', border: OutlineInputBorder()), keyboardType: TextInputType.number), SizedBox(height: 15),
            TextField(controller: _nameCtrl, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Họ và tên' : 'Full Name', border: OutlineInputBorder())), SizedBox(height: 15),
            TextField(controller: _dobCtrl, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Ngày sinh (DD/MM/YYYY)' : 'Date of Birth (DD/MM/YYYY)', border: OutlineInputBorder())), SizedBox(height: 15),
            DropdownButtonFormField<int>(
              decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Lớp học' : 'Class', border: OutlineInputBorder()),
              initialValue: _classId, items: _classes.map<DropdownMenuItem<int>>((c) => DropdownMenuItem(value: c['id'], child: Text(c['name']))).toList(),
              onChanged: (v) => setState(() => _classId = v),
            ),
            
            const Divider(height: 40),
            
            DropdownButtonFormField<String>(
              decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Quyền hạn (User)' : 'Role (User)', border: OutlineInputBorder()),
              initialValue: _userRole, 
              items: [
                DropdownMenuItem(value: 'STUDENT', child: Text(LocalizationService().currentLanguage == 'vi' ? 'Học sinh' : 'Students')),
                DropdownMenuItem(value: 'RED_FLAG', child: Text(LocalizationService().currentLanguage == 'vi' ? 'Cờ đỏ / Lớp trưởng (Được chấm điểm)' : 'Red Flag / Monitor (Can Grade)')),
              ],
              onChanged: (v) => setState(() { _userRole = v!; if (v != 'RED_FLAG') _standingClassId = null; }),
            ),
            SizedBox(height: 15),
            
            if (_userRole == 'RED_FLAG')
              DropdownButtonFormField<int>(
                decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Đứng lớp (Chỉ dành cho Cờ đỏ)' : 'Assigned Class (For Red Flag Only)', border: OutlineInputBorder()),
                initialValue: _standingClassId, 
                items: [DropdownMenuItem<int>(value: null, child: Text(LocalizationService().currentLanguage == 'vi' ? '-- Không đứng lớp --' : '-- Not assigned --')), ..._classes.map((c) => DropdownMenuItem<int>(value: c['id'], child: Text(LocalizationService().currentLanguage == 'vi' ? 'Lớp ${c["name"]}' : 'Class ${c["name"]}')))],
                onChanged: (v) => setState(() => _standingClassId = v),
              ),

            SizedBox(height: 30),
            ElevatedButton(
              onPressed: _isSaving ? null : _save, 
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), backgroundColor: Colors.blue, foregroundColor: Colors.white), 
              child: _isSaving ? CircularProgressIndicator(color: Colors.white) : Text(LocalizationService().currentLanguage == 'vi' ? 'LƯU THAY ĐỔI' : 'SAVE CHANGES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
            ),
          ],
        ),
      ),
    );
  }
}