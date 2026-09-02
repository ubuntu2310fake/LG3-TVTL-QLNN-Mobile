import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const String baseUrl = 'https://qlnn.testifiyonline.xyz';
  static const String tvtlbaseUrl = 'https://qlnn.testifiyonline.xyz';
  static const String domain = 'qlnn.testifiyonline.xyz';
  static bool isLiquidGlassEnabled = false;

  static String cfClearance = '';

  // Sử dụng chung 1 client để giữ kết nối Keep-Alive (tránh overhead TCP/TLS Handshake)
  static final http.Client client = http.Client();

  static Future<Map<String, String>> getHeaders({Map<String, String>? extra}) async {
    final prefs = await SharedPreferences.getInstance();
    final phpsessid = prefs.getString('phpsessid') ?? '';
    final cf = cfClearance.isNotEmpty ? cfClearance : (prefs.getString('cf_clearance') ?? '');
    
    final cookieParts = <String>[];
    if (phpsessid.isNotEmpty) cookieParts.add('PHPSESSID=$phpsessid');
    if (cf.isNotEmpty) cookieParts.add('cf_clearance=$cf');
    
    final headers = <String, String>{
      if (cookieParts.isNotEmpty) 'Cookie': cookieParts.join('; '),
    };
    if (extra != null) headers.addAll(extra);
    return headers;
  }
}
