import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class ExamLookupScreen extends StatefulWidget {
  const ExamLookupScreen({super.key});

  @override
  State<ExamLookupScreen> createState() => _ExamLookupScreenState();
}

class _ExamLookupScreenState extends State<ExamLookupScreen> {
  bool _isDataLoaded = false;
  bool _isSearching = false;
  
  List<dynamic> _exams = [];
  String? _selectedExamId; // FIX: Dùng ID thay vì cả Object để chống đơ Dropdown
  
  List<dynamic> _allScores = [];
  List<dynamic> _filteredScores = [];
  Map<String, dynamic> _subjectConfig = {};

  final TextEditingController _searchController = TextEditingController();
  
  String _sessionId = '';
  String _currentUserRole = '';

  // --- CÁC BIẾN PHỤC VỤ PHÂN TRANG ---
  int _currentPage = 1;
  final int _itemsPerPage = 50;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionId = prefs.getString('phpsessid') ?? '';
    _currentUserRole = prefs.getString('role') ?? '';
    
    await _fetchExams();
  }

  Future<void> _fetchExams() async {
    try {
      Dio dio = Dio();
      if (_sessionId.isNotEmpty) dio.options.headers['Cookie'] = 'PHPSESSID=$_sessionId';
      
      final res = await dio.get('${AppConfig.baseUrl}/api/exam_data_api.php?action=list');
      if (res.data['status'] == 'success') {
        setState(() {
          _exams = res.data['data'];
          if (_exams.isNotEmpty) {
            // FIX: Gán ID mặc định nếu chưa có
            _selectedExamId = _exams[0]['id'].toString(); 
          }
        });
        if (_selectedExamId != null) {
          await _preloadScores(_selectedExamId);
        }
      }
    } catch (e) {
      debugPrint("Lỗi tải kỳ thi: $e");
    }
  }

  Future<void> _preloadScores(dynamic examId) async {
    try {
      Dio dio = Dio();
      if (_sessionId.isNotEmpty) dio.options.headers['Cookie'] = 'PHPSESSID=$_sessionId';
      final res = await dio.get('${AppConfig.baseUrl}/api/exam_data_api.php?exam_id=$examId');
      if (res.data['status'] == 'success') {
        setState(() {
          _allScores = res.data['data'];
          _subjectConfig = res.data['config'];
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải điểm: $e");
    }
  }

  // --- LOGIC TÌM KIẾM ---
  void _startSearchAction() async {
    FocusScope.of(context).unfocus();

    String kw = _searchController.text.trim().toLowerCase();
    
    if (_allScores.isEmpty && _selectedExamId != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đang đồng bộ dữ liệu từ máy chủ, vui lòng thử lại sau vài giây!')));
      return;
    }

    if (kw.isEmpty) {
      setState(() { _isDataLoaded = false; _filteredScores = []; _currentPage = 1; });
      return;
    }

    bool isNumeric = RegExp(r'^[0-9]+$').hasMatch(kw);
    if (isNumeric && kw.length != 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('SBD phải bao gồm đúng 8 chữ số. Vui lòng kiểm tra lại!', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.redAccent,
      ));
      return; 
    }

    setState(() { _isSearching = true; _isDataLoaded = false; _filteredScores = []; });
    await Future.delayed(const Duration(milliseconds: 1000));

    setState(() {
      _filteredScores = _allScores.where((s) {
        return s['sbd'].toString().toLowerCase().contains(kw) || s['student_name'].toString().toLowerCase().contains(kw);
      }).toList();
      
      _currentPage = 1; 
      _isSearching = false;
      _isDataLoaded = true;
    });
  }

  void _showAllAction() async {
    FocusScope.of(context).unfocus();
    if (_allScores.isEmpty && _selectedExamId != null) return;
    
    setState(() { _isSearching = true; _isDataLoaded = false; _filteredScores = []; });
    await Future.delayed(const Duration(milliseconds: 1000));
    
    setState(() {
      _filteredScores = List.from(_allScores);
      _currentPage = 1; 
      _isSearching = false;
      _isDataLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    int totalPages = (_filteredScores.length / _itemsPerPage).ceil();
    if (totalPages == 0) totalPages = 1;
    
    int startIndex = (_currentPage - 1) * _itemsPerPage;
    int endIndex = (startIndex + _itemsPerPage < _filteredScores.length) ? startIndex + _itemsPerPage : _filteredScores.length;
    List<dynamic> pagedScores = _filteredScores.isEmpty ? [] : _filteredScores.sublist(startIndex, endIndex);

    return Scaffold(
      backgroundColor: isDark ? Theme.of(context).scaffoldBackgroundColor : Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Tra cứu Điểm thi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Cập nhật danh sách kỳ thi',
            onPressed: () {
              setState(() { _isDataLoaded = false; _filteredScores = []; _searchController.clear(); });
              _fetchExams();
            },
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Theme.of(context).cardColor,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: _selectedExamId,
                  decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Chọn kỳ thi'),
                  items: _exams.map((e) => DropdownMenuItem<String>(
                    value: e['id'].toString(), 
                    child: Text(e['exam_name'])
                  )).toList(),
                  onChanged: (val) async {
                    if (val != null) {
                      setState(() { _selectedExamId = val; _isDataLoaded = false; _allScores.clear(); _searchController.clear(); _currentPage = 1; });
                      await _preloadScores(val);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  onSubmitted: (_) => _startSearchAction(),
                  decoration: InputDecoration(
                    hintText: 'Nhập SBD (8 số) hoặc Họ Tên...',
                    filled: true, 
                    fillColor: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    suffixIcon: Container(
                      margin: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.blue.shade700, borderRadius: BorderRadius.circular(8)),
                      child: IconButton(
                        icon: const Icon(Icons.search, color: Colors.white),
                        onPressed: _startSearchAction,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: _isSearching 
              ? const Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(strokeWidth: 3), 
                    SizedBox(height: 16),
                    Text('Đang giải mã dữ liệu thí sinh...', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  ],
                ))
              : !_isDataLoaded 
                ? Center(child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_person, size: 80, color: Colors.blue.withOpacity(0.2)),
                          const SizedBox(height: 16),
                          const Text('Chế độ truy vấn bảo mật', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('Vui lòng nhập thông tin định danh và bấm Tìm kiếm', style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey), textAlign: TextAlign.center),
                          
                          if (_currentUserRole == 'ADMIN' || _currentUserRole == 'TEACHER')
                            Column(
                              children: [
                                const SizedBox(height: 30),
                                const Divider(),
                                const SizedBox(height: 15),
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      side: const BorderSide(color: Colors.redAccent),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: const Icon(Icons.lock_open),
                                    label: const Text('Mở khóa toàn bộ dữ liệu (Quyền Giáo viên)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    onPressed: _showAllAction,
                                  ),
                                )
                              ],
                            ),
                        ],
                      ),
                    ),
                  ))
                : pagedScores.isEmpty
                  ? const Center(child: Text('Không tìm thấy bản ghi nào.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: pagedScores.length,
                      itemBuilder: (ctx, i) => _buildScoreCard(pagedScores[i], isDark),
                    ),
          ),

          // --- THANH PHÂN TRANG ---
          if (_isDataLoaded && totalPages > 1)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                boxShadow: [BoxShadow(color: isDark ? Colors.black26 : Colors.grey.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, -2))],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.first_page),
                    color: _currentPage > 1 ? Colors.blue.shade700 : Colors.grey,
                    onPressed: _currentPage > 1 ? () => setState(() => _currentPage = 1) : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    color: _currentPage > 1 ? Colors.blue.shade700 : Colors.grey,
                    onPressed: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
                  ),
                  
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: isDark ? Colors.blue.withOpacity(0.2) : Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text('Trang $_currentPage / $totalPages', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.blue.shade300 : Colors.blue.shade900)),
                  ),
                  
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    color: _currentPage < totalPages ? Colors.blue.shade700 : Colors.grey,
                    onPressed: _currentPage < totalPages ? () => setState(() => _currentPage++) : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.last_page),
                    color: _currentPage < totalPages ? Colors.blue.shade700 : Colors.grey,
                    onPressed: _currentPage < totalPages ? () => setState(() => _currentPage = totalPages) : null,
                  ),
                ],
              ),
            )
        ],
      ),
    );
  }

  Widget _buildScoreCard(dynamic student, bool isDark) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(student['student_name'] ?? 'Không tên', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text('SBD: ${student['sbd']} | Lớp: ${student['class_name']}', style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey, fontSize: 13)),
            const Divider(),
            ..._subjectConfig.keys.map((sub) {
              final cfg = _subjectConfig[sub];
              final colTong = cfg['TONG'];
              final colTN = cfg['TN'];
              final colTL = cfg['TL'];

              Widget scoreDisplayWidget;

              if (colTN != null && colTL != null && student[colTN] != null && student[colTL] != null) {
                scoreDisplayWidget = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${student[colTN]}', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.black87)),
                    const Text(' + ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text('${student[colTL]}', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.black87)),
                    const Text(' = ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                      student[colTong]?.toString() ?? '-', 
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 15)
                    ),
                  ],
                );
              } else {
                scoreDisplayWidget = Text(
                  student[colTong]?.toString() ?? '-', 
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 15)
                );
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(sub, style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.black54)),
                    scoreDisplayWidget,
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}