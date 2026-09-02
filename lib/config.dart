import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'main.dart';
import 'cloudflare_captcha_service.dart';
import 'dart:convert';

class AppConfig {
  static const String baseUrl = 'https://qlnn.testifiyonline.xyz';
  static const String tvtlbaseUrl = 'https://qlnn.testifiyonline.xyz';
  static const String domain = 'qlnn.testifiyonline.xyz';
  static bool isLiquidGlassEnabled = false;

  static String cfClearance = '';
  static String shieldPass = '';

  // Sử dụng chung 1 client bọc lại để giữ kết nối Keep-Alive và tự động đánh chặn mã 252 (LG3 Shield)
  static final http.Client client = AppHttpClient(http.Client());

  static Future<Map<String, String>> getHeaders({Map<String, String>? extra}) async {
    final prefs = await SharedPreferences.getInstance();
    final phpsessid = prefs.getString('phpsessid') ?? '';
    final cf = cfClearance.isNotEmpty ? cfClearance : (prefs.getString('cf_clearance') ?? '');
    final shield = shieldPass.isNotEmpty ? shieldPass : (prefs.getString('lg3_shield_pass') ?? '');
    
    final cookieParts = <String>[];
    if (phpsessid.isNotEmpty) cookieParts.add('PHPSESSID=$phpsessid');
    if (cf.isNotEmpty) cookieParts.add('cf_clearance=$cf');
    if (shield.isNotEmpty) cookieParts.add('lg3_shield_pass=$shield');
    
    final headers = <String, String>{
      if (cookieParts.isNotEmpty) 'Cookie': cookieParts.join('; '),
    };
    if (extra != null) headers.addAll(extra);
    return headers;
  }
}

class AppHttpClient extends http.BaseClient {
  final http.Client _inner;
  AppHttpClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Luôn gắn headers mới nhất (bao gồm cả lg3_shield_pass)
    final dynamicHeaders = await AppConfig.getHeaders();
    request.headers.addAll(dynamicHeaders);

    http.StreamedResponse response = await _inner.send(request);

    // Kiểm tra xem có dính Captcha 252 / 403 / 503 không
final contentType = response.headers['content-type'] ?? '';
    final isErrorStatus = response.statusCode == 252 || response.statusCode == 403 || response.statusCode == 503 || response.statusCode == 429 || response.statusCode == 500 || response.statusCode == 502;
    final isHtml = contentType.contains('text/html');

    if (isErrorStatus || isHtml) {
      // Đọc toàn bộ body để kiểm tra
      final responseBody = await response.stream.bytesToString();
      
if (CloudflareCaptchaService.isCloudflareChallenge(response.statusCode, responseBody)) {
        debugPrint('AppHttpClient: Đã phát hiện LG3 Shield (Mã ${response.statusCode})');
        
        final context = navigatorKey.currentState?.context;
        debugPrint('AppHttpClient: navigatorKey.currentState = ${navigatorKey.currentState}');
        debugPrint('AppHttpClient: context = $context');
        
        if (context != null) {
          // Bật Popup giải Captcha và chờ người dùng giải xong
          // Bật Popup giải Captcha và chờ người dùng giải xong
          final success = await CloudflareCaptchaService().handleChallenge(context);
          if (success) {
            // Tự động GỬI LẠI request sau khi có thẻ bài lg3_shield_pass
            debugPrint('AppHttpClient: Giải Captcha thành công! Tự động gửi lại request...');
            
            // Reconstruct the request (BaseRequest cannot be reused)
            http.BaseRequest newRequest;
            if (request is http.Request) {
              newRequest = http.Request(request.method, request.url)
                ..encoding = request.encoding
                ..bodyBytes = request.bodyBytes;
            } else if (request is http.MultipartRequest) {
              newRequest = http.MultipartRequest(request.method, request.url)
                ..fields.addAll(request.fields)
                ..files.addAll(request.files);
            } else {
              newRequest = http.Request(request.method, request.url);
            }
            
            final newHeaders = await AppConfig.getHeaders();
            newRequest.headers.addAll(request.headers);
            newRequest.headers.addAll(newHeaders); // Override with new cookie

            return await _inner.send(newRequest);
          }
        }
      }
      
      // Nếu không phải Challenge hoặc popup thất bại, trả về response cũ (cần đóng gói lại stream vì đã đọc)
      return http.StreamedResponse(
        Stream.value(utf8.encode(responseBody)),
        response.statusCode,
        contentLength: utf8.encode(responseBody).length,
        request: request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    }
    
    return response;
  }
}
