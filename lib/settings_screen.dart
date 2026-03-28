import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart'; 
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'device_helper.dart';
import 'main.dart'; // Lấy cả themeNotifier và currentAppVersion từ đây

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _themeMode = 'system';
  bool _isNotiEnabled = false;
  
  String _fwVersion = 'Đang tải...';
  String _engineVersion = 'Đang tải...';
  bool _isCheckingUpdate = false; 

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _fetchServerInfo();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeMode = prefs.getString('theme_mode') ?? 'system';
      _isNotiEnabled = prefs.getBool('push_enabled') ?? false;
    });
  }

  Future<void> _fetchServerInfo() async {
    try {
      final res = await http.get(Uri.parse('https://qlnn.testifiyonline.xyz/api/system_info_api'));
      final data = jsonDecode(res.body);
      if (data['status'] == 'success') {
        setState(() {
          _fwVersion = data['firmware_version'];
          _engineVersion = data['engine_version'];
        });
      }
    } catch (e) {
      setState(() { _fwVersion = 'Lỗi kết nối'; _engineVersion = 'Lỗi kết nối'; });
    }
  }

  // ĐÃ FIX: Thêm ngoặc nhọn { } để trị lỗi gạch chân xanh Linter
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
        'https://qlnn.testifiyonline.xyz/api/check_update.php',
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
          final String changelog = data['note'] ?? 'Bản cập nhật tối ưu hóa cho thiết bị của bạn.';
          final bool isForceUpdate = data['is_force_update'] == true;
          
          if (mounted) _showUpdateDialog(newVersion, changelog, downloadUrl, isForceUpdate);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Bạn đang sử dụng phiên bản mới nhất!', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.green,
            ));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Không thể kết nối đến máy chủ cập nhật.'),
          backgroundColor: Colors.orange,
        ));
      }
    } finally {
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
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
                    const SizedBox(width: 10),
                    Expanded(child: Text('Bản cập nhật v$newVersion', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isForceUpdate) 
                      const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Ứng dụng đã quá cũ và không còn được hỗ trợ. Bắt buộc phải cập nhật!', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14))),
                    const Text('Có phiên bản mới với các thay đổi:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 150),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
                      child: SingleChildScrollView(child: Text(changelog, style: const TextStyle(fontSize: 13, color: Colors.black87))),
                    ),
                    if (isDownloading) ...[
                      const SizedBox(height: 20),
                      LinearProgressIndicator(value: progress, backgroundColor: Colors.grey.shade300, color: Colors.blue, minHeight: 8, borderRadius: BorderRadius.circular(10)),
                      const SizedBox(height: 8),
                      Center(child: Text('Đang tải: ${(progress * 100).toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                    ]
                  ],
                ),
                actions: [
                  if (!isDownloading && !isForceUpdate)
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Để sau', style: TextStyle(color: Colors.grey))),
                  FilledButton.icon(
                    onPressed: isDownloading ? null : () async {
                      await Permission.requestInstallPackages.request();
                      setPopupState(() { isDownloading = true; progress = 0.0; });
                      try {
                        Directory tempDir = await getTemporaryDirectory();
                        String savePath = "${tempDir.path}/LG3_Update_v$newVersion.apk";

                        await Dio().download(downloadUrl, savePath, onReceiveProgress: (rcv, total) {
                          if (total != -1) setPopupState(() { progress = rcv / total; });
                        });

                        if (!isForceUpdate && context.mounted) Navigator.pop(context);
                        await OpenFilex.open(savePath);
                        if (isForceUpdate) setPopupState(() { isDownloading = false; progress = 1.0; });
                      } catch (e) {
                        setPopupState(() { isDownloading = false; });
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lỗi khi tải bản cập nhật!')));
                      }
                    },
                    icon: isDownloading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.download, size: 18),
                    label: Text(isDownloading ? 'Đang tải...' : 'Cập nhật ngay'),
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
      appBar: AppBar(title: const Text('Cài đặt hệ thống', style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(padding: EdgeInsets.only(left: 8, bottom: 8), child: Text('GIAO DIỆN & HIỂN THỊ', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold))),
          Card(
            elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.withOpacity(0.2))),
            child: Column(
              children: [
                RadioListTile(value: 'system', groupValue: _themeMode, title: const Text('Theo hệ thống'), secondary: const Icon(Icons.brightness_auto, color: Colors.blueGrey), onChanged: (v) => _changeTheme(v.toString())),
                const Divider(height: 1, indent: 60),
                RadioListTile(value: 'light', groupValue: _themeMode, title: const Text('Giao diện Sáng'), secondary: const Icon(Icons.light_mode, color: Colors.orange), onChanged: (v) => _changeTheme(v.toString())),
                const Divider(height: 1, indent: 60),
                RadioListTile(value: 'dark', groupValue: _themeMode, title: const Text('Giao diện Tối'), secondary: const Icon(Icons.dark_mode, color: Colors.deepPurple), onChanged: (v) => _changeTheme(v.toString())),
              ],
            ),
          ),
          const SizedBox(height: 25),

          const Padding(padding: EdgeInsets.only(left: 8, bottom: 8), child: Text('TÙY CHỈNH THÔNG BÁO', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold))),
          Card(
            elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.withOpacity(0.2))),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              secondary: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: _isNotiEnabled ? Colors.orange.withOpacity(0.1) : Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(_isNotiEnabled ? Icons.notifications_active : Icons.notifications_off, color: _isNotiEnabled ? Colors.orange : Colors.grey, size: 24)),
              title: const Text('Nhận Thông báo', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Báo điểm trừ, tin nhắn cảnh báo AI'),
              value: _isNotiEnabled, activeColor: Colors.orange, onChanged: _toggleNotification,
            ),
          ),
          const SizedBox(height: 25),

          const Padding(padding: EdgeInsets.only(left: 8, bottom: 8), child: Text('THÔNG TIN PHẦN MỀM', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold))),
          Card(
            elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.withOpacity(0.2))),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.phone_android, color: Colors.blue),
                  title: const Text('Phiên bản Ứng dụng (App)'),
                  trailing: const Text('v$currentAppVersion', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), 
                ),
                const Divider(height: 1, indent: 50),
                ListTile(
                  leading: const Icon(Icons.cloud_done, color: Colors.green),
                  title: const Text('Phiên bản Firmware Server'),
                  trailing: Text('v$_fwVersion', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                const Divider(height: 1, indent: 50),
                ListTile(
                  leading: const Icon(Icons.memory, color: Colors.purple),
                  title: const Text('LG3 Guard Engine'),
                  trailing: Text('v$_engineVersion', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                const Divider(height: 1, indent: 50),
                
                ListTile(
                  leading: const Icon(Icons.system_update_alt, color: Colors.orange),
                  title: const Text('Kiểm tra phiên bản mới', style: TextStyle(fontWeight: FontWeight.w600)),
                  trailing: _isCheckingUpdate 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                      : const Icon(Icons.chevron_right),
                  onTap: _isCheckingUpdate ? null : _manualCheckUpdate,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 30),
          Center(child: Text('Trường THPT Lạng Giang số 3 © 2026\nTập thể A1-K48', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500, fontSize: 12))),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}