import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'config.dart';
import 'localization_service.dart';

class CloudflareCaptchaService {
  static final CloudflareCaptchaService _instance = CloudflareCaptchaService._internal();
  factory CloudflareCaptchaService() => _instance;
  CloudflareCaptchaService._internal();

  bool _isChallengeShowing = false;

  /// Kiểm tra xem response từ server có phải là trang Cloudflare Challenge hoặc LG3 Shield Captcha không
  static bool isCloudflareChallenge(int statusCode, String body) {
    if (statusCode == 252 || statusCode == 403 || statusCode == 503 || statusCode == 429 || statusCode == 302) {
      final lower = body.toLowerCase();
      if (lower.contains('challenges.cloudflare.com') ||
          lower.contains('just a moment...') ||
          lower.contains('cf-turnstile') ||
          lower.contains('_cf_chl_opt') ||
          lower.contains('ray id:') ||
          lower.contains('captcha_challenge.php') ||
          lower.contains('xác thực bảo vệ lg3') ||
          lower.contains('lg3 shield')) {
        return true;
      }
    }
    return false;
  }

  /// Mở modal WebView để người dùng giải Captcha (Cloudflare Turnstile hoặc LG3 Math Captcha)
  Future<bool> handleChallenge(BuildContext context) async {
    if (_isChallengeShowing) return false;
    _isChallengeShowing = true;

    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const CloudflareCaptchaDialog(),
      );
      return result ?? false;
    } finally {
      _isChallengeShowing = false;
    }
  }
}

class CloudflareCaptchaDialog extends StatefulWidget {
  const CloudflareCaptchaDialog({super.key});

  @override
  State<CloudflareCaptchaDialog> createState() => _CloudflareCaptchaDialogState();
}

class _CloudflareCaptchaDialogState extends State<CloudflareCaptchaDialog> {
  late final WebViewController _controller;
  bool _isLoading = true;
  Timer? _cookieCheckTimer;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36')
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (url) async {
            if (mounted) setState(() => _isLoading = false);
            _checkClearanceCookie();
          },
        ),
      )
      ..loadRequest(Uri.parse('${AppConfig.baseUrl}/captcha_challenge.php'));

    // Định kỳ kiểm tra cookie cf_clearance hoặc lg3_shield_pass
    _cookieCheckTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      _checkClearanceCookie();
    });
  }

  Future<void> _checkClearanceCookie() async {
    try {
      final cookieString = await _controller.runJavaScriptReturningResult('document.cookie');
      final raw = cookieString.toString();
      bool hasPassed = false;
      
      if (raw.contains('cf_clearance') || raw.contains('lg3_shield_pass')) {
        final cookies = raw.replaceAll('"', '').split(';');
        final prefs = await SharedPreferences.getInstance();
        
        for (var c in cookies) {
          final parts = c.trim().split('=');
          if (parts.isNotEmpty && parts.length > 1) {
            final key = parts[0];
            final val = parts.sublist(1).join('=');
            
            if (key == 'cf_clearance' && val.isNotEmpty) {
              await prefs.setString('cf_clearance', val);
              AppConfig.cfClearance = val;
              hasPassed = true;
            }
            if (key == 'lg3_shield_pass' && val.isNotEmpty) {
              await prefs.setString('lg3_shield_pass', val);
              AppConfig.shieldPass = val;
              hasPassed = true;
            }
          }
        }
      }

      if (hasPassed) {
        _cookieCheckTimer?.cancel();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(LocalizationService().currentLanguage == 'vi'
                  ? 'Xác thực bảo vệ thành công!'
                  : 'Security verification successful!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
          Navigator.of(context).pop(true);
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _cookieCheckTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVi = LocalizationService().currentLanguage == 'vi';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 520,
          width: double.infinity,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: const Color(0xFF005FBA),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isVi ? 'Xác thực bảo vệ LG3 Shield' : 'LG3 Shield Security Verification',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
              ),
              if (_isLoading)
                const LinearProgressIndicator(minHeight: 2, color: Color(0xFF005FBA)),
              Expanded(
                child: WebViewWidget(controller: _controller),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade100,
                child: Row(
                  children: [
                    const Icon(Icons.touch_app_outlined, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isVi
                            ? 'Vui lòng hoàn thành câu đố xác thực bảo vệ phía trên.'
                            : 'Please complete the security puzzle above.',
                        style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
