import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class ConsultingTestScreen extends StatefulWidget {
  const ConsultingTestScreen({super.key});

  @override
  State<ConsultingTestScreen> createState() => _ConsultingTestScreenState();
}

class _ConsultingTestScreenState extends State<ConsultingTestScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isInitDone = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getString('phpsessid') ?? '';
    final lang = prefs.getString('lang') ?? 'vi';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            // Khi load xong page, ép Web đổi theme Sáng/Tối ngay lập tức
            _syncTheme();
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      );

    final cookieManager = WebViewCookieManager();
    if (sessionId.isNotEmpty) {
      await cookieManager.setCookie(
        WebViewCookie(
          name: 'PHPSESSID',
          value: sessionId,
          domain: AppConfig.domain,
          path: '/',
        ),
      );
    }

    // Gắn thêm cookie ngôn ngữ đồng bộ
    await cookieManager.setCookie(
      WebViewCookie(
        name: 'lang',
        value: lang,
        domain: AppConfig.domain,
        path: '/',
      ),
    );

    // ĐÃ THÊM ?iframe=1 ĐỂ ẨN HEADER VÀ BANNER QUẢNG CÁO APP
    _controller.loadRequest(Uri.parse('${AppConfig.baseUrl}/consulting_test.php?iframe=1'));

    if (mounted) {
      setState(() {
        _isInitDone = true;
      });
    }
  }

  // Hàm bắn JavaScript xuống Web để đồng bộ Sáng/Tối
  void _syncTheme() {
    if (!mounted || !_isInitDone) return;
    
    // Đọc theme hiện tại của App Flutter
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeValue = isDark ? 'dark' : 'light';
    
    // Gắn attribute data-theme vào thẻ <html> của Web
    _controller.runJavaScript("document.documentElement.setAttribute('data-theme', '$themeValue');");
  }

  @override
  Widget build(BuildContext context) {
    // Để ở build() giúp Web tự động đổi màu ngay lập tức nếu user kéo thanh thông báo xuống đổi chế độ Tối -> Sáng
    _syncTheme();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Đánh giá Nghề nghiệp', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (_isInitDone) {
                setState(() => _isLoading = true);
                _controller.reload();
              }
            },
          )
        ],
      ),
      body: Stack(
        children: [
          if (_isInitDone) WebViewWidget(controller: _controller),
          
          if (_isLoading || !_isInitDone)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}