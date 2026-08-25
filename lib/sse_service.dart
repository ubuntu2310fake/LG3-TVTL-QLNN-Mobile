import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'localization_service.dart';

typedef OnSseNotificationCallback = void Function(
    String title, String body, String notiId, Map<String, dynamic> data);

class SseService {
  static final SseService _instance = SseService._internal();
  factory SseService() => _instance;
  SseService._internal();

  http.Client? _client;
  StreamSubscription? _subscription;
  bool _isConnected = false;
  bool _shouldReconnect = true;
  Timer? _reconnectTimer;
  OnSseNotificationCallback? onNotificationReceived;

  final Set<String> _processedEventIds = {};

  bool get isConnected => _isConnected;

  void start({OnSseNotificationCallback? onNotification}) {
    if (onNotification != null) {
      onNotificationReceived = onNotification;
    }
    _shouldReconnect = true;
    _connect();
  }

  void stop() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _client?.close();
    _client = null;
    _isConnected = false;
  }

  Future<void> _connect() async {
    if (_isConnected) return;
    _reconnectTimer?.cancel();

    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      if (sessionId.isEmpty) {
        // Chưa đăng nhập, thử lại sau 5 giây
        if (_shouldReconnect) {
          _reconnectTimer = Timer(const Duration(seconds: 5), _connect);
        }
        return;
      }

      _client = http.Client();
      final request = http.Request(
        'GET',
        Uri.parse('${AppConfig.baseUrl}/api/sse_stream.php'),
      );
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';
      request.headers['Cookie'] = 'PHPSESSID=$sessionId';

      final response = await _client!.send(request);

      if (response.statusCode == 200) {
        _isConnected = true;
        debugPrint('✅ [SSE] Connected to real-time notification stream');

        String eventType = 'message';
        String dataBuffer = '';

        _subscription = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          (line) {
            line = line.trim();
            if (line.isEmpty) {
              if (dataBuffer.isNotEmpty) {
                _handleSseEvent(eventType, dataBuffer);
                eventType = 'message';
                dataBuffer = '';
              }
              return;
            }

            if (line.startsWith('event:')) {
              eventType = line.substring(6).trim();
            } else if (line.startsWith('data:')) {
              dataBuffer += line.substring(5).trim();
            } else if (line.startsWith('id:')) {
              // event id
            }
          },
          onError: (error) {
            debugPrint('⚠️ [SSE] Error in stream: $error');
            _scheduleReconnect();
          },
          onDone: () {
            debugPrint('ℹ️ [SSE] Stream closed by server');
            _scheduleReconnect();
          },
          cancelOnError: true,
        );
      } else {
        debugPrint('⚠️ [SSE] Connection failed with status: ${response.statusCode}');
        _scheduleReconnect();
      }
    } catch (e) {
      debugPrint('❌ [SSE] Connection exception: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _isConnected = false;
    _subscription?.cancel();
    _subscription = null;
    _client?.close();
    _client = null;

    if (_shouldReconnect) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 3), _connect);
    }
  }

  Future<void> _handleSseEvent(String eventType, String rawData) async {
    try {
      final dynamic decoded = jsonDecode(rawData);
      if (decoded is! Map<String, dynamic>) return;
      final data = decoded;

      final prefs = await SharedPreferences.getInstance();
      final currentUsername = prefs.getString('username') ?? '';
      final currentRole = prefs.getString('role') ?? 'STUDENT';
      final currentHomeroomClassId = prefs.getInt('homeroom_class_id') ?? 0;
      final currentStudentClassId = prefs.getInt('class_id') ?? 0;
      final isVi = LocalizationService().currentLanguage == 'vi';

      // Deduplication check
      final eventUniqueId = '${eventType}_${data['violation_id'] ?? data['id'] ?? data['time'] ?? rawData.hashCode}';
      if (_processedEventIds.contains(eventUniqueId)) return;
      _processedEventIds.add(eventUniqueId);
      if (_processedEventIds.length > 200) {
        _processedEventIds.remove(_processedEventIds.first);
      }

      String title = '';
      String body = '';
      String url = '';
      String action = '';
      String notiType = 'GENERAL';
      bool isRelevant = false;

      // ==============================================================
      // EVENT: VIOLATION_NEW
      // ==============================================================
      if (eventType == 'violation_new') {
        final studentName = data['student_name'] ?? 'Học sinh';
        final studentCode = (data['student_code'] ?? '').toString().trim();
        final className = data['class_name'] ?? '';
        final classId = int.tryParse((data['class_id'] ?? '0').toString()) ?? 0;
        final totalPoints = data['total_points'] ?? data['recorded_points'] ?? 0;
        final errorsStr = data['errors_str'] ?? (data['display_name'] ?? '');
        final reporter = data['reporter_fullname'] ?? (data['reporter'] ?? 'Người chấm');

        notiType = 'VIOLATION';

        // 1. Nhóm 4: Chính học sinh đó vi phạm
        if (currentUsername.isNotEmpty && currentUsername.toLowerCase() == studentCode.toLowerCase()) {
          isRelevant = true;
          title = isVi ? '⚠️ Vi phạm nền nếp' : '⚠️ Rule Violation';
          body = isVi
              ? 'Bạn bị trừ ${totalPoints}đ. Lỗi: $errorsStr.'
              : 'You were deducted ${totalPoints} pts. Error: $errorsStr.';
          url = '/student_violations.php';
          action = 'open_student_violations';
        }
        // 2. Nhóm 2: GVCN của lớp đó
        else if (currentRole == 'TEACHER' && classId > 0 && currentHomeroomClassId == classId) {
          isRelevant = true;
          title = isVi ? '🔔 Báo cáo lớp $className' : '🔔 Class $className Report';
          body = isVi
              ? 'HS $studentName bị trừ ${totalPoints}đ.\nLỗi: $errorsStr\n✍️ $reporter'
              : 'Student $studentName deducted ${totalPoints} pts.\nError: $errorsStr\n✍️ $reporter';
          url = '/teacher_dashboard.php';
          action = 'open_my_class';
        }
        // 3. Nhóm 1: Học sinh cùng lớp (hoặc RED_FLAG đứng lớp)
        else if ((currentRole == 'STUDENT' || currentRole == 'RED_FLAG') &&
            classId > 0 &&
            currentStudentClassId == classId) {
          isRelevant = true;
          title = isVi ? '🔔 Báo cáo lớp $className' : '🔔 Class $className Report';
          body = isVi
              ? 'HS $studentName bị trừ ${totalPoints}đ.\nLỗi: $errorsStr\n✍️ $reporter'
              : 'Student $studentName deducted ${totalPoints} pts.\nError: $errorsStr\n✍️ $reporter';
          url = '/teacher_dashboard.php';
          action = 'open_my_class';
        }
        // 4. Nhóm 3: GV không chủ nhiệm & ADMIN
        else if (currentRole == 'ADMIN' || (currentRole == 'TEACHER' && currentHomeroomClassId != classId)) {
          isRelevant = true;
          title = isVi ? '🔔 Báo cáo vi phạm: $className' : '🔔 Violation: $className';
          body = isVi
              ? 'HS $studentName ($className) bị trừ ${totalPoints}đ.\nLỗi: $errorsStr\n✍️ $reporter'
              : 'Student $studentName ($className) deducted ${totalPoints} pts.\nError: $errorsStr\n✍️ $reporter';
          url = '/violation_history.php';
          action = 'open_violation_history';
        }
      }
      // ==============================================================
      // EVENT: PSYCHOLOGY_ALERT (Cảnh báo tâm lý)
      // ==============================================================
      else if (eventType == 'psychology_alert') {
        final studentName = data['student_name'] ?? 'Học sinh';
        final classId = int.tryParse((data['class_id'] ?? '0').toString()) ?? 0;
        final riskLevel = data['risk_level'] ?? 'WARNING';
        final message = data['message'] ?? '';

        // Chỉ gửi cho GVCN của lớp đó hoặc ADMIN
        if (currentRole == 'ADMIN' || (currentRole == 'TEACHER' && classId > 0 && currentHomeroomClassId == classId)) {
          isRelevant = true;
          notiType = 'PSYCHOLOGY';
          final riskEmoji = (riskLevel == 'DANGER') ? '🆘' : '⚠️';
          title = isVi
              ? '$riskEmoji CẢNH BÁO TÂM LÝ: $studentName'
              : '$riskEmoji PSYCHOLOGY ALERT: $studentName';
          body = isVi
              ? 'Phát hiện dấu hiệu \'$riskLevel\'.\nNội dung: "$message"'
              : 'Risk level \'$riskLevel\' detected.\nContent: "$message"';
          url = '/teacher_dashboard.php';
          action = 'open_my_class';
        }
      }

      if (isRelevant && title.isNotEmpty) {
        final notiId = DateTime.now().millisecondsSinceEpoch.toString();
        final notiData = {
          'url': url,
          'action': action,
          'type': notiType,
          'id': notiId,
          ...data.map((k, v) => MapEntry(k.toString(), v.toString())),
        };

        // Lưu vào SharedPreferences local_notifications để hiển thị trong Notification Panel
        await _saveToLocalNotifications(prefs, notiId, title, body, notiData);

        // Bắn overlay top toast ngay lập tức trên app
        onNotificationReceived?.call(title, body, notiId, notiData);
      }
    } catch (e) {
      debugPrint('⚠️ [SSE] Parse error: $e');
    }
  }

  Future<void> _saveToLocalNotifications(
      SharedPreferences prefs, String notiId, String title, String body, Map<String, dynamic> data) async {
    try {
      await prefs.reload();
      final notiStr = prefs.getString('local_notifications');
      List<Map<String, dynamic>> notifs = [];
      if (notiStr != null) {
        try {
          final raw = jsonDecode(notiStr) as List;
          notifs = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        } catch (_) {}
      }

      if (!notifs.any((n) => n['id'] == notiId)) {
        notifs.insert(0, {
          'id': notiId,
          'title': title,
          'body': body,
          'isRead': false,
          'time': DateTime.now().toIso8601String(),
          'data': data,
        });

        if (notifs.length > 50) notifs = notifs.sublist(0, 50);
        await prefs.setString('local_notifications', jsonEncode(notifs));
      }
    } catch (e) {
      debugPrint('⚠️ [SSE] Error saving local notification: $e');
    }
  }
}
