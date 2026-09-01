import 'package:http/http.dart' as http;

class AppConfig {
  static const String baseUrl = 'https://qlnn.testifiyonline.xyz';
  static const String tvtlbaseUrl = 'https://qlnn.testifiyonline.xyz';
  static const String domain = 'qlnn.testifiyonline.xyz';
  static bool isLiquidGlassEnabled = false;

  // Sử dụng chung 1 client để giữ kết nối Keep-Alive (tránh overhead TCP/TLS Handshake)
  static final http.Client client = http.Client();
}
