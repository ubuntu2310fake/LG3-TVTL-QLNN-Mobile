import 'localization_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
// ĐÃ THÊM: Thư viện để upload file multipart
import 'package:http_parser/http_parser.dart'; 
import 'package:mime/mime.dart';
import 'config.dart';

class TvtlService {
  static const String phpBaseUrl = AppConfig.baseUrl;
  static const String pythonBaseUrl = AppConfig.tvtlbaseUrl;

  // --- 1. SSO ĐĂNG NHẬP LIÊN THÔNG ---
    static Future<bool> ensurePythonLogin() async {
    // No longer needed, using PHP session directly
    return true;
  }

  // --- 2. GIAO TIẾP NGƯỜI VỚI NGƯỜI (MESSENGER) ---
  
  static Future<List<dynamic>> getTeachers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phpSession = prefs.getString('phpsessid') ?? '';
      final cookieHeader = 'PHPSESSID=$phpSession';
      
      final res = await http.get(Uri.parse('$phpBaseUrl/consulting_chat.php?endpoint=/api/list_teachers'), headers: {'Cookie': cookieHeader});
      
      if (res.statusCode == 200) {
        List<dynamic> data = jsonDecode(res.body);
        return data.map((item) => {
          'id': item['id'].toString(), // Ép kiểu String cho đồng bộ
          'full_name': item['full_name'],
          'avatar': item['avatar'],
          'role': 'teacher',
        }).toList();
      }
    } catch (e) { print(LocalizationService().currentLanguage == 'vi' ? "Lỗi getTeachers: $e" : "Error getTeachers: $e"); }
    return [];
  }

  static Future<List<dynamic>> getConversations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phpSession = prefs.getString('phpsessid') ?? '';
      final cookieHeader = 'PHPSESSID=$phpSession';
      
      final res = await http.get(Uri.parse('$phpBaseUrl/consulting_chat.php?endpoint=/api/teacher/get_conversations'), headers: {'Cookie': cookieHeader});
      
      if (res.statusCode == 200) {
        List<dynamic> data = jsonDecode(res.body);
        return data.map((item) => {
          'id': item['partner_id'].toString(), // Ép kiểu String cho đồng bộ
          'full_name': item['partner_name'],
          'avatar': item['avatar'],
          'role': item['partner_role'] ?? 'student',
        }).toList();
      }
    } catch (e) { print(LocalizationService().currentLanguage == 'vi' ? "Lỗi getConversations: $e" : "Error getConversations: $e"); }
    return [];
  }

  static Future<List<dynamic>> getChatHistory({required String partnerId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phpSession = prefs.getString('phpsessid') ?? '';
      final cookieHeader = 'PHPSESSID=$phpSession';
      
      // Đã chuyển sang dùng chung API /api/chat/get như bản Web (hỗ trợ Reply, Reaction)
      final res = await http.post(
        Uri.parse('$phpBaseUrl/consulting_chat.php?endpoint=/api/chat/get'),
        headers: {'Content-Type': 'application/json', 'Cookie': cookieHeader},
        body: jsonEncode({'partner_id': partnerId}),
      );
      
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (e) { print(LocalizationService().currentLanguage == 'vi' ? "Lỗi tải tin nhắn: $e" : "Error loading messages: $e"); }
    return [];
  }

  static Future<Map<String, dynamic>?> sendMessage(String content, {required String partnerId, int? replyId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phpSession = prefs.getString('phpsessid') ?? '';
      final cookieHeader = 'PHPSESSID=$phpSession';
      final res = await http.post(
        Uri.parse('$phpBaseUrl/consulting_chat.php?endpoint=/api/chat/send'),
        headers: {'Content-Type': 'application/json', 'Cookie': cookieHeader},
        body: jsonEncode({
          'receiver_id': partnerId, 
          'content': content,
          // FIX: Ép kiểu reply_id sang int đúng chuẩn Database Python
          if (replyId != null) 'reply_id': replyId.toInt() 
        }),
      );
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { print(LocalizationService().currentLanguage == 'vi' ? "Lỗi gửi tin nhắn: $e" : "Error sending message: $e"); }
    return null;
  }

  // ĐÃ THÊM: 4. UPLOAD ẢNH CHAT
  static Future<String?> uploadChatFile(String filePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phpSession = prefs.getString('phpsessid') ?? '';
      final cookieHeader = 'PHPSESSID=$phpSession';
      
      final url = Uri.parse('$phpBaseUrl/consulting_chat.php?endpoint=/api/chat/upload');
      final request = http.MultipartRequest('POST', url)
        ..headers.addAll({'Cookie': cookieHeader})
        ..files.add(await http.MultipartFile.fromPath(
          'file', // Bắt buộc trùng tên 'file' bên app.py
          filePath,
          contentType: MediaType.parse(lookupMimeType(filePath) ?? 'image/jpeg'),
        ));

      final response = await request.send();
      if (response.statusCode == 200) {
        final resStr = await response.stream.bytesToString();
        final data = jsonDecode(resStr);
        if (data['success'] == true) {
          // Trả về URL dạng [IMG]:/static/uploads/...
          return data['url']; 
        }
      }
    } catch (e) { print(LocalizationService().currentLanguage == 'vi' ? "Lỗi upload ảnh: $e" : "Error uploading image: $e"); }
    return null;
  }

  // ĐÃ THÊM: 5. XÓA TIN NHẮN CHAT
  static Future<bool> deleteMessage(int messageId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phpSession = prefs.getString('phpsessid') ?? '';
      final cookieHeader = 'PHPSESSID=$phpSession';
      final res = await http.post(
        Uri.parse('$phpBaseUrl/consulting_chat.php?endpoint=/api/chat/delete'),
        headers: {'Content-Type': 'application/json', 'Cookie': cookieHeader},
        body: jsonEncode({'message_id': messageId}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['success'] == true;
      }
    } catch (e) { print(LocalizationService().currentLanguage == 'vi' ? "Lỗi xóa tin nhắn: $e" : "Error deleting message: $e"); }
    return false;
  }

  // --- 3. GIAO TIẾP VỚI AI (GÓC TƯ VẤN) ---
  static Future<String?> askAIBot(String prompt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phpSession = prefs.getString('phpsessid') ?? '';
      final cookieHeader = 'PHPSESSID=$phpSession';
      final res = await http.post(
        Uri.parse('$phpBaseUrl/consulting_ai.php?local_api=1'),
        headers: {'Content-Type': 'application/json', 'Cookie': cookieHeader},
        body: jsonEncode({
          'user_text': prompt,
          'lang': LocalizationService().currentLanguage,
        }),
      );
      
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['advice'];
      }
    } catch (e) { print(LocalizationService().currentLanguage == 'vi' ? "Lỗi mạng askAIBot: $e" : "Network error askAIBot: $e"); }
    return null;
  }
  // =================================================================
  // 4. API BẠN BÈ & KẾT BẠN
  // =================================================================

  // Lấy danh sách bạn bè, lời mời đã nhận, lời mời đã gửi
  static Future<Map<String, dynamic>?> getFriendsData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phpSession = prefs.getString('phpsessid') ?? '';
      final cookieHeader = 'PHPSESSID=$phpSession';
      final res = await http.get(
        Uri.parse('$phpBaseUrl/consulting_chat.php?endpoint=/api/friends/list'),
        headers: {'Cookie': cookieHeader},
      );
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { print(LocalizationService().currentLanguage == 'vi' ? "Lỗi getFriendsData: $e" : "Error getFriendsData: $e"); }
    return null;
  }

  // Tìm kiếm học sinh để kết bạn
  static Future<List<dynamic>?> searchFriends(String query) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phpSession = prefs.getString('phpsessid') ?? '';
      final cookieHeader = 'PHPSESSID=$phpSession';
      final res = await http.post(
        Uri.parse('$phpBaseUrl/consulting_chat.php?endpoint=/api/friends/search'),
        headers: {'Content-Type': 'application/json', 'Cookie': cookieHeader},
        body: jsonEncode({'query': query}),
      );
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { print(LocalizationService().currentLanguage == 'vi' ? "Lỗi searchFriends: $e" : "Error searchFriends: $e"); }
    return null;
  }

  // Gửi lời mời kết bạn
  static Future<bool> requestFriend(int targetId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phpSession = prefs.getString('phpsessid') ?? '';
      final cookieHeader = 'PHPSESSID=$phpSession';
      final res = await http.post(
        Uri.parse('$phpBaseUrl/consulting_chat.php?endpoint=/api/friends/request'),
        headers: {'Content-Type': 'application/json', 'Cookie': cookieHeader},
        body: jsonEncode({'target_id': targetId}),
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['success'] == true;
      }
    } catch (e) { print(LocalizationService().currentLanguage == 'vi' ? "Lỗi requestFriend: $e" : "Error requestFriend: $e"); }
    return false;
  }

  // Phản hồi lời mời (Đồng ý / Từ chối)
  static Future<bool> respondFriend(int reqId, String action) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phpSession = prefs.getString('phpsessid') ?? '';
      final cookieHeader = 'PHPSESSID=$phpSession';
      final res = await http.post(
        Uri.parse('$phpBaseUrl/consulting_chat.php?endpoint=/api/friends/respond'),
        headers: {'Content-Type': 'application/json', 'Cookie': cookieHeader},
        body: jsonEncode({'req_id': reqId, 'action': action}),
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['success'] == true;
      }
    } catch (e) { print(LocalizationService().currentLanguage == 'vi' ? "Lỗi respondFriend: $e" : "Error respondFriend: $e"); }
    return false;
  }
}