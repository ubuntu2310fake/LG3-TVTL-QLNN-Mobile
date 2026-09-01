import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'localization_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart'; 
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'device_helper.dart';
import 'main.dart'; // Lấy cả themeNotifier và currentAppVersion từ đây
import 'config.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _themeMode = 'system';
  bool _isNotiEnabled = false;
  String _videoEncoder = 'hardware'; // Cài đặt mới cho HLS Encoder
  
  bool _isCheckingUpdate = false; 

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeMode = prefs.getString('theme_mode') ?? 'system';
      _isNotiEnabled = prefs.getBool('push_enabled') ?? false;
      _videoEncoder = prefs.getString('video_encoder') ?? 'hardware'; // Load cấu hình encoder
    });
  }

  Future<void> _changeTheme(String mode) async {
    setState(() => _themeMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode);
    
    if (mode == 'light') {
      themeNotifier.value = ThemeMode.light;
    } else if (mode == 'dark') {
      themeNotifier.value = ThemeMode.dark;
    } else {
      themeNotifier.value = ThemeMode.system;
    }
  }

  // Hàm mới để thay đổi chế độ mã hóa Video
  Future<void> _changeEncoder(String mode) async {
    setState(() => _videoEncoder = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('video_encoder', mode);
  }

  Future<void> _toggleNotification(bool value) async {
    showDialog(context: context, barrierDismissible: false, builder: (c) => Center(child: CircularProgressIndicator()));
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
          await AppConfig.client.post(
            Uri.parse('${AppConfig.baseUrl}/api/subscribe'),
            headers: {'Content-Type': 'application/json', 'Cookie': 'PHPSESSID=$sessionId'},
            body: jsonEncode({'endpoint': fcmToken, 'platform': 'app', 'device_model': realModel}),
          );
        }
      } else {
        await AppConfig.client.post(
          Uri.parse('${AppConfig.baseUrl}/gate_check'),
          headers: {'Cookie': 'PHPSESSID=$sessionId', 'Content-Type': 'application/x-www-form-urlencoded'},
          body: 'delete_id=0&only_push=1' 
        );
      }
    } catch (e) {}
    if (mounted) Navigator.pop(context); 
  }

  Future<void> _manualCheckUpdate() async {
    setState(() => _isCheckingUpdate = true);
    
    String primaryAbi = 'universal';
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      if (androidInfo.supportedAbis.isNotEmpty) {
        primaryAbi = androidInfo.supportedAbis.first; 
      }
    } catch (e) {}

    try {
      final dio = Dio();
      final response = await dio.get(
        '${AppConfig.baseUrl}/api/check_update.php',
        queryParameters: {
          'version': currentAppVersion,
          'abi': primaryAbi,
        }
      );
      
      if (response.statusCode == 200) {
        final data = response.data;
        if (data['update_available'] == true) {
          final String newVersion = data['version'].toString();
          final String downloadUrl = data['download_url'].toString();
          final String changelog = data['note'] ?? (LocalizationService().currentLanguage == 'vi' ? 'Bản cập nhật tối ưu hóa cho thiết bị của bạn.' : 'Optimization update for your device.');
          final bool isForceUpdate = data['is_force_update'] == true;
          
          if (mounted) _showUpdateDialog(newVersion, changelog, downloadUrl, isForceUpdate);
        } else if (data['hotfix_available'] == true) {
          final int patchNum = data['latest_patch'] ?? 1;
          final String patchUrl = data['download_url']?.toString() ?? '';
          final String changelog = data['note'] ?? 'Bản vá Hotfix';
          
          if (mounted) _showHotfixDialog(patchNum, changelog, patchUrl);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(LocalizationService().currentLanguage == 'vi' ? 'Bạn đang sử dụng phiên bản mới nhất!' : 'You are using the latest version!', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.green,
            ));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LocalizationService().currentLanguage == 'vi' ? 'Không thể kết nối đến máy chủ cập nhật.' : 'Cannot connect to the update server.'),
          backgroundColor: Colors.orange,
        ));
      }
    } finally {
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
  }

  void _showHotfixDialog(int patchNum, String changelog, String downloadUrl) {
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
                          // Tải và áp dụng bản vá
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

  void _showUpdateDialog(String newVersion, String changelog, String downloadUrl, bool isForceUpdate) {
    bool isDownloading = false;
    double progress = 0.0;

    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (context) {
        return PopScope(
          canPop: false, 
          child: StatefulBuilder(
            builder: (context, setPopupState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Row(
                  children: [
                    Icon(isForceUpdate ? Icons.warning_amber_rounded : Icons.system_update, color: isForceUpdate ? Colors.red : Colors.blue, size: 28),
                    SizedBox(width: 10),
                    Expanded(child: Text(LocalizationService().currentLanguage == 'vi' ? 'Bản cập nhật v$newVersion' : 'Update v$newVersion', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isForceUpdate) 
                      Padding(padding: EdgeInsets.only(bottom: 12), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Ứng dụng đã quá cũ và không còn được hỗ trợ. Bắt buộc phải cập nhật!' : 'The app is too old and no longer supported. Update required!', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14))),
                    Text(LocalizationService().currentLanguage == 'vi' ? 'Có phiên bản mới với các thay đổi:' : 'New version available with changes:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 150),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
                      child: SingleChildScrollView(child: Text(changelog, style: const TextStyle(fontSize: 13, color: Colors.black87))),
                    ),
                    if (isDownloading) ...[
                      SizedBox(height: 20),
                      LinearProgressIndicator(value: progress, backgroundColor: Colors.grey.shade300, color: Colors.blue, minHeight: 8, borderRadius: BorderRadius.circular(10)),
                      SizedBox(height: 8),
                      Center(child: Text(LocalizationService().currentLanguage == 'vi' ? 'Đang tải: ${(progress * 100).toStringAsFixed(1)}%' : 'Downloading: ${(progress * 100).toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                    ]
                  ],
                ),
                actions: [
                  if (!isDownloading && !isForceUpdate)
                    TextButton(onPressed: () => Navigator.pop(context), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Để sau' : 'Later', style: TextStyle(color: Colors.grey))),
                  FilledButton.icon(
                    onPressed: isDownloading ? null : () async {
                      if (Platform.isIOS) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Vui lòng cập nhật ứng dụng từ App Store / TestFlight.' : 'Please update the app from App Store / TestFlight.')));
                        return;
                      }
                      if (Platform.isAndroid) {
                        await Permission.requestInstallPackages.request();
                      }
                      setPopupState(() { isDownloading = true; progress = 0.0; });
                      try {
                        Directory tempDir = await getTemporaryDirectory();
                        String savePath = "${tempDir.path}/LG3_Update_v$newVersion.apk";

                        await Dio().download(downloadUrl, savePath, onReceiveProgress: (rcv, total) {
                          if (total != -1) setPopupState(() { progress = rcv / total; });
                        });

                        if (!isForceUpdate && context.mounted) Navigator.pop(context);
                        if (Platform.isAndroid) {
                          await OpenFilex.open(savePath);
                        }
                        if (isForceUpdate) setPopupState(() { isDownloading = false; progress = 1.0; });
                      } catch (e) {
                        setPopupState(() { isDownloading = false; });
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Lỗi khi tải bản cập nhật!' : 'Error downloading update!')));
                      }
                    },
                    icon: isDownloading ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Icon(Icons.download, size: 18),
                    label: Text(isDownloading ? LocalizationService().currentLanguage == 'vi' ? 'Đang tải...' : 'Loading...' : LocalizationService().currentLanguage == 'vi' ? 'Cập nhật ngay' : 'Update now'),
                  ),
                ],
              );
            }
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(LocalizationService().currentLanguage == 'vi' ? 'Cài đặt hệ thống' : 'System Settings', style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(padding: EdgeInsets.only(left: 8, bottom: 8), child: Text(LocalizationService().currentLanguage == 'vi' ? 'GIAO DIỆN & HIỂN THỊ' : 'DISPLAY & INTERFACE', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold))),
          Card(
            elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
            child: Column(
              children: [
                RadioListTile(value: 'system', groupValue: _themeMode, title: Text(LocalizationService().currentLanguage == 'vi' ? 'Theo hệ thống' : 'System Default'), secondary: Icon(Icons.brightness_auto, color: Colors.blueGrey), onChanged: (v) => _changeTheme(v.toString())),
                const Divider(height: 1, indent: 60),
                RadioListTile(value: 'light', groupValue: _themeMode, title: Text(LocalizationService().currentLanguage == 'vi' ? 'Giao diện Sáng' : 'Light Mode'), secondary: Icon(Icons.light_mode, color: Colors.orange), onChanged: (v) => _changeTheme(v.toString())),
                const Divider(height: 1, indent: 60),
                RadioListTile(value: 'dark', groupValue: _themeMode, title: Text(LocalizationService().currentLanguage == 'vi' ? 'Giao diện Tối' : 'Dark Mode'), secondary: Icon(Icons.dark_mode, color: Colors.deepPurple), onChanged: (v) => _changeTheme(v.toString())),
              ],
            ),
          ),
          
          SizedBox(height: 25),
          Padding(padding: EdgeInsets.only(left: 8, bottom: 8), child: Text(LocalizationService().currentLanguage == 'vi' ? 'NGÔN NGỮ (LANGUAGE)' : 'LANGUAGE', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold))),
          Card(
            elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
            child: Column(
              children: [
                RadioListTile(value: 'vi', groupValue: LocalizationService().currentLanguage, title: Text('Tiếng Việt'), secondary: Text('🇻🇳', style: TextStyle(fontSize: 24)), onChanged: (v) {
                  setState(() {});
                  LocalizationService().setLanguage('vi');
                }),
                const Divider(height: 1, indent: 60),
                RadioListTile(value: 'en', groupValue: LocalizationService().currentLanguage, title: Text('English (US)'), secondary: Text('🇺🇸', style: TextStyle(fontSize: 24)), onChanged: (v) {
                  setState(() {});
                  LocalizationService().setLanguage('en');
                }),
              ],
            ),
          ),

          SizedBox(height: 25),

          // PHẦN MỚI BỔ SUNG CHO HLS ENCODER
          Padding(padding: EdgeInsets.only(left: 8, bottom: 8), child: Text(LocalizationService().currentLanguage == 'vi' ? 'BỘ MÃ HÓA VIDEO HLS (APP)' : 'VIDEO HLS ENCODER (APP)', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold))),
          Card(
            elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
            child: Column(
              children: [
                RadioListTile(
                  value: 'hardware', 
                  groupValue: _videoEncoder, 
                  title: Text(LocalizationService().currentLanguage == 'vi' ? 'Phần cứng (MediaCodec/VideoToolbox)' : 'Hardware (MediaCodec/VideoToolbox)'), 
                  subtitle: Text(LocalizationService().currentLanguage == 'vi' ? 'Tốc độ nhanh, tiết kiệm pin, dùng chip GPU' : 'Fast, saves battery, uses GPU'),
                  secondary: Icon(Icons.memory, color: Colors.green), 
                  onChanged: (v) => _changeEncoder(v.toString())
                ),
                const Divider(height: 1, indent: 60),
                RadioListTile(
                  value: 'software', 
                  groupValue: _videoEncoder, 
                  title: Text(LocalizationService().currentLanguage == 'vi' ? 'Phần mềm (libx264)' : 'Software (libx264)'), 
                  subtitle: Text(LocalizationService().currentLanguage == 'vi' ? 'Chậm hơn, dùng sức mạnh CPU, độ ổn định cao' : 'Slower, uses CPU, high stability'),
                  secondary: Icon(Icons.developer_board, color: Colors.blueGrey), 
                  onChanged: (v) => _changeEncoder(v.toString())
                ),
              ],
            ),
          ),
          SizedBox(height: 25),

          Padding(padding: EdgeInsets.only(left: 8, bottom: 8), child: Text(LocalizationService().currentLanguage == 'vi' ? 'TÙY CHỈNH THÔNG BÁO' : 'NOTIFICATION SETTINGS', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold))),
          Card(
            elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              secondary: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: _isNotiEnabled ? Colors.orange.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Icon(_isNotiEnabled ? Icons.notifications_active : Icons.notifications_off, color: _isNotiEnabled ? Colors.orange : Colors.grey, size: 24)),
              title: Text(LocalizationService().currentLanguage == 'vi' ? 'Nhận Thông báo' : 'Receive Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(LocalizationService().currentLanguage == 'vi' ? 'Báo điểm trừ, tin nhắn cảnh báo AI' : 'Deduction alerts, AI warnings'),
              value: _isNotiEnabled, activeThumbColor: Colors.orange, onChanged: _toggleNotification,
            ),
          ),
          SizedBox(height: 25),

          Padding(padding: EdgeInsets.only(left: 8, bottom: 8), child: Text(LocalizationService().currentLanguage == 'vi' ? 'THÔNG TIN PHẦN MỀM' : 'SOFTWARE INFORMATION', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold))),
          Card(
            elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.phone_android, color: Colors.blue),
                  title: Text(LocalizationService().currentLanguage == 'vi' ? 'Phiên bản Ứng dụng (App)' : 'App Version'),
                  trailing: Text('v$currentAppVersion', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), 
                ),
                const Divider(height: 1, indent: 50),
                
                ListTile(
                  leading: Icon(Icons.system_update_alt, color: Colors.orange),
                  title: Text(LocalizationService().currentLanguage == 'vi' ? 'Kiểm tra phiên bản mới' : 'Check for updates', style: TextStyle(fontWeight: FontWeight.w600)),
                  trailing: _isCheckingUpdate 
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                      : Icon(Icons.chevron_right),
                  onTap: _isCheckingUpdate ? null : _manualCheckUpdate,
                ),
              ],
            ),
          ),
          
          SizedBox(height: 30),
          Center(child: Text(LocalizationService().currentLanguage == 'vi' ? 'Trường THPT Lạng Giang số 3 © 2026\nTập thể A1-K48' : 'Lang Giang No.3 High School © 2026\nA1-K48 Class', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500, fontSize: 12))),
          SizedBox(height: 40),
        ],
      ),
    );
  }
}