import 'localization_service.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

class VideoRenderService {
  final WebViewController webViewController;
  VideoRenderService(this.webViewController);

  // mode = 0 (Copy), 1 (720p), 2 (1080p)
  Future<void> startHlsProcess(int mode) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.video);
      if (result == null || result.files.single.path == null) {
        _sendErrorToWeb(LocalizationService().currentLanguage == 'vi' ? "Đã hủy chọn Video." : "Da huy chon Video.");
        return;
      }
      String inputPath = result.files.single.path!;
      
      webViewController.runJavaScript("window.onFlutterRenderStart();");
      _updateProgressToWeb(0, LocalizationService().currentLanguage == 'vi' ? "Đang chuẩn bị gửi Video..." : "Preparing video...");

      final tempDir = await getTemporaryDirectory();
      final taskId = "vid_lg3_${DateTime.now().millisecondsSinceEpoch}";
      final outDir = Directory("${tempDir.path}/LG3_HLS/$taskId");
      await outDir.create(recursive: true);
      
      final outPath = "${outDir.path}/index.m3u8";
      final segmentPath = "${outDir.path}/segment_%03d.ts";

      _updateProgressToWeb(50, LocalizationService().currentLanguage == 'vi' ? "Đang chuẩn bị gửi Video lên máy chủ..." : "Preparing to send video to server...");
      final rawVideoFile = File(inputPath);
      final ext = inputPath.split('.').last;
      final copyPath = "${outDir.path}/video_raw.$ext";
      await rawVideoFile.copy(copyPath);
      _updateProgressToWeb(100, LocalizationService().currentLanguage == 'vi' ? "Đang tải lên máy chủ VPS..." : "Uploading to VPS server...");
      await _uploadFilesToVps(outDir, taskId);

    } catch (e) {
      _sendErrorToWeb(LocalizationService().currentLanguage == 'vi' ? "Lỗi hệ thống: ${e}" : "System error: ${e}");
    }
  }

  Future<void> _uploadFilesToVps(Directory dir, String taskId) async {
    try {
      List<FileSystemEntity> allFiles = dir.listSync();
      List<File> validFiles = allFiles.whereType<File>().toList();
      
      if (validFiles.isEmpty) {
        _sendErrorToWeb(LocalizationService().currentLanguage == "vi" ? "Lỗi: Không có file HLS để upload." : "Error: No HLS files to upload.");
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      Dio dio = Dio();
      if (sessionId.isNotEmpty) {
        dio.options.headers['Cookie'] = 'PHPSESSID=$sessionId';
      }

      int totalBytes = validFiles.fold(0, (sum, file) => sum + file.lengthSync());
      int uploadedBytes = 0;
      int uploadedCount = 0; 
      String finalUrl = ''; 
      
      DateTime startTime = DateTime.now();

      for (var file in validFiles) {
        String fileName = file.path.split('/').last;
        FormData formData = FormData.fromMap({
          "task_id": taskId,
          "files[]": await MultipartFile.fromFile(file.path, filename: fileName),
        });

        var response = await dio.post('${AppConfig.baseUrl}/api/upload_hls_pc.php', data: formData);
        
        if (response.statusCode == 200 && response.data['status'] == 'success') {
          finalUrl = response.data['url'];
        } else {
          _sendErrorToWeb(LocalizationService().currentLanguage == 'vi' ? 'Server báo lỗi: ${response.data["msg"]}' : 'Server error: ${response.data["msg"]}');
          return;
        }
        
        uploadedBytes += file.lengthSync();
        uploadedCount++;

        // Thuật toán tính Tốc độ và ETA
        int elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
        double speedBps = elapsedMs > 0 ? (uploadedBytes / (elapsedMs / 1000.0)) : 0;
        double speedMbps = speedBps / (1024 * 1024);
        
        int remainingBytes = totalBytes - uploadedBytes;
        int etaSec = speedBps > 0 ? (remainingBytes / speedBps).round() : 0;
        String etaStr = etaSec > 60 ? "${etaSec ~/ 60}p ${etaSec % 60}s" : "${etaSec}s";

        String statusText = LocalizationService().currentLanguage == 'vi' ? "Đang đẩy VPS: $uploadedCount/${validFiles.length} file | ${speedMbps.toStringAsFixed(1)} MB/s | ETA: $etaStr" : "Uploading VPS: $uploadedCount/${validFiles.length} file | ${speedMbps.toStringAsFixed(1)} MB/s | ETA: $etaStr";
        int percent = ((uploadedCount / validFiles.length) * 100).toInt();

        _updateProgressToWeb(percent, statusText);
      }

      if (finalUrl.isNotEmpty) {
        webViewController.runJavaScript("window.onFlutterRenderComplete('" + finalUrl + "');");
      } else {
        _sendErrorToWeb(LocalizationService().currentLanguage == 'vi' ? 'VPS nhận file nhưng không trả về URL.' : 'VPS received file but no URL.');
      }
      dir.deleteSync(recursive: true);
    } catch (e) {
      _sendErrorToWeb(LocalizationService().currentLanguage == 'vi' ? 'Mất kết nối với VPS: ${e}' : 'Lost connection to VPS: ${e}');
    }
  }

  void _updateProgressToWeb(int percent, String text) {
    webViewController.runJavaScript("window.onFlutterRenderProgress($percent, '$text');");
  }

  void _sendErrorToWeb(String error) {
    String safeError = error.replaceAll("'", "\'").replaceAll("\n", " ");
    webViewController.runJavaScript("window.onFlutterRenderError('$safeError');");
  }
}
