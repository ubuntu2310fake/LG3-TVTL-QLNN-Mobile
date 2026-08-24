import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'config.dart';

class VideoRenderService {
  final WebViewController webViewController;
  VideoRenderService(this.webViewController);

  // mode = 0 (Copy), 1 (720p), 2 (1080p)
  Future<void> startHlsProcess(int mode) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.video);
      if (result == null || result.files.single.path == null) {
        _sendErrorToWeb("Đã hủy chọn Video.");
        return;
      }
      String inputPath = result.files.single.path!;
      
      webViewController.runJavaScript("window.onFlutterRenderStart();");
      _updateProgressToWeb(0, "Đang soi cấu trúc Video...");

      final mediaInfoSession = await FFprobeKit.getMediaInformation(inputPath);
      final mediaInfo = mediaInfoSession.getMediaInformation();
      
      double totalDurationSec = 1.0;
      int videoWidth = 0;
      int videoHeight = 0;

      if (mediaInfo != null) {
        if (mediaInfo.getDuration() != null) totalDurationSec = double.parse(mediaInfo.getDuration()!);
        if (mediaInfo.getStreams() != null) {
          for (var stream in mediaInfo.getStreams()!) {
            if (stream.getType() == "video") {
              videoWidth = stream.getWidth() ?? 0;
              videoHeight = stream.getHeight() ?? 0;
              break;
            }
          }
        }
      }

      if (videoWidth > 0 && videoHeight > 0) {
        int shortestSide = videoWidth < videoHeight ? videoWidth : videoHeight;
        if (shortestSide < 720) {
          _sendErrorToWeb("Video quá mờ (${videoWidth}x${videoHeight}). Vui lòng chọn video rõ nét hơn (Tối thiểu 720p).");
          return; 
        }
      }

      final tempDir = await getTemporaryDirectory();
      final taskId = "vid_lg3_${DateTime.now().millisecondsSinceEpoch}";
      final outDir = Directory("${tempDir.path}/LG3_HLS/$taskId");
      await outDir.create(recursive: true);
      
      final outPath = "${outDir.path}/index.m3u8";
      final segmentPath = "${outDir.path}/segment_%03d.ts";

      String ffmpegCommand = "";
      String hwEncoder = Platform.isAndroid ? "h264_mediacodec" : "h264_videotoolbox";

      if (mode == 0) {
        ffmpegCommand = '-y -i "$inputPath" -c:v copy -c:a copy -f hls -hls_time 10 -hls_playlist_type vod -hls_segment_filename "$segmentPath" "$outPath"';
      } else if (mode == 1) {
        ffmpegCommand = '-y -i "$inputPath" -vf scale=-2:720 -c:v $hwEncoder -b:v 2500k -c:a aac -b:a 128k -f hls -hls_time 10 -hls_playlist_type vod -hls_segment_filename "$segmentPath" "$outPath"';
      } else {
        ffmpegCommand = '-y -i "$inputPath" -vf scale=-2:1080 -c:v $hwEncoder -b:v 5000k -c:a aac -b:a 128k -f hls -hls_time 10 -hls_playlist_type vod -hls_segment_filename "$segmentPath" "$outPath"';
      }

      _updateProgressToWeb(1, mode == 0 ? "Đang xé nhỏ Video..." : "Đang nén Video (GPU)...");

      await FFmpegKit.executeAsync(
        ffmpegCommand,
        (session) async {
          final returnCode = await session.getReturnCode();
          if (ReturnCode.isSuccess(returnCode)) {
            _updateProgressToWeb(100, "Xử lý hoàn tất! Đang kết nối máy chủ...");
            await _uploadFilesToVps(outDir, taskId);
          } else {
            final logs = await session.getLogs();
            String lastLog = logs.isNotEmpty ? logs.last.getMessage() : "Unknown Error";
            _sendErrorToWeb("Lỗi nén (Mã: $returnCode). Chi tiết: ${lastLog.replaceAll("'", "").replaceAll("\n", " ")}");
          }
        },
        null,
        (statistics) {
          int percent = ((statistics.getTime() / (totalDurationSec * 1000)) * 100).toInt();
          if (percent > 99) percent = 99;
          _updateProgressToWeb(percent, mode == 0 ? "Đang cắt khúc Video..." : "Đang nén Video (Gia tốc phần cứng)...");
        }
      );

    } catch (e) {
      _sendErrorToWeb("Lỗi hệ thống: ${e.toString().replaceAll("'", "")}");
    }
  }

  Future<void> _uploadFilesToVps(Directory dir, String taskId) async {
    try {
      List<FileSystemEntity> allFiles = dir.listSync();
      List<File> validFiles = allFiles.whereType<File>().toList();
      
      if (validFiles.isEmpty) {
        _sendErrorToWeb("Lỗi: Không có file HLS để upload.");
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
          _sendErrorToWeb("Server báo lỗi: ${response.data['msg']}");
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

        String statusText = "Đang đẩy VPS: $uploadedCount/${validFiles.length} file | ${speedMbps.toStringAsFixed(1)} MB/s | ETA: $etaStr";
        int percent = ((uploadedCount / validFiles.length) * 100).toInt();

        _updateProgressToWeb(percent, statusText);
      }

      if (finalUrl.isNotEmpty) {
        webViewController.runJavaScript("window.onFlutterRenderComplete('$finalUrl');");
      } else {
        _sendErrorToWeb("VPS nhận file nhưng không trả về URL.");
      }
      
      dir.deleteSync(recursive: true);
    } catch (e) {
      _sendErrorToWeb("Mất kết nối với VPS: ${e.toString().replaceAll("'", "")}");
    }
  }

  void _updateProgressToWeb(int percent, String text) {
    webViewController.runJavaScript("window.onFlutterRenderProgress($percent, '$text');");
  }

  void _sendErrorToWeb(String error) {
    String safeError = error.replaceAll("'", "\\'").replaceAll("\n", " ");
    webViewController.runJavaScript("window.onFlutterRenderError('$safeError');");
  }
}