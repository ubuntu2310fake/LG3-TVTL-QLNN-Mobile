import 'localization_service.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart'; 
import 'package:image_cropper/image_cropper.dart'; 
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; 
import 'device_helper.dart'; 
import 'config.dart';

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
      final response = await AppConfig.client.get(
        Uri.parse('${AppConfig.baseUrl}/api/profile_api.php'),
        headers: {'Cookie': 'PHPSESSID=$sessionId'},
      );

      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        _devices = data['devices'];
        _currentSession = data['current_session'];
        
        final currentDeviceData = _devices.firstWhere((d) => d['session_id'] == _currentSession, orElse: () => null);
        _isThisDevicePushEnabled = (currentDeviceData != null && currentDeviceData['push_enabled'] == 1);

        await prefs.setBool('push_enabled', _isThisDevicePushEnabled);

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
          ListTile(leading: Icon(Icons.camera_alt), title: Text(LocalizationService().currentLanguage == 'vi' ? 'Chụp ảnh mới' : 'Take a photo'), onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(leading: Icon(Icons.photo_library), title: Text(LocalizationService().currentLanguage == 'vi' ? 'Chọn từ thư viện' : 'Choose from gallery'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
      ]))
    );
    if (source == null) return;

    try {
      // ĐÃ FIX LỖI "imageHeight" THÀNH "maxHeight"
      final XFile? image = await _picker.pickImage(source: source, maxWidth: 500, maxHeight: 500, imageQuality: 80);
      if (image == null) return; 

      if (mounted) _cropPickedImage(image.path);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? '❌ Lỗi chọn ảnh: $e' : '❌ Error selecting image: $e'), backgroundColor: Colors.red));
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
              toolbarTitle: LocalizationService().currentLanguage == 'vi' ? 'Cắt ảnh đại diện' : 'Cat anh dai dien',
              toolbarColor: Theme.of(context).colorScheme.primary,
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: true), 
          IOSUiSettings(title: LocalizationService().currentLanguage == 'vi' ? 'Cắt ảnh đại diện' : 'Cat anh dai dien', aspectRatioLockEnabled: true),
        ],
      );

      if (croppedFile == null) return; 

      if (mounted) _uploadCroppedAvatar(croppedFile.path);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? '❌ Lỗi cắt ảnh: $e' : '❌ Error cropping image: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _uploadCroppedAvatar(String croppedPath) async {
    if (!mounted) return;
    setState(() => _isUploadingAvatar = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';

      // Đã sửa đường dẫn thành api/profile_api (KHÔNG ĐUÔI PHP)
      var request = http.MultipartRequest('POST', Uri.parse('${AppConfig.baseUrl}/api/profile_api.php'));
      request.headers['Cookie'] = 'PHPSESSID=$sessionId';
      
      // SỬA LẠI THÀNH 'avatar' ĐỂ KHỚP VỚI PHP SERVER
      request.files.add(await http.MultipartFile.fromPath('avatar', croppedPath));

      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      var data = jsonDecode(responseData);

      if (response.statusCode == 200 && data['status'] == 'success') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? '✅ Đã đổi Avatar thành công!' : '✅ Avatar changed successfully!'), backgroundColor: Colors.green));
        setState(() { 
          String newUrl = data['new_avatar_url'] ?? 'static/default.png';
          _userData!['avatar'] = "${AppConfig.baseUrl}$newUrl"; 
        });
      } else { throw Exception(data['msg'] ?? (LocalizationService().currentLanguage == 'vi' ? "Lỗi upload" : "Upload error")); }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? '❌ Lỗi tải ảnh: $e' : '❌ Error loading image: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _deleteAvatar() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(LocalizationService().currentLanguage == 'vi' ? 'Xác nhận' : 'Confirm'), content: Text(LocalizationService().currentLanguage == 'vi' ? 'Bạn muốn xóa ảnh đại diện?' : 'Ban muon xoa anh dai dien?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Hủy' : 'Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Xóa' : 'Xoa', style: TextStyle(color: Colors.red))),
        ],
      )
    );
    if (confirm != true) return;
    
    setState(() => _isUploadingAvatar = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      final res = await AppConfig.client.post(
        Uri.parse('${AppConfig.baseUrl}/api/profile_api.php'),
        headers: {'Cookie': 'PHPSESSID=$sessionId'},
        body: {'action': 'delete_avatar'},
      );
      final data = jsonDecode(res.body);
      if (data['status'] == 'success') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? '✅ Đã xóa ảnh đại diện!' : '✅ Avatar deleted successfully!'), backgroundColor: Colors.green));
        setState(() { _userData!['avatar'] = "${AppConfig.baseUrl}/static/default.png"; });
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _kickDevice(String targetSessionId, String deviceName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(LocalizationService().currentLanguage == 'vi' ? 'Xác nhận' : 'Confirm'), content: Text(LocalizationService().currentLanguage == 'vi' ? 'Đăng xuất khỏi $deviceName?' : 'Log out of $deviceName?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Hủy' : 'Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Đăng xuất' : 'Log out', style: TextStyle(color: Colors.red))),
        ],
      )
    );
    if (confirm != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      
      final response = await AppConfig.client.post(
        Uri.parse('${AppConfig.baseUrl}/api/profile_api.php'),
        headers: {'Cookie': 'PHPSESSID=$sessionId'},
        body: {'action': 'delete_device', 'device_id': targetSessionId},
      );
      if (jsonDecode(response.body)['status'] == 'success') {
        setState(() => _devices.removeWhere((d) => d['session_id'] == targetSessionId));
      }
    } catch (e) {}
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
          final response = await AppConfig.client.post(
            Uri.parse('${AppConfig.baseUrl}/api/subscribe'),
            headers: {'Content-Type': 'application/json', 'Cookie': 'PHPSESSID=$sessionId'},
            body: jsonEncode({'endpoint': fcmToken, 'platform': 'app', 'device_model': realModel}),
          );
          if (jsonDecode(response.body)['status'] == 'success') {
            setState(() => _isThisDevicePushEnabled = true);
            _fetchProfileData(); 
          }
        }
      } else {
        await AppConfig.client.post(
          Uri.parse('${AppConfig.baseUrl}/gate_check'),
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


  final TextEditingController _fbCtrl = TextEditingController();
  final TextEditingController _ttCtrl = TextEditingController();
  final TextEditingController _igCtrl = TextEditingController();
  final TextEditingController _ytCtrl = TextEditingController();
  final TextEditingController _zlCtrl = TextEditingController();
  final TextEditingController _ghCtrl = TextEditingController();
  final TextEditingController _thCtrl = TextEditingController();

  bool _socialInit = false;

  Future<void> _apiPost(Map<String, String> body, Function(Map<String, dynamic>) onSuccess, {bool showToast = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getString('phpsessid') ?? '';
    try {
      final res = await AppConfig.client.post(
        Uri.parse('${AppConfig.baseUrl}/api/profile_api.php'),
        headers: {'Cookie': 'PHPSESSID=$sessionId'},
        body: body,
      );
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        String msg = d['msg'] ?? '';
        if (LocalizationService().currentLanguage == 'en') {
            if (msg.contains('bật Bảo mật 2 Yếu tố')) msg = '2-Factor Authentication (2FA) enabled successfully!';
            else if (msg.contains('tắt Bảo mật 2 Yếu tố')) msg = '2-Factor Authentication (2FA) disabled successfully!';
            else if (msg.contains('khoá Secret 2FA')) msg = '2FA Secret not initialized!';
            else if (msg.contains('Mã xác thực 2FA không chính xác')) msg = 'Invalid or expired 2FA code!';
            else if (msg.contains('cập nhật thành công') || msg.contains('Đã cập nhật thông tin')) msg = 'Updated successfully!';
            else if (msg.contains('Gửi mã OTP thành công') || msg.contains('Đã gửi mã xác nhận OTP')) msg = 'OTP sent to email successfully!';
            else if (msg.contains('liên kết và xác thực email thành công') || msg.contains('Liên kết Email thành công')) msg = 'Email linked and verified successfully!';
            else if (msg.contains('hủy liên kết email')) msg = 'Email unlinked successfully!';
            else if (msg.contains('Mã OTP không chính xác')) msg = 'Invalid OTP code!';
            else if (msg.contains('Mã OTP đã hết hạn')) msg = 'OTP code has expired!';
            else if (msg.contains('liên kết với một tài khoản khác')) msg = 'This email is already linked to another account!';
            else if (msg.contains('không hợp lệ')) msg = 'Invalid email address!';
            else if (msg.contains('Đã đổi Avatar') || msg.contains('Đã đổi ảnh đại diện')) msg = 'Avatar changed successfully!';
            else if (msg.contains('Đã xóa ảnh đại diện')) msg = 'Avatar deleted successfully!';
            else if (msg.contains('đăng xuất thiết bị')) msg = 'Device logged out successfully!';
            else if (msg.contains('Không thể tự kick')) msg = 'Cannot kick current active device!';
            else if (msg.contains('Gửi email thất bại')) msg = 'Failed to send email!';
            else if (msg == 'Success') msg = 'Success';
            else if (msg == 'Error') msg = 'Error';
        }

        if (d['status'] == 'success') {
          if (showToast && msg.trim().isNotEmpty && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
          }
          onSuccess(d);
        } else {
          if (showToast && msg.trim().isNotEmpty && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
          }
        }
      }
    } catch (e) {
      if (showToast && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Lỗi kết nối' : 'Connection Error'), backgroundColor: Colors.red));
    }
  }

  void _showEmailLinkDialog() {
    bool isEmailLinked = _userData != null && _userData!['email'] != null && _userData!['email'].toString().isNotEmpty && (_userData!['email_verified'] == 1 || _userData!['email_verified'] == '1' || _userData!['email_verified'] == true);
    if (isEmailLinked) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(LocalizationService().currentLanguage == 'vi' ? 'Hủy liên kết Email' : 'Unlink Email'),
          content: Text(LocalizationService().currentLanguage == 'vi' 
            ? 'Bạn có chắc chắn muốn hủy liên kết email ${_userData!['email']}?' 
            : 'Are you sure you want to unlink email ${_userData!['email']}?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Hủy' : 'Cancel')),
            FilledButton(
              onPressed: () {
                _apiPost({'action': 'unlink_email'}, (d) { Navigator.pop(ctx); _fetchProfileData(); });
              },
              child: Text(LocalizationService().currentLanguage == 'vi' ? 'Hủy liên kết' : 'Unlink'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
            ),
          ],
        ),
      );
      return;
    }

    final TextEditingController emailCtrl = TextEditingController(text: (_userData != null && _userData!['email'] != null) ? _userData!['email'].toString() : '');
    final TextEditingController otpCtrl = TextEditingController();
    bool step2 = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mark_email_read, size: 50, color: Colors.blue),
              SizedBox(height: 10),
              Text(step2 ? (LocalizationService().currentLanguage == 'vi' ? 'Nhập mã OTP' : 'Enter OTP Code') : (LocalizationService().currentLanguage == 'vi' ? 'Liên kết Email' : 'Link Email'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              SizedBox(height: 20),
              if (!step2) TextField(controller: emailCtrl, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Email cá nhân' : 'Personal Email', border: OutlineInputBorder())),
              if (step2) TextField(controller: otpCtrl, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Mã OTP (6 số)' : 'OTP Code (6 digits)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
              SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (!step2) {
                      _apiPost({'action': 'send_email_otp', 'email': emailCtrl.text}, (d) {
                        if (d['status'] == 'success') setState(() => step2 = true);
                      });
                    } else {
                      _apiPost({'action': 'verify_email_otp', 'otp': otpCtrl.text}, (d) { 
                        if (d['status'] == 'success') { Navigator.pop(ctx); _fetchProfileData(); }
                      });
                    }
                  },
                  child: Text(step2 ? (LocalizationService().currentLanguage == 'vi' ? 'Xác nhận' : 'Confirm') : (LocalizationService().currentLanguage == 'vi' ? 'Gửi mã OTP' : 'Send OTP')),
                ),
              ),
              SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _show2FADialog() {
    bool enabled = _userData?['two_factor_enabled'] == 1;
    if (enabled) {
      final TextEditingController otpCtrl = TextEditingController();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(LocalizationService().currentLanguage == 'vi' ? 'Tắt 2FA' : 'Disable 2FA'),
          content: TextField(controller: otpCtrl, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Mã OTP (6 số)' : 'OTP Code (6 digits)'), keyboardType: TextInputType.number),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Hủy' : 'Cancel')),
            FilledButton(
              onPressed: () {
                _apiPost({'action': 'disable_2fa', 'code': otpCtrl.text}, (d) { Navigator.pop(ctx); _fetchProfileData(); });
              },
              child: Text(LocalizationService().currentLanguage == 'vi' ? 'Tắt 2FA' : 'Disable 2FA'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
            ),
          ],
        ),
      );
    } else {
      _apiPost({'action': 'get_2fa_setup'}, (d) {
        if (d['status'] == 'success') {
          final String otpUri = d['otp_uri'] ?? '';
          final String secretCode = d['secret'] ?? '';
          final String qrUrl = 'https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${Uri.encodeComponent(otpUri)}';
          
          final TextEditingController otpCtrl = TextEditingController();
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (ctx) => Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.security, size: 50, color: Colors.green),
                  SizedBox(height: 10),
                  Text(LocalizationService().currentLanguage == 'vi' ? 'Bật 2FA' : 'Enable 2FA', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  SizedBox(height: 10),
                  Text(LocalizationService().currentLanguage == 'vi' ? '1. Quét mã QR bằng ứng dụng Authenticator' : '1. Scan QR with Authenticator app'),
                  SizedBox(height: 10),
                  Image.network(qrUrl, width: 150, height: 150),
                  SizedBox(height: 10),
                  Text(LocalizationService().currentLanguage == 'vi' ? 'Hoặc nhập mã thủ công:' : 'Or enter setup key manually:', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  SelectableText(secretCode, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Theme.of(context).colorScheme.primary)),
                  SizedBox(height: 20),
                  Text(LocalizationService().currentLanguage == 'vi' ? '2. Nhập mã 6 số để xác nhận' : '2. Enter 6-digit code to confirm'),
                  SizedBox(height: 10),
                  TextField(controller: otpCtrl, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Mã OTP (6 số)' : 'OTP Code (6 digits)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
                  SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        _apiPost({'action': 'enable_2fa', 'code': otpCtrl.text}, (d2) { Navigator.pop(ctx); _fetchProfileData(); });
                      },
                      child: Text(LocalizationService().currentLanguage == 'vi' ? 'Xác nhận Bật 2FA' : 'Confirm Enable 2FA'),
                    ),
                  ),
                  SizedBox(height: 20),
                ],
              ),
            ),
          );
        }
      }, showToast: false);
    }
  }

  void _showChangePasswordDialog() {
    final TextEditingController oldCtrl = TextEditingController();
    final TextEditingController newCtrl = TextEditingController();
    final TextEditingController confirmCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_reset, size: 50, color: Colors.red),
            SizedBox(height: 10),
            Text(LocalizationService().currentLanguage == 'vi' ? 'Đổi mật khẩu' : 'Change Password', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 20),
            TextField(controller: oldCtrl, obscureText: true, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Mật khẩu cũ' : 'Old Password', border: OutlineInputBorder())),
            SizedBox(height: 10),
            TextField(controller: newCtrl, obscureText: true, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Mật khẩu mới' : 'New Password', border: OutlineInputBorder())),
            SizedBox(height: 10),
            TextField(controller: confirmCtrl, obscureText: true, decoration: InputDecoration(labelText: LocalizationService().currentLanguage == 'vi' ? 'Nhập lại mật khẩu mới' : 'Confirm New Password', border: OutlineInputBorder())),
            SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  if (newCtrl.text != confirmCtrl.text) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Mật khẩu mới không khớp!' : 'New passwords do not match!'), backgroundColor: Colors.red));
                    return;
                  }
                  final prefs = await SharedPreferences.getInstance();
                  final sessionId = prefs.getString('phpsessid') ?? '';
                  try {
                    final res = await AppConfig.client.post(
                      Uri.parse('${AppConfig.baseUrl}/api/change_password_api.php'),
                      headers: {'Cookie': 'PHPSESSID=$sessionId'},
                      body: {'action': 'change_password', 'old_password': oldCtrl.text, 'new_password': newCtrl.text, 'confirm_password': confirmCtrl.text},
                    );
                    if (res.statusCode == 200) {
                      final d = jsonDecode(res.body);
                      String msg = d['msg'] ?? '';
                      if (LocalizationService().currentLanguage == 'en') {
                         if (msg.contains('đổi mật khẩu thành công')) msg = 'Password changed successfully!';
                         if (msg.contains('không đúng')) msg = 'Incorrect old password!';
                      }
                      if (d['status'] == 'success') {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
                      }
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Lỗi kết nối' : 'Connection Error'), backgroundColor: Colors.red));
                  }
                },
                child: Text(LocalizationService().currentLanguage == 'vi' ? 'Lưu thay đổi' : 'Save Changes'),
              ),
            ),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Scaffold(body: Center(child: CircularProgressIndicator()));

    if (!_socialInit && _studentData != null) {
      _fbCtrl.text = _studentData?['facebook_url'] ?? '';
      _ttCtrl.text = _studentData?['tiktok_url'] ?? '';
      _igCtrl.text = _studentData?['instagram_url'] ?? '';
      _ytCtrl.text = _studentData?['youtube_url'] ?? '';
      _zlCtrl.text = _studentData?['zalo_url'] ?? '';
      _ghCtrl.text = _studentData?['github_url'] ?? '';
      _thCtrl.text = _studentData?['threads_url'] ?? '';
      _socialInit = true;
    }

    if (_userData == null) return Scaffold(body: Center(child: Text(LocalizationService().currentLanguage == 'vi' ? 'Không thể tải dữ liệu. Vui lòng kiểm tra kết nối mạng!' : 'Unable to load data. Please check your network connection!')));

    return Scaffold(
      appBar: AppBar(title: Text(LocalizationService().currentLanguage == 'vi' ? 'Hồ sơ cá nhân' : 'Personal Profile', style: TextStyle(fontWeight: FontWeight.bold))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 120), // FIX: Prevent bottom nav overlap
        child: Column(
          children: [
            Card(
              elevation: 0, color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2))),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        // ĐÃ BỎ "padding: const EdgeInsets.all(3)" GÂY LỖI
                        CircleAvatar(radius: 55, backgroundColor: Colors.white,
                          child: CircleAvatar(radius: 52, backgroundImage: NetworkImage(_userData!['avatar'].toString().startsWith('http') ? _userData!['avatar'] : "${AppConfig.baseUrl}${_userData!['avatar']}"), backgroundColor: Colors.grey.shade200),
                        ),
                        if (_isUploadingAvatar)
                          const CircleAvatar(radius: 55, backgroundColor: Colors.black54, child: CircularProgressIndicator(color: Colors.white)),
                        Positioned(
                          right: 0, bottom: 0,
                          child: GestureDetector(
                            onTap: _isUploadingAvatar ? null : _startAvatarChangeProcess, // GỌI HÀM MỚI
                            child: CircleAvatar(radius: 18, backgroundColor: Theme.of(context).colorScheme.primary,
                              child: Icon(Icons.camera_alt, size: 18, color: Colors.white),
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
                    SizedBox(height: 16),
                    Text(_userData!['full_name'] ?? _userData!['username'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    if (_studentData != null) ...[
                      Text('${_studentData!['class_name']} - ${_userData!['username']}', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600, fontSize: 16)),
                    ] else ...[
                      Text(LocalizationService().currentLanguage == "vi" ? "Quyền: ${_userData!['role']}" : "Role: ${_userData!['role']}", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 15)),
                  ],
                    ],
                ),
              ),
            ),
            
            SizedBox(height: 16),
            Card(
              elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.orange.shade300)),
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                secondary: Icon(_isThisDevicePushEnabled ? Icons.notifications_active : Icons.notifications_off, color: _isThisDevicePushEnabled ? Colors.orange : Colors.grey),
                title: Text(LocalizationService().currentLanguage == 'vi' ? 'Nhận thông báo máy này' : 'Receive push notifications', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(LocalizationService().currentLanguage == 'vi' ? 'Báo điểm trừ, cảnh báo AI Python' : 'Penalty points, AI warnings'),
                value: _isThisDevicePushEnabled,
                activeThumbColor: Colors.orange,
                onChanged: _toggleNotification,
              ),
            ),

            SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  if (_userData != null && ['STUDENT', 'RED_FLAG'].contains(_userData!['role'])) ...[
                    ListTile(
                      leading: Icon(Icons.open_in_new, color: Colors.blue),
                      title: Text(LocalizationService().currentLanguage == 'vi' ? 'Xem trang Bio của tôi' : 'View My Bio Page'),
                      trailing: Icon(Icons.chevron_right),
                      onTap: () async {
                        final code = _userData?['username'] ?? '';
                        final Uri url = Uri.parse('${AppConfig.baseUrl}/$code');
                        if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {}
                      },
                    ),
                    Divider(height: 1),
                  ],
                  Builder(
                    builder: (context) {
                      bool isEmailLinked = _userData != null && _userData!['email'] != null && _userData!['email'].toString().isNotEmpty && (_userData!['email_verified'] == 1 || _userData!['email_verified'] == '1' || _userData!['email_verified'] == true);
                      String emailSub = '';
                      if (isEmailLinked) {
                        emailSub = _userData!['email'];
                      } else if (_userData != null && _userData!['email'] != null && _userData!['email'].toString().isNotEmpty) {
                        emailSub = LocalizationService().currentLanguage == 'vi' ? 'Chưa xác thực: ${_userData!['email']}' : 'Unverified: ${_userData!['email']}';
                      } else {
                        emailSub = LocalizationService().currentLanguage == 'vi' ? 'Chưa liên kết' : 'Not linked';
                      }
                      return ListTile(
                        leading: Icon(Icons.email, color: Colors.orange),
                        title: Text(LocalizationService().currentLanguage == 'vi' ? 'Liên kết Email' : 'Link Email'),
                        subtitle: Text(emailSub, style: TextStyle(fontSize: 12, color: isEmailLinked ? Colors.green : (emailSub.contains(':') ? Colors.orange : Colors.grey))),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isEmailLinked ? Colors.green.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isEmailLinked ? Colors.green : Colors.grey),
                              ),
                              child: Text(
                                isEmailLinked ? 'ON' : 'OFF',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isEmailLinked ? Colors.green : Colors.grey),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: _showEmailLinkDialog,
                      );
                    },
                  ),
                  Divider(height: 1),
                  Builder(
                    builder: (context) {
                      bool is2FA = _userData?['two_factor_enabled'] == 1;
                      String twoFASub = is2FA 
                        ? (LocalizationService().currentLanguage == 'vi' ? 'Đang bảo vệ tài khoản' : 'Account protected') 
                        : (LocalizationService().currentLanguage == 'vi' ? 'Chưa kích hoạt' : 'Not activated');
                      return ListTile(
                        leading: Icon(Icons.security, color: Colors.green),
                        title: Text(LocalizationService().currentLanguage == 'vi' ? 'Xác thực 2 yếu tố (2FA)' : '2-Factor Authentication (2FA)'),
                        subtitle: Text(twoFASub, style: TextStyle(fontSize: 12, color: is2FA ? Colors.green : Colors.grey)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: is2FA ? Colors.green.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: is2FA ? Colors.green : Colors.grey),
                              ),
                              child: Text(
                                is2FA ? 'ON' : 'OFF',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: is2FA ? Colors.green : Colors.grey),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: _show2FADialog,
                      );
                    },
                  ),
                  Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.lock_reset, color: Colors.red),
                    title: Text(LocalizationService().currentLanguage == 'vi' ? 'Đổi mật khẩu' : 'Change Password'),
                    trailing: Icon(Icons.chevron_right),
                    onTap: _showChangePasswordDialog,
                  ),
                ],
              ),
            ),

            SizedBox(height: 16),
            if (_userData != null && ['STUDENT', 'RED_FLAG'].contains(_userData!['role'])) ...[
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      TextField(controller: _fbCtrl, decoration: InputDecoration(labelText: 'Facebook URL', prefixIcon: Icon(Icons.facebook, color: Colors.blue))),
                      SizedBox(height: 10),
                      TextField(controller: _zlCtrl, decoration: InputDecoration(labelText: 'Zalo URL', prefixIcon: Icon(Icons.chat, color: Colors.blueAccent))),
                      SizedBox(height: 10),
                      TextField(controller: _ttCtrl, decoration: InputDecoration(labelText: 'TikTok URL', prefixIcon: Icon(Icons.music_note, color: Colors.black))),
                      SizedBox(height: 10),
                      TextField(controller: _igCtrl, decoration: InputDecoration(labelText: 'Instagram URL', prefixIcon: Icon(Icons.camera_alt, color: Colors.pink))),
                      SizedBox(height: 10),
                      TextField(controller: _ytCtrl, decoration: InputDecoration(labelText: 'YouTube URL', prefixIcon: Icon(Icons.play_circle, color: Colors.red))),
                      SizedBox(height: 10),
                      TextField(controller: _ghCtrl, decoration: InputDecoration(labelText: 'GitHub URL', prefixIcon: Icon(Icons.code, color: Colors.black87))),
                      SizedBox(height: 10),
                      TextField(controller: _thCtrl, decoration: InputDecoration(labelText: 'Threads URL', prefixIcon: Icon(Icons.alternate_email, color: Colors.black))),
                      SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: Icon(Icons.save),
                          label: Text(LocalizationService().currentLanguage == 'vi' ? 'Lưu MXH' : 'Save Social Media'),
                          onPressed: () {
                            _apiPost({
                              'facebook_url': _fbCtrl.text,
                              'zalo_url': _zlCtrl.text,
                              'tiktok_url': _ttCtrl.text,
                              'instagram_url': _igCtrl.text,
                              'youtube_url': _ytCtrl.text,
                              'github_url': _ghCtrl.text,
                              'threads_url': _thCtrl.text,
                            }, (d) => _fetchProfileData());
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16),
            ],

            SizedBox(height: 16),
            Card(
              elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: EdgeInsets.all(16), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Lịch sử đăng nhập' : 'Login History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
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
                          backgroundColor: isCurrent ? Colors.green.withValues(alpha: 0.1) : Colors.grey.shade100,
                          child: Icon(_getDeviceIcon(dev['user_agent'], displayModel, dev['platform'] ?? 'web'), color: isCurrent ? Colors.green : Colors.grey, size: 20),
                        ),
                        title: Row(children: [
                            Expanded(child: Text(displayModel, style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600, color: isCurrent ? Colors.green : null))),
                            if (dev['push_enabled'] == 1) Icon(Icons.notifications_active, color: Colors.orange, size: 16),
                        ]),
                        subtitle: Text(
                          LocalizationService().currentLanguage == "vi" 
                            ? "Đăng nhập: ${_formatDate(dev['last_active'] ?? dev['created_at'])}" 
                            : "Login: ${_formatDate(dev['last_active'] ?? dev['created_at'])}", 
                          style: const TextStyle(fontSize: 12, color: Colors.grey)
                        ),
                        trailing: !isCurrent ? IconButton(icon: Icon(Icons.logout, color: Colors.redAccent, size: 20), onPressed: () => _kickDevice(dev['session_id'], displayModel)) : null,
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
  String _formatDate(dynamic dateStr) {
    if (dateStr == null || dateStr.toString().trim().isEmpty) return LocalizationService().currentLanguage == 'vi' ? 'Gần đây' : 'Recently';
    try {
      final dt = DateTime.parse(dateStr.toString());
      final d = dt.day.toString().padLeft(2, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$d/$m $h:$min';
    } catch (_) {
      return dateStr.toString();
    }
  }

  bool empty(dynamic val) => val == null || val.toString().trim() == '';
}