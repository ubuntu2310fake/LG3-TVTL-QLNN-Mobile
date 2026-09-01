import 'localization_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineSyncService {
  static final _key = encrypt.Key.fromUtf8('LG3_TVTL_QLNN_SecretKey_2026_XYZ'); 

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/lg3_encrypted_vault.dat'); 
  }

  // 1. TẢI CỤC MÃ HÓA SERVER VỀ LƯU TRỰC TIẾP
  static Future<bool> syncData() async {
    try {
      final res = await AppConfig.client.get(Uri.parse('${AppConfig.baseUrl}/api/sync_data_secure.php'));
      final data = jsonDecode(res.body);
      if (data['status'] == 'success' && data['secure_payload'] != null) {
        final file = await _getFile();
        // Lưu thẳng chuỗi (Base64IV:Base64Data) xuống máy. Ai tháo máy cũng không đọc được.
        await file.writeAsString(data['secure_payload']); 
        return true;
      }
    } catch (e) { print(LocalizationService().currentLanguage == 'vi' ? "Lỗi đồng bộ: $e" : "Sync error: $e"); }
    return false;
  }

  // 2. GIẢI MÃ BUNG DỮ LIỆU RA DÙNG (Cực nhẹ, chỉ tốn vài mili-giây)
  static Future<Map<String, dynamic>> getMasterData() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return {};
      
      final securePayload = await file.readAsString();
      final parts = securePayload.split(':'); // parts[0] là IV, parts[1] là dữ liệu mã hóa
      if (parts.length != 2) return {};

      final iv = encrypt.IV.fromBase64(parts[0]);
      final encrypter = encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.cbc));
      
      // Bung lụa!
      final decryptedJson = encrypter.decrypt64(parts[1], iv: iv);
      return jsonDecode(decryptedJson);
    } catch (e) {
      print(LocalizationService().currentLanguage == 'vi' ? "Lỗi giải mã: $e" : "Decoding error: $e");
      return {};
    }
  }

  // 3. TẢI VÀ LƯU AVATAR CỦA USER VÀO MÁY ĐỂ DÙNG OFFLINE
  static Future<void> syncUserAvatar(String sessionId) async {
    try {
      if (sessionId.isEmpty) return;
      final res = await AppConfig.client.get(
        Uri.parse('${AppConfig.baseUrl}/api/profile_api'),
        headers: {'Cookie': 'PHPSESSID=$sessionId'},
      );
      final data = jsonDecode(res.body);
      if (data['status'] == 'success' && data['user'] != null) {
        final prefs = await SharedPreferences.getInstance();
        String rawAvatar = data['user']['avatar'] ?? '';
        String fullAvatarUrl = rawAvatar.startsWith('http') ? rawAvatar : '${AppConfig.baseUrl}$rawAvatar';
        await prefs.setString('avatar', fullAvatarUrl);
        if (data['user']['full_name'] != null) {
          await prefs.setString('full_name', data['user']['full_name']);
        }

        if (rawAvatar.isNotEmpty && !rawAvatar.contains('default.png')) {
          final imgRes = await AppConfig.client.get(Uri.parse(fullAvatarUrl));
          if (imgRes.statusCode == 200) {
            final dir = await getApplicationDocumentsDirectory();
            final avatarFile = File('${dir.path}/user_avatar.png');
            await avatarFile.writeAsBytes(imgRes.bodyBytes);
            await prefs.setString('local_avatar_path', avatarFile.path);
          }
        } else {
          final dir = await getApplicationDocumentsDirectory();
          final avatarFile = File('${dir.path}/user_avatar.png');
          if (await avatarFile.exists()) await avatarFile.delete();
          await prefs.remove('local_avatar_path');
        }
      }
    } catch (e) {
      print("Lỗi sync avatar: $e");
    }
  }

}
