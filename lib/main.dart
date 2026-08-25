import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; 
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:app_links/app_links.dart';
import 'public_profile_screen.dart';
import 'offline_queue_service.dart';

import 'login_screen.dart';
import 'main_shell.dart';
import 'config.dart';
import 'localization_service.dart';
import 'device_helper.dart';

const String currentAppVersion = "2.0.3";
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

bool _isProcessingNoti = false;
List<RemoteMessage> _notiQueue = [];

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  _notiQueue.add(message);
  if (_isProcessingNoti) return; 
  _isProcessingNoti = true;

  try { await Firebase.initializeApp(); } catch (e) {}
  
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  
  AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/launcher_icon');
  const DarwinInitializationSettings initializationSettingsDarwin = DarwinInitializationSettings();
  InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsDarwin,
    macOS: initializationSettingsDarwin,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'lg3_main_channel', LocalizationService().currentLanguage == 'vi' ? 'Thông báo chung' : 'General announcements',
    channelDescription: LocalizationService().currentLanguage == 'vi' ? 'Kênh thông báo mặc định của LG3' : 'LG3 default notification channel',
    importance: Importance.max, priority: Priority.high,
  );
  const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
    presentAlert: true, presentBadge: true, presentSound: true,
  );
  NotificationDetails platformDetails = NotificationDetails(
    android: androidDetails,
    iOS: darwinDetails,
    macOS: darwinDetails,
  );

  final prefs = await SharedPreferences.getInstance();
  await prefs.reload(); 

  final String? notiStr = prefs.getString('local_notifications');
  List<Map<String, dynamic>> notifs = [];
  if (notiStr != null) {
    try { 
      List<dynamic> raw = jsonDecode(notiStr);
      notifs = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {}
  }

  while (_notiQueue.isNotEmpty) {
    final msg = _notiQueue.removeAt(0);

    String title = msg.notification?.title ?? msg.data['title'] ?? (LocalizationService().currentLanguage == 'vi' ? 'Thông báo hệ thống' : 'System notification');
    String body = msg.notification?.body ?? msg.data['body'] ?? msg.data['content'] ?? (LocalizationService().currentLanguage == 'vi' ? 'Bạn có thông báo mới.' : 'You have a new notification.');
    Map<String, String> safeData = {};
    msg.data.forEach((k, v) => safeData[k.toString()] = v.toString());
    
    String notiId = msg.messageId ?? Random().nextInt(99999999).toString();

    if (!notifs.any((n) => n['id'] == notiId)) {
      notifs.insert(0, {
        'id': notiId,
        'title': title, 'body': body, 'isRead': false, 
        'time': DateTime.now().toIso8601String(), 'data': safeData,
      });
    }

    int pushId = Random().nextInt(2147483647);
    await flutterLocalNotificationsPlugin.show(pushId, title, body, platformDetails);
  }
  
  if (notifs.length > 50) notifs = notifs.sublist(0, 50);
  
  await prefs.setString('local_notifications', jsonEncode(notifs)); 

  _isProcessingNoti = false;
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
  await LocalizationService().init();
    if (task == "syncOfflineQueue") { await OfflineQueueService.processQueue(); }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalizationService().init();
  if (!kIsWeb && Platform.isAndroid) {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        firebaseMessagingBackgroundHandler(message);
      });
    } catch (e) {
      debugPrint('Firebase init error (missing plist?): $e');
    }
  }

  if (!kIsWeb && Platform.isAndroid) {
    try { await FlutterDisplayMode.setHighRefreshRate(); } catch (e) { }
    Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    Workmanager().registerPeriodicTask(
      "1", "syncOfflineQueue", 
      frequency: const Duration(minutes: 15), constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  final prefs = await SharedPreferences.getInstance();
  final savedTheme = prefs.getString('theme_mode') ?? 'system';
  if (savedTheme == 'light') {
    themeNotifier.value = ThemeMode.light;
  } else if (savedTheme == 'dark') themeNotifier.value = ThemeMode.dark;
  else themeNotifier.value = ThemeMode.system;

  if (Platform.isIOS) {
    try {
      final iosInfo = await DeviceInfoPlugin().iosInfo;
      final version = double.tryParse(iosInfo.systemVersion.split('.').first) ?? 0;
      if (version >= 26) {
        AppConfig.isLiquidGlassEnabled = true;
      }
    } catch (e) {
      debugPrint('Failed to detect iOS version: $e');
    }
  }

  // Khởi tạo App Links
  final _appLinks = AppLinks();
  
  Future.delayed(Duration(seconds: 2), () async {
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        if (initialUri.host.endsWith('testifiyonline.xyz')) {
          final pathSegments = initialUri.pathSegments;
          if (pathSegments.isNotEmpty) {
            String possibleCode = pathSegments.first.toUpperCase();
            if (RegExp(r'^K\d{2}A\d{1,2}\d{2,3}$').hasMatch(possibleCode)) {
              if (navigatorKey.currentState != null) {
                navigatorKey.currentState!.push(
                  MaterialPageRoute(builder: (_) => PublicProfileScreen(studentCode: possibleCode)),
                );
              }
            }
          }
        }
      }
    } catch (e) {}
  });

  _appLinks.uriLinkStream.listen((uri) {
    debugPrint('Received DeepLink: $uri');
    if (uri.host.endsWith('testifiyonline.xyz')) {
      final pathSegments = uri.pathSegments;
      if (pathSegments.isNotEmpty) {
        String possibleCode = pathSegments.first.toUpperCase();
        if (RegExp(r'^K\d{2}A\d{1,2}\d{2,3}$').hasMatch(possibleCode)) {
          // It's a student code!
          if (navigatorKey.currentState != null) {
            navigatorKey.currentState!.push(
              MaterialPageRoute(builder: (_) => PublicProfileScreen(studentCode: possibleCode)),
            );
          }
        }
      }
    }
  });

  runApp(const LG3App());
}



final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class LG3App extends StatelessWidget {
  const LG3App({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return ValueListenableBuilder<String>(
          valueListenable: LocalizationService().languageNotifier,
          builder: (context, lang, child) {
            return MaterialApp(key: ValueKey(lang), navigatorKey: navigatorKey,
          title: LocalizationService().currentLanguage == 'vi' ? 'LG3 Quản Lý Nền Nếp' : 'LG3 Quan Ly Nen Nep',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeData(
             
            textTheme: GoogleFonts.beVietnamProTextTheme(ThemeData.light().textTheme),
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF005FBA), brightness: Brightness.light),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            
            textTheme: GoogleFonts.beVietnamProTextTheme(ThemeData.dark().textTheme),
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF005FBA), brightness: Brightness.dark),
            useMaterial3: true,
          ),
          home: const SplashScreen(),
            );
          },
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
  void initState() { super.initState(); _checkAutoLogin(); }

  Future<void> _checkAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberToken = prefs.getString('remember_token');
    final oldSess = prefs.getString('phpsessid') ?? '';
    final deviceName = await DeviceHelper.getDeviceModel();

    if (rememberToken != null && rememberToken.isNotEmpty) {
      try {
        final response = await http.post(
          Uri.parse('${AppConfig.baseUrl}/api/login_api.php'), 
          body: {
            'remember_token': rememberToken,
            'device_name': deviceName,
            'old_session_id': oldSess,
          }
        ).timeout(const Duration(seconds: 5));
        final data = jsonDecode(response.body);
        if (response.statusCode == 200 && data['status'] == 'success') {
          await prefs.setString('phpsessid', data['session_id']);
          if (!mounted) return; Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainShell())); return;
        }
      } catch (e) {
        debugPrint('Auto login failed/timeout: $e');
        if (oldSess.isNotEmpty) {
          if (!mounted) return; Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainShell())); return;
        }
      }
    }
    await Future.delayed(const Duration(milliseconds: 500)); 
    if (!mounted) return; Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF005FBA),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.asset('assets/images/lg3512512.png', width: 100, height: 100, errorBuilder: (context, error, stackTrace) => Icon(Icons.shield_rounded, size: 80, color: Colors.white))),
            SizedBox(height: 20),
            Padding(padding: EdgeInsets.symmetric(horizontal: 24.0), child: Text(LocalizationService().currentLanguage == 'vi' ? 'SIÊU ỨNG DỤNG LG3' : 'LG3 SUPER APP', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.5, height: 1.4))),
            SizedBox(height: 40),
            CircularProgressIndicator(color: Colors.white.withValues(alpha: 0.8)),
          ],
        ),
      ),
    );
  }
}