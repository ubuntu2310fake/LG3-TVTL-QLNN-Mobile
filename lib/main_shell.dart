import 'dart:io';
import 'offline_sync.dart';
import 'dart:convert';
import 'dart:ui'; 
import 'dart:async'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'localization_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart'; 
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'login_screen.dart';
import 'sse_service.dart';
import 'widgets/liquid_glass_container.dart';
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
import 'chess_lobby_screen.dart';

import 'exam_lookup_screen.dart';
import 'manage_exams_screen.dart';
import 'grammar_check_screen.dart';
import 'manage_violations_screen.dart';

import 'human_chat_list_screen.dart';
import 'ai_consulting_screen.dart';
import 'consulting_test_screen.dart'; 
import 'main.dart'; 
import 'config.dart';

const List<FontFeature> _interFeatures = [
  FontFeature.enable('cv05'), FontFeature.enable('cv08'), FontFeature.enable('ss01'),
];
const double _interSpacing = -0.15; 

// ==============================================================
// WIDGET MARQUEE (TỰ ĐỘNG CHẠY CHỮ) CHO TICKER
// ==============================================================
class MarqueeWidget extends StatefulWidget {
  final String text;
  const MarqueeWidget({super.key, required this.text});

  @override
  State<MarqueeWidget> createState() => _MarqueeWidgetState();
}

class _MarqueeWidgetState extends State<MarqueeWidget> {
  late ScrollController _scrollController;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScrolling());
  }

  void _startScrolling() {
    // Chạy vòng lặp đẩy ScrollView nhích sang phải liên tục
    _timer = Timer.periodic(const Duration(milliseconds: 25), (timer) {
      if (_scrollController.hasClients) {
        double maxScroll = _scrollController.position.maxScrollExtent;
        double currentScroll = _scrollController.offset;
        if (currentScroll >= maxScroll) {
          _scrollController.jumpTo(0.0); // Reset về đầu
        } else {
          _scrollController.jumpTo(currentScroll + 1.0); // Tốc độ trôi
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  
  String _getInitialLetter(String name) {
    if (name.isEmpty) return 'U';
    List<String> parts = name.trim().split(RegExp(r'\s+'));
    String last = parts.last;
    return last.isNotEmpty ? last[0].toUpperCase() : name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(), // Khóa không cho kéo tay
      child: Row(
        children: [
          SizedBox(width: MediaQuery.of(context).size.width), // Khoảng trống xuất phát
          Text(
            widget.text, 
            style: TextStyle(
              fontWeight: FontWeight.w600, 
              fontSize: 13, 
              letterSpacing: 0.5,
              color: isDark ? Colors.blue.shade300 : Colors.blue.shade800
            )
          ),
          SizedBox(width: MediaQuery.of(context).size.width), // Khoảng trống chờ lặp lại
        ],
      ),
    );
  }
}

// ==============================================================
// MAIN SHELL CLASS
// ==============================================================
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {

  Future<void> _requestNotificationPermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (!status.isGranted) await Permission.notification.request();
    }
  }
  
  int _currentIndex = 0;
  String _userName = LocalizationService().currentLanguage == 'vi' ? 'Đang tải...' : 'Loading...';
  String _role = 'STUDENT';
  String _avatar = '${AppConfig.baseUrl}/static/default.png';
  String _localAvatarPath = '';
  String _tickerText = ''; // BIẾN LƯU NỘI DUNG TICKER
  bool _isOfflineMode = false;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  final ValueNotifier<List<Map<String, dynamic>>> _notificationsNotifier = ValueNotifier([]);

  Timer? _notiTimer;
  String _lastNotiStr = '';
  final Set<String> _seenNotiIds = {};

  bool get _isStaff => ['TEACHER', 'ADMIN', 'RED_FLAG'].contains(_role);
  bool get _isAdmin => _role == 'ADMIN';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestNotificationPermission();
    _loadUserData();
    _fetchTicker(); // GỌI API TẢI TICKER
    _loadNotifications(isInit: true); 
    _setupGlobalFCMListeners();
    _checkUpdate(); 

    _notiTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _loadNotifications(isInit: false);
    });

    // Khởi động SSE Stream để nhận thông báo thời gian thực ngay trên app
    SseService().start(onNotification: (title, body, notiId, data) {
      if (mounted) {
        _showInAppNotification(title, body, notiId, data);
        _loadNotifications(isInit: false);
      }
    });

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> result) {
      bool isOffline = !result.contains(ConnectivityResult.wifi) && !result.contains(ConnectivityResult.mobile) && !result.contains(ConnectivityResult.ethernet);
      if (mounted && _isOfflineMode != isOffline) {
        setState(() { _isOfflineMode = isOffline; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isOffline ? LocalizationService().currentLanguage == 'vi' ? 'Đã mất kết nối mạng. Chuyển sang chế độ ngoại tuyến.' : 'Network disconnected. Switched to offline mode.' : LocalizationService().currentLanguage == 'vi' ? 'Đã khôi phục kết nối mạng.' : 'Network connection restored.'),
          backgroundColor: isOffline ? Colors.red : Colors.green,
          duration: const Duration(seconds: 3),
        ));
      }
    });
    Connectivity().checkConnectivity().then((result) {
      bool isOffline = !result.contains(ConnectivityResult.wifi) && !result.contains(ConnectivityResult.mobile) && !result.contains(ConnectivityResult.ethernet);
      if (mounted) setState(() { _isOfflineMode = isOffline; });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SseService().stop();
    _notiTimer?.cancel(); 
    _connectivitySubscription.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadNotifications(isInit: false, forceReload: true);
      _fetchTicker(); // Nạp lại Ticker khi mở lại app
    }
  }

  // LẤY DỮ LIỆU TICKER TỪ MÁY CHỦ
  Future<void> _fetchTicker() async {
    try {
      final dio = Dio();
      final response = await dio.get('${AppConfig.baseUrl}/api/get_ticker_api.php');
      if (response.statusCode == 200 && response.data['status'] == 'success') {
        setState(() {
          _tickerText = response.data['ticker'] ?? '';
        });
      }
    } catch (e) {
      debugPrint(LocalizationService().currentLanguage == 'vi' ? "Lỗi tải Ticker: $e" : "Error loading Ticker: $e");
    }
  }

  bool _isForceChangePassShown = false;

  Future<void> _checkForceChangePassword() async {
    final prefs = await SharedPreferences.getInstance();
    bool mustChange = prefs.getBool('must_change_password') ?? false;
    
    if (!mustChange) {
      try {
        final sessionId = prefs.getString('phpsessid') ?? '';
        if (sessionId.isNotEmpty) {
          final res = await http.get(
            Uri.parse('${AppConfig.baseUrl}/api/profile_api.php'),
            headers: {'Cookie': 'PHPSESSID=$sessionId'},
          );
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            if (data['user'] != null && data['user']['must_change_password'] == true) {
              mustChange = true;
              await prefs.setBool('must_change_password', true);
            }
          }
        }
      } catch (_) {}
    }

    if (mustChange && mounted && !_isForceChangePassShown) {
      _isForceChangePassShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showForceChangePasswordDialog();
      });
    }
  }

  void _showForceChangePasswordDialog() {
    final oldPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    bool obscureOld = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          bool isVi = LocalizationService().currentLanguage == 'vi';
          return PopScope(
            canPop: false,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              title: Column(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.key_rounded, color: Colors.red, size: 32),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isVi ? 'Yêu Cầu Đổi Mật Khẩu' : 'Password Change Required',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: GoogleFonts.beVietnamPro().fontFamily,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isVi
                        ? 'Tài khoản của bạn đang sử dụng mật khẩu mặc định. Để bảo vệ dữ liệu cá nhân, vui lòng tạo mật khẩu mới để tiếp tục.'
                        : 'Your account is using a default password. To protect your personal data, please create a new password to continue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.normal,
                      fontFamily: GoogleFonts.beVietnamPro().fontFamily,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    // Mật khẩu hiện tại
                    TextField(
                      controller: oldPassCtrl,
                      obscureText: obscureOld,
                      decoration: InputDecoration(
                        labelText: isVi ? 'Mật khẩu hiện tại' : 'Current password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(obscureOld ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setDialogState(() => obscureOld = !obscureOld),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Mật khẩu mới
                    TextField(
                      controller: newPassCtrl,
                      obscureText: obscureNew,
                      decoration: InputDecoration(
                        labelText: isVi ? 'Mật khẩu mới' : 'New password',
                        prefixIcon: const Icon(Icons.lock_reset_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(obscureNew ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isVi
                          ? '🔒 Yêu cầu: Ít nhất 6 ký tự, gồm chữ hoa (A-Z), chữ thường (a-z), số (0-9) và ký tự đặc biệt (!@#...).'
                          : '🔒 Required: At least 6 chars, incl. uppercase (A-Z), lowercase (a-z), numbers (0-9) and special chars (!@#...).',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 14),
                    // Nhập lại mật khẩu mới
                    TextField(
                      controller: confirmPassCtrl,
                      obscureText: obscureConfirm,
                      decoration: InputDecoration(
                        labelText: isVi ? 'Xác nhận mật khẩu mới' : 'Confirm new password',
                        prefixIcon: const Icon(Icons.check_circle_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(obscureConfirm ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF005FBA),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            String oldP = oldPassCtrl.text.trim();
                            String newP = newPassCtrl.text;
                            String confirmP = confirmPassCtrl.text;

                            if (oldP.isEmpty || newP.isEmpty || confirmP.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(isVi ? '❌ Vui lòng điền đủ tất cả các trường!' : '❌ Please fill in all fields!'),
                                backgroundColor: Colors.red,
                              ));
                              return;
                            }

                            if (newP != confirmP) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(isVi ? '❌ Mật khẩu xác nhận không khớp!' : '❌ Passwords do not match!'),
                                backgroundColor: Colors.red,
                              ));
                              return;
                            }

                            if (newP == '123456') {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(isVi ? '❌ Mật khẩu mới không được là 123456!' : '❌ New password cannot be 123456!'),
                                backgroundColor: Colors.red,
                              ));
                              return;
                            }

                            if (newP.length < 6) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(isVi ? '❌ Mật khẩu phải có ít nhất 6 ký tự!' : '❌ Password must be at least 6 characters!'),
                                backgroundColor: Colors.red,
                              ));
                              return;
                            }

                            if (!RegExp(r'[A-Z]').hasMatch(newP)) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(isVi ? '❌ Mật khẩu phải chứa ít nhất 1 chữ cái viết hoa (A-Z)!' : '❌ Must contain at least 1 uppercase letter (A-Z)!'),
                                backgroundColor: Colors.red,
                              ));
                              return;
                            }

                            if (!RegExp(r'[a-z]').hasMatch(newP)) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(isVi ? '❌ Mật khẩu phải chứa ít nhất 1 chữ cái viết thường (a-z)!' : '❌ Must contain at least 1 lowercase letter (a-z)!'),
                                backgroundColor: Colors.red,
                              ));
                              return;
                            }

                            if (!RegExp(r'[0-9]').hasMatch(newP)) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(isVi ? '❌ Mật khẩu phải chứa ít nhất 1 chữ số (0-9)!' : '❌ Must contain at least 1 digit (0-9)!'),
                                backgroundColor: Colors.red,
                              ));
                              return;
                            }

                            if (!RegExp(r'[^A-Za-z0-9]').hasMatch(newP)) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(isVi ? '❌ Mật khẩu phải chứa ít nhất 1 ký tự đặc biệt (!@#...)!' : '❌ Must contain at least 1 special character (!@#...)!'),
                                backgroundColor: Colors.red,
                              ));
                              return;
                            }

                            setDialogState(() => isSubmitting = true);

                            try {
                              final prefs = await SharedPreferences.getInstance();
                              final sessionId = prefs.getString('phpsessid') ?? '';
                              final res = await http.post(
                                Uri.parse('${AppConfig.baseUrl}/api/change_password_api.php'),
                                headers: {'Cookie': 'PHPSESSID=$sessionId'},
                                body: {
                                  'action': 'change_password',
                                  'old_password': oldP,
                                  'new_password': newP,
                                  'confirm_password': confirmP,
                                },
                              );
                              final data = jsonDecode(res.body);
                              if (data['status'] == 'success') {
                                await prefs.setBool('must_change_password', false);
                                _isForceChangePassShown = false;
                                if (mounted) {
                                  Navigator.of(dialogCtx, rootNavigator: true).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(isVi ? '✅ Đổi mật khẩu thành công!' : '✅ Password changed successfully!'),
                                    backgroundColor: Colors.green,
                                  ));
                                }
                              } else {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(data['msg'] ?? (isVi ? 'Đổi mật khẩu thất bại!' : 'Failed to change password!')),
                                    backgroundColor: Colors.red,
                                  ));
                                }
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(isVi ? 'Lỗi kết nối máy chủ' : 'Server connection error'),
                                  backgroundColor: Colors.red,
                                ));
                              }
                            } finally {
                              setDialogState(() => isSubmitting = false);
                            }
                          },
                    child: isSubmitting
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.save, size: 20),
                              const SizedBox(width: 8),
                              Text(isVi ? 'LƯU VÀ TIẾP TỤC' : 'SAVE AND CONTINUE', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: () async {
                      Navigator.of(dialogCtx, rootNavigator: true).pop();
                      _isForceChangePassShown = false;
                      try {
                        final prefs = await SharedPreferences.getInstance();
                        await http.get(Uri.parse('${AppConfig.baseUrl}/logout.php'), headers: {'Cookie': 'PHPSESSID=${prefs.getString('phpsessid')}'});
                        await prefs.clear();
                      } catch (_) {}
                      if (!mounted) return;
                      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                    },
                    icon: const Icon(Icons.logout, size: 18, color: Colors.grey),
                    label: Text(
                      isVi ? 'Đăng xuất tài khoản' : 'Logout',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('full_name') ?? (LocalizationService().currentLanguage == 'vi' ? 'Người dùng' : 'User');
      _role = prefs.getString('role') ?? 'STUDENT';
      _avatar = prefs.getString('avatar') ?? '${AppConfig.baseUrl}/static/default.png';
      _localAvatarPath = prefs.getString('local_avatar_path') ?? '';
    });
    
    // Kiểm tra xem có bắt buộc đổi mật khẩu mặc định hay không
    _checkForceChangePassword();

    // Asynchronously sync avatar and master data
    try {
      final sessionId = prefs.getString('phpsessid') ?? '';
      if (sessionId.isNotEmpty) {
        await OfflineSyncService.syncUserAvatar(sessionId);
        if (mounted) {
          setState(() {
            _avatar = prefs.getString('avatar') ?? _avatar;
            _localAvatarPath = prefs.getString('local_avatar_path') ?? '';
            _userName = prefs.getString('full_name') ?? _userName;
          });
        }
      }
    } catch (_) {}
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
        '${AppConfig.baseUrl}/api/check_update.php',
        queryParameters: {'version': currentAppVersion, 'abi': primaryAbi}
      );
      
      if (response.statusCode == 200 && response.data['update_available'] == true) {
        final data = response.data;
        if (mounted) _showUpdateDialog(data['version'].toString(), data['note'] ?? (LocalizationService().currentLanguage == 'vi' ? 'Bản cập nhật tối ưu hóa' : 'Optimization update'), data['download_url'].toString(), data['is_force_update'] == true);
      } else if (response.statusCode == 200 && response.data['hotfix_available'] == true) {
        final data = response.data;
        final int patchNum = data['latest_patch'] ?? 1;
        final String patchUrl = data['download_url']?.toString() ?? '';
        final String changelog = data['note'] ?? 'Bản vá Hotfix';
        if (mounted) _showHotfixPopup(patchNum, changelog, patchUrl);
      } else {
        // Nếu không có bản cập nhật mới, kiểm tra nhắc người dùng bật Mở liên kết mặc định
        _checkDefaultLinkPrompt();
      }
    } catch (e) {
      _checkDefaultLinkPrompt();
    }
  }

  Future<void> _checkDefaultLinkPrompt() async {
    if (!Platform.isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      bool hasAsked = prefs.getBool('has_prompted_default_links') ?? false;
      if (!hasAsked && mounted) {
        // Đợi UI render xong thì hiện dialog gợi ý bật liên kết mặc định
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _showDefaultLinkDialog();
        });
      }
    } catch (_) {}
  }

  void _showHotfixPopup(int patchNum, String changelog, String downloadUrl) {
    bool isApplying = false;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setHotfixState) {
          bool isVi = LocalizationService().currentLanguage == 'vi';
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.bolt, color: Colors.amber, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isVi ? 'Bản vá nhanh #$patchNum' : 'Hotfix Patch #$patchNum',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isVi ? 'Có bản vá sửa lỗi nhanh không cần cài lại APK:' : 'A fast hotfix patch is available:',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 120),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.withOpacity(0.3)),
                  ),
                  child: SingleChildScrollView(
                    child: Text(changelog, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                  ),
                ),
              ],
            ),
            actions: [
              if (!isApplying)
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(isVi ? 'Để sau' : 'Later', style: const TextStyle(color: Colors.grey)),
                ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.amber.shade800,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: isApplying
                    ? null
                    : () async {
                        setHotfixState(() => isApplying = true);
                        try {
                          await Future.delayed(const Duration(seconds: 1));
                          if (mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(isVi ? '✅ Đã nạp bản vá thành công!' : '✅ Hotfix applied successfully!'),
                              backgroundColor: Colors.green,
                            ));
                          }
                        } catch (e) {
                          setHotfixState(() => isApplying = false);
                        }
                      },
                icon: isApplying
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.download_done, size: 18),
                label: Text(isApplying ? (isVi ? 'Đang nạp...' : 'Applying...') : (isVi ? 'Áp dụng ngay' : 'Apply Now')),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDefaultLinkDialog() {
    bool isVi = LocalizationService().currentLanguage == 'vi';
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF005FBA).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.link_rounded, color: Color(0xFF005FBA), size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isVi ? 'Mở trực tiếp trên App' : 'Open Links in App',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isVi 
                ? 'Để trải nghiệm tốt nhất (tự động mở App khi bấm vào link học sinh, thông báo, mã QR thay vì mở trình duyệt Web), vui lòng bật quyền "Mở các liên kết được hỗ trợ".'
                : 'For the best experience, allow LG3 App to automatically open supported links (*.testifiyonline.xyz) directly instead of browser.',
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: Color(0xFF005FBA)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isVi ? 'Bấm "Cài đặt" -> Bật "Mở các liên kết được hỗ trợ"' : 'Tap "Settings" -> Enable "Open supported links"',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF005FBA)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('has_prompted_default_links', true);
              if (mounted) Navigator.pop(ctx);
            },
            child: Text(isVi ? 'Để sau' : 'Later', style: const TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF005FBA),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('has_prompted_default_links', true);
              if (mounted) Navigator.pop(ctx);
              try {
                const platform = MethodChannel('com.lg3.app/default_settings');
                await platform.invokeMethod('openAppOpenByDefaultSettings');
              } catch (_) {}
            },
            child: Text(isVi ? 'Cài đặt ngay' : 'Open Settings', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
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
                title: Row(children: [Icon(isForceUpdate ? Icons.warning_amber_rounded : Icons.system_update, color: isForceUpdate ? Colors.red : Colors.blue, size: 28), SizedBox(width: 10), Expanded(child: Text(LocalizationService().currentLanguage == 'vi' ? 'Bản cập nhật v$newVersion' : 'Update v$newVersion', style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.bold, fontSize: 18)))]),
                content: Column(
                  mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isForceUpdate) Padding(padding: EdgeInsets.only(bottom: 12), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Bắt buộc phải cập nhật để tiếp tục sử dụng!' : 'Update required to continue!', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14))),
                    Text(LocalizationService().currentLanguage == 'vi' ? 'Thay đổi:' : 'Changelog:', style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.bold, color: Colors.blueGrey)), SizedBox(height: 8),
                    Container(width: double.infinity, constraints: const BoxConstraints(maxHeight: 150), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isDark ? Colors.grey[800] : Colors.grey.shade100, borderRadius: BorderRadius.circular(12), border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300)), child: SingleChildScrollView(child: Text(changelog, style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontSize: 13, color: isDark ? Colors.white70 : Colors.black87)))),
                    if (isDownloading) ...[SizedBox(height: 20), LinearProgressIndicator(value: progress, backgroundColor: Colors.grey.shade300, color: Colors.blue, minHeight: 8, borderRadius: BorderRadius.circular(10)), SizedBox(height: 8), Center(child: Text(LocalizationService().currentLanguage == 'vi' ? 'Đang tải: ${(progress * 100).toStringAsFixed(1)}%' : 'Downloading: ${(progress * 100).toStringAsFixed(1)}%', style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.bold, color: Colors.blue)))]
                  ],
                ),
                actions: [
                  if (!isDownloading && !isForceUpdate) 
                    TextButton(onPressed: () => Navigator.pop(context), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Để sau' : 'Later', style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, color: Colors.grey))),
                  FilledButton.icon(
                    onPressed: isDownloading ? null : () async {
                      if (Platform.isIOS) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Vui lòng cập nhật ứng dụng từ App Store / TestFlight.' : 'Please update the app from App Store / TestFlight.')));
                        return;
                      }
                      if (Platform.isAndroid) {
                        final status = await Permission.requestInstallPackages.status;
                        if (!status.isGranted) {
                          final req = await Permission.requestInstallPackages.request();
                          if (!req.isGranted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(LocalizationService().currentLanguage == 'vi'
                                  ? 'Vui lòng cấp quyền Cài đặt ứng dụng không rõ nguồn gốc để tiếp tục!'
                                  : 'Please grant Install Unknown Apps permission to update!'),
                              action: SnackBarAction(
                                label: LocalizationService().currentLanguage == 'vi' ? 'Cài đặt' : 'Settings',
                                onPressed: () => openAppSettings(),
                              ),
                            ));
                            return;
                          }
                        }
                      }
                      setPopupState(() { isDownloading = true; progress = 0.0; });
                      try {
                        Directory? downloadDir;
                        if (Platform.isAndroid) {
                          final extDirs = await getExternalCacheDirectories();
                          if (extDirs != null && extDirs.isNotEmpty) {
                            downloadDir = extDirs.first;
                          }
                        }
                        downloadDir ??= await getTemporaryDirectory();
                        String savePath = "${downloadDir.path}/LG3_v$newVersion.apk";
                        final file = File(savePath);
                        if (await file.exists()) {
                          try { await file.delete(); } catch (_) {}
                        }
                        await Dio().download(downloadUrl, savePath, onReceiveProgress: (rcv, total) { if (total != -1) setPopupState(() { progress = rcv / total; }); });
                        if (!isForceUpdate && context.mounted) Navigator.pop(context); 
                        if (Platform.isAndroid) {
                          final result = await OpenFilex.open(savePath, type: 'application/vnd.android.package-archive');
                          if (result.type != ResultType.done && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Không thể tự mở file APK (${result.message})' : 'Could not open APK (${result.message})')));
                          }
                        }
                        if (isForceUpdate) setPopupState(() { isDownloading = false; progress = 1.0; });
                      } catch (e) {
                        setPopupState(() { isDownloading = false; }); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Lỗi tải bản cập nhật!' : 'Failed to download update!')));
                      }
                    },
                    icon: isDownloading ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Icon(Icons.download, size: 18), label: Text(isDownloading ? LocalizationService().currentLanguage == 'vi' ? 'Đang tải...' : 'Loading...' : LocalizationService().currentLanguage == 'vi' ? 'Cập nhật ngay' : 'Update now', style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing)),
                  ),
                ],
              );
            }
          ),
        );
      }
    );
  }

  Future<void> _loadNotifications({bool isInit = false, bool forceReload = false}) async {
    final prefs = await SharedPreferences.getInstance(); 
    if (isInit || forceReload) await prefs.reload();
    final String? notiStr = prefs.getString('local_notifications');
    final bool isNotiEnabled = prefs.getBool('push_enabled') ?? true;

    if (notiStr != null && notiStr != _lastNotiStr) { 
      _lastNotiStr = notiStr;
      try { 
        List<dynamic> raw = jsonDecode(notiStr); 
        final newList = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _notificationsNotifier.value = newList;
        
        int delayMs = 0;
        for (var n in newList) {
          String nid = n['id'].toString();
          if (!_seenNotiIds.contains(nid)) {
            _seenNotiIds.add(nid);
            if (!isInit && isNotiEnabled && !forceReload) {
              final dt = DateTime.parse(n['time']);
              if (DateTime.now().difference(dt).inSeconds < 60) {
                final notiData = Map<String, dynamic>.from(n['data'] ?? {});
                final type = (notiData['type'] ?? '').toString();
                if (type == 'CHESS_CHALLENGE') {
                  Future.delayed(Duration(milliseconds: delayMs), () {
                    if (mounted) _showChessChallengeDialog(notiData);
                  });
                } else {
                  Future.delayed(Duration(milliseconds: delayMs), () {
                    if (mounted) _showInAppNotification(n['title'], n['body'], nid, notiData);
                  });
                }
                delayMs += 800; 
              }
            }
          }
        }
      } catch (e) {} 
    }
  }

  Future<void> _saveNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    String str = jsonEncode(_notificationsNotifier.value);
    _lastNotiStr = str; 
    await prefs.setString('local_notifications', str);
  }

  Future<void> _setupGlobalFCMListeners() async {
    FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) { _markAsReadAndHandleClick(message); });
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) { Future.delayed(const Duration(milliseconds: 500), () { _markAsReadAndHandleClick(initialMessage); }); }
  }

  void _markIdAsRead(String notiId) {
    if (notiId.isEmpty) return;
    List<Map<String, dynamic>> updatedList = List.from(_notificationsNotifier.value);
    int index = updatedList.indexWhere((n) => n['id'] == notiId);
    if (index != -1) {
      updatedList[index]['isRead'] = true; 
      _notificationsNotifier.value = updatedList; 
      _saveNotifications();
    }
  }

  void _markAsReadAndHandleClick(RemoteMessage message) async {
    await _loadNotifications(isInit: false, forceReload: true); 
    _markIdAsRead(message.messageId ?? ''); 
    _handleNotificationClick(message.data);
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
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 15, offset: Offset(0, 5))], border: Border.all(color: isDark ? Colors.blue.shade900 : Colors.blue.shade200, width: 1.5)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: isDark ? Colors.blue.withValues(alpha: 0.1) : Colors.blue.shade50, shape: BoxShape.circle), child: Icon(Icons.notifications_active, color: Colors.blue)),
                        SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Text(title, style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : Colors.black87)), SizedBox(height: 4), Text(body, style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontSize: 13, color: isDark ? Colors.white70 : Colors.black54), maxLines: 2, overflow: TextOverflow.ellipsis)])),
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
    final url = (data['url'] ?? '').toString();
    final action = (data['action'] ?? '').toString();
    final type = (data['type'] ?? '').toString();

    // 1. Vi phạm của tôi (Chính học sinh bị trừ điểm)
    if (action == 'open_student_violations' || url.contains('student_violations')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentViolationsScreen()));
    }
    // 2. Lớp của tôi (GVCN / Học sinh cùng lớp / Cảnh báo tâm lý gửi GVCN)
    else if (action == 'open_my_class' || url.contains('teacher_dashboard') || url.contains('my_class')) {
      if (_isStaff) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherDashboardScreen()));
      } else {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentViolationsScreen()));
      }
    }
    // 3. Lịch sử vi phạm (GV không chủ nhiệm / Admin)
    else if (action == 'open_violation_history' || url.contains('violation_history')) {
      if (_isStaff) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ViolationHistoryScreen()));
      } else {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentViolationsScreen()));
      }
    }
    // 4. Trực cổng / Kiểm tra cổng
    else if (action == 'open_gate_check' || url.contains('gate_check')) {
      if (_isStaff) {
        setState(() => _currentIndex = 1);
      } else {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentViolationsScreen()));
      }
    }
    // 5. Kiểm tra lớp
    else if (action == 'open_class_check' || url.contains('class_check')) {
      if (_isStaff) {
        setState(() => _currentIndex = 2);
      } else {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentViolationsScreen()));
      }
    }
    // 6. Chat tư vấn tâm lý / Bạn bè
    else if (action == 'open_chat' || url.contains('consulting_dashboard') || url.contains('chat')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const HumanChatListScreen()));
    }
    // 7. Lời mời kết bạn / Trang cá nhân
    else if (action == 'open_friends' || url.contains('friends') || url.contains('my_profile')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
    }
    // 8. Tra cứu điểm thi
    else if (action == 'open_exam_scores' || url.contains('exam') || url.contains('tracuudiemthi')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ExamLookupScreen()));
    }
    // 9. Cảnh báo tâm lý fallback
    else if (action == 'open_psychology_alert') {
      if (_isStaff) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherDashboardScreen()));
      }
    }
    // 10. Thách đấu Cờ Vua
    else if (action == 'open_chess' || url.contains('chess') || type == 'CHESS_CHALLENGE') {
      final matchId = (data['target_id'] ?? data['match_id'] ?? '').toString();
      if (matchId.isNotEmpty) {
        _showChessChallengeDialog(data);
      } else {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ChessLobbyScreen()));
      }
    }
  }

  void _showChessChallengeDialog(Map<String, dynamic> data) {
    if (!mounted) return;
    final matchId = (data['target_id'] ?? data['match_id'] ?? '').toString();
    final challengerName = (data['challenger_name'] ?? data['title'] ?? (LocalizationService().currentLanguage == 'vi' ? 'Đối thủ' : 'Opponent')).toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.sports_esports_rounded, color: Colors.orange, size: 40),
        title: Text(LocalizationService().currentLanguage == 'vi' ? 'Thách đấu Cờ Vua' : 'Chess Challenge'),
        content: Text(
          LocalizationService().currentLanguage == 'vi'
              ? '$challengerName muốn thách đấu cờ vua với bạn!'
              : '$challengerName wants to challenge you to a chess match!',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final prefs = await SharedPreferences.getInstance();
              final sessionId = prefs.getString('phpsessid') ?? '';
              http.post(
                Uri.parse('${AppConfig.baseUrl}/api/chess_api.php'),
                headers: {'Cookie': 'PHPSESSID=$sessionId', 'Content-Type': 'application/x-www-form-urlencoded'},
                body: 'action=decline&match_id=$matchId',
              );
            },
            child: Text(LocalizationService().currentLanguage == 'vi' ? 'Từ chối' : 'Decline'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final prefs = await SharedPreferences.getInstance();
              final sessionId = prefs.getString('phpsessid') ?? '';
              final res = await http.post(
                Uri.parse('${AppConfig.baseUrl}/api/chess_api.php'),
                headers: {'Cookie': 'PHPSESSID=$sessionId', 'Content-Type': 'application/x-www-form-urlencoded'},
                body: 'action=accept&match_id=$matchId',
              );
              try {
                final d = jsonDecode(res.body);
                if (d['status'] == 'success') {
                  if (mounted) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ChessLobbyScreen(matchId: matchId)));
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(d['msg'] ?? 'Error')));
                  }
                }
              } catch (_) {
                if (mounted) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ChessLobbyScreen(matchId: matchId)));
                }
              }
            },
            child: Text(LocalizationService().currentLanguage == 'vi' ? 'Chấp nhận' : 'Accept'),
          ),
        ],
      ),
    );
  }

  void _showNotificationsPanel() {
    _loadNotifications(isInit: false);
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
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(LocalizationService().currentLanguage == 'vi' ? 'Thông báo' : 'Notifications', style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontSize: 20, fontWeight: FontWeight.bold)), if (unreadCount > 0) TextButton(onPressed: () { _notificationsNotifier.value = notifs.map((n) => {...n, 'isRead': true}).toList(); _saveNotifications(); }, child: Text(LocalizationService().currentLanguage == 'vi' ? 'Đánh dấu đã đọc tất cả' : 'Mark all as read', style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing)))])
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: notifs.isEmpty
                        ? Center(child: Text(LocalizationService().currentLanguage == 'vi' ? 'Không có thông báo nào' : 'No notifications', style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, color: Colors.grey)))
                        : ListView.builder(
                            itemCount: notifs.length,
                            itemBuilder: (context, index) {
                              final n = notifs[index]; final isRead = n['isRead'] == true; final dt = DateTime.parse(n['time']); final timeStr = "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} ${dt.day}/${dt.month}";
                              return Container(
                                color: isRead ? Colors.transparent : (isDark ? Colors.blue.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.05)),
                                child: ListTile(
                                  leading: CircleAvatar(backgroundColor: isRead ? (isDark ? Colors.grey[800] : Colors.grey.shade200) : (isDark ? Colors.blue.shade900 : Colors.blue.shade100), child: Icon(Icons.notifications, color: isRead ? Colors.grey : Colors.blue)),
                                  title: Text(n['title'], style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: isRead ? FontWeight.normal : FontWeight.bold)),
                                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(height: 4), Text(n['body'], style: const TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing)), SizedBox(height: 4), Text(timeStr, style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontSize: 11, color: isDark ? Colors.blueGrey.shade300 : Colors.blueGrey.shade400))]),
                                  onTap: () { if (!isRead) { _markIdAsRead(n['id'].toString()); } Navigator.pop(context); _handleNotificationClick(n['data'] ?? {}); },
                                  onLongPress: () { List<Map<String, dynamic>> updatedList = List.from(notifs); updatedList.removeAt(index); _notificationsNotifier.value = updatedList; _saveNotifications(); },
                                ),
                              );
                            },
                          ),
                  ),
                  if (notifs.isNotEmpty) TextButton(onPressed: () { _notificationsNotifier.value = []; _saveNotifications(); }, child: Text(LocalizationService().currentLanguage == 'vi' ? 'Xóa tất cả' : 'Clear all', style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, color: Colors.red))), SizedBox(height: 10),
                ],
              ),
            );
          }
        );
      }
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: Text(LocalizationService().currentLanguage == 'vi' ? 'Xác nhận' : 'Confirm', style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing)), content: Text(LocalizationService().currentLanguage == 'vi' ? 'Bạn có chắc chắn muốn đăng xuất khỏi thiết bị này?' : 'Are you sure you want to log out from this device?', style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing)), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Hủy' : 'Cancel', style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing))), TextButton(onPressed: () => Navigator.pop(context, true), child: Text(T('logout', def: LocalizationService().currentLanguage == 'vi' ? 'Đăng xuất' : 'Logout'), style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, color: Colors.red)))]));
    if (confirm != true) return;
    try { final prefs = await SharedPreferences.getInstance(); await http.get(Uri.parse('${AppConfig.baseUrl}/logout.php'), headers: {'Cookie': 'PHPSESSID=${prefs.getString('phpsessid')}'}); } catch (e) {}
    final prefs = await SharedPreferences.getInstance(); await prefs.clear();
    if (!mounted) return; Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  Widget _buildBody() {
    if (_isStaff) {
      switch (_currentIndex) {
        case 0: return HomeScreen(onNavigate: (index) { setState(() { _currentIndex = index; }); }, isOffline: _isOfflineMode);
        case 1: return const GateCheckScreen();
        case 2: return const ClassCheckScreen();
        default: return Center(child: Text(LocalizationService().currentLanguage == 'vi' ? 'Không tìm thấy trang' : 'Page not found', style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing)));
      }
    } else {
      switch (_currentIndex) {
        case 0: return HomeScreen(onNavigate: (index) { setState(() { _currentIndex = index; }); }, isOffline: _isOfflineMode);
        case 1: return const AiConsultingScreen(); 
        case 2: return const RankingScreen();      
        default: return Center(child: Text(LocalizationService().currentLanguage == 'vi' ? 'Không tìm thấy trang' : 'Page not found', style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing)));
      }
    }
  }

  String _getAppBarTitle() {
    if (_isStaff) {
      switch (_currentIndex) {
        case 0: return LocalizationService().currentLanguage == 'vi' ? 'Siêu ứng dụng LG3' : 'LG3 Super App';
        case 1: return LocalizationService().currentLanguage == 'vi' ? 'KIỂM TRA CỔNG' : 'GATE CHECK';
        case 2: return LocalizationService().currentLanguage == 'vi' ? 'KIỂM TRA LỚP' : 'CLASS CHECK';
        default: return 'LG3';
      }
    } else {
      switch (_currentIndex) {
        case 0: return LocalizationService().currentLanguage == 'vi' ? 'Siêu ứng dụng LG3' : 'LG3 Super App';
        case 1: return 'GÓC TƯ VẤN';
        case 2: return 'BẢNG XẾP HẠNG';
        default: return 'LG3';
      }
    }
  }

  
  String _getInitialLetter(String name) {
    if (name.isEmpty) return 'U';
    List<String> parts = name.trim().split(RegExp(r'\s+'));
    String last = parts.last;
    return last.isNotEmpty ? last[0].toUpperCase() : name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      extendBodyBehindAppBar: false,
      extendBody: false,
      appBar: AppBar(
        title: Text(_getAppBarTitle(), style: const TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.w900, fontSize: 18)),
        centerTitle: true, elevation: 0, scrolledUnderElevation: 2,
        backgroundColor: null,
        surfaceTintColor: Colors.transparent, // CRITICAL FIX for Material 3 opaque bug
        flexibleSpace: null,
        actions: [
          ValueListenableBuilder<List<Map<String, dynamic>>>(
            valueListenable: _notificationsNotifier,
            builder: (context, notifs, child) {
              int unreadCount = notifs.where((n) => n['isRead'] == false).length;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(icon: Icon(Icons.notifications_none), onPressed: _showNotificationsPanel),
                  if (unreadCount > 0)
                    Positioned(
                      right: 8, top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        child: Text(unreadCount > 9 ? '9+' : '$unreadCount', style: const TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    )
                ],
              );
            }
          ),
          SizedBox(width: 8),
        ],
      ),
      
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(color: isDark ? Colors.grey[900] : Theme.of(context).colorScheme.primary),
              accountName: Text(_userName, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
              accountEmail: Text(LocalizationService().currentLanguage == 'vi' ? 'Quyền: $_role' : 'Role: $_role', style: GoogleFonts.beVietnamPro(fontSize: 13, color: Colors.white70)),
              currentAccountPicture: CircleAvatar(
                backgroundColor: isDark ? Colors.grey[800] : Colors.blue.shade100,
                backgroundImage: (_localAvatarPath.isNotEmpty && File(_localAvatarPath).existsSync())
                    ? FileImage(File(_localAvatarPath))
                    : ((_avatar.isNotEmpty && !_avatar.contains('default.png') && !_isOfflineMode)
                        ? NetworkImage(_avatar)
                        : null),
                child: ((_localAvatarPath.isEmpty || !File(_localAvatarPath).existsSync()) &&
                        (_avatar.isEmpty || _avatar.contains('default.png') || _isOfflineMode))
                    ? Text(_getInitialLetter(_userName), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blue))
                    : null,
              ),
            ),
            
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (_isOfflineMode) ...[
                    Padding(padding: EdgeInsets.all(16), child: Text(LocalizationService().currentLanguage == 'vi' ? 'CHẾ ĐỘ NGOẠI TUYẾN' : 'OFFLINE MODE', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16))),
                    if (_isStaff) ListTile(leading: Icon(Icons.qr_code_scanner, color: Colors.blue), title: Text(LocalizationService().currentLanguage == 'vi' ? 'Kiểm tra cổng (Offline)' : 'Gate Check (Offline)'), onTap: () { Navigator.pop(context); setState(() { _currentIndex = 1; }); }),
                    if (_isStaff) ListTile(leading: Icon(Icons.fact_check, color: Colors.orange), title: Text(LocalizationService().currentLanguage == 'vi' ? 'Kiểm tra lớp (Offline)' : 'Class Check (Offline)'), onTap: () { Navigator.pop(context); setState(() { _currentIndex = 2; }); }),
                    if (_isStaff) ListTile(leading: Icon(Icons.history, color: Colors.purple), title: Text(LocalizationService().currentLanguage == 'vi' ? 'Lịch sử vi phạm (Cache)' : 'Violation History (Cache)'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ViolationHistoryScreen())); }),
                    ListTile(leading: Icon(Icons.sync, color: Colors.green), title: Text(LocalizationService().currentLanguage == 'vi' ? 'Đồng bộ Offline' : 'Sync Offline'), onTap: () { Navigator.pop(context); /* Implement sync if needed */ }),
                  ] else ...[
                    ListTile(leading: Icon(Icons.person, color: Colors.blue), title: Text(LocalizationService().currentLanguage == 'vi' ? 'Hồ sơ cá nhân' : 'My Profile', style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen())); }),
                    ListTile(leading: Icon(Icons.lock_reset, color: Colors.blueGrey), title: Text(LocalizationService().currentLanguage == 'vi' ? 'Đổi mật khẩu' : 'Change Password', style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ChangePasswordScreen())); }),
                    ListTile(leading: Icon(Icons.workspace_premium, color: Colors.amber), title: Text(LocalizationService().currentLanguage == 'vi' ? 'Bảng xếp hạng thi đua' : 'Leaderboard', style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => RankingScreen())); }),
                    ListTile(leading: Icon(Icons.settings, color: Colors.grey), title: Text(LocalizationService().currentLanguage == 'vi' ? 'Cài đặt App' : 'App Settings', style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen())); }),// 
//                     ListTile(leading: Icon(Icons.newspaper, color: Colors.blue), title: Text(LocalizationService().currentLanguage == 'vi' ? 'Tin tức & Thông báo' : 'News & Announcements', style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => NewsScreen())); }),
                    
                    ListTile(leading: Icon(Icons.scoreboard, color: Colors.amber), title: Text(T('exam_lookup', def: LocalizationService().currentLanguage == 'vi' ? 'Tra cứu Điểm thi' : 'Exam Lookup'), style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ExamLookupScreen())); }),
                    ListTile(leading: Icon(Icons.spellcheck, color: Colors.green), title: Text(T('grammar_ai', def: LocalizationService().currentLanguage == 'vi' ? 'Trợ lý Grammar AI' : 'Grammar AI'), style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => GrammarCheckScreen())); }),

                    const Divider(),
                    Padding(padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8), child: Text(T('counseling_career', def: LocalizationService().currentLanguage == 'vi' ? 'TƯ VẤN TÂM LÝ & HƯỚNG NGHIỆP' : 'COUNSELING & CAREER'), style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold))),
                    
                    ListTile(leading: Icon(Icons.explore, color: Colors.green), title: Text(T('career_advice', def: LocalizationService().currentLanguage == 'vi' ? 'Đánh giá Nghề nghiệp' : 'Career Assessment'), style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ConsultingTestScreen())); }),
                    ListTile(leading: Icon(Icons.games, color: Colors.orange), title: Text(T('chess_game', def: LocalizationService().currentLanguage == 'vi' ? 'Cờ Vua Multiplayer' : 'Multiplayer Chess')), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ChessLobbyScreen())); }),
                    ListTile(leading: Icon(Icons.forum, color: Colors.blue), title: Text(LocalizationService().currentLanguage == 'vi' ? 'Chat' : 'Chat', style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => HumanChatListScreen())); }),
                    ListTile(leading: Icon(Icons.psychology, color: Colors.purple), title: Text(LocalizationService().currentLanguage == 'vi' ? 'Góc tư vấn' : 'Counseling Corner', style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => AiConsultingScreen())); }),

                    if (['STUDENT', 'RED_FLAG'].contains(_role))
                      ListTile(leading: Icon(Icons.warning_amber, color: Colors.orange), title: Text(T('student_violations', def: LocalizationService().currentLanguage == 'vi' ? 'Lỗi của tôi / Sổ đầu bài' : 'My Violations / Logbook'), style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => StudentViolationsScreen())); }),

                    if (_isStaff) ...[
                      const Divider(),
                      Padding(padding: EdgeInsets.only(left: 16, top: 8, bottom: 8), child: Text(T('discipline_academic', def: LocalizationService().currentLanguage == 'vi' ? 'CÔNG TÁC NỀN NẾP & HỌC TẬP' : 'DISCIPLINE & ACADEMIC WORK'), style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold))),
                      
                      ListTile(leading: Icon(Icons.history, color: Colors.purple), title: Text(T('violation_history', def: LocalizationService().currentLanguage == 'vi' ? 'Lịch sử vi phạm' : 'Violation History'), style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ViolationHistoryScreen())); }),
                      ListTile(leading: Icon(Icons.edit_note, color: Colors.teal), title: Text(T('academic_scores', def: LocalizationService().currentLanguage == 'vi' ? 'Nhập điểm học tập' : 'Academic Scores'), style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => InputAcademicScreen())); }),
                      ListTile(leading: Icon(Icons.file_download, color: Colors.green), title: Text(T('export_report', def: LocalizationService().currentLanguage == 'vi' ? 'Xuất báo cáo Excel' : 'Export Excel'), style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ExportReportScreen())); }),
                      ListTile(leading: Icon(Icons.co_present, color: Colors.deepOrange), title: Text(T('teacher_dashboard', def: LocalizationService().currentLanguage == 'vi' ? 'Lớp của tôi' : 'My Class'), style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => TeacherDashboardScreen())); }),
                    ],

                    if (_isAdmin) ...[
                      const Divider(),
                      Padding(padding: EdgeInsets.only(left: 16, top: 8, bottom: 8), child: Text(T('system_admin', def: LocalizationService().currentLanguage == 'vi' ? 'HỆ THỐNG ADMIN' : 'ADMIN SYSTEM'), style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold))),
                      
                      ListTile(leading: Icon(Icons.gavel, color: Colors.red), title: Text(T('manage_violations', def: LocalizationService().currentLanguage == 'vi' ? 'Quản lý Vi phạm' : 'Manage Violations'), style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ManageViolationsScreen())); }),
                      ListTile(leading: Icon(Icons.task, color: Colors.pink), title: Text(T('manage_exams', def: LocalizationService().currentLanguage == 'vi' ? 'Quản lý Kỳ thi' : 'Manage Exams'), style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ManageExamsScreen())); }),
                      ListTile(leading: Icon(Icons.people_alt, color: Colors.indigo), title: Text(T('manage_students', def: LocalizationService().currentLanguage == 'vi' ? 'Học sinh toàn trường' : 'All Students'), style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ManageStudentsScreen())); }),
                      ListTile(leading: Icon(Icons.admin_panel_settings, color: Colors.redAccent), title: Text(T('manage_users', def: LocalizationService().currentLanguage == 'vi' ? 'Tài khoản & Phân quyền' : 'Accounts & Permissions'), style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ManageUsersScreen())); }),
                      ListTile(leading: Icon(Icons.security, color: Colors.brown), title: Text(T('banned_ips', def: LocalizationService().currentLanguage == 'vi' ? 'Lịch sử khóa IP' : 'Banned IPs History'), style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => BannedIpsScreen())); }),
                      ListTile(leading: Icon(Icons.analytics, color: Colors.blueGrey), title: Text(T('traffic_monitor', def: LocalizationService().currentLanguage == 'vi' ? 'Giám sát lưu lượng' : 'Traffic Monitor'), style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => TrafficMonitorScreen())); }),
                    ],
                  ],
                ],
              ),
            ),
            
            const Divider(height: 1),
            ListTile(leading: Icon(Icons.logout, color: Colors.redAccent), title: Text(T('logout', def: LocalizationService().currentLanguage == 'vi' ? 'Đăng xuất' : 'Logout'), style: TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, color: Colors.redAccent, fontWeight: FontWeight.bold)), onTap: _logout),
            SizedBox(height: 20),
          ],
        ),
      ),
      
      // BỌC _buildBody() BẰNG KHỐI TICKER Ở TRÊN CÙNG
      body: Column(
        children: [
          if (_tickerText.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? Colors.blue.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.05),
                border: Border(bottom: BorderSide(color: Colors.blue.withValues(alpha: 0.1))),
              ),
              child: MarqueeWidget(text: _tickerText),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
      
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarTheme.of(context).copyWith(
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary);
            }
            return const TextStyle(fontFeatures: _interFeatures, letterSpacing: _interSpacing, fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey);
          }),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (int index) { setState(() { _currentIndex = index; }); },
          height: 70, labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          destinations: _isStaff 
            ? [
                NavigationDestination(selectedIcon: Icon(Icons.home), icon: Icon(Icons.home_outlined), label: LocalizationService().currentLanguage == 'vi' ? 'Trang chủ' : 'Home'),
                NavigationDestination(selectedIcon: Icon(Icons.qr_code_scanner), icon: Icon(Icons.qr_code_scanner_outlined), label: LocalizationService().currentLanguage == 'vi' ? 'Kiểm tra cổng' : 'Gate Check'),
                NavigationDestination(selectedIcon: Icon(Icons.fact_check), icon: Icon(Icons.fact_check_outlined), label: LocalizationService().currentLanguage == 'vi' ? 'Kiểm tra lớp' : 'Class Check'),
              ]
            : [
                NavigationDestination(selectedIcon: Icon(Icons.home), icon: Icon(Icons.home_outlined), label: LocalizationService().currentLanguage == 'vi' ? 'Trang chủ' : 'Home'),
                NavigationDestination(selectedIcon: Icon(Icons.psychology), icon: Icon(Icons.psychology_outlined), label: LocalizationService().currentLanguage == 'vi' ? 'Góc tư vấn' : 'Counseling Corner'),
                NavigationDestination(selectedIcon: Icon(Icons.workspace_premium), icon: Icon(Icons.workspace_premium_outlined), label: LocalizationService().currentLanguage == 'vi' ? 'Xếp hạng' : 'Ranking'),
              ],
        ),
      ),
    );
  }
}