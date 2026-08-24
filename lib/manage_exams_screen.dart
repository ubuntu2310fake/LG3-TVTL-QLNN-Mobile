import 'localization_service.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'config.dart';

class ManageExamsScreen extends StatefulWidget {
  const ManageExamsScreen({super.key});

  @override
  State<ManageExamsScreen> createState() => _ManageExamsScreenState();
}

class _ManageExamsScreenState extends State<ManageExamsScreen> {
  bool _isLoadingExams = true;
  bool _isUploading = false;
  List<dynamic> _exams = [];
  dynamic _selectedExamId;
  PlatformFile? _selectedFile;
  String _sessionId = '';

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionId = prefs.getString('phpsessid') ?? '';
    _fetchExams();
  }

  Dio _getDio() {
    Dio dio = Dio();
    if (_sessionId.isNotEmpty) dio.options.headers['Cookie'] = 'PHPSESSID=$_sessionId';
    return dio;
  }

  Future<void> _fetchExams() async {
    setState(() => _isLoadingExams = true);
    try {
      final res = await _getDio().get('${AppConfig.baseUrl}/api/manage_exams_api.php?action=list');
      if (res.statusCode == 200 && res.data['status'] == 'success') {
        setState(() {
          _exams = res.data['data'];
          if (_selectedExamId != null && !_exams.any((e) => e['id'].toString() == _selectedExamId.toString())) {
            _selectedExamId = null;
          }
        });
      }
    } catch (e) {
      _showMsg(LocalizationService().currentLanguage == 'vi' ? 'Lỗi tải danh sách: $e' : 'Error loading list: $e', isError: true);
    }
    setState(() => _isLoadingExams = false);
  }

  Future<void> _createExam(String name, String school) async {
    Navigator.pop(context);
    setState(() => _isLoadingExams = true);
    try {
      final res = await _getDio().post(
        '${AppConfig.baseUrl}/api/manage_exams_api.php?action=create',
        data: jsonEncode({'name': name, 'school': school}),
        options: Options(contentType: Headers.jsonContentType),
      );
      if (res.data['status'] == 'success') {
        _showMsg(LocalizationService().currentLanguage == 'vi' ? 'Tạo kỳ thi thành công!' : 'Exam created successfully!');
        _fetchExams();
      } else {
        _showMsg(res.data['msg'], isError: true);
      }
    } catch (e) {
      _showMsg(LocalizationService().currentLanguage == 'vi' ? 'Lỗi kết nối API' : 'API connection error', isError: true);
    }
  }

  // ==========================================
  // BOX XÁC NHẬN XÓA THEO CHUẨN WINUI 3.0 (DART)
  // ==========================================
  Future<void> _deleteExam(dynamic id, String examName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300)
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
              SizedBox(width: 10),
              Expanded(child: Text(LocalizationService().currentLanguage == 'vi' ? 'Xác nhận xóa' : 'Xac nhan xoa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isDark ? Colors.white : Colors.black87))),
            ],
          ),
          content: Text(
            LocalizationService().currentLanguage == 'vi' ? 'Bạn có chắc chắn muốn xóa kỳ thi "$examName"? Toàn bộ điểm số liên quan sẽ bị xóa sạch và KHÔNG THỂ KHÔI PHỤC.' : 'Ban co chac chan muon xoa ky thi "$examName"? Toan bo diem so lien quan se bi xoa sach va KHONG THE KHOI PHUC.', 
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false), 
              child: Text(LocalizationService().currentLanguage == 'vi' ? 'Hủy' : 'Cancel', style: TextStyle(color: Colors.grey))
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
              ),
              onPressed: () => Navigator.pop(ctx, true), 
              child: Text(LocalizationService().currentLanguage == 'vi' ? 'Xóa vĩnh viễn' : 'Xoa vinh vien', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      }
    );

    if (confirm != true) return;

    setState(() => _isLoadingExams = true);
    try {
      await _getDio().get('${AppConfig.baseUrl}/api/manage_exams_api.php?action=delete&id=$id');
      _showMsg(LocalizationService().currentLanguage == 'vi' ? 'Đã xóa kỳ thi $examName!' : 'Da xoa ky thi $examName!');
      _fetchExams();
    } catch (e) {
      _showMsg(LocalizationService().currentLanguage == 'vi' ? 'Lỗi xóa kỳ thi' : 'Error deleting exam', isError: true);
    }
  }

  Future<void> _uploadExcel() async {
    if (_selectedExamId == null || _selectedFile == null) return;
    setState(() => _isUploading = true);
    try {
      FormData formData = FormData.fromMap({
        'exam_id': _selectedExamId,
        'fileScore': await MultipartFile.fromFile(_selectedFile!.path!, filename: _selectedFile!.name),
      });
      final res = await _getDio().post('${AppConfig.baseUrl}/api/import_scores_api.php', data: formData);
      if (res.data['status'] == 'success') {
        _showMsg(LocalizationService().currentLanguage == 'vi' ? 'Nhập và tính điểm thành công!' : 'Scores entered and calculated successfully!');
        setState(() => _selectedFile = null);
      } else {
        _showMsg(res.data['msg'], isError: true);
      }
    } catch (e) {
      _showMsg(LocalizationService().currentLanguage == 'vi' ? 'Lỗi tải file lên VPS' : 'Error uploading file to VPS', isError: true);
    }
    setState(() => _isUploading = false);
  }

  void _showMsg(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: isError ? Colors.red : Colors.green));
  }

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final schoolCtrl = TextEditingController(text: LocalizationService().currentLanguage == 'vi' ? 'THPT Lạng Giang số 3' : 'THPT Lang Giang so 3');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text(LocalizationService().currentLanguage == 'vi' ? 'Tạo Kỳ thi mới' : 'Create New Exam', style: TextStyle(color: Colors.blue)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Tên kỳ thi (VD: Giữa kỳ 1)' : 'Exam Name (e.g. Midterm 1)')),
            SizedBox(height: 10),
            TextField(controller: schoolCtrl, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Tên trường' : 'School Name')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Hủy' : 'Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(onPressed: () => _createExam(nameCtrl.text, schoolCtrl.text), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Tạo mới' : 'Create')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Theme.of(context).scaffoldBackgroundColor : Colors.grey.shade100,
      appBar: AppBar(title: Text(LocalizationService().currentLanguage == 'vi' ? 'Quản lý Kỳ thi & Điểm' : 'Manage Exams & Scores')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: Icon(Icons.add),
        label: Text(LocalizationService().currentLanguage == 'vi' ? 'Tạo kỳ thi' : 'Create exam'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              color: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(LocalizationService().currentLanguage == 'vi' ? 'Nhập điểm từ Excel' : 'Import scores from Excel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
                    SizedBox(height: 16),
                    DropdownButtonFormField<dynamic>(
                      dropdownColor: Theme.of(context).cardColor,
                      decoration: InputDecoration(border: OutlineInputBorder(), labelText: LocalizationService().currentLanguage == 'vi' ? '1. Chọn kỳ thi mục tiêu' : '1. Select target exam'),
                      initialValue: _selectedExamId,
                      items: _exams.map((ex) => DropdownMenuItem(value: ex['id'], child: Text(ex['exam_name']))).toList(),
                      onChanged: (val) => setState(() => _selectedExamId = val),
                    ),
                    SizedBox(height: 16),
                    InkWell(
                      onTap: () async {
                        FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx']);
                        if (result != null) setState(() => _selectedFile = result.files.single);
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          border: Border.all(color: isDark ? Colors.green.shade700 : Colors.green.shade400, width: 2, style: BorderStyle.solid),
                          color: isDark ? Colors.green.withValues(alpha: 0.1) : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.file_upload, size: 40, color: isDark ? Colors.green.shade400 : Colors.green.shade600),
                            SizedBox(height: 8),
                            Text(
                              _selectedFile != null ? _selectedFile!.name : LocalizationService().currentLanguage == 'vi' ? '2. Bấm để chọn file .xlsx' : '2. Tap to select .xlsx file', 
                              style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                        icon: _isUploading ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Icon(Icons.check_circle),
                        label: Text(_isUploading ? LocalizationService().currentLanguage == 'vi' ? 'Đang xử lý DB...' : 'Dang xu ly DB...' : LocalizationService().currentLanguage == 'vi' ? 'Bắt đầu Lưu vào DB' : 'Bat dau Luu vao DB'),
                        onPressed: (_selectedExamId != null && _selectedFile != null && !_isUploading) ? _uploadExcel : null,
                      ),
                    )
                  ],
                ),
              ),
            ),
            SizedBox(height: 20),
            
            // DANH SÁCH KỲ THI
            Card(
              color: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(LocalizationService().currentLanguage == 'vi' ? 'Lịch sử Kỳ thi' : 'Exam History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(height: 10),
                    if (_isLoadingExams) Center(child: CircularProgressIndicator()),
                    if (!_isLoadingExams && _exams.isEmpty) Text(LocalizationService().currentLanguage == 'vi' ? 'Chưa có dữ liệu.' : 'Chua co du lieu.'),
                    if (!_isLoadingExams)
                      ..._exams.map((ex) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(ex['exam_name'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                        subtitle: Text('${ex['school_name']} | ID: ${ex['id']}', style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey)),
                        trailing: IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          // GỌI HÀM XÓA CÓ CONFIRM
                          onPressed: () => _deleteExam(ex['id'], ex['exam_name']),
                        ),
                      )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}