import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'offline_sync.dart';

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
  bool _isDataLoaded = false;
  bool _isFetchingMatrix = false; // Biến cờ hiệu đang tải dữ liệu matrix
  
  List<Map<String, String>> _classes = [];
  List<Map<String, dynamic>> _columns = [];
  final Map<int, Map<String, double>> _scores = {};
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
    for (int day = 2; day <= 7; day++) {
      _scores[day] = {};
      for (var col in _columns) {
        _scores[day]![col['code']] = (col['max'] as num).toDouble();
      }
    }
    _bonusCtrl.text = '0';
    _noteCtrl.text = '';
    _gateData = [];
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
      
      final String url = 'https://qlnn.testifiyonline.xyz/class_check.php?action=load_matrix&class_id=$_selectedClassId&week=${_weekCtrl.text}';
      
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
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể tải điểm đã lưu (Lỗi mạng)'), backgroundColor: Colors.orange));
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chưa chọn lớp!'))); return;
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

    final payload = {
      'class_id': _selectedClassId, 'week': _weekCtrl.text,
      'scores': scoresPayload, 'general_note': _noteCtrl.text, 'bonus_score': _bonusCtrl.text
    };

    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';

      final response = await http.post(
        Uri.parse('https://qlnn.testifiyonline.xyz/class_check.php?action=save_matrix'), // FIX URL (Thiếu .php)
        headers: { 'Content-Type': 'application/json; charset=UTF-8', 'Cookie': 'PHPSESSID=$sessionId' },
        body: jsonEncode(payload),
      );

      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Đã lưu bảng điểm!'), backgroundColor: Colors.green));
      } else { throw Exception(data['msg'] ?? "Lỗi server"); }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Lỗi kết nối!'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDataLoaded) return const Center(child: CircularProgressIndicator());

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
                  hint: const Text('-- Chọn Lớp --', style: TextStyle(fontSize: 15)),
                  value: _selectedClassId,
                  items: _classes.map((c) => DropdownMenuItem(value: c['id'], child: Text(c['name']!, style: const TextStyle(fontWeight: FontWeight.w600)))).toList(),
                  onChanged: (val) {
                    setState(() => _selectedClassId = val);
                    _loadMatrixData(); // GỌI HÀM KHI ĐỔI LỚP
                  },
                  dropdownColor: Theme.of(context).colorScheme.surface,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 75,
                child: TextField(
                  controller: _weekCtrl,
                  decoration: InputDecoration(
                    labelText: 'Tuần', labelStyle: const TextStyle(fontSize: 14),
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

        // CẢNH BÁO LỖI TRỰC CỔNG
        if (_gateData.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade200)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [Icon(Icons.warning, color: Colors.red, size: 18), SizedBox(width: 5), Text('Cảnh báo từ Đoàn Trường:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red))]),
                const SizedBox(height: 5),
                ..._gateData.map((g) => Text('• [${g['recorded_violation_name']}] -${g['recorded_points']}', style: const TextStyle(color: Colors.red, fontSize: 13))),
              ],
            ),
          ),

        Expanded(
          child: _isFetchingMatrix 
            ? const Center(child: CircularProgressIndicator()) 
            : SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(Theme.of(context).colorScheme.surfaceContainerHighest),
                    columnSpacing: 16, dataRowMinHeight: 45, dataRowMaxHeight: 45,
                    columns: [
                      const DataColumn(label: Text('Thứ', style: TextStyle(fontWeight: FontWeight.bold))),
                      ..._columns.map((c) => DataColumn(label: Text(c['code'], style: const TextStyle(fontWeight: FontWeight.bold)))),
                      const DataColumn(label: Text('Tổng', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                    ],
                    rows: [
                      for (int day = 2; day <= 7; day++)
                        DataRow(
                          cells: [
                            DataCell(Text('T$day', style: const TextStyle(fontWeight: FontWeight.bold))),
                            ..._columns.map((c) => DataCell(
                                  SizedBox(
                                    width: 45,
                                    child: TextFormField(
                                      // Sử dụng thuộc tính key để ép Flutter vẽ lại widget khi đổi giá trị từ server
                                      key: ValueKey('score_${day}_${c['code']}_${_scores[day]![c['code']]}'),
                                      initialValue: _scores[day]![c['code']].toString(),
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: _scores[day]![c['code']]! < (c['max'] as num).toDouble() ? Colors.red : null,
                                        fontWeight: _scores[day]![c['code']]! < (c['max'] as num).toDouble() ? FontWeight.bold : null,
                                      ),
                                      onChanged: (val) {
                                        setState(() {
                                          double parsed = double.tryParse(val) ?? 0;
                                          double maxPts = (c['max'] as num).toDouble();
                                          if (parsed > maxPts) parsed = maxPts;
                                          if (parsed < 0) parsed = 0;
                                          _scores[day]![c['code']] = parsed;
                                        });
                                      },
                                      decoration: const InputDecoration(border: InputBorder.none, isDense: true),
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
                          const Text('ĐIỂM CỘNG (+):', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 60,
                            child: TextField(
                              controller: _bonusCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                              decoration: const InputDecoration(border: UnderlineInputBorder(), isDense: true),
                              onChanged: (val) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Text('TỔNG CUỐI:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(width: 10),
                          Text(
                            (_getGrandTotal() + (double.tryParse(_bonusCtrl.text) ?? 0)).toStringAsFixed(1),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Colors.blue),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _noteCtrl, maxLines: 3,
                        decoration: const InputDecoration(hintText: 'Nhập ghi chú chi tiết lỗi...', border: OutlineInputBorder()),
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
          decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(0, -4), blurRadius: 10)]),
          child: SizedBox(
            width: double.infinity, height: 50,
            child: FilledButton.icon(
              onPressed: _isLoading ? null : _submitClassCheck,
              icon: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save),
              label: const Text('LƯU BẢNG ĐIỂM', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        )
      ],
    );
  }
}