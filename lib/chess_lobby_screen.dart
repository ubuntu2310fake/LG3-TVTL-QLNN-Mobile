import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'localization_service.dart';

class ChessLobbyScreen extends StatefulWidget {
  final String? matchId;

  const ChessLobbyScreen({super.key, this.matchId});

  @override
  State<ChessLobbyScreen> createState() => _ChessLobbyScreenState();
}

class _ChessLobbyScreenState extends State<ChessLobbyScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _initialized = false;

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
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final themeStr = isDark ? 'dark' : 'light';
            // Inject CSS to hide web header if needed, adjust padding and force theme
            _controller.runJavaScript("""
              if ('$themeStr' === 'dark') {
                document.documentElement.setAttribute('data-theme', 'dark');
                localStorage.setItem('theme_mode', 'dark');
              } else {
                document.documentElement.removeAttribute('data-theme');
                localStorage.setItem('theme_mode', 'light');
              }
              document.querySelector('header')?.style.setProperty('display', 'none', 'important');
              document.querySelector('nav')?.style.setProperty('display', 'none', 'important');
              document.querySelector('.sidebar')?.style.setProperty('display', 'none', 'important');
              document.querySelector('.chess-header')?.style.setProperty('margin-top', '20px');
              document.getElementById('pwaPromoModal')?.style.setProperty('display', 'none', 'important');
            """);
          },
        ),
      );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _initWebView();
    }
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
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeStr = isDark ? 'dark' : 'light';
    String url = '${AppConfig.baseUrl}/chess.php?iframe=1&lang=${LocalizationService().currentLanguage}&theme=$themeStr';
    if (widget.matchId != null && widget.matchId!.isNotEmpty) {
      url += '&match_id=${widget.matchId}';
    }
    _controller.loadRequest(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LocalizationService().currentLanguage == 'vi' ? 'Cờ Vua' : 'Chess'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
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
