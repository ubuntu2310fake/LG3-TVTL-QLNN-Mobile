import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class OfflineSyncService {
  static final _key = encrypt.Key.fromUtf8('LG3_TVTL_QLNN_SecretKey_2026_XYZ'); 

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/lg3_encrypted_vault.dat'); 
  }

  // 1. TẢI CỤC MÃ HÓA SERVER VỀ LƯU TRỰC TIẾP
  static Future<bool> syncData() async {
    try {
      final res = await http.get(Uri.parse('https://qlnn.testifiyonline.xyz/api/sync_data_secure.php'));
      final data = jsonDecode(res.body);
      if (data['status'] == 'success' && data['secure_payload'] != null) {
        final file = await _getFile();
        // Lưu thẳng chuỗi (Base64IV:Base64Data) xuống máy. Ai tháo máy cũng không đọc được.
        await file.writeAsString(data['secure_payload']); 
        return true;
      }
    } catch (e) { print("Lỗi đồng bộ: $e"); }
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
      print("Lỗi giải mã: $e");
      return {};
    }
  }
}