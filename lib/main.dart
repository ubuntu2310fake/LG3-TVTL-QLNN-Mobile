import 'dart:convert';
import 'dart:ui'; // BẮT BUỘC ĐỂ DÙNG FontFeature
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import 'login_screen.dart';
import 'main_shell.dart';

// ==========================================
// KHAI BÁO BIẾN TOÀN CỤC (Chỉ sửa ở đây)
// ==========================================
const String currentAppVersion = "1.0.3_r1";

// BIẾN TOÀN CỤC ĐỂ ĐIỀU KHIỂN THEME TOÀN APP
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Load cấu hình Theme đã lưu từ trước
  final prefs = await SharedPreferences.getInstance();
  final savedTheme = prefs.getString('theme_mode') ?? 'system';
  if (savedTheme == 'light') themeNotifier.value = ThemeMode.light;
  else if (savedTheme == 'dark') themeNotifier.value = ThemeMode.dark;
  else themeNotifier.value = ThemeMode.system;

  runApp(const LG3App());
}

// HÀM ÁP DỤNG FONT INTER KÈM CÁC CẤU HÌNH NÂNG CAO CHO TOÀN BỘ APP (GIỐNG WEB)
TextTheme buildInterTextTheme(TextTheme base) {
  return base.copyWith(
    // Áp dụng cho mọi kiểu chữ từ nhỏ đến lớn
    displayLarge: _applyInter(base.displayLarge),
    displayMedium: _applyInter(base.displayMedium),
    displaySmall: _applyInter(base.displaySmall),
    headlineLarge: _applyInter(base.headlineLarge),
    headlineMedium: _applyInter(base.headlineMedium),
    headlineSmall: _applyInter(base.headlineSmall),
    titleLarge: _applyInter(base.titleLarge),
    titleMedium: _applyInter(base.titleMedium),
    titleSmall: _applyInter(base.titleSmall),
    bodyLarge: _applyInter(base.bodyLarge),
    bodyMedium: _applyInter(base.bodyMedium),
    bodySmall: _applyInter(base.bodySmall),
    labelLarge: _applyInter(base.labelLarge),
    labelMedium: _applyInter(base.labelMedium),
    labelSmall: _applyInter(base.labelSmall),
  );
}

// Hàm bổ trợ để ép cấu hình chuẩn Web CSS
TextStyle _applyInter(TextStyle? style) {
  return (style ?? const TextStyle()).copyWith(
    fontFamily: 'Inter',
    letterSpacing: -0.15, // Tương đương -0.011em
    fontFeatures: [
      const FontFeature.enable('cv05'), // Lowercase 'l' with tail
      const FontFeature.enable('cv08'), // Upper case 'I' with serifs
      const FontFeature.enable('ss01'), // Open digits (ví dụ số 1, 6, 9 thoáng hơn)
    ],
  );
}

class LG3App extends StatelessWidget {
  const LG3App({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          title: 'LG3 Quản Lý Nền Nếp',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeData(
            fontFamily: 'Inter', // Cấu hình Font mặc định
            textTheme: buildInterTextTheme(ThemeData.light().textTheme), // Áp dụng chi tiết FontFeature
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF005FBA), brightness: Brightness.light),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            fontFamily: 'Inter', // Cấu hình Font mặc định
            textTheme: buildInterTextTheme(ThemeData.dark().textTheme), // Áp dụng chi tiết FontFeature
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF005FBA), brightness: Brightness.dark),
            useMaterial3: true,
          ),
          home: const SplashScreen(),
        );
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
  }

  Future<void> _checkAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberToken = prefs.getString('remember_token');

    // NẾU CÓ THẺ "NHỚ ĐĂNG NHẬP" -> GỌI API LẤY SESSION MỚI
    if (rememberToken != null && rememberToken.isNotEmpty) {
      try {
        final response = await http.post(
          Uri.parse('https://qlnn.testifiyonline.xyz/api/login_api'),
          body: {'remember_token': rememberToken},
        );
        final data = jsonDecode(response.body);
        
        if (response.statusCode == 200 && data['status'] == 'success') {
          await prefs.setString('phpsessid', data['session_id']);
          if (!mounted) return;
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainShell()));
          return;
        }
      } catch (e) {
        // LỖI MẠNG: Vẫn cho vào App để dùng Data Offline!
        final oldSess = prefs.getString('phpsessid');
        if (oldSess != null && oldSess.isNotEmpty) {
          if (!mounted) return;
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainShell()));
          return;
        }
      }
    }
    
    // NẾU KHÔNG CÓ TOKEN HOẶC BỊ TỪ CHỐI -> ĐÁ RA LOGIN
    await Future.delayed(const Duration(milliseconds: 500)); 
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF005FBA),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20), 
              child: Image.asset(
                'assets/images/lg3512512.png',
                width: 100, 
                height: 100,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.shield_rounded, size: 80, color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
            
            // ĐÃ SỬA: Căn giữa dòng chữ, ép xuống dòng cho đẹp
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.0),
              child: Text(
                'LG3 - TƯ VẤN TÂM LÝ\nVÀ QUẢN LÝ THI ĐUA', 
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white, 
                  fontSize: 22, 
                  fontWeight: FontWeight.bold, 
                  letterSpacing: 1.5,
                  height: 1.4 // Tạo khoảng cách giữa 2 dòng
                )
              ),
            ),
            
            const SizedBox(height: 40),
            CircularProgressIndicator(color: Colors.white.withOpacity(0.8)),
          ],
        ),
      ),
    );
  }
}