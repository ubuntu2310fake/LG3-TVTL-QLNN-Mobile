import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

import 'video_render_service.dart';
import 'config.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  late final WebViewController _controller;
  late final VideoRenderService _videoRenderService;
  
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
    
    bool isArm64Supported = false;
    if (Platform.isAndroid) {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      if (androidInfo.supportedAbis.contains('arm64-v8a')) {
        isArm64Supported = true;
      }
    } else if (Platform.isIOS) {
      isArm64Supported = true; 
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            _syncTheme();
            
            // 1. Khai báo hỗ trợ phần cứng
            _controller.runJavaScript("window.tvtl_hardware_supported = $isArm64Supported;");
            
            // 2. FIX LỖI POPUP VÀ GIỮ BADGE ANDROID
            _controller.runJavaScript("""
              // --- A. TẮT VÒNG LẶP PING ĐỂ KHÔNG BỊ ĐÈ BADGE ---
              if (window.pcToolPingInterval) {
                  clearInterval(window.pcToolPingInterval);
              }
              window.tvtl_isAppMode = true;

              // --- B. GÀI BIẾN TÊN PHIÊN BẢN ---
              let badge = document.getElementById('tool_pc_badge');
              if(badge) {
                  badge.innerHTML = '<span class="status-dot online"></span> LG3-TVTL-QLNN Android v2.0.0';
                  badge.style.borderColor = '#10b981';
                  badge.style.color = '#10b981';
                  badge.style.background = 'rgba(16, 185, 129, 0.1)';
              }

              // --- C. FIX LỖI NHẢY POPUP TRÊN WEBVIEW ---
              var style = document.createElement('style'); 
              style.innerHTML = `
                /* Fix Modal Tin tức */
                .win-modal-overlay { 
                    position: fixed !important; 
                    top: 0 !important; 
                    left: 0 !important; 
                    height: 100vh !important; 
                    height: 100dvh !important; /* Dùng chiều cao động chuẩn của điện thoại */
                    align-items: center !important; 
                    justify-content: center !important; 
                }
                .win-modal-content { 
                    max-height: 85dvh !important; 
                    margin: auto !important; 
                }
                /* Fix luôn hộp thoại SweetAlert2 lỡ có bị */
                .swal2-container { 
                    position: fixed !important; 
                    top: 0 !important; 
                    left: 0 !important; 
                    height: 100dvh !important; 
                }
              `; 
              document.head.appendChild(style);
            """);

            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..addJavaScriptChannel(
        'LG3Bridge',
        onMessageReceived: (JavaScriptMessage message) {
          try {
            final data = jsonDecode(message.message);
            if (data['action'] == 'START_HLS_RENDER') {
              _showQualitySelectionDialog(context);
            }
          } catch (e) {
            debugPrint("Lỗi Parse JS Bridge: $e");
          }
        },
      );

    _videoRenderService = VideoRenderService(_controller);

    if (sessionId.isNotEmpty) {
      final cookieManager = WebViewCookieManager();
      await cookieManager.setCookie(
        WebViewCookie(
          name: 'PHPSESSID',
          value: sessionId,
          domain: '${AppConfig.domain}',
          path: '/',
        ),
      );
    }

    _controller.loadRequest(Uri.parse('${AppConfig.baseUrl}/news.php?iframe=1'));

    if (mounted) {
      setState(() {
        _isInitDone = true;
      });
    }
  }

  void _showQualitySelectionDialog(BuildContext context) {
    // 1. KIỂM TRA CHẾ ĐỘ SÁNG / TỐI
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      backgroundColor: Theme.of(context).cardColor, // Tự động nền theo theme
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Định dạng Video đăng tải",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              
              ListTile(
                leading: const Icon(Icons.flash_on, color: Colors.orange),
                title: const Text("Tốc độ siêu tốc (Khuyên dùng)"),
                subtitle: const Text("Cắt HLS không nén, giữ nguyên bản gốc, cực kỳ nhanh."),
                // Dùng Opacity cho màu nền để không đè chết màu chữ trong Dark Mode
                tileColor: isDark ? Colors.orange.withOpacity(0.15) : Colors.orange.shade50,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                onTap: () {
                  Navigator.pop(context); 
                  _videoRenderService.startHlsProcess(0); 
                },
              ),
              const SizedBox(height: 10),

              ListTile(
                leading: const Icon(Icons.compress, color: Colors.blue),
                title: const Text("Tiêu chuẩn (HD 720p)"),
                subtitle: const Text("Nén GPU tiết kiệm dung lượng 4G, tốc độ ổn định."),
                tileColor: isDark ? Colors.blue.withOpacity(0.15) : Colors.blue.shade50,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                onTap: () {
                  Navigator.pop(context); 
                  _videoRenderService.startHlsProcess(1); 
                },
              ),
              const SizedBox(height: 10),

              ListTile(
                leading: const Icon(Icons.hd, color: Colors.green),
                title: const Text("Chất lượng cao (FHD 1080p)"),
                subtitle: const Text("Nén GPU giữ độ nét cao nhất, thời gian xử lý lâu hơn."),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10), 
                  side: BorderSide(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300)
                ),
                onTap: () {
                  Navigator.pop(context); 
                  _videoRenderService.startHlsProcess(2); 
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _syncTheme() {
    if (!mounted || !_isInitDone) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeValue = isDark ? 'dark' : 'light';
    _controller.runJavaScript("document.documentElement.setAttribute('data-theme', '$themeValue');");
  }

  @override
  Widget build(BuildContext context) {
    _syncTheme();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tin tức & Thông báo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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