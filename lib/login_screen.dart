import 'localization_service.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
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
  bool _rememberMe = true; // Mặc định là Nhớ đăng nhập

  Future<void> _handleLogin() async {
    if (_usernameCtrl.text.trim().isEmpty || _passwordCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Vui lòng nhập đủ thông tin!' : 'Please enter all information!')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/login_api.php'), 
        body: {
          'username': _usernameCtrl.text.trim(),
          'password': _passwordCtrl.text,
          'remember_me': _rememberMe ? '1' : '0' 
        },
      );

      // ĐÃ SỬA: Kiểm tra HTTP Status Code trước khi Decode JSON
      if (response.statusCode == 200) {
        try {
            final data = jsonDecode(response.body);
            
            if (data['status'] == 'success') {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('phpsessid', data['session_id']);
                
                // ĐÃ SỬA: Ép kiểu toString() để chống lỗi khi lưu SharedPreferences
                if (data['remember_token'] != null) {
                  await prefs.setString('remember_token', data['remember_token'].toString()); 
                }
                
                await prefs.setString('full_name', data['user']['full_name'].toString());
                await prefs.setString('role', data['user']['role'].toString());

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
              child: Column(
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}