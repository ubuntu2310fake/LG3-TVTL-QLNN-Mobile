import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class InputAcademicScreen extends StatefulWidget {
  const InputAcademicScreen({super.key});
  @override
  State<InputAcademicScreen> createState() => _InputAcademicScreenState();
}

class _InputAcademicScreenState extends State<InputAcademicScreen> {
  bool _isLoading = true;
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

      final response = await http.get(Uri.parse(url), headers: {'Cookie': 'PHPSESSID=$sessionId'});
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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Không có dữ liệu lớp nào thay đổi để lưu!'), backgroundColor: Colors.orange));
        }
        setState(() => _isSaving = false);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      
      final response = await http.post(
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Đã lưu điểm học tập!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Có lỗi xảy ra!'), backgroundColor: Colors.red));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhập Điểm Học Tập', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          Row(
            children: [
              Text('Tuần ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white70 : Colors.black87)),
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
          const SizedBox(width: 15),
        ],
      ),
      backgroundColor: isDark ? Theme.of(context).colorScheme.background : const Color(0xFFF0F2F5),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            padding: const EdgeInsets.only(bottom: 80, left: 12, right: 12, top: 12),
            itemCount: _classesData.length,
            itemBuilder: (context, index) {
              final c = _classesData[index];
              final cid = c['class_id'];
              return Card(
                color: isDark ? Colors.grey[900] : Colors.white,
                elevation: 1, margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 40, height: 40, alignment: Alignment.center, 
                        decoration: BoxDecoration(color: isDark ? Colors.blue.withOpacity(0.2) : Colors.blue.shade50, shape: BoxShape.circle), 
                        child: Text('${index + 1}', style: TextStyle(color: isDark ? Colors.blue[300] : Colors.blue.shade700, fontWeight: FontWeight.bold))
                      ),
                      const SizedBox(width: 15),
                      Expanded(child: Text(c['class_name'], style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87))),
                      SizedBox(
                        width: 60, 
                        child: TextField(
                          controller: _countCtrls[cid], keyboardType: TextInputType.number, textAlign: TextAlign.center, 
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                          decoration: InputDecoration(
                            labelText: 'Số tiết', labelStyle: TextStyle(color: isDark ? Colors.grey[400] : Colors.black54),
                            contentPadding: const EdgeInsets.all(8), 
                            border: const OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[400]!))
                          )
                        )
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 80, 
                        child: TextField(
                          controller: _scoreCtrls[cid], keyboardType: const TextInputType.numberWithOptions(decimal: true), textAlign: TextAlign.center, 
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                          decoration: InputDecoration(
                            labelText: 'Tổng điểm', labelStyle: TextStyle(color: isDark ? Colors.grey[400] : Colors.black54),
                            contentPadding: const EdgeInsets.all(8), 
                            border: const OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[400]!))
                          )
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
        icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save),
        label: const Text('LƯU ĐIỂM', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white,
      ),
    );
  }
}