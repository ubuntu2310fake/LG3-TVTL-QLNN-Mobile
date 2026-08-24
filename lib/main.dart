import 'dart:convert';
import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; 
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';
import 'offline_queue_service.dart';

import 'login_screen.dart';
import 'main_shell.dart';
import 'config.dart';

const String currentAppVersion = "2.0.0";
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
  
  // FIX: Sửa 'ic_launcher' thành 'launcher_icon' để gọi đúng logo của trường LG3
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/launcher_icon');
  const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'lg3_main_channel', 'Thông báo chung',
    importance: Importance.max, 
    priority: Priority.high, 
    icon: '@mipmap/launcher_icon', // FIX Ở ĐÂY
  );
  const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidDetails);

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

    String title = msg.notification?.title ?? msg.data['title'] ?? 'Thông báo hệ thống';
    String body = msg.notification?.body ?? msg.data['body'] ?? msg.data['content'] ?? 'Bạn có thông báo mới.';
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
    await flutterLocalNotificationsPlugin.show(pushId, title, body, platformChannelSpecifics);
  }
  
  if (notifs.length > 50) notifs = notifs.sublist(0, 50);
  
  await prefs.setString('local_notifications', jsonEncode(notifs)); 

  _isProcessingNoti = false;
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (task == "syncOfflineQueue") { await OfflineQueueService.processQueue(); }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    firebaseMessagingBackgroundHandler(message);
  });

  try { await FlutterDisplayMode.setHighRefreshRate(); } catch (e) { }
  
  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  Workmanager().registerPeriodicTask(
    "1", "syncOfflineQueue", 
    frequency: const Duration(minutes: 15), constraints: Constraints(networkType: NetworkType.connected),
  );

  final prefs = await SharedPreferences.getInstance();
  final savedTheme = prefs.getString('theme_mode') ?? 'system';
  if (savedTheme == 'light') themeNotifier.value = ThemeMode.light;
  else if (savedTheme == 'dark') themeNotifier.value = ThemeMode.dark;
  else themeNotifier.value = ThemeMode.system;

  runApp(const LG3App());
}

TextTheme buildInterTextTheme(TextTheme base) {
  return base.copyWith(
    displayLarge: _applyInter(base.displayLarge), displayMedium: _applyInter(base.displayMedium), displaySmall: _applyInter(base.displaySmall),
    headlineLarge: _applyInter(base.headlineLarge), headlineMedium: _applyInter(base.headlineMedium), headlineSmall: _applyInter(base.headlineSmall),
    titleLarge: _applyInter(base.titleLarge), titleMedium: _applyInter(base.titleMedium), titleSmall: _applyInter(base.titleSmall),
    bodyLarge: _applyInter(base.bodyLarge), bodyMedium: _applyInter(base.bodyMedium), bodySmall: _applyInter(base.bodySmall),
    labelLarge: _applyInter(base.labelLarge), labelMedium: _applyInter(base.labelMedium), labelSmall: _applyInter(base.labelSmall),
  );
}

TextStyle _applyInter(TextStyle? style) {
  return (style ?? const TextStyle()).copyWith(
    fontFamily: 'Inter', letterSpacing: -0.15,
    fontFeatures: [ const FontFeature.enable('cv05'), const FontFeature.enable('cv08'), const FontFeature.enable('ss01') ],
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
            fontFamily: 'Inter', 
            textTheme: buildInterTextTheme(ThemeData.light().textTheme),
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF005FBA), brightness: Brightness.light),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            fontFamily: 'Inter',
            textTheme: buildInterTextTheme(ThemeData.dark().textTheme),
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
  void initState() { super.initState(); _checkAutoLogin(); }

  Future<void> _checkAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberToken = prefs.getString('remember_token');

    if (rememberToken != null && rememberToken.isNotEmpty) {
      try {
        final response = await http.post(Uri.parse('${AppConfig.baseUrl}/api/login_api'), body: {'remember_token': rememberToken});
        final data = jsonDecode(response.body);
        if (response.statusCode == 200 && data['status'] == 'success') {
          await prefs.setString('phpsessid', data['session_id']);
          if (!mounted) return; Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainShell())); return;
        }
      } catch (e) {
        final oldSess = prefs.getString('phpsessid');
        if (oldSess != null && oldSess.isNotEmpty) {
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
            ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.asset('assets/images/lg3512512.png', width: 100, height: 100, errorBuilder: (context, error, stackTrace) => const Icon(Icons.shield_rounded, size: 80, color: Colors.white))),
            const SizedBox(height: 20),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 24.0), child: Text('LG3 - TƯ VẤN TÂM LÝ\nVÀ QUẢN LÝ THI ĐUA', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.5, height: 1.4))),
            const SizedBox(height: 40),
            CircularProgressIndicator(color: Colors.white.withOpacity(0.8)),
          ],
        ),
      ),
    );
  }
}