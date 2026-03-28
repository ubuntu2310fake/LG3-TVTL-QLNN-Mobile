import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'offline_sync.dart';

class GateCheckScreen extends StatefulWidget {
  const GateCheckScreen({super.key});

  @override
  State<GateCheckScreen> createState() => _GateCheckScreenState();
}

class _GateCheckScreenState extends State<GateCheckScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _weekCtrl = TextEditingController(text: '20');
  
  Map<String, dynamic>? _selectedStudent;
  bool _isScanning = false;
  bool _isLoading = false;
  
  // Biến cho tính năng Chấm Bù
  bool _isCustomTime = false;
  DateTime? _customDateTime;

  final Set<int> _selectedViolations = {};
  
  List<dynamic> _offlineStudents = [];
  List<Map<String, dynamic>> _violations = [];
  List<dynamic> _searchResults = [];
  
  // BIẾN CHO CHỨC NĂNG CHỌN LỚP
  List<String> _classes = [];
  String? _selectedClassFilter;
  List<dynamic> _classStudents = [];
  
  // Lưu lịch sử vừa chấm
  List<Map<String, dynamic>> _historyList = [];

  @override
  void initState() {
    super.initState();
    _loadLocalData(); 
  }

  Future<void> _loadLocalData() async {
    final data = await OfflineSyncService.getMasterData();
    if (!mounted) return;
    setState(() {
      if (data['current_week'] != null) {
        _weekCtrl.text = data['current_week'].toString();
      }
      _offlineStudents = data['students'] ?? [];
      
      // Trích xuất danh sách lớp tự động và SẮP XẾP THEO HỆ SỐ TỰ NHIÊN
      Set<String> classNames = {};
      for (var s in _offlineStudents) {
        if (s['class_name'] != null) {
          classNames.add(s['class_name'].toString());
        }
      }
      
      // THUẬT TOÁN NATURAL SORT (10A2 đứng trước 10A10)
      _classes = classNames.toList()..sort((a, b) {
        final RegExp regExp = RegExp(r'(\d+)|([^\d]+)');
        final matchesA = regExp.allMatches(a).map((m) => m.group(0)!).toList();
        final matchesB = regExp.allMatches(b).map((m) => m.group(0)!).toList();

        for (int i = 0; i < matchesA.length && i < matchesB.length; i++) {
          final partA = matchesA[i];
          final partB = matchesB[i];

          final numA = int.tryParse(partA);
          final numB = int.tryParse(partB);

          if (numA != null && numB != null) {
            final cmp = numA.compareTo(numB);
            if (cmp != 0) return cmp;
          } else {
            final cmp = partA.compareTo(partB);
            if (cmp != 0) return cmp;
          }
        }
        return matchesA.length.compareTo(matchesB.length);
      });

      if (data['gate_violations'] != null) {
        _violations = List<Map<String, dynamic>>.from(data['gate_violations'].map((v) => {
          'id': v['id'], 'name': v['name'], 'points': v['points']
        }));
      }
    });
  }

  Future<void> _handleSync() async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đang tải dữ liệu từ máy chủ LG3...')));
    final success = await OfflineSyncService.syncData();
    if (success) {
      await _loadLocalData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Đã đồng bộ thành công!'), backgroundColor: Colors.green));
    }
  }

  void _searchLocal(String query) {
    if (query.isEmpty) { setState(() => _searchResults = []); return; }
    final q = query.toLowerCase();
    setState(() {
      _searchResults = _offlineStudents.where((s) {
        return s['name'].toString().toLowerCase().contains(q) || s['code'].toString().toLowerCase().contains(q);
      }).toList();
      
      _selectedClassFilter = null;
      _classStudents = [];
    });
  }

  Future<void> _pickCustomTime() async {
    final date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    setState(() {
      _customDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submitViolation() async {
    if (_selectedStudent == null || _selectedViolations.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';

      var request = http.Request('POST', Uri.parse('https://qlnn.testifiyonline.xyz/gate_check'));
      request.headers['Cookie'] = 'PHPSESSID=$sessionId';
      request.headers['Content-Type'] = 'application/x-www-form-urlencoded';

      List<String> bodyParts = [
        'student_id=${_selectedStudent!['id']}',
        'week=${_weekCtrl.text}',
        'other_note=${Uri.encodeQueryComponent(_noteCtrl.text)}',
      ];

      if (_isCustomTime && _customDateTime != null) {
        String f(int n) => n.toString().padLeft(2, '0');
        String timeStr = '${_customDateTime!.year}-${f(_customDateTime!.month)}-${f(_customDateTime!.day)} ${f(_customDateTime!.hour)}:${f(_customDateTime!.minute)}:00';
        bodyParts.add('custom_time=${Uri.encodeQueryComponent(timeStr)}');
      }

      for (var vid in _selectedViolations) { 
        bodyParts.add('violation_ids[]=$vid'); 
      }
      
      request.body = bodyParts.join('&');

      var response = await http.Client().send(request);
      var responseData = await response.stream.bytesToString();
      var data = jsonDecode(responseData);

      if (response.statusCode == 200 && data['status'] == 'success') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Đã lưu thành công!'), backgroundColor: Colors.green));
        setState(() {
          if (data['new_data'] != null) {
            _historyList.insertAll(0, List<Map<String, dynamic>>.from(data['new_data']));
          }
          _selectedStudent = null; _selectedViolations.clear(); _noteCtrl.clear();
          _selectedClassFilter = null; _classStudents.clear();
        });
      } else { throw Exception(data['msg'] ?? "Lỗi server"); }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Lỗi kết nối!'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteRecord(dynamic id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xác nhận'), content: const Text('Xóa lỗi vi phạm này?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Xóa', style: TextStyle(color: Colors.red))),
        ],
      )
    );
    if (confirm != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      final response = await http.post(
        Uri.parse('https://qlnn.testifiyonline.xyz/gate_check'),
        headers: { 'Cookie': 'PHPSESSID=$sessionId', 'Content-Type': 'application/x-www-form-urlencoded' },
        body: 'delete_id=$id'
      );
      if (jsonDecode(response.body)['status'] == 'success') {
        setState(() => _historyList.removeWhere((item) => item['id'] == id));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa lỗi!')));
      }
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Kiểm tra cổng', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
              SizedBox(width: 80, child: TextField(controller: _weekCtrl, decoration: const InputDecoration(labelText: 'Tuần', border: OutlineInputBorder(), isDense: true), keyboardType: TextInputType.number, textAlign: TextAlign.center)),
            ],
          ),
          const SizedBox(height: 16),

          if (_isScanning)
            Container(
              height: 250, clipBehavior: Clip.hardEdge, decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2)),
              child: MobileScanner(onDetect: (capture) {
                final barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final code = barcodes.first.rawValue ?? '';
                  final cleanCode = code.contains("Ma_HS_") ? code.split("Ma_HS_")[1] : code;
                  setState(() { _isScanning = false; _searchCtrl.text = cleanCode; _searchLocal(cleanCode); });
                }
              }),
            ),
            
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => setState(() => _isScanning = !_isScanning),
            icon: Icon(_isScanning ? Icons.stop : Icons.qr_code_scanner),
            label: Text(_isScanning ? 'Tắt Camera' : 'QUÉT MÃ QR'),
            style: FilledButton.styleFrom(backgroundColor: _isScanning ? Colors.red.shade700 : Theme.of(context).colorScheme.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
          ),

          const SizedBox(height: 16),
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '🔍 Nhập tên hoặc mã HS...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true, fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
              suffixIcon: IconButton(icon: const Icon(Icons.cloud_download, color: Colors.deepOrange), onPressed: _handleSync),
            ),
            onChanged: _searchLocal,
          ),
          
          if (_searchResults.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 250), 
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _searchResults.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (c, i) {
                  final s = _searchResults[i];
                  return ListTile(
                    title: Text(s['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Lớp: ${s['class_name']} - Mã: ${s['code']}'),
                    leading: CircleAvatar(backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200], child: const Icon(Icons.person, color: Colors.grey)),
                    onTap: () { setState(() { _selectedStudent = s; _searchResults = []; _searchCtrl.clear(); }); },
                  );
                }
              ),
            ),

          if (_searchResults.isEmpty && _selectedStudent == null) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('HOẶC CHỌN LỚP', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 15),
            
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300)
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  hint: const Text('-- Chọn lớp --', style: TextStyle(fontWeight: FontWeight.w600)),
                  value: _selectedClassFilter,
                  items: _classes.map((c) => DropdownMenuItem(value: c, child: Text('Lớp $c', style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedClassFilter = val;
                      _classStudents = _offlineStudents.where((s) => s['class_name'] == val).toList();
                    });
                  }
                )
              )
            ),

            if (_classStudents.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 15),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, childAspectRatio: 2.5, crossAxisSpacing: 10, mainAxisSpacing: 10
                ),
                itemCount: _classStudents.length,
                itemBuilder: (context, index) {
                  final s = _classStudents[index];
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedStudent = s;
                        _classStudents = []; 
                        _selectedClassFilter = null; 
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8)
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(color: isDark ? Colors.grey[800] : Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
                            child: Text(s['code'], style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey.shade700, fontSize: 10))
                          ),
                        ]
                      )
                    )
                  );
                }
              )
          ],

          const SizedBox(height: 20),

          if (_selectedStudent != null) ...[
            Card(
              elevation: 0, color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
              shape: RoundedRectangleBorder(side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2), borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(child: Icon(Icons.person)), const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_selectedStudent!['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text('${_selectedStudent!['class_name']} - ${_selectedStudent!['code']}', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                        ])),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _selectedStudent = null))
                      ],
                    ),
                    const Divider(height: 16),
                    const Text('Chọn lỗi vi phạm:', style: TextStyle(fontWeight: FontWeight.bold)),
                    ..._violations.map((v) => CheckboxListTile(
                          contentPadding: EdgeInsets.zero, title: Text(v['name']), subtitle: Text('-${v['points']} điểm', style: const TextStyle(color: Colors.red)),
                          value: _selectedViolations.contains(v['id']), activeColor: Colors.red,
                          onChanged: (bool? checked) { setState(() { if (checked == true) _selectedViolations.add(v['id']); else _selectedViolations.remove(v['id']); }); },
                        )),
                    
                    Container(
                      margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero, dense: true,
                            title: const Text('Chấm bù / Sửa ngày giờ', style: TextStyle(fontWeight: FontWeight.bold)),
                            value: _isCustomTime,
                            onChanged: (val) => setState(() => _isCustomTime = val),
                          ),
                          if (_isCustomTime)
                            Row(
                              children: [
                                Expanded(child: Text(_customDateTime == null ? "Chưa chọn giờ" : "${_customDateTime!.hour}:${_customDateTime!.minute.toString().padLeft(2,'0')} ${_customDateTime!.day}/${_customDateTime!.month}", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold))),
                                OutlinedButton.icon(onPressed: _pickCustomTime, icon: const Icon(Icons.edit_calendar, size: 18), label: const Text('Chọn')),
                              ],
                            )
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),
                    TextField(controller: _noteCtrl, decoration: InputDecoration(hintText: 'Ghi chú thêm...', border: const OutlineInputBorder(), isDense: true, fillColor: isDark ? Colors.grey[800] : Colors.white, filled: true)),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isLoading ? null : _submitViolation,
                        icon: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save),
                        label: const Text('LƯU VI PHẠM', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600, padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    )
                  ],
                ),
              ),
            )
          ],

          if (_historyList.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Vừa chấm xong', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey)),
            Card(
              elevation: 2, margin: const EdgeInsets.only(top: 8),
              child: Column(
                children: _historyList.map((h) => Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      title: RichText(text: TextSpan(children: [
                        TextSpan(text: h['student_name'] ?? 'Tập thể', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                        TextSpan(text: ' (${h['class_name']})', style: const TextStyle(color: Colors.grey)),
                      ])),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text('- ${h['violation_name']}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                          Text(h['time_str'], style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                      trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () => _deleteRecord(h['id'])),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  ],
                )).toList(),
              ),
            )
          ]
        ],
      ),
    );
  }
}