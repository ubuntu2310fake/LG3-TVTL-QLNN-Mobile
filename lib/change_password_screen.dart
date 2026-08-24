import 'localization_service.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _oldPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _isObscureOld = true, _isObscureNew = true, _isObscureConfirm = true;
  bool _isLoading = false;

  Future<void> _submitChange() async {
    if (_newPassCtrl.text != _confirmPassCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? '❌ Mật khẩu xác nhận không khớp!' : '❌ Passwords do not match!'), backgroundColor: Colors.red));
      return;
    }
    if (_newPassCtrl.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? '❌ Mật khẩu phải từ 6 ký tự!' : '❌ Password must be at least 6 characters!'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';

      final response = await http.post(
        Uri.parse('https://qlnn.testifiyonline.xyz/api/change_password_api'),
        headers: {'Cookie': 'PHPSESSID=$sessionId', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'old_password': _oldPassCtrl.text,
          'new_password': _newPassCtrl.text,
          'confirm_password': _confirmPassCtrl.text,
        }),
      );

      final data = jsonDecode(response.body);
      if (!mounted) return;

      if (data['status'] == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${data['msg']}'), backgroundColor: Colors.green));
        Navigator.pop(context); 
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ ${data['msg']}'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? '❌ Lỗi kết nối: $e' : '❌ Connection error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildPassField(String label, TextEditingController ctrl, bool isObscure, VoidCallback toggle, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextField(
        controller: ctrl,
        obscureText: isObscure,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true, fillColor: isDark ? Colors.grey[800] : Colors.white,
          suffixIcon: IconButton(
            icon: Icon(isObscure ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
            onPressed: toggle,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text(LocalizationService().currentLanguage == 'vi' ? 'Đổi Mật Khẩu' : 'Change Password', style: TextStyle(fontWeight: FontWeight.bold))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.lock_reset, size: 80, color: Colors.blue),
            SizedBox(height: 20),
            _buildPassField(LocalizationService().currentLanguage == 'vi' ? 'Mật khẩu hiện tại' : 'Current Password', _oldPassCtrl, _isObscureOld, () => setState(() => _isObscureOld = !_isObscureOld), isDark),
            _buildPassField(LocalizationService().currentLanguage == 'vi' ? 'Mật khẩu mới' : 'New Password', _newPassCtrl, _isObscureNew, () => setState(() => _isObscureNew = !_isObscureNew), isDark),
            _buildPassField(LocalizationService().currentLanguage == 'vi' ? 'Xác nhận mật khẩu mới' : 'Confirm Password', _confirmPassCtrl, _isObscureConfirm, () => setState(() => _isObscureConfirm = !_isObscureConfirm), isDark),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: _isLoading ? null : _submitChange,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading 
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(LocalizationService().currentLanguage == 'vi' ? 'LƯU MẬT KHẨU' : 'SAVE PASSWORD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            )
          ],
        ),
      ),
    );
  }
}