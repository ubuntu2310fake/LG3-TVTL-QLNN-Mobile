import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class ManageViolationsScreen extends StatefulWidget {
  const ManageViolationsScreen({super.key});

  @override
  State<ManageViolationsScreen> createState() => _ManageViolationsScreenState();
}

class _ManageViolationsScreenState extends State<ManageViolationsScreen> {
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
    
    // Khởi tạo quản lý Cookie để ép Session từ App vào WebView
    final cookieManager = WebViewCookieManager();
    if (sessionId.isNotEmpty) {
      await cookieManager.setCookie(
        WebViewCookie(
          name: 'PHPSESSID',
          value: sessionId,
          domain: '${AppConfig.domain}',
          path: '/',
        ),
      );
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent) // Giúp WebView ăn theo màu nền của Flutter
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() => _isLoading = false);
              _syncTheme(); // Đồng bộ ngay khi tải xong trang
            }
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('''
              Page resource error:
              code: ${error.errorCode}
              description: ${error.description}
              errorType: ${error.errorType}
              isForMainFrame: ${error.isForMainFrame}
            ''');
          },
        ),
      )
      ..loadRequest(Uri.parse('${AppConfig.baseUrl}/manage_violations.php?iframe=1'));

    if (mounted) {
      setState(() {
        _isInitDone = true;
      });
    }
  }

  // Hàm ép giao diện web chạy theo Dark/Light mode của điện thoại
  void _syncTheme() {
    if (!mounted || !_isInitDone) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeValue = isDark ? 'dark' : 'light';
    _controller.runJavaScript("document.documentElement.setAttribute('data-theme', '$themeValue');");
  }

  @override
  Widget build(BuildContext context) {
    // Gọi liên tục ở build để bắt sự kiện người dùng đổi Theme ngay lập tức
    _syncTheme();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('QUẢN LÝ VI PHẠM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Tải lại trang',
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
          
          if (_isLoading)
            Container(
              color: Theme.of(context).scaffoldBackgroundColor, // Che cái nền trắng lúc web đang load
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Đang nạp dữ liệu...', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}