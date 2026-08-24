import 'localization_service.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class ManageViolationsScreen extends StatefulWidget {
  ManageViolationsScreen({super.key});

  @override
  State<ManageViolationsScreen> createState() => _ManageViolationsScreenState();
}

class _ManageViolationsScreenState extends State<ManageViolationsScreen> {
  bool _isLoading = true;
  final Dio _dio = Dio();

  // Timeline
  DateTime? _startDate;
  DateTime? _endHk1Date;
  DateTime? _endYearDate;
  List<DateTime> _excludedDates = [];
  int _currentWeek = 0;

  // Rules
  final TextEditingController _tickerController = TextEditingController();
  final TextEditingController _maxBaseController = TextEditingController();
  final TextEditingController _divisorController = TextEditingController();
  final TextEditingController _weightAcaController = TextEditingController();
  final TextEditingController _weightConController = TextEditingController();

  List<dynamic> _violations = [];

  String _formatDate(DateTime date) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}';
  }

  String _formatDisplayDate(DateTime date) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${twoDigits(date.day)}/${twoDigits(date.month)}/${date.year}';
  }

  DateTime _parseDate(String value) {
    final parts = value.split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2]);
  }

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _tickerController.dispose();
    _maxBaseController.dispose();
    _divisorController.dispose();
    _weightAcaController.dispose();
    _weightConController.dispose();
    super.dispose();
  }

  Future<Options> _getOptions() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getString('phpsessid') ?? '';
    return Options(
      headers: {
        'Cookie': 'PHPSESSID=$sessionId',
      },
      contentType: Headers.formUrlEncodedContentType,
    );
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final options = await _getOptions();
      final response = await _dio.get(
        '${AppConfig.baseUrl}/api/manage_violations_api.php?action=get_data',
        options: options,
      );

      if (response.data != null && response.data['status'] == 'success') {
        final data = response.data;
        
        final timeline = data['timeline'] ?? {};
        if (timeline['start_date'] != null) _startDate = _parseDate(timeline['start_date']);
        if (timeline['end_hk1_date'] != null) _endHk1Date = _parseDate(timeline['end_hk1_date']);
        if (timeline['end_year_date'] != null) _endYearDate = _parseDate(timeline['end_year_date']);
        
        _excludedDates = [];
        if (timeline['excluded_dates'] != null && timeline['excluded_dates'].toString().isNotEmpty) {
          final dates = timeline['excluded_dates'].toString().split(',').map((e) => e.trim()).toList();
          for (var d in dates) {
            if (d.isNotEmpty) _excludedDates.add(_parseDate(d));
          }
        }
        
        _currentWeek = timeline['current_week'] ?? 0;

        final rules = data['rules'] ?? {};
        _maxBaseController.text = (rules['max_base'] ?? 60).toString();
        _divisorController.text = (rules['divisor'] ?? 6).toString();
        _weightAcaController.text = (rules['weight_aca'] ?? 0.5).toString();
        _weightConController.text = (rules['weight_con'] ?? 0.5).toString();
        _tickerController.text = data['ticker_school'] ?? '';

        _violations = data['violations'] ?? [];
      }
    } catch (e) {
      debugPrint('Error fetching data: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _updateTimeline() async {
    try {
      final options = await _getOptions();
      await _dio.post(
        '${AppConfig.baseUrl}/api/manage_violations_api.php',
        data: {
          'action': 'update_timeline',
          'start_date': _startDate != null ? _formatDate(_startDate!) : '',
          'end_hk1_date': _endHk1Date != null ? _formatDate(_endHk1Date!) : '',
          'end_year_date': _endYearDate != null ? _formatDate(_endYearDate!) : '',
          'excluded_dates': _excludedDates.map(_formatDate).join(', '),
        },
        options: options,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Cập nhật thời gian thành công' : 'Time settings updated successfully')));
        _fetchData();
      }
    } catch (e) {
      debugPrint('Error updating timeline: $e');
    }
  }

  Future<void> _saveRules() async {
    try {
      final options = await _getOptions();
      await _dio.post(
        '${AppConfig.baseUrl}/api/manage_violations_api.php',
        data: {
          'action': 'save_rules',
          'max_base': _maxBaseController.text,
          'divisor': _divisorController.text,
          'weight_aca': _weightAcaController.text,
          'weight_con': _weightConController.text,
          'ticker_school': _tickerController.text,
        },
        options: options,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Lưu cấu hình thành công' : 'Configuration saved successfully')));
        _fetchData();
      }
    } catch (e) {
      debugPrint('Error saving rules: $e');
    }
  }

  Future<void> _deleteViolation(int id) async {
    try {
      final options = await _getOptions();
      await _dio.post(
        '${AppConfig.baseUrl}/api/manage_violations_api.php',
        data: {'action': 'delete', 'id': id},
        options: options,
      );
      _fetchData();
    } catch (e) {
      debugPrint('Error deleting violation: $e');
    }
  }

  void _showViolationDialog([Map<String, dynamic>? violation]) {
    final bool isEdit = violation != null;
    final contentController = TextEditingController(text: isEdit ? violation['content'] : '');
    final contentEnController = TextEditingController(text: isEdit ? (violation['content_en'] ?? '') : '');
    final shortCodeController = TextEditingController(text: isEdit ? violation['short_code'] : '');
    final pointsController = TextEditingController(text: isEdit ? violation['points'].toString() : '');
    String scope = isEdit ? (violation['scope'] ?? 'GATE') : 'GATE';
    final maxPointsController = TextEditingController(text: isEdit && violation['max_penalty_points'] != null ? violation['max_penalty_points'].toString() : '');

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? LocalizationService().currentLanguage == 'vi' ? 'Sửa Lỗi' : 'Edit Violation' : LocalizationService().currentLanguage == 'vi' ? 'Thêm Lỗi Mới' : 'Add New Violation'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: contentController, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Nội dung (TV)*' : 'Violation Content*')),
                    TextField(controller: contentEnController, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Nội dung (EN)' : 'Violation Content (English)')),
                    TextField(controller: shortCodeController, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Mã tắt*' : 'Code*')),
                    TextField(controller: pointsController, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Điểm trừ*' : 'Deduction Points*'), keyboardType: TextInputType.numberWithOptions(decimal: true)),
                    SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: scope,
                      items: [
                        DropdownMenuItem(value: 'GATE', child: Text(LocalizationService().currentLanguage == 'vi' ? 'Cổng trường (GATE)' : 'School Gate')),
                        DropdownMenuItem(value: 'CLASS', child: Text(LocalizationService().currentLanguage == 'vi' ? 'Trong lớp (CLASS)' : 'In Class (CLASS)')),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => scope = val);
                      },
                      decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Phạm vi' : 'Applicable Scope'),
                    ),
                    if (scope == 'CLASS')
                      TextField(controller: maxPointsController, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Điểm trừ tối đa (Để trống nếu không giới hạn)' : 'Max penalty (leave blank if unlimited)'), keyboardType: TextInputType.numberWithOptions(decimal: true)),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Hủy' : 'Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    if (contentController.text.isEmpty || shortCodeController.text.isEmpty || pointsController.text.isEmpty) return;
                    Navigator.pop(context);
                    try {
                      final options = await _getOptions();
                      await _dio.post(
                        '${AppConfig.baseUrl}/api/manage_violations_api.php',
                        data: {
                          'action': isEdit ? 'edit' : 'add',
                          if (isEdit) 'id': violation['id'],
                          'content': contentController.text,
                          'content_en': contentEnController.text,
                          'short_code': shortCodeController.text,
                          'points': pointsController.text,
                          'scope': scope,
                          'max_penalty_points': scope == 'CLASS' ? maxPointsController.text : '',
                        },
                        options: options,
                      );
                      _fetchData();
                    } catch (e) {
                      debugPrint('Error saving violation: $e');
                    }
                  },
                  child: Text(LocalizationService().currentLanguage == 'vi' ? 'Lưu Lại' : 'Save'),
                )
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _selectDate(BuildContext context, Function(DateTime) onSelected) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      onSelected(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(LocalizationService().currentLanguage == 'vi' ? 'QUẢN LÝ VI PHẠM' : 'MANAGE VIOLATIONS')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.black : Colors.white;
    final textColor = isDark ? Colors.white : Color(0xFF1D1D1F);
    final borderColor = isDark ? Color(0xFF262626) : Color(0xFFE2E8F0);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(LocalizationService().currentLanguage == 'vi' ? 'QUẢN LÝ VI PHẠM' : 'MANAGE VIOLATIONS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          IconButton(icon: Icon(Icons.refresh), onPressed: _fetchData),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Khối 1: Cấu hình Năm học
            _buildCard(
              title: LocalizationService().currentLanguage == 'vi' ? 'Cấu hình Năm Học' : 'Academic Year Configuration',
              icon: Icons.calendar_month,
              topColor: Color(0xFF005FBA),
              cardColor: cardColor,
              borderColor: borderColor,
              textColor: textColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: '2026-2027', // Ví dụ
                    items: [
                      DropdownMenuItem(value: '2025-2026', child: Text('2025-2026')),
                      DropdownMenuItem(value: '2026-2027', child: Text('2026-2027')),
                    ],
                    onChanged: (val) {},
                    decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Năm học' : 'Academic Year'),
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _selectDate(context, (d) => setState(() => _startDate = d)),
                          child: InputDecorator(
                            decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Khai giảng HK1' : 'Semester 1 Start'),
                            child: Text(_startDate != null ? _formatDisplayDate(_startDate!) : LocalizationService().currentLanguage == 'vi' ? 'Chọn ngày' : 'Select Date'),
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () => _selectDate(context, (d) => setState(() => _endHk1Date = d)),
                          child: InputDecorator(
                            decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Kết thúc HK1' : 'Semester 1 End'),
                            child: Text(_endHk1Date != null ? _formatDisplayDate(_endHk1Date!) : LocalizationService().currentLanguage == 'vi' ? 'Chọn ngày' : 'Select Date'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  InkWell(
                    onTap: () => _selectDate(context, (d) => setState(() => _endYearDate = d)),
                    child: InputDecorator(
                      decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Kết thúc Năm học' : 'School Year End'),
                      child: Text(_endYearDate != null ? _formatDisplayDate(_endYearDate!) : LocalizationService().currentLanguage == 'vi' ? 'Chọn ngày' : 'Select Date'),
                    ),
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Text(LocalizationService().currentLanguage == 'vi' ? 'Ngày nghỉ (Loại trừ): ' : 'Holidays (Exclusions): '),
                      IconButton(
                        icon: Icon(Icons.add_circle, color: Color(0xFF005FBA)),
                        onPressed: () => _selectDate(context, (d) => setState(() {
                          if (!_excludedDates.contains(d)) _excludedDates.add(d);
                        })),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    children: _excludedDates.map((d) => Chip(
                      label: Text(_formatDisplayDate(d)),
                      onDeleted: () => setState(() => _excludedDates.remove(d)),
                    )).toList(),
                  ),
                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.all(8),
                    color: Colors.blue.withValues(alpha: 0.1),
                    child: Text(LocalizationService().currentLanguage == 'vi' ? 'Hiện tại: Tuần $_currentWeek' : 'Current: Week $_currentWeek', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF005FBA))),
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _updateTimeline,
                    style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF005FBA)),
                    child: Text(LocalizationService().currentLanguage == 'vi' ? 'Cập nhật Thời gian' : 'Update Schedule', style: TextStyle(color: Colors.white)),
                  )
                ],
              ),
            ),
            SizedBox(height: 16),

            // Khối 2: Cấu Hình & Ticker
            _buildCard(
              title: LocalizationService().currentLanguage == 'vi' ? 'Cấu Hình & Ticker' : 'Configuration & Ticker',
              icon: Icons.settings_suggest,
              topColor: Color(0xFF8B5CF6),
              cardColor: cardColor,
              borderColor: borderColor,
              textColor: textColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tickerController,
                          decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Thông báo chạy (Ticker)' : 'Ticker Announcement'),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.format_quote),
                        tooltip: LocalizationService().currentLanguage == 'vi' ? 'Thêm dấu chấm giữa' : 'Add center dot separator',
                        onPressed: () {
                          final text = _tickerController.text;
                          final selection = _tickerController.selection;
                          final newText = text.replaceRange(
                              selection.start > -1 ? selection.start : text.length, 
                              selection.end > -1 ? selection.end : text.length, 
                              ' · ');
                          _tickerController.text = newText;
                          _tickerController.selection = TextSelection.collapsed(offset: (selection.start > -1 ? selection.start : text.length) + 3);
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: _maxBaseController, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Điểm Gốc' : 'Base Score'), keyboardType: TextInputType.numberWithOptions(decimal: true))),
                      SizedBox(width: 8),
                      Expanded(child: TextField(controller: _divisorController, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Hệ số chia' : 'Divisor'), keyboardType: TextInputType.numberWithOptions(decimal: true))),
                    ],
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: _weightAcaController, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? '% Học Tập (0.0-1.0)' : '% Academic (0.0-1.0)'), keyboardType: TextInputType.numberWithOptions(decimal: true))),
                      SizedBox(width: 8),
                      Expanded(child: TextField(controller: _weightConController, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? '% Nền Nếp (0.0-1.0)' : '% Discipline (0.0-1.0)'), keyboardType: TextInputType.numberWithOptions(decimal: true))),
                    ],
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _saveRules,
                    style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF8B5CF6)),
                    child: Text(LocalizationService().currentLanguage == 'vi' ? 'Lưu Cấu Hình' : 'Save Configuration', style: TextStyle(color: Colors.white)),
                  )
                ],
              ),
            ),
            SizedBox(height: 16),

            // Khối 3: Danh Mục Lỗi
            Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                children: [
                  ListTile(
                    title: Text(LocalizationService().currentLanguage == 'vi' ? 'Danh Mục Lỗi' : 'Violation Categories', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                    trailing: IconButton(
                      icon: Icon(Icons.add, color: Color(0xFF005FBA)),
                      onPressed: () => _showViolationDialog(),
                    ),
                  ),
                  Divider(height: 1),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    itemCount: _violations.length,
                    separatorBuilder: (context, index) => Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _violations[index];
                      final isGate = item['scope'] == 'GATE';
                      return ListTile(
                        title: Text(item['content'] ?? '', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (item['content_en'] != null && item['content_en'].toString().isNotEmpty)
                              Text(item['content_en'], style: TextStyle(color: Color(0xFF475569), fontSize: 12)),
                            SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(4)),
                                  child: Text(item['short_code'] ?? '', style: TextStyle(color: Color(0xFFC026D3), fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                                SizedBox(width: 8),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isGate ? Color(0x1A0284C7) : Color(0x1A9333EA),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: isGate ? Color(0xFF0284C7) : Color(0xFF9333EA)),
                                  ),
                                  child: Text(
                                    isGate ? LocalizationService().currentLanguage == 'vi' ? 'Cổng' : 'Gate' : LocalizationService().currentLanguage == 'vi' ? 'Lớp' : 'Class',
                                    style: TextStyle(
                                      color: isGate ? Color(0xFF0284C7) : Color(0xFF9333EA),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (!isGate && item['max_penalty_points'] != null && item['max_penalty_points'].toString().isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text(LocalizationService().currentLanguage == 'vi' ? 'Tối đa: -${item["max_penalty_points"]}' : 'Max: -${item["max_penalty_points"]}', style: TextStyle(color: Color(0xFFD93025), fontSize: 12)),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('-${item['points']}', style: TextStyle(color: Color(0xFFD93025), fontWeight: FontWeight.bold, fontSize: 16)),
                            IconButton(icon: Icon(Icons.edit, color: Color(0xFF8B5CF6)), onPressed: () => _showViolationDialog(item)),
                            IconButton(icon: Icon(Icons.delete_outline, color: Color(0xFFD93025)), onPressed: () => _deleteViolation(item['id'])),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Color topColor,
    required Color cardColor,
    required Color borderColor,
    required Color textColor,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: topColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: topColor),
                SizedBox(width: 8),
                Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
              ],
            ),
          ),
          Divider(height: 1),
          Padding(
            padding: EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}