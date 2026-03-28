import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
// ĐÃ THÊM: Thư viện để upload file multipart
import 'package:http_parser/http_parser.dart'; 
import 'package:mime/mime.dart';

class TvtlService {
  static const String phpBaseUrl = 'https://qlnn.testifiyonline.xyz';
  static const String pythonBaseUrl = 'https://tvtl.testifiyonline.xyz';

  // --- 1. SSO ĐĂNG NHẬP LIÊN THÔNG ---
  static Future<bool> ensurePythonLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phpSession = prefs.getString('phpsessid') ?? '';
      
      final tokenRes = await http.get(
        Uri.parse('$phpBaseUrl/api/get_tvtl_token.php'),
        headers: {'Cookie': 'PHPSESSID=$phpSession'},
      );
      
      if (tokenRes.statusCode != 200) return false;

      final tokenData = jsonDecode(tokenRes.body);
      if (tokenData['status'] == 'success') {
        String ssoToken = tokenData['token'];

        final pythonRes = await http.post(
          Uri.parse('$pythonBaseUrl/api/mobile/sso_login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'token': ssoToken}),
        );

        if (pythonRes.statusCode == 200) {
          String? rawCookie = pythonRes.headers['set-cookie'];
          if (rawCookie != null) {
            int index = rawCookie.indexOf(';');
            String pythonSession = (index == -1) ? rawCookie : rawCookie.substring(0, index);
            await prefs.setString('python_session', pythonSession);
            return true;
          }
        }
      }
    } catch (e) {
      print("Lỗi SSO: $e");
    }
    return false;
  }

  // --- 2. GIAO TIẾP NGƯỜI VỚI NGƯỜI (MESSENGER) ---
  
  static Future<List<dynamic>> getTeachers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pySession = prefs.getString('python_session') ?? '';
      
      final res = await http.get(Uri.parse('$pythonBaseUrl/api/list_teachers'), headers: {'Cookie': pySession});
      
      if (res.statusCode == 200) {
        List<dynamic> data = jsonDecode(res.body);
        return data.map((item) => {
          'id': item['id'].toString(), // Ép kiểu String cho đồng bộ
          'full_name': item['full_name'],
          'avatar': item['avatar'],
          'role': 'teacher',
        }).toList();
      }
    } catch (e) { print("Lỗi getTeachers: $e"); }
    return [];
  }

  static Future<List<dynamic>> getConversations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pySession = prefs.getString('python_session') ?? '';
      
      final res = await http.get(Uri.parse('$pythonBaseUrl/api/teacher/get_conversations'), headers: {'Cookie': pySession});
      
      if (res.statusCode == 200) {
        List<dynamic> data = jsonDecode(res.body);
        return data.map((item) => {
          'id': item['partner_id'].toString(), // Ép kiểu String cho đồng bộ
          'full_name': item['partner_name'],
          'avatar': item['avatar'],
          'role': item['partner_role'] ?? 'student',
        }).toList();
      }
    } catch (e) { print("Lỗi getConversations: $e"); }
    return [];
  }

  static Future<List<dynamic>> getChatHistory({required String partnerId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pySession = prefs.getString('python_session') ?? '';
      
      // Đã chuyển sang dùng chung API /api/chat/get như bản Web (hỗ trợ Reply, Reaction)
      final res = await http.post(
        Uri.parse('$pythonBaseUrl/api/chat/get'),
        headers: {'Content-Type': 'application/json', 'Cookie': pySession},
        body: jsonEncode({'partner_id': partnerId}),
      );
      
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (e) { print("Lỗi tải tin nhắn: $e"); }
    return [];
  }

  static Future<Map<String, dynamic>?> sendMessage(String content, {required String partnerId, int? replyId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pySession = prefs.getString('python_session') ?? '';
      final res = await http.post(
        Uri.parse('$pythonBaseUrl/api/chat/send'),
        headers: {'Content-Type': 'application/json', 'Cookie': pySession},
        body: jsonEncode({
          'receiver_id': partnerId, 
          'content': content,
          // FIX: Ép kiểu reply_id sang int đúng chuẩn Database Python
          if (replyId != null) 'reply_id': replyId.toInt() 
        }),
      );
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { print("Lỗi gửi tin nhắn: $e"); }
    return null;
  }

  // ĐÃ THÊM: 4. UPLOAD ẢNH CHAT
  static Future<String?> uploadChatFile(String filePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pySession = prefs.getString('python_session') ?? '';
      
      final url = Uri.parse('$pythonBaseUrl/api/chat/upload');
      final request = http.MultipartRequest('POST', url)
        ..headers.addAll({'Cookie': pySession})
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
    } catch (e) { print("Lỗi upload ảnh: $e"); }
    return null;
  }

  // ĐÃ THÊM: 5. XÓA TIN NHẮN CHAT
  static Future<bool> deleteMessage(int messageId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pySession = prefs.getString('python_session') ?? '';
      final res = await http.post(
        Uri.parse('$pythonBaseUrl/api/chat/delete'),
        headers: {'Content-Type': 'application/json', 'Cookie': pySession},
        body: jsonEncode({'message_id': messageId}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['success'] == true;
      }
    } catch (e) { print("Lỗi xóa tin nhắn: $e"); }
    return false;
  }

  // --- 3. GIAO TIẾP VỚI AI (GÓC TƯ VẤN) ---
  static Future<String?> askAIBot(String prompt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pySession = prefs.getString('python_session') ?? '';
      final res = await http.post(
        Uri.parse('$pythonBaseUrl/api/psychology'),
        headers: {'Content-Type': 'application/json', 'Cookie': pySession},
        body: jsonEncode({'user_text': prompt}),
      );
      
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['advice'];
      }
    } catch (e) { print("Lỗi mạng askAIBot: $e"); }
    return null;
  }
  // =================================================================
  // 4. API BẠN BÈ & KẾT BẠN
  // =================================================================

  // Lấy danh sách bạn bè, lời mời đã nhận, lời mời đã gửi
  static Future<Map<String, dynamic>?> getFriendsData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pySession = prefs.getString('python_session') ?? '';
      final res = await http.get(
        Uri.parse('$pythonBaseUrl/api/friends/list'),
        headers: {'Cookie': pySession},
      );
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { print("Lỗi getFriendsData: $e"); }
    return null;
  }

  // Tìm kiếm học sinh để kết bạn
  static Future<List<dynamic>?> searchFriends(String query) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pySession = prefs.getString('python_session') ?? '';
      final res = await http.post(
        Uri.parse('$pythonBaseUrl/api/friends/search'),
        headers: {'Content-Type': 'application/json', 'Cookie': pySession},
        body: jsonEncode({'query': query}),
      );
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (e) { print("Lỗi searchFriends: $e"); }
    return null;
  }

  // Gửi lời mời kết bạn
  static Future<bool> requestFriend(int targetId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pySession = prefs.getString('python_session') ?? '';
      final res = await http.post(
        Uri.parse('$pythonBaseUrl/api/friends/request'),
        headers: {'Content-Type': 'application/json', 'Cookie': pySession},
        body: jsonEncode({'target_id': targetId}),
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['success'] == true;
      }
    } catch (e) { print("Lỗi requestFriend: $e"); }
    return false;
  }

  // Phản hồi lời mời (Đồng ý / Từ chối)
  static Future<bool> respondFriend(int reqId, String action) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pySession = prefs.getString('python_session') ?? '';
      final res = await http.post(
        Uri.parse('$pythonBaseUrl/api/friends/respond'),
        headers: {'Content-Type': 'application/json', 'Cookie': pySession},
        body: jsonEncode({'req_id': reqId, 'action': action}),
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['success'] == true;
      }
    } catch (e) { print("Lỗi respondFriend: $e"); }
    return false;
  }
}