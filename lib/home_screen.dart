import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart'; 
import 'offline_sync.dart'; 
import 'device_helper.dart';
import 'config.dart';

// --- IMPORT CÁC MÀN HÌNH CHỨC NĂNG ---
import 'profile_screen.dart';
import 'change_password_screen.dart';
import 'ranking_screen.dart';
import 'student_violations_screen.dart'; 
import 'settings_screen.dart'; 
import 'teacher_dashboard_screen.dart';
import 'violation_history_screen.dart'; 
import 'input_academic_screen.dart';
import 'export_report_screen.dart';
import 'manage_students_screen.dart';
import 'manage_users_screen.dart';
import 'banned_ips_screen.dart';
import 'traffic_monitor_screen.dart'; 
import 'consulting_test_screen.dart';
import 'news_screen.dart';
import 'exam_lookup_screen.dart';
import 'manage_exams_screen.dart';
import 'grammar_check_screen.dart';
import 'manage_violations_screen.dart';
import 'human_chat_list_screen.dart';
import 'ai_consulting_screen.dart';

class HomeScreen extends StatefulWidget {
  final Function(int) onNavigate; 
  const HomeScreen({super.key, required this.onNavigate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _userName = 'Đang tải...';
  String _role = 'STUDENT';
  bool _isNotiEnabled = false;
  bool _isSyncing = false;
  String _lastSyncStr = "Chưa rõ";
  String _lang = 'vi';

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _triggerAutoSync(); // Tự động chạy đồng bộ ngầm khi vào app
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('full_name') ?? (prefs.getString('lang') == 'en' ? 'User' : 'Người dùng');
      _role = prefs.getString('role') ?? 'STUDENT';
      _isNotiEnabled = prefs.getBool('push_enabled') ?? false;
      _lang = prefs.getString('lang') ?? 'vi';
    });
  }

  String _t(String vi, String en) {
    return _lang == 'en' ? en : vi;
  }

  // HÀM ĐỒNG BỘ CHUẨN BẢN 1.0.4
  Future<void> _triggerAutoSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    final success = await OfflineSyncService.syncData();
    
    if (mounted) {
      setState(() {
        _isSyncing = false;
        if (success) {
          final now = DateTime.now();
          _lastSyncStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} - ${now.day}/${now.month}";
        }
      });
    }
  }

  Future<void> _toggleNotification(bool value) async {
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));
    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getString('phpsessid') ?? '';
    
    try {
      if (value) {
        FirebaseMessaging messaging = FirebaseMessaging.instance;
        await messaging.requestPermission(alert: true, badge: true, sound: true);
        String? fcmToken = await messaging.getToken();
        String realModel = await DeviceHelper.getDeviceModel();
        
        if (fcmToken != null) {
          final response = await http.post(
            Uri.parse('${AppConfig.baseUrl}/api/subscribe'),
            headers: {'Content-Type': 'application/json', 'Cookie': 'PHPSESSID=$sessionId'},
            body: jsonEncode({'endpoint': fcmToken, 'platform': 'app', 'device_model': realModel}),
          );
          if (jsonDecode(response.body)['status'] == 'success') {
            setState(() => _isNotiEnabled = true);
            await prefs.setBool('push_enabled', true);
          }
        }
      } else {
        await http.post(
          Uri.parse('${AppConfig.baseUrl}/gate_check'),
          headers: {'Cookie': 'PHPSESSID=$sessionId', 'Content-Type': 'application/x-www-form-urlencoded'},
          body: 'delete_id=0&only_push=1' 
        );
        setState(() => _isNotiEnabled = false);
        await prefs.setBool('push_enabled', false);
      }
    } catch (e) {}
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    bool isStaff = ['TEACHER', 'ADMIN', 'RED_FLAG'].contains(_role);
    bool isAdmin = _role == 'ADMIN';
    bool isStudent = ['STUDENT', 'RED_FLAG'].contains(_role);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LỜI CHÀO
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_t('Xin chào,', 'Hello,'), style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                  Text(_userName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 1. THẺ ĐỒNG BỘ CỤC BỘ (GIAO DIỆN CHUẨN 1.0.4)
          Card(
            elevation: 0, 
            shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: _isSyncing 
                ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)) 
                : const Icon(Icons.cloud_done_rounded, color: Colors.green, size: 32),
              title: Text(_t('Dữ liệu Cục bộ', 'Local Data'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Text(_isSyncing ? _t('Đang tải...', 'Loading...') : _t('Cập nhật: $_lastSyncStr', 'Updated: $_lastSyncStr')),
              trailing: OutlinedButton.icon(
                onPressed: _isSyncing ? null : _triggerAutoSync, 
                icon: const Icon(Icons.sync, size: 18), 
                label: Text(_t('Tải lại', 'Reload'))
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 2. THẺ THÔNG BÁO PUSH (GIAO DIỆN 1.0.5)
          Card(
            elevation: 0, 
            shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(16)),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              secondary: Container(
                padding: const EdgeInsets.all(8), 
                decoration: BoxDecoration(
                  color: _isNotiEnabled ? Colors.orange.withOpacity(0.1) : Colors.grey.withOpacity(0.1), 
                  borderRadius: BorderRadius.circular(10)
                ), 
                child: Icon(
                  _isNotiEnabled ? Icons.notifications_active : Icons.notifications_off, 
                  color: _isNotiEnabled ? Colors.orange : Colors.grey, 
                  size: 24
                )
              ),
              title: Text(_t('Nhận Thông báo', 'Receive Notifications'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Text(_t('Báo điểm trừ, tin nhắn AI', 'Penalty alert, AI chat')),
              value: _isNotiEnabled, 
              activeColor: Colors.orange, 
              onChanged: _toggleNotification,
            ),
          ),
          const SizedBox(height: 30),
  
          // BẢNG ĐIỀU KHIỂN PHÂN LOẠI (GIAO DIỆN BẢN MỚI)
          
          // --- 1. TÀI KHOẢN & CÁ NHÂN ---
          _buildSectionTitle(_t('TÀI KHOẢN & CÁ NHÂN', 'ACCOUNT & PERSONAL')),
          GridView.count(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.0,
            children: [
              _buildActionBtn(context, Icons.person, _t('Hồ sơ', 'Profile'), Colors.blue, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()))),
              _buildActionBtn(context, Icons.lock_reset, _t('Đổi mật khẩu', 'Change Password'), Colors.blueGrey, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen()))),
              _buildActionBtn(context, Icons.settings, _t('Cài đặt', 'Settings'), Colors.grey, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
              if (isStudent) _buildActionBtn(context, Icons.warning_amber, _t('Lỗi của tôi', 'My Violations'), Colors.orange, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentViolationsScreen()))),
            ],
          ),
          const SizedBox(height: 25),
  
          // --- 2. HỌC TẬP & TIỆN ÍCH ---
          _buildSectionTitle(_t('HỌC TẬP & TIỆN ÍCH', 'ACADEMIC & UTILITIES')),
          GridView.count(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.0,
            children: [
              _buildActionBtn(context, Icons.newspaper, _t('Tin tức', 'News'), Colors.blue, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewsScreen()))),
              _buildActionBtn(context, Icons.scoreboard, _t('Điểm thi', 'Exam Scores'), Colors.amber, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExamLookupScreen()))),
              _buildActionBtn(context, Icons.spellcheck, 'Grammar AI', Colors.green, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GrammarCheckScreen()))),
              _buildActionBtn(context, Icons.workspace_premium, _t('Xếp hạng', 'Ranking'), Colors.amber, () => isStaff ? Navigator.push(context, MaterialPageRoute(builder: (_) => const RankingScreen())) : widget.onNavigate(2)),
            ],
          ),
          const SizedBox(height: 25),
  
          // --- 3. TÂM LÝ & HƯỚNG NGHIỆP ---
          _buildSectionTitle(_t('TÂM LÝ & HƯỚNG NGHIỆP', 'PSYCHOLOGY & CAREER')),
          GridView.count(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.0,
            children: [
              _buildActionBtn(context, Icons.explore, _t('Nghề nghiệp', 'Career'), Colors.green, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConsultingTestScreen()))),
              _buildActionBtn(context, Icons.forum, _t('Tư vấn 1:1 ', '1:1 Consulting'), Colors.blue, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HumanChatListScreen()))),
              _buildActionBtn(context, Icons.psychology, _t('Chuyên gia AI', 'AI Specialist'), Colors.purple, () => isStaff ? Navigator.push(context, MaterialPageRoute(builder: (_) => const AiConsultingScreen())) : widget.onNavigate(1)),
            ],
          ),
  
          // --- 4. CÔNG TÁC TRỰC TUẦN (CHỈ DÀNH CHO STAFF/GIÁO VIÊN) ---
          if (isStaff) ...[
            const SizedBox(height: 25),
            _buildSectionTitle(_t('CÔNG TÁC TRỰC TUẦN & NỀN NẾP', 'WEEKLY DUTY & DISCIPLINE')),
            GridView.count(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.0,
              children: [
                _buildActionBtn(context, Icons.qr_code_scanner, _t('Kiểm tra Cổng', 'Gate Check'), Colors.purple, () => widget.onNavigate(1)),
                _buildActionBtn(context, Icons.fact_check, _t('Kiểm tra Lớp', 'Class Check'), Colors.amber, () => widget.onNavigate(2)),
                _buildActionBtn(context, Icons.co_present, _t('Lớp của tôi', 'My Class'), Colors.deepOrange, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherDashboardScreen()))),
                _buildActionBtn(context, Icons.edit_note, _t('Nhập điểm học tập', 'Academic Scores'), Colors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InputAcademicScreen()))),
                _buildActionBtn(context, Icons.gavel, _t('QL Vi phạm', 'Manage Violations'), Colors.red, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageViolationsScreen()))),
                _buildActionBtn(context, Icons.history, _t('LS Vi phạm', 'Violation History'), Colors.deepPurple, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ViolationHistoryScreen()))),
                _buildActionBtn(context, Icons.task, _t('QL Kỳ thi', 'Manage Exams'), Colors.pink, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageExamsScreen()))),
                _buildActionBtn(context, Icons.file_download, _t('Xuất báo cáo Excel', 'Export Excel'), Colors.green, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExportReportScreen()))),
              ],
            ),
          ],
  
          // --- 5. QUẢN TRỊ HỆ THỐNG (CHỈ DÀNH CHO ADMIN) ---
          if (isAdmin) ...[
            const SizedBox(height: 25),
            _buildSectionTitle(_t('QUẢN TRỊ HỆ THỐNG', 'SYSTEM ADMINISTRATION')),
            GridView.count(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.0,
              children: [
                _buildActionBtn(context, Icons.people_alt, _t('Học sinh', 'Students'), Colors.indigo, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageStudentsScreen()))),
                _buildActionBtn(context, Icons.admin_panel_settings, _t('Tài khoản', 'Accounts'), Colors.redAccent, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageUsersScreen()))),
                _buildActionBtn(context, Icons.security, _t('Khóa IP', 'Banned IPs'), Colors.brown, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BannedIpsScreen()))),
                _buildActionBtn(context, Icons.analytics, _t('Lưu lượng', 'Traffic Monitor'), Colors.blueGrey, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrafficMonitorScreen()))),
              ],
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2, fontSize: 13)),
    );
  }

  Widget _buildActionBtn(BuildContext context, IconData icon, String title, Color color, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap, 
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? color.withOpacity(0.12) : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 30, color: color),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Text(title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}