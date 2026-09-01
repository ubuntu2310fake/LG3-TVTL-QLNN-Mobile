import 'dart:convert';
import 'package:flutter/material.dart';
import 'localization_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/liquid_glass_container.dart';
import 'config.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  bool _isLoading = true;
  String _week = '';
  Map<String, dynamic> _data = {};
  String _role = 'STUDENT';

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
      _role = prefs.getString('role') ?? 'STUDENT';
      
      String url = '${AppConfig.baseUrl}/api/teacher_dashboard_api.php';
      if (_week.isNotEmpty) url += '?week=$_week';

      final response = await AppConfig.client.get(Uri.parse(url), headers: {'Cookie': 'PHPSESSID=$sessionId'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() { 
          if (_week.isEmpty && data['current_week'] != null) {
            _week = data['current_week'].toString();
          }
          _data = data; 
          _isLoading = false; 
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword(dynamic student) async {
    if (!await _confirm(LocalizationService().currentLanguage == 'vi' ? 'Bạn có chắc muốn đặt lại mật khẩu của ${student['name']} về mặc định?' : 'Reset password to default for ${student['name']}?')) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      final res = await AppConfig.client.post(
        Uri.parse('${AppConfig.baseUrl}/api/teacher_dashboard_api.php'),
        headers: {'Cookie': 'PHPSESSID=$sessionId', 'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'reset_student_password', 'student_id': student['id']}),
      );
      final data = jsonDecode(res.body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['msg'] ?? 'Success')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
  Future<void> _deleteViolation(int id) async {
    if (!await _confirm(LocalizationService().currentLanguage == 'vi' ? 'Bạn có chắc muốn xóa lỗi vi phạm này?' : 'Are you sure you want to delete this violation?')) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      await AppConfig.client.post(
        Uri.parse('${AppConfig.baseUrl}/api/teacher_dashboard_api'),
        headers: {'Cookie': 'PHPSESSID=$sessionId', 'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'delete_violation', 'id': id}),
      );
      _fetchData(); 
    } catch (e) {}
  }

  Future<void> _showEditExemptionDialog(dynamic student) async {
    bool isExempt = student['has_exemption'] == 1;
    TextEditingController reasonController = TextEditingController(text: student['exemption_reason'] ?? '');
    
    await showDialog(context: context, builder: (context) {
      return StatefulBuilder(builder: (context, setStateSB) {
        return AlertDialog(
          title: Text(LocalizationService().currentLanguage == "vi" ? "Học sinh: ${student['name']}" : "Student: ${student['name']}"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                title: Text(LocalizationService().currentLanguage == 'vi' ? 'Được miễn trừ vi phạm?' : 'Exempt from violations?'),
                value: isExempt,
                onChanged: (val) {
                  if (val != null) setStateSB(() => isExempt = val);
                },
              ),
              if (isExempt) TextField(
                controller: reasonController,
                decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Lý do miễn trừ (bệnh, v.v.)' : 'Ly do mien tru (benh, v.v.)', border: OutlineInputBorder()),
                maxLines: 2,
              )
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Huỷ' : 'Cancel')),
            ElevatedButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                final sessionId = prefs.getString('phpsessid') ?? '';
                await AppConfig.client.post(
                  Uri.parse('${AppConfig.baseUrl}/api/teacher_dashboard_api'),
                  headers: {'Cookie': 'PHPSESSID=$sessionId', 'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'action': 'edit_exemption',
                    'student_id': student['id'],
                    'has_exemption': isExempt ? 1 : 0,
                    'exemption_reason': reasonController.text
                  }),
                );
                if (mounted) Navigator.pop(context);
                _fetchData();
              },
              child: Text(LocalizationService().currentLanguage == 'vi' ? 'Lưu' : 'Save'),
            )
          ]
        );
      });
    });
  }

  Future<bool> _confirm(String msg) async {
    return await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text(LocalizationService().currentLanguage == 'vi' ? 'Xác nhận' : 'Confirm'), content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Hủy' : 'Cancel')),
        TextButton(onPressed: () => Navigator.pop(c, true), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Đồng ý' : 'Confirm', style: TextStyle(color: Colors.red))),
      ],
    )) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_data['status'] == 'error') return Scaffold(appBar: AppBar(), body: Center(child: Text(_data['msg'])));
    if (_data['has_class'] == false) return Scaffold(appBar: AppBar(title: Text(LocalizationService().currentLanguage == 'vi' ? 'Lớp của tôi' : 'My Class')), body: Center(child: Text(LocalizationService().currentLanguage == 'vi' ? 'Bạn chưa được phân công chủ nhiệm.' : 'You are not assigned as a homeroom teacher.')));

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final showPsychology = _role != 'RED_FLAG';

    return DefaultTabController(
      length: showPsychology ? 4 : 3,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                    Text(LocalizationService().currentLanguage == "vi" ? "Lớp ${_data['class_info']['name']}" : "Class ${_data['class_info']['name']}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              Text('GV: ${_data['class_info']['teacher']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.grey)),
            ],
          ),
          bottom: TabBar(
            isScrollable: true,
            labelColor: Theme.of(context).colorScheme.primary, 
            unselectedLabelColor: Colors.grey, 
            indicatorColor: Theme.of(context).colorScheme.primary,
            tabs: [
              Tab(icon: Icon(Icons.people), text: LocalizationService().currentLanguage == 'vi' ? 'Học sinh' : 'Students'),
              Tab(icon: Icon(Icons.warning_amber), text: LocalizationService().currentLanguage == 'vi' ? 'Vi phạm' : 'Violations'),
              Tab(icon: Icon(Icons.grid_on), text: LocalizationService().currentLanguage == 'vi' ? 'Điểm Sổ' : 'Record'),
              if (showPsychology) Tab(icon: Icon(Icons.psychology), text: LocalizationService().currentLanguage == 'vi' ? 'Tâm lý' : 'Psychology'),
            ],
          ),
          actions: [
            Row(
              children: [
                Text(LocalizationService().currentLanguage == 'vi' ? 'Tuần ' : 'Week ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    dropdownColor: Theme.of(context).colorScheme.surface,
                    iconEnabledColor: Theme.of(context).colorScheme.primary,
                    style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16),
                    value: _week,
                    items: List.generate(35, (i) => DropdownMenuItem(value: (i+1).toString(), child: Text('${i+1}'))),
                    onChanged: (v) { setState(() => _week = v!); _fetchData(); },
                  ),
                ),
              ],
            ),
            SizedBox(width: 15), 
          ],
        ),
        body: TabBarView(
          children: [
            ListView.builder(
              padding: const EdgeInsets.all(12), itemCount: _data['students'].length,
              itemBuilder: (c, i) {
                var s = _data['students'][i];
                return LiquidGlassContainer(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                  onTap: () => _showEditExemptionDialog(s),
                  leading: CircleAvatar(child: Text(s['name'][0])), 
                  title: Text(s['name'], style: const TextStyle(fontWeight: FontWeight.bold)), 
                  subtitle: Text(s['thuylinh'] != null ? "STT ${s['thuylinh']} • ${s['code']}" : s['code']), 
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (s['has_exemption'] == 1) const Icon(Icons.shield, color: Colors.green),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.key, size: 16),
                        label: Text(LocalizationService().currentLanguage == 'vi' ? 'Reset MK' : 'Reset Pwd', style: const TextStyle(fontSize: 12)),
                        onPressed: () => _resetPassword(s),
                      ),
                    ],
                  )
                ));
              },
            ),
            _data['violations'].isEmpty ? Center(child: Text(LocalizationService().currentLanguage == 'vi' ? 'Không có vi phạm tuần này!' : 'No violations this week!')) : ListView.builder(
              padding: const EdgeInsets.all(12), itemCount: _data['violations'].length,
              itemBuilder: (c, i) {
                var v = _data['violations'][i];
                return LiquidGlassContainer(
                  margin: const EdgeInsets.only(bottom: 8),
                  border: Border.all(color: Colors.redAccent),
                  borderRadius: BorderRadius.circular(8),
                  child: ListTile(
                    title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(v['student_name'] ?? (LocalizationService().currentLanguage == 'vi' ? 'Tập thể' : 'Collective'), style: TextStyle(fontWeight: FontWeight.bold)), Text("-${v['recorded_points']}", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))]),
                    subtitle: Text("${v['recorded_violation_name']}\n${v['date_created']} • ${v['reporter']}"), isThreeLine: true,
                    trailing: IconButton(icon: Icon(Icons.delete, color: Colors.grey), onPressed: () => _deleteViolation(v['id'])),
                  ),
                );
              },
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: isDark ? Colors.blue.withValues(alpha: 0.1) : Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(LocalizationService().currentLanguage == 'vi' ? "TỔNG ĐIỂM TUẦN:" : "WEEKLY TOTAL:", style: TextStyle(fontWeight: FontWeight.bold)), Text("${_data['matrix']['total']}", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.blue))]),
                  ),
                  SizedBox(height: 15),
                  ...(_data['matrix']['data'] as List).map((row) => LiquidGlassContainer(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ExpansionTile(
                      leading: CircleAvatar(backgroundColor: Colors.blue, child: Text(LocalizationService().currentLanguage == 'vi' ? row['day'] : {'T2':'Mon', 'T3':'Tue', 'T4':'Wed', 'T5':'Thu', 'T6':'Fri', 'T7':'Sat'}[row['day']] ?? row['day'], style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                      title: Text(LocalizationService().currentLanguage == 'vi' ? "Còn: ${row['total']}đ" : "Rem: ${row['total']}pt", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      subtitle: Text(LocalizationService().currentLanguage == 'vi' ? "Trừ: ${10 - row['total']}đ" : "Ded: ${10 - row['total']}pt", style: TextStyle(color: Colors.redAccent)),
                      children: [
                        if (row['notes'] != null && row['notes'].toString().isNotEmpty) 
                          Padding(
                            padding: const EdgeInsets.all(12), 
                            child: Row(
                              children: [
                                Icon(Icons.flag, color: Colors.red, size: 20),
                                SizedBox(width: 8),
                                Expanded(child: Text(row['notes'].toString(), style: const TextStyle(color: Colors.red, fontStyle: FontStyle.italic))),
                              ],
                            )
                          ),
                        if (row['deductions'] != null) 
                          ...(row['deductions'] as List).map((d) => ListTile(
                            dense: true,
                            title: Text(d['name']),
                            trailing: Text('-${d['points']}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                          ))
                      ],
                    )
                  )),
                ],
              ),
            ),
            if (showPsychology)
              _data['psychology'].isEmpty ? Center(child: Text(LocalizationService().currentLanguage == 'vi' ? "Tâm lý ổn định." : "Tam ly on dinh.")) : ListView.builder(
              padding: const EdgeInsets.all(12), itemCount: _data['psychology'].length,
              itemBuilder: (c, i) {
                var p = _data['psychology'][i]; bool isDanger = p['risk_level'] == 'DANGER';
                return LiquidGlassContainer(
                  margin: const EdgeInsets.only(bottom: 8),
                  border: Border.all(color: isDanger ? Colors.red : Colors.orange),
                  borderRadius: BorderRadius.circular(8),
                  child: ExpansionTile(
                    title: Text("${p['student_name']} ${isDanger ? '🆘' : '⚠️'}", style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(p['question']),
                    children: [ Padding(padding: EdgeInsets.all(16), child: Text(LocalizationService().currentLanguage == 'vi' ? "AI Tư vấn:\n${p['advice']}" : "AI Tu van:\n${p['advice']}", style: TextStyle(fontStyle: FontStyle.italic))) ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}