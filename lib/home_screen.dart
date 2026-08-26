import 'dart:convert';
import 'package:flutter/material.dart';
import 'localization_service.dart';
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
import 'exam_lookup_screen.dart';
import 'manage_exams_screen.dart';
import 'grammar_check_screen.dart';
import 'manage_violations_screen.dart';
import 'human_chat_list_screen.dart';
import 'ai_consulting_screen.dart';

class HomeScreen extends StatefulWidget {
  final Function(int) onNavigate;
  final bool isOffline;
  const HomeScreen({super.key, required this.onNavigate, this.isOffline = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _userName = LocalizationService().currentLanguage == 'vi' ? 'Đang tải...' : 'Loading...';
  String _role = 'STUDENT';
  bool _isNotiEnabled = false;
  bool _isSyncing = false;
  String _lastSyncStr = LocalizationService().currentLanguage == 'vi' ? "Chưa rõ" : "Not clear yet";

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _triggerAutoSync(); // Tự động chạy đồng bộ ngầm khi vào app
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('full_name') ?? (LocalizationService().currentLanguage == 'vi' ? 'Người dùng' : 'User');
      _role = prefs.getString('role') ?? 'STUDENT';
      _isNotiEnabled = prefs.getBool('push_enabled') ?? false;
    });
  }

  // HÀM ĐỒNG BỘ CHUẨN BẢN 1.0.4
  Future<void> _triggerAutoSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      await OfflineSyncService.syncUserAvatar(sessionId);
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
    showDialog(context: context, barrierDismissible: false, builder: (c) => Center(child: CircularProgressIndicator()));
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (widget.isOffline) {
      return SingleChildScrollView(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // OFFLINE BANNER
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off_rounded, color: Colors.red, size: 36),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          LocalizationService().currentLanguage == 'vi' ? 'CHẾ ĐỘ NGOẠI TUYẾN' : 'OFFLINE MODE',
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          LocalizationService().currentLanguage == 'vi'
                              ? (LocalizationService().currentLanguage == 'vi' ? 'Đang mất kết nối mạng. Chỉ các tính năng ngoại tuyến khả dụng.' : 'Network connection lost. Only offline features available.')
                              : 'Network disconnected. Only offline features are available.',
                          style: TextStyle(color: isDark ? Colors.grey[300] : Colors.black87, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // THẺ ĐỒNG BỘ CỤC BỘ
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: _isSyncing 
                  ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)) 
                  : const Icon(Icons.cloud_done_rounded, color: Colors.green, size: 32),
                title: Text(LocalizationService().currentLanguage == 'vi' ? 'Dữ liệu Cục bộ' : 'Local Data', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                subtitle: Text(_isSyncing ? (LocalizationService().currentLanguage == 'vi' ? 'Đang tải...' : 'Loading...') : (LocalizationService().currentLanguage == 'vi' ? 'Cập nhật: $_lastSyncStr' : 'Updated: $_lastSyncStr')),
                trailing: OutlinedButton.icon(
                  onPressed: _isSyncing ? null : _triggerAutoSync, 
                  icon: const Icon(Icons.sync, size: 18), 
                  label: Text(LocalizationService().currentLanguage == 'vi' ? 'Tải lại' : 'Refresh')
                ),
              ),
            ),
            const SizedBox(height: 25),

            _buildSectionTitle(LocalizationService().currentLanguage == 'vi' ? 'CHỨC NĂNG KHẢ DỤNG (OFFLINE)' : 'AVAILABLE FEATURES (OFFLINE)'),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.0,
              children: [
                if (isStaff) ...[
                  _buildActionBtn(context, Icons.qr_code_scanner, LocalizationService().currentLanguage == 'vi' ? 'Kiểm tra Cổng' : 'Gate Check', Colors.purple, () => widget.onNavigate(1)),
                  _buildActionBtn(context, Icons.fact_check, LocalizationService().currentLanguage == 'vi' ? 'Kiểm tra Lớp' : 'Class Check', Colors.amber, () => widget.onNavigate(2)),
                  _buildActionBtn(context, Icons.history, LocalizationService().currentLanguage == 'vi' ? 'LS Vi phạm' : 'Violation History', Colors.deepPurple, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ViolationHistoryScreen()))),
                ],
                if (isStudent)
                  _buildActionBtn(context, Icons.warning_amber, LocalizationService().currentLanguage == 'vi' ? 'Lỗi của tôi' : 'My Violations', Colors.orange, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentViolationsScreen()))),
                _buildActionBtn(context, Icons.settings, LocalizationService().currentLanguage == 'vi' ? 'Cài đặt' : 'Settings', Colors.grey, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
              ],
            ),
          ],
        ),
      );
    }


    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 120), // FIX: Prevent bottom nav overlap
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
                  Text(LocalizationService().currentLanguage == 'vi' ? 'Xin chào,' : 'Hello,', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                  Text(_userName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          SizedBox(height: 20),

          // 1. THẺ ĐỒNG BỘ CỤC BỘ (GIAO DIỆN CHUẨN 1.0.4)
          Card(
            elevation: 0, 
            shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: _isSyncing 
                ? SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)) 
                : Icon(Icons.cloud_done_rounded, color: Colors.green, size: 32),
              title: Text(LocalizationService().currentLanguage == 'vi' ? 'Dữ liệu Cục bộ' : 'Local Data', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Text(_isSyncing ? (LocalizationService().currentLanguage == 'vi' ? 'Đang tải...' : 'Loading...') : (LocalizationService().currentLanguage == 'vi' ? 'Cập nhật: $_lastSyncStr' : 'Updated: $_lastSyncStr')),
              trailing: OutlinedButton.icon(
                onPressed: _isSyncing ? null : _triggerAutoSync, 
                icon: Icon(Icons.sync, size: 18), 
                label: Text(LocalizationService().currentLanguage == 'vi' ? 'Tải lại' : 'Refresh')
              ),
            ),
          ),
          SizedBox(height: 12),

          // 2. THẺ THÔNG BÁO PUSH (GIAO DIỆN 1.0.5)
          Card(
            elevation: 0, 
            shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(16)),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              secondary: Container(
                padding: const EdgeInsets.all(8), 
                decoration: BoxDecoration(
                  color: _isNotiEnabled ? Colors.orange.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1), 
                  borderRadius: BorderRadius.circular(10)
                ), 
                child: Icon(
                  _isNotiEnabled ? Icons.notifications_active : Icons.notifications_off, 
                  color: _isNotiEnabled ? Colors.orange : Colors.grey, 
                  size: 24
                )
              ),
              title: Text(LocalizationService().currentLanguage == 'vi' ? 'Nhận Thông báo' : 'Receive Notifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Text(LocalizationService().currentLanguage == 'vi' ? 'Báo điểm trừ, tin nhắn AI' : 'Deduction & AI alerts'),
              value: _isNotiEnabled, 
              activeThumbColor: Colors.orange, 
              onChanged: _toggleNotification,
            ),
          ),
          SizedBox(height: 30),
  
          // BẢNG ĐIỀU KHIỂN PHÂN LOẠI (GIAO DIỆN BẢN MỚI)
          
          // --- 1. TÀI KHOẢN & CÁ NHÂN ---
          _buildSectionTitle(LocalizationService().currentLanguage == 'vi' ? 'TÀI KHOẢN & CÁ NHÂN' : 'ACCOUNT & PERSONAL'),
          GridView.count(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.0,
            children: [
              _buildActionBtn(context, Icons.person, LocalizationService().currentLanguage == 'vi' ? 'Hồ sơ' : 'Profile', Colors.blue, () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen()))),
              _buildActionBtn(context, Icons.lock_reset, LocalizationService().currentLanguage == 'vi' ? 'Đổi mật khẩu' : 'Password', Colors.blueGrey, () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChangePasswordScreen()))),
              _buildActionBtn(context, Icons.settings, LocalizationService().currentLanguage == 'vi' ? 'Cài đặt' : 'Settings', Colors.grey, () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen()))),
              if (isStudent) _buildActionBtn(context, Icons.warning_amber, LocalizationService().currentLanguage == 'vi' ? 'Lỗi của tôi' : 'My Violations', Colors.orange, () => Navigator.push(context, MaterialPageRoute(builder: (_) => StudentViolationsScreen()))),
            ],
          ),
          SizedBox(height: 25),
  
          // --- 2. HỌC TẬP & TIỆN ÍCH ---
          _buildSectionTitle(LocalizationService().currentLanguage == 'vi' ? 'HỌC TẬP & TIỆN ÍCH' : 'LEARNING & TOOLS'),
          GridView.count(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.0,
            children: [// 
//               _buildActionBtn(context, Icons.newspaper, LocalizationService().currentLanguage == 'vi' ? 'Tin tức' : 'News', Colors.blue, () => Navigator.push(context, MaterialPageRoute(builder: (_) => NewsScreen()))),
              _buildActionBtn(context, Icons.scoreboard, LocalizationService().currentLanguage == 'vi' ? 'Điểm thi' : 'Exam Scores', Colors.amber, () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExamLookupScreen()))),
              _buildActionBtn(context, Icons.spellcheck, 'Grammar AI', Colors.green, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GrammarCheckScreen()))),
              _buildActionBtn(context, Icons.workspace_premium, LocalizationService().currentLanguage == 'vi' ? 'Xếp hạng' : 'Ranking', Colors.amber, () => isStaff ? Navigator.push(context, MaterialPageRoute(builder: (_) => RankingScreen())) : widget.onNavigate(2)),
            ],
          ),
          SizedBox(height: 25),
  
          // --- 3. TÂM LÝ & HƯỚNG NGHIỆP ---
          _buildSectionTitle(LocalizationService().currentLanguage == 'vi' ? 'TÂM LÝ & HƯỚNG NGHIỆP' : 'COUNSELING & CAREER'),
          GridView.count(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.0,
            children: [
              _buildActionBtn(context, Icons.explore, LocalizationService().currentLanguage == 'vi' ? 'Nghề nghiệp' : 'Career Test', Colors.green, () => Navigator.push(context, MaterialPageRoute(builder: (_) => ConsultingTestScreen()))),
              _buildActionBtn(context, Icons.forum, LocalizationService().currentLanguage == 'vi' ? 'Chat' : 'Chat', Colors.blue, () => Navigator.push(context, MaterialPageRoute(builder: (_) => HumanChatListScreen()))),
              _buildActionBtn(context, Icons.psychology, LocalizationService().currentLanguage == 'vi' ? 'Góc tư vấn' : 'Counseling Corner', Colors.purple, () => isStaff ? Navigator.push(context, MaterialPageRoute(builder: (_) => AiConsultingScreen())) : widget.onNavigate(1)),
            ],
          ),
  
          // --- 4. CÔNG TÁC TRỰC TUẦN (CHỈ DÀNH CHO STAFF/GIÁO VIÊN) ---
          if (isStaff) ...[
            SizedBox(height: 25),
            _buildSectionTitle(LocalizationService().currentLanguage == 'vi' ? 'CÔNG TÁC TRỰC TUẦN & NỀN NẾP' : 'DISCIPLINE & WEEKLY DUTY'),
            GridView.count(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.0,
              children: [
                _buildActionBtn(context, Icons.qr_code_scanner, LocalizationService().currentLanguage == 'vi' ? 'Kiểm tra Cổng' : 'Gate Check', Colors.purple, () => widget.onNavigate(1)),
                _buildActionBtn(context, Icons.fact_check, LocalizationService().currentLanguage == 'vi' ? 'Kiểm tra Lớp' : 'Class Check', Colors.amber, () => widget.onNavigate(2)),
                _buildActionBtn(context, Icons.co_present, LocalizationService().currentLanguage == 'vi' ? 'Lớp của tôi' : 'My Class', Colors.deepOrange, () => Navigator.push(context, MaterialPageRoute(builder: (_) => TeacherDashboardScreen()))),
                _buildActionBtn(context, Icons.edit_note, LocalizationService().currentLanguage == 'vi' ? 'Nhập điểm học tập' : 'Academic Scores', Colors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (_) => InputAcademicScreen()))),
                _buildActionBtn(context, Icons.history, LocalizationService().currentLanguage == 'vi' ? 'LS Vi phạm' : 'Violation History', Colors.deepPurple, () => Navigator.push(context, MaterialPageRoute(builder: (_) => ViolationHistoryScreen()))),
                _buildActionBtn(context, Icons.file_download, LocalizationService().currentLanguage == 'vi' ? 'Xuất báo cáo Excel' : 'Export Excel', Colors.green, () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExportReportScreen()))),
              ],
            ),
          ],
  
          // --- 5. QUẢN TRỊ HỆ THỐNG (CHỈ DÀNH CHO ADMIN) ---
          if (isAdmin) ...[
            SizedBox(height: 25),
            _buildSectionTitle(LocalizationService().currentLanguage == 'vi' ? 'QUẢN TRỊ HỆ THỐNG' : 'SYSTEM ADMINISTRATION'),
            GridView.count(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.0,
              children: [
                _buildActionBtn(context, Icons.gavel, LocalizationService().currentLanguage == 'vi' ? 'QL Vi phạm' : 'Manage Violations', Colors.red, () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManageViolationsScreen()))),
                _buildActionBtn(context, Icons.task, LocalizationService().currentLanguage == 'vi' ? 'QL Kỳ thi' : 'Manage Exams', Colors.pink, () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManageExamsScreen()))),
                _buildActionBtn(context, Icons.people_alt, LocalizationService().currentLanguage == 'vi' ? 'Học sinh' : 'Students', Colors.indigo, () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManageStudentsScreen()))),
                _buildActionBtn(context, Icons.admin_panel_settings, LocalizationService().currentLanguage == 'vi' ? 'Tài khoản' : 'Accounts', Colors.redAccent, () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManageUsersScreen()))),
                _buildActionBtn(context, Icons.security, LocalizationService().currentLanguage == 'vi' ? 'Khóa IP' : 'Banned IPs', Colors.brown, () => Navigator.push(context, MaterialPageRoute(builder: (_) => BannedIpsScreen()))),
                _buildActionBtn(context, Icons.analytics, LocalizationService().currentLanguage == 'vi' ? 'Lưu lượng' : 'Traffic', Colors.blueGrey, () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrafficMonitorScreen()))),
              ],
            ),
          ],
          SizedBox(height: 40),
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
          color: isDark ? color.withValues(alpha: 0.12) : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 30, color: color),
            SizedBox(height: 8),
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