import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart'; 
import 'offline_sync.dart'; 
import 'device_helper.dart';

// --- IMPORT TẤT CẢ CÁC MÀN HÌNH ---
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

class HomeScreen extends StatefulWidget {
  final Function(int) onNavigate; 
  
  const HomeScreen({super.key, required this.onNavigate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _userName = "Đang tải...";
  String _role = "";
  bool _isSyncing = false;
  String _lastSyncStr = "Chưa rõ";
  bool _isNotiEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _triggerAutoSync(); 
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('full_name') ?? 'Người dùng LG3';
      _role = prefs.getString('role') ?? 'STUDENT';
      _isNotiEnabled = prefs.getBool('push_enabled') ?? false;
    });
  }

  Future<void> _triggerAutoSync() async {
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
    setState(() => _isNotiEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('push_enabled', value);
    
    try {
      final sessionId = prefs.getString('phpsessid') ?? '';
      if (value) {
        FirebaseMessaging messaging = FirebaseMessaging.instance;
        await messaging.requestPermission(alert: true, badge: true, sound: true);
        String? fcmToken = await messaging.getToken();
        String realModel = await DeviceHelper.getDeviceModel();

        if (fcmToken != null) {
          await http.post(
            Uri.parse('https://qlnn.testifiyonline.xyz/api/subscribe'),
            headers: {'Content-Type': 'application/json', 'Cookie': 'PHPSESSID=$sessionId'},
            body: jsonEncode({'endpoint': fcmToken, 'platform': 'app', 'device_model': realModel}),
          );
        }
      } else {
        await http.post(
          Uri.parse('https://qlnn.testifiyonline.xyz/gate_check'),
          headers: {'Cookie': 'PHPSESSID=$sessionId', 'Content-Type': 'application/x-www-form-urlencoded'},
          body: 'delete_id=0&only_push=1' 
        );
      }
    } catch (e) {
      setState(() => _isNotiEnabled = false);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // 1. CHỨC NĂNG DÀNH CHO TẤT CẢ MỌI NGƯỜI
    List<Widget> actionButtons = [
      _buildActionBtn(context, Icons.workspace_premium, 'Xếp hạng', Colors.amber.shade700, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RankingScreen()))),
      _buildActionBtn(context, Icons.person, 'Hồ sơ', Colors.green, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()))),
      _buildActionBtn(context, Icons.settings, 'Cài đặt App', Colors.grey.shade700, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
    ];

    // 2. CHỈ HỌC SINH VÀ CỜ ĐỎ MỚI XEM "LỖI CỦA TÔI"
    if (['STUDENT', 'RED_FLAG'].contains(_role)) {
      actionButtons.add(_buildActionBtn(context, Icons.warning_amber, 'Lỗi của tôi', Colors.orange, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentViolationsScreen()))));
    }

    // 3. QUYỀN CÁN BỘ LỚP / GIÁO VIÊN / ADMIN
    if (['TEACHER', 'ADMIN', 'RED_FLAG'].contains(_role)) {
      actionButtons.insertAll(0, [
        _buildActionBtn(context, Icons.qr_code_scanner, 'Kiểm tra cổng', Colors.red, () => widget.onNavigate(1)),
        _buildActionBtn(context, Icons.fact_check, 'Kiểm tra lớp', Colors.blue, () => widget.onNavigate(2)),
      ]);
      actionButtons.addAll([
        _buildActionBtn(context, Icons.history, 'Lịch sử vi phạm', Colors.purple, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ViolationHistoryScreen()))),
        _buildActionBtn(context, Icons.edit_note, 'Điểm học tập', Colors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InputAcademicScreen()))),
        _buildActionBtn(context, Icons.file_download, 'Xuất báo cáo', Colors.green.shade600, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExportReportScreen()))),
        _buildActionBtn(context, Icons.co_present, 'Lớp của tôi', Colors.deepOrange, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherDashboardScreen()))),
      ]);
    }

    // 4. QUYỀN QUẢN TRỊ VIÊN TỐI CAO (ĐÃ RÚT NÚT CÀI ĐẶT RA)
    if (_role == 'ADMIN') {
      actionButtons.addAll([
        _buildActionBtn(context, Icons.people_alt, 'Học sinh', Colors.indigo, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageStudentsScreen()))),
        _buildActionBtn(context, Icons.admin_panel_settings, 'Tài khoản', Colors.redAccent, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageUsersScreen()))),
        _buildActionBtn(context, Icons.security, 'Khóa IP', Colors.brown, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BannedIpsScreen()))),
        _buildActionBtn(context, Icons.analytics, 'Lưu lượng', Colors.blueGrey, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrafficMonitorScreen()))),
      ]);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // THẺ XIN CHÀO
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, Colors.blue.shade800], begin: Alignment.topLeft, end: Alignment.bottomRight),
              boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
            ),
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.white, 
                  radius: 28, 
                  backgroundImage: AssetImage('assets/images/lg3100100.png'),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Tư vấn tâm lý và quản lý thi đua', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      Text(_userName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ĐỒNG BỘ
          Card(
            elevation: 0, shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: _isSyncing ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)) : const Icon(Icons.cloud_done_rounded, color: Colors.green, size: 32),
              title: const Text('Dữ liệu Cục bộ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Text(_isSyncing ? 'Đang tải...' : 'Cập nhật: $_lastSyncStr'),
              trailing: OutlinedButton.icon(onPressed: _isSyncing ? null : _triggerAutoSync, icon: const Icon(Icons.sync, size: 18), label: const Text('Tải lại')),
            ),
          ),
          const SizedBox(height: 12),

          // PUSH NOTIFICATION
          Card(
            elevation: 0, shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(16)),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              secondary: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: _isNotiEnabled ? Colors.orange.withOpacity(0.1) : Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(_isNotiEnabled ? Icons.notifications_active : Icons.notifications_off, color: _isNotiEnabled ? Colors.orange : Colors.grey, size: 24)),
              title: const Text('Nhận Thông báo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: const Text('Báo điểm trừ, tin nhắn AI'),
              value: _isNotiEnabled, activeColor: Colors.orange, onChanged: _toggleNotification,
            ),
          ),

          const SizedBox(height: 30),
          const Text('BẢNG ĐIỀU KHIỂN', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
          const SizedBox(height: 16),
          
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: actionButtons,
          ),
        ],
      ),
    );
  }

  Widget _buildActionBtn(BuildContext context, IconData icon, String title, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.2))),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36, color: color),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}