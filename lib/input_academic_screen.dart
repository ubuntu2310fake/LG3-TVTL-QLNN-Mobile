import 'localization_service.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'widgets/custom_numpad.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/liquid_glass_container.dart';
import 'config.dart';

class InputAcademicScreen extends StatefulWidget {
  const InputAcademicScreen({super.key});
  @override
  State<InputAcademicScreen> createState() => _InputAcademicScreenState();
}

class _InputAcademicScreenState extends State<InputAcademicScreen> {
  bool _isLoading = true;
  String? _editingCell;
  bool _isSaving = false;
  String _week = '';
  List<dynamic> _classesData = [];
  
  final Map<int, TextEditingController> _scoreCtrls = {};
  final Map<int, TextEditingController> _countCtrls = {};

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
      String url = '${AppConfig.baseUrl}/api/input_academic_api';
      if (_week.isNotEmpty) url += '?week=$_week';

      final response = await AppConfig.client.get(Uri.parse(url), headers: {'Cookie': 'PHPSESSID=$sessionId'});
      final data = jsonDecode(response.body);

      if (data['status'] == 'success') {
        _classesData = data['data'];
        if (_week.isEmpty) _week = data['current_week'].toString();
        
        for (var c in _classesData) {
          int cid = c['class_id'];
          // FIX 1: Chống null crash an toàn tuyệt đối
          var score = c['score'];
          var count = c['count'];
          _scoreCtrls[cid] = TextEditingController(text: (score == null || score == 0) ? '' : score.toString());
          _countCtrls[cid] = TextEditingController(text: (count == null || count == 0) ? '' : count.toString());
        }
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveData() async {
    setState(() => _isSaving = true);
    try {
      List<Map<String, dynamic>> scoresToSave = [];
      bool hasChanges = false;
      for (var c in _classesData) {
        int cid = c['class_id'];
        
        // FIX 2: Xử lý thay thế dấu phẩy thành dấu chấm trước khi Parse. Dùng tryParse chống crash.
        String rawScore = _scoreCtrls[cid]!.text.replaceAll(',', '.').trim();
        String rawCount = _countCtrls[cid]!.text.trim();
        
        double currentScore = rawScore.isEmpty ? 0 : (double.tryParse(rawScore) ?? 0);
        int currentCount = rawCount.isEmpty ? 0 : (int.tryParse(rawCount) ?? 0);
        
        double oldScore = c['score'] == null ? 0 : (c['score'] as num).toDouble();
        int oldCount = c['count'] ?? 0;

        // Chỉ lưu nếu có sai khác
        if ((currentScore - oldScore).abs() > 0.001 || currentCount != oldCount) {
          scoresToSave.add({
            'class_id': cid,
            'score': currentScore,
            'count': currentCount,
          });
          hasChanges = true;
        }
      }

      if (!hasChanges) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? '⚠️ Không có dữ liệu lớp nào thay đổi để lưu!' : '⚠️ Khong co du lieu lop nao thay doi de luu!'), backgroundColor: Colors.orange));
        }
        setState(() => _isSaving = false);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      
      final response = await AppConfig.client.post(
        Uri.parse('${AppConfig.baseUrl}/api/input_academic_api'),
        headers: {'Cookie': 'PHPSESSID=$sessionId', 'Content-Type': 'application/json'},
        body: jsonEncode({'week': _week, 'scores': scoresToSave}),
      );

      final data = jsonDecode(response.body);
      if (data['status'] == 'success' && mounted) {
        for (var saved in scoresToSave) {
          var c = _classesData.firstWhere((element) => element['class_id'] == saved['class_id']);
          c['score'] = saved['score'];
          c['count'] = saved['count'];
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? '✅ Đã lưu điểm học tập!' : '✅ Da luu diem hoc tap!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? '❌ Có lỗi xảy ra!' : '❌ An error occurred!'), backgroundColor: Colors.red));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  
  void _showNumpad(BuildContext context, TextEditingController ctrl, String cellId, String title) {
    setState(() => _editingCell = cellId);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CustomNumpad(
        title: title,
        controller: ctrl,
        onSubmit: () => Navigator.pop(context),
      ),
    ).then((_) {
      if (mounted) setState(() => _editingCell = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(LocalizationService().currentLanguage == 'vi' ? 'Nhập Điểm Học Tập' : 'Input Academic Scores', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          Row(
            children: [
              Text(LocalizationService().currentLanguage == 'vi' ? 'Tuần ' : 'Week ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white70 : Colors.black87)),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  // Fix màu nền Dropbox theo chế độ sáng/tối
                  dropdownColor: isDark ? Colors.grey[850] : Colors.white, 
                  iconEnabledColor: isDark ? Colors.blue[300] : Theme.of(context).colorScheme.primary,
                  style: TextStyle(color: isDark ? Colors.blue[300] : Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16),
                  value: _week.isEmpty ? null : _week,
                  items: List.generate(35, (i) => DropdownMenuItem(
                    value: (i+1).toString(), 
                    child: Text('${i+1}', style: TextStyle(color: isDark ? Colors.white : Colors.black87)) // Fix màu chữ item
                  )),
                  onChanged: (v) { setState(() => _week = v!); _fetchData(); },
                ),
              ),
            ],
          ),
          SizedBox(width: 15),
        ],
      ),
      backgroundColor: isDark ? Theme.of(context).colorScheme.surface : const Color(0xFFF0F2F5),
      body: _isLoading 
        ? Center(child: CircularProgressIndicator())
        : ListView.builder(
            padding: const EdgeInsets.only(bottom: 80, left: 12, right: 12, top: 12),
            itemCount: _classesData.length,
            itemBuilder: (context, index) {
              final c = _classesData[index];
              final cid = c['class_id'];
              return LiquidGlassContainer(
                margin: const EdgeInsets.only(bottom: 8),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 40, height: 40, alignment: Alignment.center, 
                        decoration: BoxDecoration(color: isDark ? Colors.blue.withValues(alpha: 0.2) : Colors.blue.shade50, shape: BoxShape.circle), 
                        child: Text('${index + 1}', style: TextStyle(color: isDark ? Colors.blue[300] : Colors.blue.shade700, fontWeight: FontWeight.bold))
                      ),
                      SizedBox(width: 15),
                      Expanded(child: Text(c['class_name'], style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87))),
                      SizedBox(
                        width: 60,
                        child: TextField(
                          readOnly: true, onTap: () => _showNumpad(context, _countCtrls[cid]!, '${cid}_count', '${c['class_name']} - ${LocalizationService().currentLanguage == 'vi' ? 'Số tiết' : 'Periods'}'), 
                          controller: _countCtrls[cid], textAlign: TextAlign.center, 
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                          decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Số tiết' : 'Periods', labelStyle: TextStyle(color: isDark ? Colors.grey[400] : Colors.black54), contentPadding: const EdgeInsets.all(8), border: const OutlineInputBorder(), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[400]!)), fillColor: _editingCell == '${cid}_count' ? Colors.blue.withValues(alpha: 0.2) : null, filled: _editingCell == '${cid}_count')
                        )
                      ),
                      SizedBox(width: 10),
                      SizedBox(
                        width: 80, 
                        child: TextField(
                          readOnly: true, onTap: () => _showNumpad(context, _scoreCtrls[cid]!, '${cid}_score', '${c['class_name']} - ${LocalizationService().currentLanguage == 'vi' ? 'Tổng điểm' : 'Total Score'}'), 
                          controller: _scoreCtrls[cid], textAlign: TextAlign.center, 
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                          decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Tổng điểm' : 'Total Score', labelStyle: TextStyle(color: isDark ? Colors.grey[400] : Colors.black54), contentPadding: const EdgeInsets.all(8), border: const OutlineInputBorder(), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[400]!)), fillColor: _editingCell == '${cid}_score' ? Colors.blue.withValues(alpha: 0.2) : null, filled: _editingCell == '${cid}_score')
                        )
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSaving ? null : _saveData,
        icon: _isSaving ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Icon(Icons.save),
        label: Text(LocalizationService().currentLanguage == 'vi' ? 'LƯU ĐIỂM' : 'SAVE SCORES', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white,
      ),
    );
  }
}