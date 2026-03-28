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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Mật khẩu xác nhận không khớp!'), backgroundColor: Colors.red));
      return;
    }
    if (_newPassCtrl.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Mật khẩu phải từ 6 ký tự!'), backgroundColor: Colors.red));
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Lỗi kết nối: $e'), backgroundColor: Colors.red));
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
      appBar: AppBar(title: const Text('Đổi Mật Khẩu', style: TextStyle(fontWeight: FontWeight.bold))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.lock_reset, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            _buildPassField('Mật khẩu hiện tại', _oldPassCtrl, _isObscureOld, () => setState(() => _isObscureOld = !_isObscureOld), isDark),
            _buildPassField('Mật khẩu mới', _newPassCtrl, _isObscureNew, () => setState(() => _isObscureNew = !_isObscureNew), isDark),
            _buildPassField('Xác nhận mật khẩu mới', _confirmPassCtrl, _isObscureConfirm, () => setState(() => _isObscureConfirm = !_isObscureConfirm), isDark),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _isLoading ? null : _submitChange,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('LƯU MẬT KHẨU', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            )
          ],
        ),
      ),
    );
  }
}