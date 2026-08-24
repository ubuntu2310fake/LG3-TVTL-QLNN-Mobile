import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'localization_service.dart';

class ChessLobbyScreen extends StatefulWidget {
  const ChessLobbyScreen({super.key});

  @override
  State<ChessLobbyScreen> createState() => _ChessLobbyScreenState();
}

class _ChessLobbyScreenState extends State<ChessLobbyScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoading = false);
            // Inject CSS to hide web header if needed, or adjust padding
            _controller.runJavaScript("""
              document.querySelector('header')?.style.setProperty('display', 'none', 'important');
              document.querySelector('nav')?.style.setProperty('display', 'none', 'important');
              document.querySelector('.sidebar')?.style.setProperty('display', 'none', 'important');
              document.querySelector('.chess-header')?.style.setProperty('margin-top', '20px'); document.getElementById('pwaPromoModal')?.style.setProperty('display', 'none', 'important');
            """);
          },
        ),
      );
    _initWebView();
  }

  Future<void> _initWebView() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getString('phpsessid') ?? '';
    final uri = Uri.parse(AppConfig.baseUrl);
    
    if (sessionId.isNotEmpty) {
      final cookieManager = WebViewCookieManager();
      await cookieManager.setCookie(
        WebViewCookie(
          name: 'PHPSESSID',
          value: sessionId,
          domain: uri.host,
          path: '/',
        ),
      );
    }
    
    // The web chess path might be /chess.php or something?
    // Let's assume it's /chess.php or /chess.php
    _controller.loadRequest(Uri.parse('${AppConfig.baseUrl}/chess.php?iframe=1&lang=${LocalizationService().currentLanguage}'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LocalizationService().currentLanguage == 'vi' ? 'Cờ Vua' : 'Chess'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _controller.reload();
            },
          )
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
