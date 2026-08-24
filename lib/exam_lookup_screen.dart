import 'localization_service.dart';
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

  String _translateSubject(String sub) {
    if (LocalizationService().currentLanguage == 'vi') return sub;
    const map = {
      'Toán': 'Math',
      'Văn': 'Literature',
      'Anh': 'English',
      'Lý': 'Physics',
      'Hóa': 'Chemistry',
      'Sinh': 'Biology',
      'Sử': 'History',
      'Địa': 'Geography',
      'KTPL': 'Civic Education',
      'CNCN': 'Technology (Ind)',
      'CNNN': 'Technology (Agr)',
    };
    return map[sub] ?? sub;
  }

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
  
  String _sortMode = 'sbd';

  void _applySort() {
    if (_sortMode == 'sbd') {
      _filteredScores.sort((a, b) => a['sbd'].toString().compareTo(b['sbd'].toString()));
    } else if (_sortMode == 'name') {
      _filteredScores.sort((a, b) => (a['student_name'] ?? '').toString().compareTo((b['student_name'] ?? '').toString()));
    } else if (_sortMode == 'class') {
      _filteredScores.sort((a, b) => (a['class_name'] ?? '').toString().compareTo((b['class_name'] ?? '').toString()));
    }
    _currentPage = 1;
  }

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
      
      final res = await dio.get('${AppConfig.baseUrl}/api/exam_data_api.php?action=list&lang=${LocalizationService().currentLanguage}');
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
      debugPrint(LocalizationService().currentLanguage == 'vi' ? "Lỗi tải kỳ thi: $e" : "Error loading exams: $e");
    }
  }

  Future<void> _preloadScores(dynamic examId) async {
    try {
      Dio dio = Dio();
      if (_sessionId.isNotEmpty) dio.options.headers['Cookie'] = 'PHPSESSID=$_sessionId';
      final res = await dio.get('${AppConfig.baseUrl}/api/exam_data_api.php?exam_id=$examId&lang=${LocalizationService().currentLanguage}');
      if (res.data['status'] == 'success') {
        setState(() {
          _allScores = res.data['data'];
          _subjectConfig = res.data['config'];
        });
      }
    } catch (e) {
      debugPrint(LocalizationService().currentLanguage == 'vi' ? "Lỗi tải điểm: $e" : "Error loading scores: $e");
    }
  }

  // --- LOGIC TÌM KIẾM ---
  void _startSearchAction() async {
    FocusScope.of(context).unfocus();

    String kw = _searchController.text.trim().toLowerCase();
    
    if (_allScores.isEmpty && _selectedExamId != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Đang đồng bộ dữ liệu từ máy chủ, vui lòng thử lại sau vài giây!' : 'Syncing data from server, please try again in a few seconds!')));
      return;
    }

    if (kw.isEmpty) {
      setState(() { _isDataLoaded = false; _filteredScores = []; _currentPage = 1; });
      return;
    }

    bool isNumeric = RegExp(r'^[0-9]+$').hasMatch(kw);
    if (isNumeric && kw.length != 8) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(LocalizationService().currentLanguage == 'vi' ? 'SBD phải bao gồm đúng 8 chữ số. Vui lòng kiểm tra lại!' : 'ID must be exactly 8 digits. Please check again!', style: TextStyle(fontWeight: FontWeight.bold)),
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
      
      _applySort();
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
      _applySort();
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
        title: Text(LocalizationService().currentLanguage == 'vi' ? 'Tra cứu Điểm thi' : 'Exam Lookup'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            tooltip: LocalizationService().currentLanguage == 'vi' ? 'Cập nhật danh sách kỳ thi' : 'Refresh exam list',
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
                  initialValue: _selectedExamId,
                  decoration: InputDecoration(border: OutlineInputBorder(), labelText: LocalizationService().currentLanguage == 'vi' ? 'Chọn kỳ thi' : 'Select exam'),
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
                SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  onSubmitted: (_) => _startSearchAction(),
                  decoration: InputDecoration(
                    hintText: LocalizationService().currentLanguage == 'vi' ? 'Nhập SBD (8 số) hoặc Họ Tên...' : 'Enter ID (8 digits) or Name...',
                    filled: true, 
                    fillColor: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    suffixIcon: Container(
                      margin: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.blue.shade700, borderRadius: BorderRadius.circular(8)),
                      child: IconButton(
                        icon: Icon(Icons.search, color: Colors.white),
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
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(strokeWidth: 3), 
                    SizedBox(height: 16),
                    Text(LocalizationService().currentLanguage == 'vi' ? 'Đang giải mã dữ liệu thí sinh...' : 'Decoding candidate data...', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  ],
                ))
              : !_isDataLoaded 
                ? Center(child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_person, size: 80, color: Colors.blue.withValues(alpha: 0.2)),
                          SizedBox(height: 16),
                          Text(LocalizationService().currentLanguage == 'vi' ? 'Chế độ truy vấn bảo mật' : 'Secure query mode', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(LocalizationService().currentLanguage == 'vi' ? 'Vui lòng nhập thông tin định danh và bấm Tìm kiếm' : 'Please enter identity info and press Search', style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey), textAlign: TextAlign.center),
                          
                          if (_currentUserRole == 'ADMIN' || _currentUserRole == 'TEACHER')
                            Column(
                              children: [
                                SizedBox(height: 30),
                                const Divider(),
                                SizedBox(height: 15),
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      side: const BorderSide(color: Colors.redAccent),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: Icon(Icons.lock_open),
                                    label: Text(LocalizationService().currentLanguage == 'vi' ? 'Mở khóa toàn bộ dữ liệu (Quyền Giáo viên)' : 'Unlock all data (Teacher Privileges)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
                  ? Center(child: Text(LocalizationService().currentLanguage == 'vi' ? 'Không tìm thấy bản ghi nào.' : 'No records found.'))
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(LocalizationService().currentLanguage == 'vi' ? 'Sắp xếp: ' : 'Sort by: ', style: TextStyle(fontWeight: FontWeight.bold)),
                              SizedBox(width: 8),
                              DropdownButton<String>(
                                value: _sortMode,
                                isDense: true,
                                underline: SizedBox(),
                                items: [
                                  DropdownMenuItem(value: 'sbd', child: Text(LocalizationService().currentLanguage == 'vi' ? 'Theo SBD' : 'By ID')),
                                  DropdownMenuItem(value: 'name', child: Text(LocalizationService().currentLanguage == 'vi' ? 'Theo Tên' : 'By Name')),
                                  DropdownMenuItem(value: 'class', child: Text(LocalizationService().currentLanguage == 'vi' ? 'Theo Lớp' : 'By Class')),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _sortMode = val;
                                      _applySort();
                                    });
                                  }
                                }
                              )
                            ],
                          )
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: pagedScores.length,
                            itemBuilder: (ctx, i) => _buildScoreCard(pagedScores[i], isDark),
                          )
                        )
                      ]
                    ),
          ),

          // --- THANH PHÂN TRANG ---
          if (_isDataLoaded && totalPages > 1)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                boxShadow: [BoxShadow(color: isDark ? Colors.black26 : Colors.grey.withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(0, -2))],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(Icons.first_page),
                    color: _currentPage > 1 ? Colors.blue.shade700 : Colors.grey,
                    onPressed: _currentPage > 1 ? () => setState(() => _currentPage = 1) : null,
                  ),
                  IconButton(
                    icon: Icon(Icons.chevron_left),
                    color: _currentPage > 1 ? Colors.blue.shade700 : Colors.grey,
                    onPressed: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
                  ),
                  
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: isDark ? Colors.blue.withValues(alpha: 0.2) : Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text(LocalizationService().currentLanguage == 'vi' ? 'Trang $_currentPage / $totalPages' : 'Page $_currentPage / $totalPages', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.blue.shade300 : Colors.blue.shade900)),
                  ),
                  
                  IconButton(
                    icon: Icon(Icons.chevron_right),
                    color: _currentPage < totalPages ? Colors.blue.shade700 : Colors.grey,
                    onPressed: _currentPage < totalPages ? () => setState(() => _currentPage++) : null,
                  ),
                  IconButton(
                    icon: Icon(Icons.last_page),
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
            Text(student['student_name'] ?? (LocalizationService().currentLanguage == 'vi' ? 'Không tên' : 'Unknown name'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(LocalizationService().currentLanguage == 'vi' ? 'SBD: ${student["sbd"]} | Lớp: ${student["class_name"]}' : 'SBD: ${student["sbd"]} | Class: ${student["class_name"]}', style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey, fontSize: 13)),
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
                    Text(' + ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text('${student[colTL]}', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.black87)),
                    Text(' = ', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                    Text(_translateSubject(sub), style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.black54)),
                    scoreDisplayWidget,
                  ],
                ),
              );
            }),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  icon: Icon(Icons.gavel, size: 16),
                  label: Text(LocalizationService().currentLanguage == 'vi' ? 'Phúc khảo' : 'Appeal'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.orange, side: const BorderSide(color: Colors.orange)),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Đã gửi yêu cầu phúc khảo cho học sinh ${student["student_name"]}!' : 'Re-eval requested for ${student["student_name"]}!')));
                  }
                )
              ]
            )
          ],
        ),
      ),
    );
  }
}