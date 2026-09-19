import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'localization_service.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'offline_sync.dart';
import 'offline_queue_service.dart';
import 'widgets/liquid_glass_container.dart';
import 'config.dart';

class GateCheckScreen extends StatefulWidget {
  const GateCheckScreen({super.key});

  @override
  State<GateCheckScreen> createState() => _GateCheckScreenState();
}

class _GateCheckScreenState extends State<GateCheckScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  
  Map<String, dynamic>? _selectedStudent;
  File? _evidenceImage;
  bool _isScanning = false;
  bool _isLoading = false;
  
  CameraFacing _selectedCamera = CameraFacing.back;
  late MobileScannerController _cameraController;
  
  bool _isCustomTime = false;
  DateTime? _customDateTime;

  final Set<int> _selectedViolations = {};
  
  List<dynamic> _offlineStudents = [];
  List<Map<String, dynamic>> _violations = [];
  List<dynamic> _searchResults = [];
  
  List<String> _classes = [];
  String? _selectedClassFilter;
  List<dynamic> _classStudents = [];
  
  bool _isHistoryLoading = false;
  final List<Map<String, dynamic>> _historyList = [];

  @override
  void initState() {
    super.initState();
    _cameraController = MobileScannerController(facing: _selectedCamera);
    _loadLocalData(); 
    _fetchHistory();
    _initSSE();
  }

  Future<void> _fetchHistory() async {
    setState(() => _isHistoryLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      final res = await AppConfig.client.get(
        Uri.parse('${AppConfig.baseUrl}/api/gate_check_api.php?action=recent_json'),
        headers: {'Cookie': 'PHPSESSID=$sessionId'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['status'] == 'success' && data['violations'] != null) {
          if (!mounted) return;
          setState(() {
            _historyList.clear();
            _historyList.addAll(List<Map<String, dynamic>>.from(data['violations']));
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching gate history: $e');
    } finally {
      if (mounted) setState(() => _isHistoryLoading = false);
    }
  }

  void _initSSE() {
    // TODO: Implement Server-Sent Events (SSE) for realtime updates
    // e.g. connect to SSE stream and update _historyList when other gates scan
    debugPrint("SSE placeholder initialized");
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalData() async {
    final data = await OfflineSyncService.getMasterData();
    if (!mounted) return;
    setState(() {
      _offlineStudents = data['students'] ?? [];
      
      Set<String> classNames = {};
      for (var s in _offlineStudents) {
        if (s['class_name'] != null) classNames.add(s['class_name'].toString());
      }
      
      _classes = classNames.toList()..sort((a, b) {
        final RegExp regExp = RegExp(r'(\d+)|([^\d]+)');
        final matchesA = regExp.allMatches(a).map((m) => m.group(0)!).toList();
        final matchesB = regExp.allMatches(b).map((m) => m.group(0)!).toList();
        for (int i = 0; i < matchesA.length && i < matchesB.length; i++) {
          final partA = matchesA[i]; final partB = matchesB[i];
          final numA = int.tryParse(partA); final numB = int.tryParse(partB);
          if (numA != null && numB != null) {
            final cmp = numA.compareTo(numB); if (cmp != 0) return cmp;
          } else {
            final cmp = partA.compareTo(partB); if (cmp != 0) return cmp;
          }
        }
        return matchesA.length.compareTo(matchesB.length);
      });

      if (data['gate_violations'] != null) {
        _violations = List<Map<String, dynamic>>.from(data['gate_violations'].map((v) => { 'id': v['id'], 'name': v['name'], 'name_en': v['name_en'], 'points': v['points'] }));
      }
    });
  }

  Future<void> _handleSync() async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Đang tải dữ liệu từ máy chủ LG3...' : 'Loading data from LG3 server...')));
    final success = await OfflineSyncService.syncData();
    if (success) {
      await _loadLocalData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? '✅ Đã đồng bộ thành công!' : '✅ Synced successfully!'), backgroundColor: Colors.green));
    }
  }

  void _searchLocal(String query) {
    if (query.isEmpty) { setState(() => _searchResults = []); return; }
    final q = query.toLowerCase();
    setState(() {
      _searchResults = _offlineStudents.where((s) {
        final className = (s['class_name'] ?? '').toString();
        if (className.startsWith('K46') || s['grade'] == 13 || s['grade'] == '13') return false;
        return s['name'].toString().toLowerCase().contains(q) || s['code'].toString().toLowerCase().contains(q);
      }).toList();
      _searchResults.sort((a, b) {
        final codeA = (a['code'] ?? '').toString().toLowerCase();
        final codeB = (b['code'] ?? '').toString().toLowerCase();
        if (codeA == q) return -1;
        if (codeB == q) return 1;
        final classA = (a['class_name'] ?? '').toString();
        final classB = (b['class_name'] ?? '').toString();
        final is10A = classA.startsWith('10') ? 0 : 1;
        final is10B = classB.startsWith('10') ? 0 : 1;
        if (is10A != is10B) return is10A.compareTo(is10B);
        return (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString());
      });
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
    setState(() => _customDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _pickEvidence(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 82,
      );
      if (picked != null) {
        setState(() {
          _evidenceImage = File(picked.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LocalizationService().currentLanguage == 'vi' ? 'Không thể mở ảnh/camera: $e' : 'Could not open camera/gallery: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  void _removeEvidence() {
    setState(() {
      _evidenceImage = null;
    });
  }

  void _showEvidenceDialog(String imgPath) {
    final url = imgPath.startsWith('http') ? imgPath : '${AppConfig.baseUrl}/$imgPath';
    showDialog(
      context: context,
      builder: (c) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      height: 250,
                      color: Colors.black54,
                      child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 180,
                    color: Colors.black54,
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        LocalizationService().currentLanguage == 'vi' ? 'Không thể tải ảnh bằng chứng' : 'Could not load evidence image',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: Icon(Icons.close, color: Colors.white, size: 20),
                ),
                onPressed: () => Navigator.pop(c),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitViolation() async {
    if (_selectedStudent == null || _selectedViolations.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      var request = http.MultipartRequest('POST', Uri.parse('${AppConfig.baseUrl}/api/gate_check_api.php'));
      request.headers['Cookie'] = 'PHPSESSID=$sessionId';

      request.fields['student_id'] = '${_selectedStudent!['id']}';
      request.fields['other_note'] = _noteCtrl.text;
      request.fields['violation_ids'] = _selectedViolations.join(',');
      request.fields['violation_ids[]'] = _selectedViolations.first.toString();

      if (_isCustomTime && _customDateTime != null) {
        String f(int n) => n.toString().padLeft(2, '0');
        String timeStr = '${_customDateTime!.year}-${f(_customDateTime!.month)}-${f(_customDateTime!.day)} ${f(_customDateTime!.hour)}:${f(_customDateTime!.minute)}:00';
        request.fields['custom_time'] = timeStr;
      }

      if (_evidenceImage != null && await _evidenceImage!.exists()) {
        request.files.add(await http.MultipartFile.fromPath('evidence_image', _evidenceImage!.path));
      }

      var response = await AppConfig.client.send(request);
      var responseData = await response.stream.bytesToString();
      var data = jsonDecode(responseData);

      if (response.statusCode == 200 && data['status'] == 'success') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? '✅ Đã lưu thành công!' : '✅ Saved successfully!'), backgroundColor: Colors.green));
        setState(() {
          if (data['new_data'] != null) _historyList.insertAll(0, List<Map<String, dynamic>>.from(data['new_data']));
          _selectedStudent = null; _selectedViolations.clear(); _noteCtrl.clear(); _selectedClassFilter = null; _classStudents.clear();
          _evidenceImage = null;
        });
      } else { throw Exception(data['msg'] ?? (LocalizationService().currentLanguage == 'vi' ? "Lỗi server" : "Server error")); }
    } catch (e) {
      List<String> bodyParts = [
        'student_id=${_selectedStudent!['id']}',
        'other_note=${Uri.encodeQueryComponent(_noteCtrl.text)}',
        'violation_ids=${_selectedViolations.join(',')}'
      ];
      if (_isCustomTime && _customDateTime != null) {
        String f(int n) => n.toString().padLeft(2, '0');
        String timeStr = '${_customDateTime!.year}-${f(_customDateTime!.month)}-${f(_customDateTime!.day)} ${f(_customDateTime!.hour)}:${f(_customDateTime!.minute)}:00';
        bodyParts.add('custom_time=${Uri.encodeQueryComponent(timeStr)}');
      }
      for (var vid in _selectedViolations) { bodyParts.add('violation_ids[]=$vid'); }

      await OfflineQueueService.enqueue(
        url: '${AppConfig.baseUrl}/api/gate_check_api.php', method: 'POST', contentType: 'application/x-www-form-urlencoded', body: bodyParts.join('&'),
        title: LocalizationService().currentLanguage == 'vi' ? 'Trực cổng: ${_selectedStudent!['name']} - Lớp ${_selectedStudent!['class_name']}' : 'Gate duty: ${_selectedStudent!['name']} - Class ${_selectedStudent!['class_name']}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? '⚠️ Mất mạng! Đã lưu Offline ngầm.' : '⚠️ Offline! Saved locally.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Colors.orange));
        setState(() { _selectedStudent = null; _selectedViolations.clear(); _noteCtrl.clear(); _selectedClassFilter = null; _classStudents.clear(); _evidenceImage = null; });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteRecord(dynamic id) async {
    final confirm = await showDialog<bool>(
      context: context, builder: (c) => AlertDialog(
        title: Text(LocalizationService().currentLanguage == 'vi' ? 'Xác nhận' : 'Confirm'), content: Text(LocalizationService().currentLanguage == 'vi' ? 'Xóa lỗi vi phạm này?' : 'Delete this violation?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Hủy' : 'Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Xóa' : 'Delete', style: TextStyle(color: Colors.red))),
        ],
      )
    );
    if (confirm != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final res = await AppConfig.client.post(
        Uri.parse('${AppConfig.baseUrl}/api/gate_check_api.php'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded', 'Cookie': 'PHPSESSID=${prefs.getString('phpsessid')}'},
        body: 'delete_id=$id'
      );
      if (jsonDecode(res.body)['status'] == 'success') {
        setState(() => _historyList.removeWhere((item) => item['id'] == id));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Đã xóa lỗi!' : 'Violation deleted!')));
      }
    } catch (e) {}
  }

  // ==========================================
  // HÀM TẠO AVATAR CHỐNG LỖI MẠNG
  // ==========================================
  Widget _buildAvatar(dynamic studentData, double radius) {
    String? imgUrl = studentData['image_url'];
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final fallbackBg = isDark ? Colors.grey[800] : Colors.grey[200];
    final fallbackIconColor = isDark ? Colors.grey[400] : Colors.grey;

    if (imgUrl != null && imgUrl.isNotEmpty && imgUrl != 'null') {
      // Ép tên miền vào nếu db chỉ lưu đường dẫn ảo
      String fullUrl = imgUrl.startsWith('http') ? imgUrl : '${AppConfig.baseUrl}/$imgUrl';
      
      return ClipOval(
        child: Image.network(
          fullUrl,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => CircleAvatar(
            radius: radius, backgroundColor: fallbackBg,
            child: Icon(Icons.person, color: fallbackIconColor, size: radius),
          ),
        ),
      );
    }
    
    // Nếu không có link ảnh
    return CircleAvatar(
      radius: radius, backgroundColor: fallbackBg,
      child: Icon(Icons.person, color: fallbackIconColor, size: radius),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 120), // FIX: Prevent bottom nav overlap
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  LocalizationService().currentLanguage == 'vi' ? 'Kiểm tra cổng' : 'Gate Check',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (_isHistoryLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 16),

          if (_isScanning) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(LocalizationService().currentLanguage == 'vi' ? 'Camera: ' : 'Camera: ', style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<CameraFacing>(
                  value: _selectedCamera,
                  items: [
                    DropdownMenuItem(value: CameraFacing.back, child: Text(LocalizationService().currentLanguage == 'vi' ? 'Sau' : 'Back')),
                    DropdownMenuItem(value: CameraFacing.front, child: Text(LocalizationService().currentLanguage == 'vi' ? 'Trước' : 'Front')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedCamera = val);
                      _cameraController.switchCamera();
                    }
                  }
                )
              ]
            ),
            Container(
              height: 250, clipBehavior: Clip.hardEdge, decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2)),
              child: MobileScanner(
                controller: _cameraController,
                onDetect: (capture) {
                final barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final code = barcodes.first.rawValue ?? '';
                  final cleanCode = code.contains("Ma_HS_") ? code.split("Ma_HS_")[1] : code;
                  setState(() { _isScanning = false; _searchCtrl.text = cleanCode; _searchLocal(cleanCode); });
                }
              }),
            ),
          ],
            
          SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => setState(() => _isScanning = !_isScanning),
            icon: Icon(_isScanning ? Icons.stop : Icons.qr_code_scanner),
            label: Text(_isScanning ? LocalizationService().currentLanguage == 'vi' ? 'Tắt Camera' : 'Tat Camera' : LocalizationService().currentLanguage == 'vi' ? 'QUÉT MÃ QR' : 'SCAN QR CODE'),
            style: FilledButton.styleFrom(backgroundColor: _isScanning ? Colors.red.shade700 : Theme.of(context).colorScheme.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
          ),

          SizedBox(height: 16),
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: LocalizationService().currentLanguage == 'vi' ? '🔍 Nhập tên hoặc mã HS...' : '🔍 Enter name or ID...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true, fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
              suffixIcon: IconButton(icon: Icon(Icons.cloud_download, color: Colors.deepOrange), onPressed: _handleSync),
            ),
            onChanged: _searchLocal,
          ),
          
          if (_searchResults.isNotEmpty)
            LiquidGlassContainer(
              margin: const EdgeInsets.only(top: 8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 250),
                child: ListView.separated(
                shrinkWrap: true,
                itemCount: _searchResults.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (c, i) {
                  final s = _searchResults[i];
                  return ListTile(
                    title: Text(s['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(LocalizationService().currentLanguage == 'vi' ? (s['thuylinh'] != null ? 'STT ${s['thuylinh']} • Lớp: ${s['class_name']} - Mã: ${s['code']}' : 'Lớp: ${s['class_name']} - Mã: ${s['code']}') : (s['thuylinh'] != null ? 'STT ${s['thuylinh']} • Class: ${s['class_name']} - ID: ${s['code']}' : 'Class: ${s['class_name']} - ID: ${s['code']}')),
                    leading: _buildAvatar(s, 20), // DÙNG AVATAR CHUẨN MỚI
                    onTap: () { setState(() { _selectedStudent = s; _searchResults = []; _searchCtrl.clear(); }); },
                  );
                }
              ),
            ),
          ),

          if (_searchResults.isEmpty && _selectedStudent == null) ...[
            SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(LocalizationService().currentLanguage == 'vi' ? 'HOẶC CHỌN LỚP' : 'OR SELECT CLASS', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                Expanded(child: Divider()),
              ],
            ),
            SizedBox(height: 15),
            
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
                  hint: Text(LocalizationService().currentLanguage == 'vi' ? '-- Chọn lớp --' : '-- Select Class --', style: TextStyle(fontWeight: FontWeight.w600)),
                  value: _selectedClassFilter,
                  items: _classes.map((c) => DropdownMenuItem(value: c, child: Text(LocalizationService().currentLanguage == 'vi' ? 'Lớp $c' : 'Class $c', style: TextStyle(fontWeight: FontWeight.bold)))).toList(),
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
                  crossAxisCount: 2, childAspectRatio: 2.2, crossAxisSpacing: 10, mainAxisSpacing: 10
                ),
                itemCount: _classStudents.length,
                itemBuilder: (context, index) {
                  final s = _classStudents[index];
                  return InkWell(
                    onTap: () { setState(() { _selectedStudent = s; _classStudents = []; _selectedClassFilter = null; }); },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8)
                      ),
                      child: Row(
                        children: [
                          _buildAvatar(s, 18), // HIỂN THỊ ẢNH Ở LƯỚI GRID
                          SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                                SizedBox(height: 2),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(color: isDark ? Colors.grey[800] : Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
                                  child: Text(s['thuylinh'] != null ? "STT ${s['thuylinh']} • ${s['code']}" : s['code'], style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey.shade700, fontSize: 10))
                                ),
                              ]
                            ),
                          )
                        ],
                      )
                    )
                  );
                }
              )
          ],

          SizedBox(height: 20),

          if (_selectedStudent != null) ...[
            LiquidGlassContainer(
              border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildAvatar(_selectedStudent, 24), // AVATAR Ở CARD CHỌN LỖI
                        SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_selectedStudent!['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text('${_selectedStudent!['class_name']} - ${_selectedStudent!['code']}', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                        ])),
                        IconButton(icon: Icon(Icons.close), onPressed: () => setState(() => _selectedStudent = null))
                      ],
                    ),
                    const Divider(height: 16),
                    Text(LocalizationService().currentLanguage == 'vi' ? 'Chọn lỗi vi phạm:' : 'Select violation:', style: TextStyle(fontWeight: FontWeight.bold)),
                    ..._violations.map((v) => CheckboxListTile(
                          contentPadding: EdgeInsets.zero, title: Text(LocalizationService().currentLanguage == 'vi' ? (v['name'] ?? '') : (v['name_en'] ?? v['name'] ?? '')), subtitle: Text(LocalizationService().currentLanguage == 'vi' ? '-${v["points"]} điểm' : '-${v["points"]} pt', style: TextStyle(color: Colors.red)),
                          value: _selectedViolations.contains(v['id']), activeColor: Colors.red,
                          onChanged: (bool? checked) { setState(() { if (checked == true) {
                            _selectedViolations.add(v['id']);
                          } else {
                            _selectedViolations.remove(v['id']);
                          } }); },
                        )),
                    
                    Container(
                      margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero, dense: true,
                            title: Text(LocalizationService().currentLanguage == 'vi' ? 'Chấm bù / Sửa ngày giờ' : 'Custom date/time', style: TextStyle(fontWeight: FontWeight.bold)),
                            value: _isCustomTime,
                            onChanged: (val) => setState(() => _isCustomTime = val),
                          ),
                          if (_isCustomTime)
                            Row(
                              children: [
                                Expanded(child: Text(_customDateTime == null ? LocalizationService().currentLanguage == 'vi' ? "Chưa chọn giờ" : "Chua chon gio" : "${_customDateTime!.hour}:${_customDateTime!.minute.toString().padLeft(2,'0')} ${_customDateTime!.day}/${_customDateTime!.month}", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold))),
                                OutlinedButton.icon(onPressed: _pickCustomTime, icon: Icon(Icons.edit_calendar, size: 18), label: Text(LocalizationService().currentLanguage == 'vi' ? 'Chọn' : 'Select')),
                              ],
                            )
                        ],
                      ),
                    ),

                    SizedBox(height: 10),
                    TextField(controller: _noteCtrl, decoration: InputDecoration(hintText: LocalizationService().currentLanguage == 'vi' ? 'Ghi chú thêm...' : 'Ghi chu them...', border: OutlineInputBorder(), isDense: true, fillColor: isDark ? Colors.grey[800] : Colors.white, filled: true)),
                    SizedBox(height: 12),

                    // Ảnh bằng chứng vi phạm
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.camera_alt, size: 18, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 6),
                              Text(
                                LocalizationService().currentLanguage == 'vi' ? 'Ảnh bằng chứng vi phạm' : 'Evidence Photo',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_evidenceImage != null) ...[
                            Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    _evidenceImage!,
                                    height: 120,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: InkWell(
                                    onTap: _removeEvidence,
                                    child: CircleAvatar(
                                      radius: 14,
                                      backgroundColor: Colors.black.withValues(alpha: 0.7),
                                      child: const Icon(Icons.close, size: 16, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _pickEvidence(ImageSource.camera),
                                  icon: const Icon(Icons.photo_camera, size: 16),
                                  label: Text(LocalizationService().currentLanguage == 'vi' ? 'Chụp ảnh' : 'Camera', style: const TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _pickEvidence(ImageSource.gallery),
                                  icon: const Icon(Icons.photo_library, size: 16),
                                  label: Text(LocalizationService().currentLanguage == 'vi' ? 'Chọn ảnh' : 'Gallery', style: const TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isLoading ? null : _submitViolation,
                        icon: _isLoading ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Icon(Icons.save),
                        label: Text(LocalizationService().currentLanguage == 'vi' ? 'LƯU VI PHẠM' : 'SAVE VIOLATION', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600, padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    )
                  ],
                ),
              ),
            )
          ],

          if (_isHistoryLoading && _historyList.isEmpty) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ] else if (_historyList.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  LocalizationService().currentLanguage == 'vi' ? 'Vừa chấm xong' : 'Recently graded',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20, color: Colors.grey),
                  tooltip: LocalizationService().currentLanguage == 'vi' ? 'Làm mới' : 'Refresh',
                  onPressed: _fetchHistory,
                ),
              ],
            ),
            LiquidGlassContainer(
              margin: const EdgeInsets.only(top: 8),
              child: Column(
                children: _historyList.map((h) => Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      title: RichText(text: TextSpan(children: [
                        TextSpan(text: h['student_name'] ?? (LocalizationService().currentLanguage == 'vi' ? 'Tập thể' : 'Collective'), style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                        TextSpan(text: ' (${h['class_name']})', style: const TextStyle(color: Colors.grey)),
                      ])),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text('- ${h['violation_name']}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                          Text(h['time_str'] ?? h['time_label'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          if (h['evidence_img'] != null && h['evidence_img'].toString().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: InkWell(
                                onTap: () => _showEvidenceDialog(h['evidence_img'].toString()),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.image, size: 14, color: Colors.blueAccent),
                                    const SizedBox(width: 4),
                                    Text(
                                      LocalizationService().currentLanguage == 'vi' ? 'Xem ảnh bằng chứng' : 'View evidence',
                                      style: const TextStyle(fontSize: 11, color: Colors.blueAccent, decoration: TextDecoration.underline),
                                    ),
                                  ],
                                ),
                              ),
                            ),
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