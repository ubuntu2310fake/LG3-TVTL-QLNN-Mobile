import 'dart:convert';
import 'dart:io';
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart'; 

import 'login_screen.dart';
import 'home_screen.dart';
import 'gate_check_screen.dart';
import 'class_check_screen.dart';
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

import 'human_chat_list_screen.dart';
import 'ai_consulting_screen.dart';
import 'holland_test_screen.dart';

// THÊM DÒNG NÀY ĐỂ LẤY BIẾN currentAppVersion TỪ main.dart
import 'main.dart'; 

const List<FontFeature> _interFeatures = [
  FontFeature.enable('cv05'),
  FontFeature.enable('cv08'),
  FontFeature.enable('ss01'),
];
const double _interSpacing = -0.15; 

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload(); 
  final String? notiStr = prefs.getString('local_notifications');
  List<Map<String, dynamic>> notifs = [];
  if (notiStr != null) {
    try { notifs = List<Map<String, dynamic>>.from(jsonDecode(notiStr)); } catch (e) {}
  }

  String title = message.notification?.title ?? message.data['title'] ?? 'Thông báo hệ thống';
  String body = message.notification?.body ?? message.data['body'] ?? message.data['content'] ?? 'Bạn có thông báo mới.';
  Map<String, String> safeData = {};
  message.data.forEach((k, v) => safeData[k.toString()] = v.toString());
  
  String notiId = message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString();

  if (!notifs.any((n) => n['id'] == notiId)) {
    notifs.insert(0, {
      'id': notiId,
      'title': title, 'body': body, 'isRead': false, 
      'time': DateTime.now().toIso8601String(), 'data': safeData,
    });
    await prefs.setString('local_notifications', jsonEncode(notifs));
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  String _userName = 'Đang tải...';
  String _role = 'STUDENT';
  String _avatar = 'https://qlnn.testifiyonline.xyz/static/default.png';

  final ValueNotifier<List<Map<String, dynamic>>> _notificationsNotifier = ValueNotifier([]);

  bool get _isStaff => ['TEACHER', 'ADMIN', 'RED_FLAG'].contains(_role);

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadNotifications();
    _setupGlobalFCMListeners();
    _checkUpdate(); 
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('full_name') ?? 'Người dùng';
      _role = prefs.getString('role') ?? 'STUDENT';
      _avatar = prefs.getString('avatar') ?? 'https://qlnn.testifiyonline.xyz/static/default.png';
    });
  }

  Future<void> _checkUpdate() async {
    String primaryAbi = 'universal';
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      if (androidInfo.supportedAbis.isNotEmpty) primaryAbi = androidInfo.supportedAbis.first;
    } catch (e) {}

    try {
      final dio = Dio();
      final response = await dio.get(
        'https://qlnn.testifiyonline.xyz/api/check_update.php',
        // Biến currentAppVersion giờ được lấy tự động từ main.dart
        queryParameters: {'version': currentAppVersion, 'abi': primaryAbi}
      );
      
      if (response.statusCode == 200 && response.data['update_available'] == true) {
        final data = response.data;
        final String newVersion = data['version'].toString();
        final String downloadUrl = data['download_url'].toString();
        final String changelog = data['note'] ?? 'Bản cập nhật tối ưu hóa hệ thống.';
        final bool isForceUpdate = data['is_force_update'] == true;
        
        if (mounted) _showUpdateDialog(newVersion, changelog, downloadUrl, isForceUpdate);
      }
    } catch (e) {}
  }

  void _showUpdateDialog(String newVersion, String changelog, String downloadUrl, bool isForceUpdate) {
    bool isDownloading = false; double progress = 0.0;
    showDialog(
      context: context, barrierDismissible: false,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return PopScope(
          canPop: false, 
          child: StatefulBuilder(
            builder: (context, setPopupState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Row(children: [Icon(isForceUpdate ? Icons.warning_amber_rounded : Icons.system_update, color: isForceUpdate ? Colors.red : Colors.blue, size: 28), const SizedBox(width: 10), Expanded(child: Text('Bản cập nhật v$newVersion', style: const TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.bold, fontSize: 18)))]),
                content: Column(
                  mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isForceUpdate) 
                      const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Ứng dụng đã quá cũ và không còn được hỗ trợ. Bắt buộc phải cập nhật để tiếp tục sử dụng!', style: TextStyle(fontFamily: 'Inter', color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14))),
                    const Text('Có phiên bản mới với các thay đổi:', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.bold, color: Colors.blueGrey)), const SizedBox(height: 8),
                    Container(width: double.infinity, constraints: const BoxConstraints(maxHeight: 150), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isDark ? Colors.grey[800] : Colors.grey.shade100, borderRadius: BorderRadius.circular(12), border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300)), child: SingleChildScrollView(child: Text(changelog, style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontSize: 13, color: isDark ? Colors.white70 : Colors.black87)))),
                    if (isDownloading) ...[const SizedBox(height: 20), LinearProgressIndicator(value: progress, backgroundColor: Colors.grey.shade300, color: Colors.blue, minHeight: 8, borderRadius: BorderRadius.circular(10)), const SizedBox(height: 8), Center(child: Text('Đang tải: ${(progress * 100).toStringAsFixed(1)}%', style: const TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.bold, color: Colors.blue)))]
                  ],
                ),
                actions: [
                  if (!isDownloading && !isForceUpdate) 
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Để sau', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, color: Colors.grey))),
                  
                  FilledButton.icon(
                    onPressed: isDownloading ? null : () async {
                      await Permission.requestInstallPackages.request();
                      setPopupState(() { isDownloading = true; progress = 0.0; });
                      try {
                        Directory tempDir = await getTemporaryDirectory(); String savePath = "${tempDir.path}/LG3_Update_v$newVersion.apk";
                        await Dio().download(downloadUrl, savePath, onReceiveProgress: (rcv, total) { if (total != -1) setPopupState(() { progress = rcv / total; }); });
                        if (!isForceUpdate && context.mounted) Navigator.pop(context); 
                        await OpenFilex.open(savePath);
                        if (isForceUpdate) setPopupState(() { isDownloading = false; progress = 1.0; });
                      } catch (e) {
                        setPopupState(() { isDownloading = false; }); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lỗi khi tải bản cập nhật!', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing))));
                      }
                    },
                    icon: isDownloading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.download, size: 18), label: Text(isDownloading ? 'Đang tải...' : 'Cập nhật ngay', style: const TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing)),
                  ),
                ],
              );
            }
          ),
        );
      }
    );
  }

  // ... (TẤT CẢ CÁC HÀM TỪ _loadNotifications TRỞ ĐI GIỮ NGUYÊN BẢN CŨ CỦA SẾP NHA) ...

  Future<void> _loadNotifications() async {
    final prefs = await SharedPreferences.getInstance(); await prefs.reload(); 
    final String? notiStr = prefs.getString('local_notifications');
    if (notiStr != null) { try { _notificationsNotifier.value = List<Map<String, dynamic>>.from(jsonDecode(notiStr)); } catch (e) {} }
  }

  Future<void> _saveNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('local_notifications', jsonEncode(_notificationsNotifier.value));
  }

  Future<void> _setupGlobalFCMListeners() async {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      await _saveIncomingMessage(message, isRead: false);
      String title = message.notification?.title ?? message.data['title'] ?? 'Thông báo mới';
      String body = message.notification?.body ?? message.data['body'] ?? message.data['content'] ?? '';
      Map<String, String> safeData = {}; message.data.forEach((k, v) => safeData[k.toString()] = v.toString());
      _showInAppNotification(title, body, message.messageId ?? '', safeData);
    });
    
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) { _markAsReadAndHandleClick(message); });

    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) { Future.delayed(const Duration(milliseconds: 500), () { _markAsReadAndHandleClick(initialMessage); }); }
  }

  Future<void> _saveIncomingMessage(RemoteMessage message, {required bool isRead}) async {
    String title = message.notification?.title ?? message.data['title'] ?? 'Thông báo hệ thống';
    String body = message.notification?.body ?? message.data['body'] ?? message.data['content'] ?? 'Bạn có thông báo mới.';
    Map<String, String> safeData = {}; message.data.forEach((k, v) => safeData[k.toString()] = v.toString());
    String notiId = message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString();

    final currentNotifs = List<Map<String, dynamic>>.from(_notificationsNotifier.value);
    if (!currentNotifs.any((n) => n['id'] == notiId)) {
      currentNotifs.insert(0, { 'id': notiId, 'title': title, 'body': body, 'isRead': isRead, 'time': DateTime.now().toIso8601String(), 'data': safeData, });
      _notificationsNotifier.value = currentNotifs; await _saveNotifications();
    }
  }

  void _markIdAsRead(String notiId) {
    if (notiId.isEmpty) return;
    List<Map<String, dynamic>> updatedList = List.from(_notificationsNotifier.value);
    int index = updatedList.indexWhere((n) => n['id'] == notiId);
    if (index != -1) {
      updatedList[index]['isRead'] = true; _notificationsNotifier.value = updatedList; _saveNotifications();
    }
  }

  void _markAsReadAndHandleClick(RemoteMessage message) async {
    await _loadNotifications(); await _saveIncomingMessage(message, isRead: true); _markIdAsRead(message.messageId ?? ''); _handleNotificationClick(message.data);
  }

  void _showInAppNotification(String title, String body, String notiId, Map<String, dynamic> data) {
    if (!mounted) return;
    final overlay = Overlay.of(context); late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Positioned(
          top: MediaQuery.of(context).padding.top + 16.0, left: 16.0, right: 16.0,
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder(
              tween: Tween<double>(begin: -100, end: 0), duration: const Duration(milliseconds: 400), curve: Curves.easeOutBack,
              builder: (context, double val, child) { return Transform.translate(offset: Offset(0, val), child: child); },
              child: Dismissible(
                key: UniqueKey(), direction: DismissDirection.up, onDismissed: (_) => entry.remove(),
                child: GestureDetector(
                  onTap: () { entry.remove(); _markIdAsRead(notiId); _handleNotificationClick(data); },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 15, offset: Offset(0, 5))], border: Border.all(color: isDark ? Colors.blue.shade900 : Colors.blue.shade200, width: 1.5)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: isDark ? Colors.blue.withOpacity(0.1) : Colors.blue.shade50, shape: BoxShape.circle), child: const Icon(Icons.notifications_active, color: Colors.blue)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Text(title, style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : Colors.black87)), const SizedBox(height: 4), Text(body, style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontSize: 13, color: isDark ? Colors.white70 : Colors.black54), maxLines: 2, overflow: TextOverflow.ellipsis)])),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    );
    overlay.insert(entry); Future.delayed(const Duration(seconds: 4), () { if (entry.mounted) entry.remove(); });
  }

  void _handleNotificationClick(Map<String, dynamic> data) {
    if (data.containsKey('url')) {
      final url = data['url'].toString();
      if (url.contains('gate_check') && _isStaff) { setState(() => _currentIndex = 1); } 
      else if ((url.contains('class_check') || url.contains('teacher_dashboard')) && _isStaff) { setState(() => _currentIndex = 2); } 
    }
  }

  void _showNotificationsPanel() {
    _loadNotifications();
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: _notificationsNotifier,
          builder: (context, notifs, child) {
            int unreadCount = notifs.where((n) => n['isRead'] == false).length;
            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Thông báo', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontSize: 20, fontWeight: FontWeight.bold)), if (unreadCount > 0) TextButton(onPressed: () { _notificationsNotifier.value = notifs.map((n) => {...n, 'isRead': true}).toList(); _saveNotifications(); }, child: const Text('Đánh dấu đã đọc tất cả', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing)))])
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: notifs.isEmpty
                        ? const Center(child: Text('Không có thông báo nào', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, color: Colors.grey)))
                        : ListView.builder(
                            itemCount: notifs.length,
                            itemBuilder: (context, index) {
                              final n = notifs[index]; final isRead = n['isRead'] == true; final dt = DateTime.parse(n['time']); final timeStr = "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} ${dt.day}/${dt.month}";
                              return Container(
                                color: isRead ? Colors.transparent : (isDark ? Colors.blue.withOpacity(0.1) : Colors.blue.withOpacity(0.05)),
                                child: ListTile(
                                  leading: CircleAvatar(backgroundColor: isRead ? (isDark ? Colors.grey[800] : Colors.grey.shade200) : (isDark ? Colors.blue.shade900 : Colors.blue.shade100), child: Icon(Icons.notifications, color: isRead ? Colors.grey : Colors.blue)),
                                  title: Text(n['title'], style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: isRead ? FontWeight.normal : FontWeight.bold)),
                                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const SizedBox(height: 4), Text(n['body'], style: const TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing)), const SizedBox(height: 4), Text(timeStr, style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontSize: 11, color: isDark ? Colors.blueGrey.shade300 : Colors.blueGrey.shade400))]),
                                  onTap: () { if (!isRead) { _markIdAsRead(n['id'].toString()); } Navigator.pop(context); _handleNotificationClick(n['data'] ?? {}); },
                                  onLongPress: () { List<Map<String, dynamic>> updatedList = List.from(notifs); updatedList.removeAt(index); _notificationsNotifier.value = updatedList; _saveNotifications(); },
                                ),
                              );
                            },
                          ),
                  ),
                  if (notifs.isNotEmpty) TextButton(onPressed: () { _notificationsNotifier.value = []; _saveNotifications(); }, child: const Text('Xóa tất cả', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, color: Colors.red))), const SizedBox(height: 10),
                ],
              ),
            );
          }
        );
      }
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Xác nhận', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing)), content: const Text('Bạn có chắc chắn muốn đăng xuất khỏi thiết bị này?', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing)), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing))), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Đăng xuất', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, color: Colors.red)))]));
    if (confirm != true) return;
    try { final prefs = await SharedPreferences.getInstance(); await http.get(Uri.parse('https://qlnn.testifiyonline.xyz/logout.php'), headers: {'Cookie': 'PHPSESSID=${prefs.getString('phpsessid')}'}); } catch (e) {}
    final prefs = await SharedPreferences.getInstance(); await prefs.clear();
    if (!mounted) return; Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  Widget _buildBody() {
    if (_isStaff) {
      switch (_currentIndex) {
        case 0: return HomeScreen(onNavigate: (index) { setState(() { _currentIndex = index; }); });
        case 1: return const GateCheckScreen();
        case 2: return const ClassCheckScreen();
        default: return const Center(child: Text('Không tìm thấy trang', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing)));
      }
    } else {
      switch (_currentIndex) {
        case 0: return HomeScreen(onNavigate: (index) { setState(() { _currentIndex = index; }); });
        case 1: return const AiConsultingScreen(); 
        case 2: return const RankingScreen();      
        default: return const Center(child: Text('Không tìm thấy trang', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing)));
      }
    }
  }

  String _getAppBarTitle() {
    if (_isStaff) {
      switch (_currentIndex) {
        case 0: return 'LG3-TVTL-QLNN';
        case 1: return 'KIỂM TRA CỔNG';
        case 2: return 'KIỂM TRA LỚP';
        default: return 'LG3';
      }
    } else {
      switch (_currentIndex) {
        case 0: return 'LG3-TVTL-QLNN';
        case 1: return 'CHUYÊN GIA AI';
        case 2: return 'BẢNG XẾP HẠNG';
        default: return 'LG3';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getAppBarTitle(), style: const TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.w900, fontSize: 18)),
        centerTitle: true, elevation: 0, scrolledUnderElevation: 2,
        actions: [
          ValueListenableBuilder<List<Map<String, dynamic>>>(
            valueListenable: _notificationsNotifier,
            builder: (context, notifs, child) {
              int unreadCount = notifs.where((n) => n['isRead'] == false).length;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(icon: const Icon(Icons.notifications_none), onPressed: _showNotificationsPanel),
                  if (unreadCount > 0)
                    Positioned(
                      right: 8, top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        child: Text(unreadCount > 9 ? '9+' : '$unreadCount', style: const TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    )
                ],
              );
            }
          ),
          const SizedBox(width: 8),
        ],
      ),
      
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[900] : Theme.of(context).colorScheme.primary),
              accountName: Text(_userName, style: const TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
              accountEmail: Text('Quyền: $_role', style: const TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, color: Colors.white70)),
              currentAccountPicture: CircleAvatar(backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Theme.of(context).colorScheme.surface, backgroundImage: NetworkImage(_avatar)),
            ),
            
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ListTile(leading: const Icon(Icons.person, color: Colors.blue), title: const Text('Hồ sơ cá nhân', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())); }),
                  ListTile(leading: const Icon(Icons.lock_reset, color: Colors.blueGrey), title: const Text('Đổi mật khẩu', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen())); }),
                  ListTile(leading: const Icon(Icons.workspace_premium, color: Colors.amber), title: const Text('Bảng xếp hạng thi đua', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const RankingScreen())); }),
                  ListTile(leading: const Icon(Icons.settings, color: Colors.grey), title: const Text('Cài đặt App', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())); }),

                  const Divider(),
                  const Padding(padding: EdgeInsets.only(left: 16, top: 8, bottom: 8), child: Text('TƯ VẤN TÂM LÝ', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold))),
                  
                  ListTile(leading: const Icon(Icons.explore, color: Colors.green), title: const Text('Trắc nghiệm Holland', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const HollandTestScreen())); }),
                  ListTile(leading: const Icon(Icons.forum, color: Colors.blue), title: const Text('Tư vấn trực tiếp', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const HumanChatListScreen())); }),
                  ListTile(leading: const Icon(Icons.psychology, color: Colors.purple), title: const Text('Chuyên gia AI', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const AiConsultingScreen())); }),

                  if (['STUDENT', 'RED_FLAG'].contains(_role))
                    ListTile(leading: const Icon(Icons.warning_amber, color: Colors.orange), title: const Text('Lỗi của tôi / Sổ đầu bài', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentViolationsScreen())); }),

                  if (_isStaff) ...[
                    const Divider(),
                    const Padding(padding: EdgeInsets.only(left: 16, top: 8, bottom: 8), child: Text('CÔNG TÁC NỀN NẾP', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold))),
                    
                    ListTile(leading: const Icon(Icons.history, color: Colors.purple), title: const Text('Lịch sử vi phạm', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const ViolationHistoryScreen())); }),
                    ListTile(leading: const Icon(Icons.edit_note, color: Colors.teal), title: const Text('Nhập điểm học tập', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const InputAcademicScreen())); }),
                    ListTile(leading: const Icon(Icons.file_download, color: Colors.green), title: const Text('Xuất báo cáo Excel', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const ExportReportScreen())); }),
                    ListTile(leading: const Icon(Icons.co_present, color: Colors.deepOrange), title: const Text('Lớp của tôi', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherDashboardScreen())); }),
                  ],

                  if (_role == 'ADMIN') ...[
                    const Divider(),
                    const Padding(padding: EdgeInsets.only(left: 16, top: 8, bottom: 8), child: Text('HỆ THỐNG', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold))),
                    
                    ListTile(leading: const Icon(Icons.people_alt, color: Colors.indigo), title: const Text('Học sinh toàn trường', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageStudentsScreen())); }),
                    ListTile(leading: const Icon(Icons.admin_panel_settings, color: Colors.redAccent), title: const Text('Tài khoản & Phân quyền', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageUsersScreen())); }),
                    ListTile(leading: const Icon(Icons.security, color: Colors.brown), title: const Text('Lịch sử khóa IP', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const BannedIpsScreen())); }),
                    ListTile(leading: const Icon(Icons.analytics, color: Colors.blueGrey), title: const Text('Giám sát lưu lượng', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const TrafficMonitorScreen())); }),
                  ],
                ],
              ),
            ),
            
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.logout, color: Colors.redAccent), title: const Text('Đăng xuất', style: TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, color: Colors.redAccent, fontWeight: FontWeight.bold)), onTap: _logout),
            const SizedBox(height: 20),
          ],
        ),
      ),
      
      body: _buildBody(),
      
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarTheme.of(context).copyWith(
          labelTextStyle: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary);
            }
            return const TextStyle(fontFamily: 'Inter', fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey);
          }),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (int index) { setState(() { _currentIndex = index; }); },
          height: 70, labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          destinations: _isStaff 
            ? const [
                NavigationDestination(selectedIcon: Icon(Icons.home), icon: Icon(Icons.home_outlined), label: 'Trang chủ'),
                NavigationDestination(selectedIcon: Icon(Icons.qr_code_scanner), icon: Icon(Icons.qr_code_scanner_outlined), label: 'Kiểm tra cổng'),
                NavigationDestination(selectedIcon: Icon(Icons.fact_check), icon: Icon(Icons.fact_check_outlined), label: 'Kiểm tra lớp'),
              ]
            : const [
                NavigationDestination(selectedIcon: Icon(Icons.home), icon: Icon(Icons.home_outlined), label: 'Trang chủ'),
                NavigationDestination(selectedIcon: Icon(Icons.psychology), icon: Icon(Icons.psychology_outlined), label: 'Tư vấn AI'),
                NavigationDestination(selectedIcon: Icon(Icons.workspace_premium), icon: Icon(Icons.workspace_premium_outlined), label: 'Xếp hạng'),
              ],
        ),
      ),
    );
  }
}