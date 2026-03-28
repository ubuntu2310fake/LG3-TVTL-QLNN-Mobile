import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class DeviceHelper {
  // LẤY MODEL MÁY THẬT (Chuẩn chuyên nghiệp)
  static Future<String> getDeviceModel() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        // Trả về e.g., "Google Pixel 8" hoặc "Samsung SM-G991B"
        return "${androidInfo.manufacturer} ${androidInfo.model}";
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        // Trả về e.g., "iPhone 15 Pro"
        return iosInfo.utsname.machine ?? "iPhone"; 
      }
    } catch (e) {
      print("Lỗi lấy device info: $e");
    }
    return Platform.isAndroid ? "Android Device" : "iOS Device";
  }
}