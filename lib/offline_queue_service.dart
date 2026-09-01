import 'config.dart';
import 'localization_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

class OfflineQueueService {
  static const String _queueKey = 'offline_sync_queue';

  // --- HÀM 1: BẮN THÔNG BÁO RUNG MÁY HỆ THỐNG TRỰC TIẾP ---
  static Future<void> _showSystemNotification(int notiId, String title, String body) async {
    FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    
    // Khởi tạo icon thông báo (Sử dụng icon mặc định của App)
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    
    // ĐÃ FIX TẠI ĐÂY: Đổi 'initializationSettings:' thành 'settings:'
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
    );

    AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'offline_sync_channel_1', 
      LocalizationService().currentLanguage == 'vi' ? 'Đồng bộ Offline' : 'Offline Sync',
      channelDescription: LocalizationService().currentLanguage == 'vi' ? 'Thông báo khi ứng dụng đồng bộ dữ liệu lúc có mạng' : 'Notify when app syncs data online',
      importance: Importance.max, 
      priority: Priority.high,
      ticker: 'ticker',
      icon: '@mipmap/ic_launcher',
    );
    NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);
    
    // FIX 2: Bắt buộc dùng tham số có tên cho hàm show() ở bản mới
    await flutterLocalNotificationsPlugin.show(
      notiId,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  // --- HÀM 2: BƠM THÔNG BÁO VÀO HỘP THƯ CHUÔNG IN-APP ---
  static Future<void> _addLocalNotification(String title, String body) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final String? notiStr = prefs.getString('local_notifications');
    List<Map<String, dynamic>> notifs = [];
    
    if (notiStr != null) {
      try { notifs = List<Map<String, dynamic>>.from(jsonDecode(notiStr)); } catch (e) {}
    }

    notifs.insert(0, {
      'id': 'offline_${DateTime.now().millisecondsSinceEpoch}',
      'title': title,
      'body': body,
      'isRead': false,
      'time': DateTime.now().toIso8601String(),
      'data': {},
    });

    await prefs.setString('local_notifications', jsonEncode(notifs));
  }

  // --- HÀM 3: GHI NHẬN LỖI VÀO KHO KHI MẤT MẠNG ---
  static Future<void> enqueue({
    required String url,
    required String method,
    required String contentType,
    required dynamic body,
    required String title,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    List<String> queue = prefs.getStringList(_queueKey) ?? [];

    final String uniqueId = DateTime.now().millisecondsSinceEpoch.toString();

    final item = {
      'id': uniqueId,
      'url': url,
      'method': method,
      'contentType': contentType,
      'body': body is String ? body : jsonEncode(body),
      'title': title,
      'timestamp': DateTime.now().toIso8601String(),
    };

    queue.add(jsonEncode(item));
    await prefs.setStringList(_queueKey, queue);

    // 1. Lưu vào chuông in-app để biết là đang chờ
    await _addLocalNotification(LocalizationService().currentLanguage == 'vi' ? '⏳ Đã lưu ngầm (Offline)' : '⏳ Saved locally (Offline)', LocalizationService().currentLanguage == 'vi' ? 'Chờ có mạng: $title' : 'Waiting for network: $title');

    // 2. Kích hoạt lính đánh thuê 1 lần (Ép nổ ở giây thứ 1 khi có Wifi trên Android)
    if (!kIsWeb && Platform.isAndroid) {
      Workmanager().registerOneOffTask(
        "instant_sync_$uniqueId", 
        "syncOfflineQueue", // Gọi đúng tên task đã khai báo ở main.dart
        constraints: Constraints(networkType: NetworkType.connected),
      );
    }
  }

  // --- HÀM 4: XỬ LÝ ĐẨY DỮ LIỆU LÊN SERVER KHI CÓ MẠNG (CHẠY NGẦM) ---
  static Future<bool> processQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    List<String> queue = prefs.getStringList(_queueKey) ?? [];
    if (queue.isEmpty) return true;

    final sessionId = prefs.getString('phpsessid') ?? '';
    
    // Đọc cài đặt bật/tắt thông báo của người dùng (giống main_shell.dart)
    final bool isNotiEnabled = prefs.getBool('push_enabled') ?? false;

    List<String> remainingQueue = [];
    bool allSuccess = true;

    for (String itemStr in queue) {
      try {
        final item = jsonDecode(itemStr);
        
        // FIX 3: Ép kiểu dữ liệu Headers chuẩn <String, String>
        final Map<String, String> headers = {
          'Cookie': 'PHPSESSID=$sessionId',
          'Content-Type': item['contentType'].toString(),
        };

        http.Response response;
        if (item['method'] == 'POST') {
          response = await AppConfig.client.post(
            Uri.parse(item['url']),
            headers: headers,
            body: item['body'],
          ).timeout(const Duration(seconds: 15));
        } else {
          response = await AppConfig.client.get(
            Uri.parse(item['url']), 
            headers: headers
          ).timeout(const Duration(seconds: 15));
        }

        try {
          final data = jsonDecode(response.body);
          if (response.statusCode == 200 && data['status'] == 'success') {
            
            // THÀNH CÔNG -> 1. Luôn lưu vào hộp thư In-App để tăng số chuông đỏ
            await _addLocalNotification(LocalizationService().currentLanguage == 'vi' ? '✅ Đồng bộ thành công' : '✅ Sync successful', item['title']);
            
            // THÀNH CÔNG -> 2. Chỉ Rung máy (System Noti) khi User cho phép
            if (isNotiEnabled) {
               // Dùng hashcode của ID để tạo mã thông báo duy nhất, không bị đè nhau
               await _showSystemNotification(item['id'].hashCode, LocalizationService().currentLanguage == 'vi' ? 'Đồng bộ dữ liệu thành công' : 'Data sync successful', item['title']);
            }
            
          } else {
            // Lỗi từ server (Hết session, sai format...) -> Giữ lại kho
            remainingQueue.add(itemStr);
            allSuccess = false;
          }
        } catch (_) {
          // Lỗi parse JSON (Server trả HTML lỗi) -> Giữ lại kho
          remainingQueue.add(itemStr);
          allSuccess = false;
        }
      } catch (e) {
        // Lỗi timeout, rớt mạng giữa chừng -> Giữ lại kho
        remainingQueue.add(itemStr);
        allSuccess = false;
      }
    }

    // Ghi đè lại kho bằng những gói tin bị lỗi chưa gửi được
    await prefs.setStringList(_queueKey, remainingQueue);
    return allSuccess;
  }
}