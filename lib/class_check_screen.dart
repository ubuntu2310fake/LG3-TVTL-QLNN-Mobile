import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'widgets/custom_numpad.dart';
import 'localization_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'offline_sync.dart';
import 'offline_queue_service.dart'; // ĐÃ THÊM IMPORT
import 'widgets/liquid_glass_container.dart';
import 'config.dart'; // 👉 THÊM IMPORT NÀY

class ClassCheckScreen extends StatefulWidget {
  const ClassCheckScreen({super.key});

  @override
  State<ClassCheckScreen> createState() => _ClassCheckScreenState();
}

class _ClassCheckScreenState extends State<ClassCheckScreen> {
  String? _selectedClassId;
  final TextEditingController _weekCtrl = TextEditingController(text: '20');
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _bonusCtrl = TextEditingController(text: '0');
  bool _isLoading = false;
  String? _editingCell;
  bool _isDataLoaded = false;
  bool _isFetchingMatrix = false; // Biến cờ hiệu đang tải dữ liệu matrix
  
  List<Map<String, String>> _classes = [];
  List<Map<String, dynamic>> _columns = [];
  final Map<int, Map<String, double>> _scores = {};
  final Map<int, bool> _dayOff = {};
  bool _isHolidayWeek = false;
  List<dynamic> _gateData = []; // Lưu trữ lỗi trực cổng (GATE) để hiện cảnh báo

  @override
  void initState() {
    super.initState();
    _loadLocalData();
  }

  Future<void> _loadLocalData() async {
    final data = await OfflineSyncService.getMasterData();
    if (!mounted) return;
    setState(() {
      // SET TUẦN CHUẨN TỪ SERVER
      if (data['current_week'] != null) {
        _weekCtrl.text = data['current_week'].toString();
      }

      if (data['classes'] != null) {
        _classes = List<Map<String, String>>.from(data['classes'].map((c) => {
          'id': c['id'].toString(), 'name': c['name'].toString()
        }));
      }
      if (data['class_cols'] != null) {
        _columns = List<Map<String, dynamic>>.from(data['class_cols']);
      }
      
      _initDefaultScores();
      _isDataLoaded = true;
    });
  }

  void _initDefaultScores() {
    for (int day in [7, 2, 3, 4, 5, 6]) {
      _scores[day] = {};
      _dayOff[day] = false;
      for (var col in _columns) {
        _scores[day]![col['code']] = (col['max'] as num).toDouble();
      }
    }
    _bonusCtrl.text = '0';
    _noteCtrl.text = '';
    _gateData = [];
    _isHolidayWeek = false;
  }

  // --- THÊM HÀM NÀY ĐỂ TẢI DỮ LIỆU MATRIX TỪ SERVER ---
  Future<void> _loadMatrixData() async {
    if (_selectedClassId == null || _weekCtrl.text.isEmpty) return;

    setState(() {
      _isFetchingMatrix = true;
      _initDefaultScores(); // Reset bảng điểm về mặc định (Max) trước khi nạp dữ liệu mới
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      
      final String url = '${AppConfig.baseUrl}/api/class_check_api.php?action=load_matrix&class_id=$_selectedClassId&week=${_weekCtrl.text}';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {'Cookie': 'PHPSESSID=$sessionId'},
      );

      final data = jsonDecode(response.body);

      if (data['status'] == 'success') {
        setState(() {
          // 1. Điền điểm cộng
          if (data['bonus_score'] != null) {
            _bonusCtrl.text = data['bonus_score'].toString();
          }

          // 2. Điền ghi chú
          if (data['general_note'] != null) {
            _noteCtrl.text = data['general_note'].toString();
          }

          // 3. Đổ dữ liệu điểm đã bị trừ vào bảng
          if (data['saved_scores'] != null) {
            List<dynamic> savedScores = data['saved_scores'];
            for (var scoreInfo in savedScores) {
              int day = int.tryParse(scoreInfo['day'].toString()) ?? 0;
              String code = scoreInfo['code'].toString();
              double deduction = double.tryParse(scoreInfo['deduction'].toString()) ?? 0.0;

              if (_scores.containsKey(day) && _scores[day]!.containsKey(code)) {
                // Tính điểm còn lại = Max - Điểm bị trừ
                double maxPts = (_columns.firstWhere((c) => c['code'] == code)['max'] as num).toDouble();
                double remaining = maxPts - deduction;
                
                // Đảm bảo không bị âm
                if(remaining < 0) remaining = 0;
                
                _scores[day]![code] = remaining;
              }
            }
          }

          // 4. Lưu thông tin cảnh báo trực cổng
          if (data['gate_data'] != null) {
             _gateData = data['gate_data'];
          }

          if (data['is_holiday_week'] == true) {
             _isHolidayWeek = true;
          } else {
             _isHolidayWeek = false;
          }
          
          if (data['day_off'] != null) {
             List<dynamic> dayOffList = data['day_off'];
             for (var d in dayOffList) {
               int dayNum = int.tryParse(d.toString()) ?? 0;
               if (_dayOff.containsKey(dayNum)) _dayOff[dayNum] = true;
             }
          }
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Không thể tải điểm đã lưu (Lỗi mạng)' : 'Cannot load saved points (Network error)'), backgroundColor: Colors.orange));
    } finally {
      if (mounted) setState(() => _isFetchingMatrix = false);
    }
  }

  double _getRowTotal(int day) {
    return _scores[day]!.values.fold(0, (sum, item) => sum + item);
  }

  double _getGrandTotal() {
    double total = 0;
    _scores.forEach((day, cols) => total += cols.values.fold(0, (sum, item) => sum + item));
    return total;
  }

  Future<void> _submitClassCheck() async {
    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Chưa chọn lớp!' : 'No class selected!'))); return;
    }
    setState(() => _isLoading = true);

    List<Map<String, dynamic>> scoresPayload = [];
    _scores.forEach((day, cols) {
      cols.forEach((code, value) {
        double maxPts = (_columns.firstWhere((c) => c['code'] == code)['max'] as num).toDouble();
        double deduction = maxPts - value;
        scoresPayload.add({'day': day.toString(), 'code': code, 'deduction': deduction});
      });
    });

    List<int> dayOffPayload = [];
    _dayOff.forEach((day, isOff) {
      if (isOff) dayOffPayload.add(day);
    });

    final payload = {
      'class_id': _selectedClassId, 'week': _weekCtrl.text,
      'scores': scoresPayload, 'general_note': _noteCtrl.text, 'bonus_score': _bonusCtrl.text,
      'day_off': dayOffPayload
    };

    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/class_check_api.php?action=save_matrix'), 
        headers: { 'Content-Type': 'application/json; charset=UTF-8', 'Cookie': 'PHPSESSID=$sessionId' },
        body: jsonEncode(payload),
      );

      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? '✅ Đã lưu bảng điểm!' : '✅ Scores saved!'), backgroundColor: Colors.green));
      } else { throw Exception(data['msg'] ?? (LocalizationService().currentLanguage == 'vi' ? "Lỗi server" : "Server error")); }
    } catch (e) {
      // FIX OFFLINE: Đẩy vào Queue
      await OfflineQueueService.enqueue(
        url: '${AppConfig.baseUrl}/api/class_check_api.php?action=save_matrix',
        method: 'POST',
        contentType: 'application/json; charset=UTF-8',
        body: payload, // Dart map, service sẽ tự jsonEncode
        title: LocalizationService().currentLanguage == 'vi' ? 'Chấm điểm lớp: $_selectedClassId - Tuần ${_weekCtrl.text}' : 'Cham diem lop: $_selectedClassId - Tuan ${_weekCtrl.text}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? '⚠️ Mất mạng! Đã lưu Offline ngầm.' : '⚠️ Offline! Saved locally.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Colors.orange));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  
  void _showNumpad(BuildContext context, TextEditingController ctrl) {
    setState(() => _editingCell = 'bonus');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CustomNumpad(
        title: LocalizationService().currentLanguage == 'vi' ? 'Điểm cộng (+)' : 'Bonus Points (+)',
        controller: ctrl,
        onSubmit: () => Navigator.pop(context),
      ),
    ).then((_) {
      if (mounted) setState(() => _editingCell = null);
    });
  }

  
  void _showGridNumpad(BuildContext context, int day, String code, double maxPts) {
    setState(() => _editingCell = '${day}_$code');
    String dayName = LocalizationService().currentLanguage == 'vi' ? 'T$day' : {2:'Mon',3:'Tue',4:'Wed',5:'Thu',6:'Fri',7:'Sat'}[day] ?? 'T$day';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CustomNumpad(
        title: '$dayName - $code',
        initialValue: _scores[day]![code].toString(),
        onChanged: (val) {
          setState(() {
            double parsed = double.tryParse(val) ?? 0;
            if (parsed > maxPts) parsed = maxPts;
            if (parsed < 0) parsed = 0;
            _scores[day]![code] = parsed;
          });
        },
        onSubmit: () => Navigator.pop(context),
      ),
    ).then((_) {
      if (mounted) setState(() => _editingCell = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDataLoaded) return Center(child: CircularProgressIndicator());

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.grey)),
                    isDense: true,
                  ),
                  hint: Text(LocalizationService().currentLanguage == 'vi' ? '-- Chọn Lớp --' : '-- Select Class --', style: TextStyle(fontSize: 15)),
                  initialValue: _selectedClassId,
                  items: _classes.map((c) => DropdownMenuItem(value: c['id'], child: Text(c['name']!, style: const TextStyle(fontWeight: FontWeight.w600)))).toList(),
                  onChanged: (val) {
                    setState(() => _selectedClassId = val);
                    _loadMatrixData(); // GỌI HÀM KHI ĐỔI LỚP
                  },
                  dropdownColor: Theme.of(context).colorScheme.surface,
                ),
              ),
              SizedBox(width: 12),
              SizedBox(
                width: 75,
                child: TextField(
                  controller: _weekCtrl,
                  decoration: InputDecoration(
                    labelText: LocalizationService().currentLanguage == 'vi' ? 'Tuần' : 'Week', labelStyle: TextStyle(fontSize: 14),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.grey)),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  onSubmitted: (val) => _loadMatrixData(), // GỌI HÀM KHI NHẬP XONG TUẦN (Bấm Enter trên bàn phím)
                  onChanged: (val) => _loadMatrixData(), // Hoặc khi gõ ký tự
                ),
              ),
            ],
          ),
        ),

        if (_isHolidayWeek)
          LiquidGlassContainer(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.shade200),
            child: Row(children: [Icon(Icons.event_busy, color: Colors.orange, size: 18), SizedBox(width: 8), Expanded(child: Text(LocalizationService().currentLanguage == 'vi' ? 'Tuần này là tuần nghỉ lễ/không tính điểm!' : 'This week is a holiday/no scoring!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)))]),
          ),

        // CẢNH BÁO LỖI TRỰC CỔNG
        if (_gateData.isNotEmpty)
          LiquidGlassContainer(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.shade200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Icon(Icons.warning, color: Colors.red, size: 18), SizedBox(width: 5), Text(LocalizationService().currentLanguage == 'vi' ? 'Cảnh báo từ Đoàn Trường:' : 'Warning from Youth Union:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red))]),
                SizedBox(height: 5),
                ..._gateData.map((g) => Text('• [${g['recorded_violation_name']}] -${g['recorded_points']}', style: const TextStyle(color: Colors.red, fontSize: 13))),
              ],
            ),
          ),

        Expanded(
          child: _isFetchingMatrix 
            ? Center(child: CircularProgressIndicator()) 
            : SingleChildScrollView(
            scrollDirection: Axis.vertical,
            padding: const EdgeInsets.only(bottom: 120), // FIX: Prevent bottom nav overlap
            child: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(Theme.of(context).colorScheme.surfaceContainerHighest),
                    columnSpacing: 16, dataRowMinHeight: 45, dataRowMaxHeight: 45,
                    columns: [
                      DataColumn(label: Text(LocalizationService().currentLanguage == 'vi' ? 'Thứ' : 'Day', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text(LocalizationService().currentLanguage == 'vi' ? 'Nghỉ' : 'Abs', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
                      ..._columns.map((c) => DataColumn(label: Text(c['code'], style: const TextStyle(fontWeight: FontWeight.bold)))),
                      DataColumn(label: Text(LocalizationService().currentLanguage == 'vi' ? 'Tổng' : 'Total', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                    ],
                    rows: [
                      for (int day in [7, 2, 3, 4, 5, 6])
                        DataRow(
                          color: WidgetStateProperty.resolveWith((states) => (_dayOff[day] ?? false) ? Colors.grey.withValues(alpha: 0.1) : null),
                          cells: [
                            DataCell(Text(LocalizationService().currentLanguage == 'vi' ? 'T$day' : {2:'Mon',3:'Tue',4:'Wed',5:'Thu',6:'Fri',7:'Sat'}[day] ?? 'T$day', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataCell(Checkbox(
                                value: _dayOff[day] ?? false,
                                onChanged: (val) {
                                  setState(() => _dayOff[day] = val ?? false);
                                },
                            )),
                            ..._columns.map((c) => DataCell(
                                  SizedBox(
                                    width: 45,
                                    child: TextFormField(
                                      readOnly: true,
                                      onTap: () => _showGridNumpad(context, day, c['code'], (c['max'] as num).toDouble()),
                                      enabled: !(_dayOff[day] ?? false),
                                      key: ValueKey('score_${day}_${c['code']}_${_scores[day]![c['code']]}'),
                                      initialValue: _scores[day]![c['code']].toString(),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: _scores[day]![c['code']]! < (c['max'] as num).toDouble() ? Colors.red : null,
                                        fontWeight: _scores[day]![c['code']]! < (c['max'] as num).toDouble() ? FontWeight.bold : null,
                                      ),
                                      decoration: InputDecoration(border: InputBorder.none, isDense: true, fillColor: _editingCell == '${day}_${c['code']}' ? Colors.blue.withValues(alpha: 0.2) : null, filled: _editingCell == '${day}_${c['code']}'),
                                    ),
                                  ),
                                )),
                            DataCell(Text(_getRowTotal(day).toStringAsFixed(1), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))),
                          ],
                        ),
                    ],
                  ),
                ),
                
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(LocalizationService().currentLanguage == 'vi' ? 'ĐIỂM CỘNG (+):' : 'BONUS POINTS (+):', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                          SizedBox(width: 10),
                          SizedBox(
                            width: 60,
                            child: TextField(
                              readOnly: true, onTap: () => _showNumpad(context, _bonusCtrl), 
                              controller: _bonusCtrl,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                              decoration: InputDecoration(border: const UnderlineInputBorder(), isDense: true, fillColor: _editingCell == 'bonus' ? Colors.blue.withValues(alpha: 0.2) : null, filled: _editingCell == 'bonus'),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(LocalizationService().currentLanguage == 'vi' ? 'TỔNG CUỐI:' : 'FINAL TOTAL:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          SizedBox(width: 10),
                          Text(
                            (_getGrandTotal() + (double.tryParse(_bonusCtrl.text) ?? 0)).toStringAsFixed(1),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Colors.blue),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      TextField(
                        controller: _noteCtrl, maxLines: 3,
                        decoration: InputDecoration(hintText: LocalizationService().currentLanguage == 'vi' ? 'Nhập ghi chú chi tiết lỗi...' : 'Enter violation details...', border: OutlineInputBorder()),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), offset: const Offset(0, -4), blurRadius: 10)]),
          child: SizedBox(
            width: double.infinity, height: 50,
            child: FilledButton.icon(
              onPressed: _isLoading ? null : _submitClassCheck,
              icon: _isLoading ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Icon(Icons.save),
              label: Text(LocalizationService().currentLanguage == 'vi' ? 'LƯU BẢNG ĐIỂM' : 'SAVE SCORES', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        )
      ],
    );
  }
}