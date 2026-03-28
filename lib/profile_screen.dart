import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart'; 
import 'package:image_cropper/image_cropper.dart'; 
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; 
import 'device_helper.dart'; 

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  bool _isUploadingAvatar = false;
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _studentData;
  List<dynamic> _devices = [];
  String _currentSession = '';
  bool _isThisDevicePushEnabled = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _fetchProfileData();
  }

  Future<void> _fetchProfileData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';

      // ĐÃ BỎ ĐUÔI .php
      final response = await http.get(
        Uri.parse('https://qlnn.testifiyonline.xyz/api/profile_api'),
        headers: {'Cookie': 'PHPSESSID=$sessionId'},
      );

      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        _devices = data['devices'];
        _currentSession = data['current_session'];
        
        final currentDeviceData = _devices.firstWhere((d) => d['session_id'] == _currentSession, orElse: () => null);
        _isThisDevicePushEnabled = (currentDeviceData != null && currentDeviceData['push_enabled'] == 1);

        setState(() {
          _userData = data['user'];
          _studentData = data['student'];
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- HÀM 1: CHỌN NGUỒN VÀ BẮT ĐẦU CHỤP ẢNH ---
  Future<void> _startAvatarChangeProcess() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Chụp ảnh mới'), onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library), title: const Text('Chọn từ thư viện'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
      ]))
    );
    if (source == null) return;

    try {
      // ĐÃ FIX LỖI "imageHeight" THÀNH "maxHeight"
      final XFile? image = await _picker.pickImage(source: source, maxWidth: 500, maxHeight: 500, imageQuality: 80);
      if (image == null) return; 

      if (mounted) _cropPickedImage(image.path);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Lỗi chọn ảnh: $e'), backgroundColor: Colors.red));
    }
  }

  // --- HÀM 2: MỞ GIAO DIỆN CẮT ẢNH ---
  Future<void> _cropPickedImage(String imagePath) async {
    try {
      CroppedFile? croppedFile = await ImageCropper().cropImage(
        sourcePath: imagePath,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1), // Ép vuông
        uiSettings: [
          AndroidUiSettings(
              toolbarTitle: 'Cắt ảnh đại diện',
              toolbarColor: Theme.of(context).colorScheme.primary,
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: true), 
          IOSUiSettings(title: 'Cắt ảnh đại diện', aspectRatioLockEnabled: true),
        ],
      );

      if (croppedFile == null) return; 

      if (mounted) _uploadCroppedAvatar(croppedFile.path);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Lỗi cắt ảnh: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _uploadCroppedAvatar(String croppedPath) async {
    if (!mounted) return;
    setState(() => _isUploadingAvatar = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';

      // Đã sửa đường dẫn thành api/profile_api (KHÔNG ĐUÔI PHP)
      var request = http.MultipartRequest('POST', Uri.parse('https://qlnn.testifiyonline.xyz/api/profile_api'));
      request.headers['Cookie'] = 'PHPSESSID=$sessionId';
      
      // SỬA LẠI THÀNH 'avatar' ĐỂ KHỚP VỚI PHP SERVER
      request.files.add(await http.MultipartFile.fromPath('avatar', croppedPath));

      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      var data = jsonDecode(responseData);

      if (response.statusCode == 200 && data['status'] == 'success') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Đã đổi Avatar thành công!'), backgroundColor: Colors.green));
        setState(() { 
          String newUrl = data['new_avatar_url'] ?? 'static/default.png';
          _userData!['avatar'] = "https://qlnn.testifiyonline.xyz/" + newUrl; 
        });
      } else { throw Exception(data['msg'] ?? "Lỗi upload"); }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Lỗi tải ảnh: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _deleteAvatar() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xác nhận'), content: const Text('Bạn muốn xóa ảnh đại diện?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Xóa', style: TextStyle(color: Colors.red))),
        ],
      )
    );
    if (confirm != true) return;
    
    setState(() => _isUploadingAvatar = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      final res = await http.post(
        Uri.parse('https://qlnn.testifiyonline.xyz/api/profile_api'),
        headers: {'Cookie': 'PHPSESSID=$sessionId'},
        body: {'action': 'delete_avatar'},
      );
      final data = jsonDecode(res.body);
      if (data['status'] == 'success') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Đã xóa ảnh đại diện!'), backgroundColor: Colors.green));
        setState(() { _userData!['avatar'] = "https://qlnn.testifiyonline.xyz/static/default.png"; });
      }
    } catch(e) {} finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _kickDevice(String targetSessionId, String deviceName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xác nhận'), content: Text('Đăng xuất khỏi $deviceName?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Đăng xuất', style: TextStyle(color: Colors.red))),
        ],
      )
    );
    if (confirm != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      
      final response = await http.post(
        Uri.parse('https://qlnn.testifiyonline.xyz/api/profile_api'),
        headers: {'Cookie': 'PHPSESSID=$sessionId'},
        body: {'action': 'delete_device', 'device_id': targetSessionId},
      );
      if (jsonDecode(response.body)['status'] == 'success') {
        setState(() => _devices.removeWhere((d) => d['session_id'] == targetSessionId));
      }
    } catch (e) {}
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
            Uri.parse('https://qlnn.testifiyonline.xyz/api/subscribe'),
            headers: {'Content-Type': 'application/json', 'Cookie': 'PHPSESSID=$sessionId'},
            body: jsonEncode({'endpoint': fcmToken, 'platform': 'app', 'device_model': realModel}),
          );
          if (jsonDecode(response.body)['status'] == 'success') {
            setState(() => _isThisDevicePushEnabled = true);
            _fetchProfileData(); 
          }
        }
      } else {
        await http.post(
          Uri.parse('https://qlnn.testifiyonline.xyz/gate_check'),
          headers: {'Cookie': 'PHPSESSID=$sessionId', 'Content-Type': 'application/x-www-form-urlencoded'},
          body: 'delete_id=0&only_push=1' 
        );
        setState(() => _isThisDevicePushEnabled = false);
        _fetchProfileData();
      }
    } catch (e) {}
    if (mounted) { Navigator.pop(context); Navigator.pop(context); } 
    if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
  }

  IconData _getDeviceIcon(String userAgent, String deviceModel, String platform) {
    if (platform == 'app') return Icons.smartphone_rounded; 
    String ua = userAgent.toLowerCase();
    String model = deviceModel.toLowerCase();
    if (ua.contains('android') || ua.contains('iphone') || ua.contains('ipad') || model.contains('phone')) {
      return Icons.smartphone_rounded;
    }
    return Icons.computer_rounded;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_userData == null) return const Scaffold(body: Center(child: Text('Lỗi tải dữ liệu.')));

    return Scaffold(
      appBar: AppBar(title: const Text('Hồ sơ cá nhân', style: TextStyle(fontWeight: FontWeight.bold))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              elevation: 0, color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.2))),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        // ĐÃ BỎ "padding: const EdgeInsets.all(3)" GÂY LỖI
                        CircleAvatar(radius: 55, backgroundColor: Colors.white,
                          child: CircleAvatar(radius: 52, backgroundImage: NetworkImage(_userData!['avatar']), backgroundColor: Colors.grey.shade200),
                        ),
                        if (_isUploadingAvatar)
                          const CircleAvatar(radius: 55, backgroundColor: Colors.black54, child: CircularProgressIndicator(color: Colors.white)),
                        Positioned(
                          right: 0, bottom: 0,
                          child: GestureDetector(
                            onTap: _isUploadingAvatar ? null : _startAvatarChangeProcess, // GỌI HÀM MỚI
                            child: CircleAvatar(radius: 18, backgroundColor: Theme.of(context).colorScheme.primary,
                              child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                            ),
                          ),
                        ),

                        if (_userData!['avatar'] != null && !_userData!['avatar'].toString().contains('default.png'))
      Positioned(
        left: 0, bottom: 0,
        child: GestureDetector(
          onTap: _isUploadingAvatar ? null : _deleteAvatar,
          child: const CircleAvatar(radius: 18, backgroundColor: Colors.redAccent,
            child: Icon(Icons.delete, size: 18, color: Colors.white),
          ),
        ),
      ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(_userData!['full_name'] ?? _userData!['username'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    if (_studentData != null) ...[
                      Text('${_studentData!['class_name']} - ${_userData!['username']}', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600, fontSize: 16)),
                    ] else ...[
                      Text('Quyền: ${_userData!['role']}', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 15)),
                    ],
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            Card(
              elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.orange.shade300)),
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                secondary: Icon(_isThisDevicePushEnabled ? Icons.notifications_active : Icons.notifications_off, color: _isThisDevicePushEnabled ? Colors.orange : Colors.grey),
                title: const Text('Nhận thông báo máy này', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Báo điểm trừ, cảnh báo AI Python'),
                value: _isThisDevicePushEnabled,
                activeColor: Colors.orange,
                onChanged: _toggleNotification,
              ),
            ),

            const SizedBox(height: 16),
            Card(
              elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.all(16), child: Text('Lịch sử đăng nhập', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                  const Divider(height: 1),
                  ListView.separated(
                    shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                    itemCount: _devices.length,
                    separatorBuilder: (c, i) => const Divider(height: 1, indent: 60),
                    itemBuilder: (context, index) {
                      final dev = _devices[index];
                      bool isCurrent = dev['session_id'] == _currentSession;
                      String displayModel = !empty(dev['device_model']) ? dev['device_model'] : dev['device_name'];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isCurrent ? Colors.green.withOpacity(0.1) : Colors.grey.shade100,
                          child: Icon(_getDeviceIcon(dev['user_agent'], displayModel, dev['platform'] ?? 'web'), color: isCurrent ? Colors.green : Colors.grey, size: 20),
                        ),
                        title: Row(children: [
                            Expanded(child: Text(displayModel, style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600, color: isCurrent ? Colors.green : null))),
                            if (dev['push_enabled'] == 1) const Icon(Icons.notifications_active, color: Colors.orange, size: 16),
                        ]),
                        subtitle: Text('HĐ cuối: ${dev['last_active']}\n${isCurrent ? 'Máy này' : 'Thiết bị khác'}', style: const TextStyle(fontSize: 12)),
                        trailing: !isCurrent ? IconButton(icon: const Icon(Icons.logout, color: Colors.redAccent, size: 20), onPressed: () => _kickDevice(dev['session_id'], displayModel)) : null,
                      );
                    },
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
  bool empty(dynamic val) => val == null || val.toString().trim() == '';
}