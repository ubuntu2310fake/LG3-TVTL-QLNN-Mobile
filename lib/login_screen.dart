import 'localization_service.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'device_helper.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'main_shell.dart';
import 'config.dart'; // 👉 1. THÊM IMPORT NÀY

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _rememberMe = true;
  String? _twoFactorCode; // Mặc định là Nhớ đăng nhập

  Future<void> _handleLogin() async {
    if (_usernameCtrl.text.trim().isEmpty || _passwordCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Vui lòng nhập đủ thông tin!' : 'Please enter all information!')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      String deviceName = await DeviceHelper.getDeviceModel();

      final response = await AppConfig.client.post(
        Uri.parse('${AppConfig.baseUrl}/api/login_api.php'), 
        body: {
          'username': _usernameCtrl.text.trim(),
          'password': _passwordCtrl.text,
          'remember_me': _rememberMe ? '1' : '0',
          'device_name': deviceName,
          if (_twoFactorCode != null) 'two_factor_code': _twoFactorCode
        },
      );

      // ĐÃ SỬA: Kiểm tra HTTP Status Code trước khi Decode JSON
      if (response.statusCode == 200) {
        try {
            final data = jsonDecode(response.body);
            
            if (data['status'] == '2fa_required') {
                if (!mounted) return;
                setState(() => _isLoading = false);
                _show2FADialog();
                return;
            } else if (data['status'] == 'success') {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('phpsessid', data['session_id']);
                
                // ĐÃ SỬA: Ép kiểu toString() để chống lỗi khi lưu SharedPreferences
                if (data['remember_token'] != null) {
                  await prefs.setString('remember_token', data['remember_token'].toString()); 
                }
                
                await prefs.setString('full_name', data['user']['full_name'].toString());
                await prefs.setString('role', data['user']['role'].toString());

                bool mustChange = (data['must_change_password'] == true) || (data['user']?['must_change_password'] == true);
                await prefs.setBool('must_change_password', mustChange);

                if (!mounted) return;
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainShell()));
            } else {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'] ?? (LocalizationService().currentLanguage == 'vi' ? 'Đăng nhập thất bại.' : 'Login failed.'), style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
            }
        } catch (e) {
            // Lỗi khi server trả về HTML thay vì JSON (thường do lỗi code PHP)
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Máy chủ trả về dữ liệu không hợp lệ.' : 'The server returned invalid data.'), backgroundColor: Colors.orange));
        }
      } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Lỗi máy chủ: ${response.statusCode}' : 'Server error: ${response.statusCode}'), backgroundColor: Colors.red));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? '❌ Lỗi kết nối đến máy chủ LG3!' : '❌ Error connecting to LG3 server!'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _show2FADialog() {
    final TextEditingController _otpCtrl = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(LocalizationService().currentLanguage == 'vi' ? 'Xác thực 2 yếu tố' : 'Two-Factor Authentication'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(LocalizationService().currentLanguage == 'vi' ? 'Nhập mã 6 chữ số từ ứng dụng Authenticator:' : 'Enter 6-digit code from Authenticator app:'),
            SizedBox(height: 10),
            TextField(
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                hintText: '123456',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _twoFactorCode = null);
            },
            child: Text(LocalizationService().currentLanguage == 'vi' ? 'Hủy' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _twoFactorCode = _otpCtrl.text.trim();
              });
              _handleLogin();
            },
            child: Text(LocalizationService().currentLanguage == 'vi' ? 'Xác nhận' : 'Confirm'),
          ),
        ],
      ),
    );
  }

  void _showForgotPasswordDialog() {
    final TextEditingController userCtrl = TextEditingController(text: _usernameCtrl.text.trim());
    final TextEditingController otpCtrl = TextEditingController();
    final TextEditingController newPassCtrl = TextEditingController();
    bool step2 = false;
    bool isSubmitting = false;
    String infoMsg = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_reset_rounded, size: 50, color: Theme.of(ctx).colorScheme.primary),
              const SizedBox(height: 10),
              Text(
                LocalizationService().currentLanguage == 'vi' ? 'Khôi phục mật khẩu' : 'Reset Password',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              if (infoMsg.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(infoMsg, style: const TextStyle(fontSize: 12.5, color: Colors.green, fontWeight: FontWeight.w600))),
                    ],
                  ),
                ),
              ],
              if (!step2) ...[
                TextField(
                  controller: userCtrl,
                  decoration: InputDecoration(
                    labelText: LocalizationService().currentLanguage == 'vi' ? 'Tên đăng nhập / Mã học sinh' : 'Username / Student ID',
                    prefixIcon: const Icon(Icons.person),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: isSubmitting ? null : () async {
                      if (userCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                          content: Text(LocalizationService().currentLanguage == 'vi' ? 'Vui lòng nhập tài khoản!' : 'Please enter username!'),
                          backgroundColor: Colors.red,
                        ));
                        return;
                      }
                      setModalState(() => isSubmitting = true);
                      try {
                        final res = await AppConfig.client.post(
                          Uri.parse('${AppConfig.baseUrl}/api/forgot_password_api.php'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({'action': 'send_reset_otp', 'username': userCtrl.text.trim()}),
                        );
                        final data = jsonDecode(res.body);
                        if (data['status'] == 'success') {
                          String msg = data['msg'] ?? '';
                          if (LocalizationService().currentLanguage == 'en') {
                            if (msg.contains('Đã gửi mã OTP') || msg.contains('OTP')) msg = 'OTP code sent to your linked email!';
                          }
                          setModalState(() {
                            step2 = true;
                            infoMsg = msg;
                          });
                        } else {
                          String errMsg = data['msg'] ?? 'Error';
                          if (LocalizationService().currentLanguage == 'en') {
                            if (errMsg.contains('không tồn tại')) errMsg = 'Account does not exist!';
                            else if (errMsg.contains('chưa liên kết') || errMsg.contains('chưa được liên kết')) errMsg = 'Account has not linked email yet!';
                            else if (errMsg.contains('Gửi email thất bại')) errMsg = 'Failed to send email!';
                          }
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errMsg), backgroundColor: Colors.red));
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(LocalizationService().currentLanguage == 'vi' ? 'Lỗi kết nối máy chủ' : 'Server connection error'),
                          backgroundColor: Colors.red,
                        ));
                      } finally {
                        setModalState(() => isSubmitting = false);
                      }
                    },
                    child: isSubmitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(LocalizationService().currentLanguage == 'vi' ? 'Gửi mã OTP qua Email' : 'Send OTP via Email'),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: otpCtrl,
                  decoration: InputDecoration(
                    labelText: LocalizationService().currentLanguage == 'vi' ? 'Mã OTP (6 số)' : 'OTP Code (6 digits)',
                    prefixIcon: const Icon(Icons.lock_clock),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newPassCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: LocalizationService().currentLanguage == 'vi' ? 'Mật khẩu mới (Tối thiểu 6 ký tự)' : 'New Password (Min 6 chars)',
                    prefixIcon: const Icon(Icons.password),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: isSubmitting ? null : () async {
                      if (otpCtrl.text.trim().length != 6) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                          content: Text(LocalizationService().currentLanguage == 'vi' ? 'Vui lòng nhập đủ 6 số OTP!' : 'Please enter 6 digits OTP!'),
                          backgroundColor: Colors.red,
                        ));
                        return;
                      }
                      if (newPassCtrl.text.length < 6) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                          content: Text(LocalizationService().currentLanguage == 'vi' ? 'Mật khẩu phải từ 6 ký tự!' : 'Password must be at least 6 characters!'),
                          backgroundColor: Colors.red,
                        ));
                        return;
                      }
                      setModalState(() => isSubmitting = true);
                      try {
                        final res = await AppConfig.client.post(
                          Uri.parse('${AppConfig.baseUrl}/api/forgot_password_api.php'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'action': 'reset_password_with_otp',
                            'username': userCtrl.text.trim(),
                            'otp': otpCtrl.text.trim(),
                            'new_password': newPassCtrl.text,
                          }),
                        );
                        final data = jsonDecode(res.body);
                        if (data['status'] == 'success') {
                          Navigator.pop(ctx);
                          _usernameCtrl.text = userCtrl.text.trim();
                          _passwordCtrl.text = newPassCtrl.text;
                          String successMsg = data['msg'] ?? '';
                          if (LocalizationService().currentLanguage == 'en') {
                            successMsg = 'Password reset successfully! You can now log in.';
                          }
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMsg), backgroundColor: Colors.green));
                        } else {
                          String errMsg = data['msg'] ?? 'Error';
                          if (LocalizationService().currentLanguage == 'en') {
                            if (errMsg.contains('không chính xác')) errMsg = 'Invalid OTP code!';
                            else if (errMsg.contains('đã hết hạn')) errMsg = 'OTP has expired!';
                            else if (errMsg.contains('không tồn tại')) errMsg = 'Account not found!';
                          }
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errMsg), backgroundColor: Colors.red));
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(LocalizationService().currentLanguage == 'vi' ? 'Lỗi kết nối máy chủ' : 'Server connection error'),
                          backgroundColor: Colors.red,
                        ));
                      } finally {
                        setModalState(() => isSubmitting = false);
                      }
                    },
                    child: isSubmitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(LocalizationService().currentLanguage == 'vi' ? 'Đổi mật khẩu mới' : 'Reset Password'),
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showGuideDialog() {
    bool isVi = LocalizationService().currentLanguage == 'vi';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.all(20.0),
          child: ListView(
            controller: scrollController,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.menu_book_rounded, color: Theme.of(ctx).colorScheme.primary, size: 28),
                  const SizedBox(width: 8),
                  Text(
                    isVi ? 'HƯỚNG DẪN ĐĂNG NHẬP' : 'LOGIN GUIDE',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(ctx).colorScheme.primary),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              // TRƯỜNG HỢP 1: CÓ THẺ HỌC SINH
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.badge, color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          isVi ? 'TRƯỜNG HỢP 1: CÓ THẺ HỌC SINH' : 'CASE 1: HAS STUDENT ID CARD',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isVi 
                        ? '• Nhìn dòng chữ phía trên mã QR trên thẻ học sinh.'
                        : '• Look at the text above the QR code on your card.',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isVi
                        ? '• Ví dụ: 16 Truong Thanh Hieu_K48A1016 -> Tên đăng nhập là dãy số bắt đầu bằng chữ K (K48A1016).'
                        : '• Example: 16 Truong Thanh Hieu_K48A1016 -> Username is the string starting with K (K48A1016).',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isVi
                        ? '• Tuyệt đối không nhập dấu cách hay họ tên.'
                        : '• Absolutely do not enter spaces or full names.',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          '${AppConfig.baseUrl}/static/guide/ma_qr_mau.png',
                          height: 120,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // TRƯỜNG HỢP 2: KHÔNG CÓ THẺ
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          isVi ? 'TRƯỜNG HỢP 2: TỰ GHÉP MÃ' : 'CASE 2: MANUALLY BUILD ID',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isVi
                        ? 'Mã học sinh có dạng: KxxAyzzz (lớp A1 -> A9) hoặc KxxAyyzzz (lớp A10 trở đi).'
                        : 'Student ID format: KxxAyzzz (classes A1 -> A9) or KxxAyyzzz (class A10 and above).',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isVi
                        ? 'Trong đó: xx là Khóa, y/yy là Lớp, zzz là Số thứ tự.'
                        : 'Where: xx is Cohort, y/yy is Class, zzz is Student number.',
                      style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).cardColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isVi
                              ? '• Lớp 10A1, STT 16 ➔ K48A1016'
                              : '• Class 10A1, No. 16 ➔ K48A1016',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isVi
                              ? '• Lớp 10A11, STT 05 ➔ K48A11005'
                              : '• Class 10A11, No. 05 ➔ K48A11005',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isVi
                              ? '• Lớp 11A1, STT 09 ➔ K47A1009'
                              : '• Class 11A1, No. 09 ➔ K47A1009',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(isVi ? 'ĐÃ HIỂU / ĐÓNG' : 'GOT IT / CLOSE'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Stack(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo trường
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, shape: BoxShape.circle),
                    child: Icon(Icons.shield_rounded, size: 40, color: Theme.of(context).colorScheme.primary),
                  ),
                  SizedBox(height: 20),
                  Text(LocalizationService().currentLanguage == 'vi' ? 'Siêu ứng dụng LG3' : 'LG3 Super App', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                  SizedBox(height: 8),
                  Text(LocalizationService().currentLanguage == 'vi' ? 'Trường THPT Lạng Giang số 3' : 'Lang Giang High School No. 3', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600)),
                  
                  SizedBox(height: 32),
                  
                  // Form nhập liệu
                  TextField(
                    controller: _usernameCtrl,
                    decoration: InputDecoration(
                      labelText: LocalizationService().currentLanguage == 'vi' ? 'Tài khoản (GV hoặc Mã HS)' : 'Account (GV or HS Code)',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true, fillColor: Theme.of(context).colorScheme.surface,
                    ),
                  ),
                  SizedBox(height: 16),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: LocalizationService().currentLanguage == 'vi' ? 'Mật khẩu' : 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true, fillColor: Theme.of(context).colorScheme.surface,
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: _obscurePassword ? Colors.grey : Theme.of(context).colorScheme.primary),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                  
                  SizedBox(height: 10),
                  
                  // Checkbox Nhớ đăng nhập
                  Row(
                    children: [
                      Checkbox(
                        value: _rememberMe,
                        activeColor: Theme.of(context).colorScheme.primary,
                        onChanged: (val) => setState(() => _rememberMe = val ?? true),
                      ),
                      Text(LocalizationService().currentLanguage == 'vi' ? 'Giữ trạng thái đăng nhập' : 'Stay logged in', style: TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                  SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _showForgotPasswordDialog,
                      child: Text(LocalizationService().currentLanguage == 'vi' ? 'Quên mật khẩu?' : 'Forgot password?', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                    ),
                  ),
                  
                  SizedBox(height: 24),
                  
                  // Nút Đăng nhập
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: _isLoading ? null : _handleLogin,
                      child: _isLoading
                          ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(LocalizationService().currentLanguage == 'vi' ? 'ĐĂNG NHẬP' : 'LOG IN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Hướng dẫn đăng nhập
                  TextButton.icon(
                    onPressed: _showGuideDialog,
                    icon: Icon(Icons.menu_book_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                    label: Text(
                      LocalizationService().currentLanguage == 'vi' ? 'Hướng dẫn đăng nhập' : 'Login Guide',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary, fontSize: 14),
                    ),
                  ),
                  
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        LocalizationService().currentLanguage == 'vi' ? 'Mật khẩu mặc định: ' : 'Default password: ',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                      Text(
                        '123456',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                      ),
                    ],
                  ),
                ],
              ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  icon: Text(LocalizationService().currentLanguage == 'vi' ? '🇻🇳' : '🇬🇧', style: TextStyle(fontSize: 24)),
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    String newLang = LocalizationService().currentLanguage == 'vi' ? 'en' : 'vi';
                    await prefs.setString('language', newLang);
                    LocalizationService().setLanguage(newLang);
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
        ),
      ),
        ),
      ),
    );
  }
}