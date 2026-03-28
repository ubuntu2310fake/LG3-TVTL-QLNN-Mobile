import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

class ExportReportScreen extends StatefulWidget {
  const ExportReportScreen({super.key});

  @override
  State<ExportReportScreen> createState() => _ExportReportScreenState();
}

class _ExportReportScreenState extends State<ExportReportScreen> {
  String _week = '';
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    DateTime start = DateTime(2025, 9, 5);
    _week = ((DateTime.now().difference(start).inDays ~/ 7) + 1).toString();
  }

  Future<void> _downloadExcel() async {
    setState(() => _isDownloading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';

      final response = await http.post(
        Uri.parse('https://qlnn.testifiyonline.xyz/export_vpbs'),
        headers: {
          'Cookie': 'PHPSESSID=$sessionId',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'action': 'export',
          'week': _week,
        },
      );

      final contentType = response.headers['content-type'] ?? '';
      
      if (response.statusCode == 200 && contentType.contains('spreadsheetml')) {
        String filePath = '';
        String folderName = '';
        
        if (Platform.isAndroid) {
          folderName = 'Download';
          filePath = '/storage/emulated/0/Download/LG3_VPBS_Tuan_$_week.xlsx';
        } else {
          folderName = 'Tệp (Files)';
          final dir = await getApplicationDocumentsDirectory();
          filePath = '${dir.path}/LG3_VPBS_Tuan_$_week.xlsx';
        }
        
        try {
          File file = File(filePath);
          await file.writeAsBytes(response.bodyBytes);
        } catch (e) {
          final dir = await getApplicationDocumentsDirectory();
          filePath = '${dir.path}/LG3_VPBS_Tuan_$_week.xlsx';
          File file = File(filePath);
          await file.writeAsBytes(response.bodyBytes);
          folderName = 'Bộ nhớ App';
        }

        if (!mounted) return;
        
        showDialog(
          context: context,
          builder: (c) {
            final isDarkDialog = Theme.of(context).brightness == Brightness.dark;
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 28),
                  SizedBox(width: 10),
                  Text('Tải Thành Công', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: RichText(
                text: TextSpan(
                  style: TextStyle(color: isDarkDialog ? Colors.white70 : Colors.black87, fontSize: 14, height: 1.5),
                  children: [
                    const TextSpan(text: 'Báo cáo vi phạm đã được tải về máy của bạn.\n\n'),
                    const TextSpan(text: 'Vị trí lưu: ', style: TextStyle(fontWeight: FontWeight.bold)),
                    TextSpan(text: 'Thư mục $folderName\n'),
                    const TextSpan(text: 'Tên file: ', style: TextStyle(fontWeight: FontWeight.bold)),
                    TextSpan(text: 'LG3_VPBS_Tuan_$_week.xlsx\n\n'),
                    const TextSpan(text: 'Bạn có thể mở ứng dụng Quản lý tệp (File Manager) hoặc Zalo để gửi file này đi.'),
                  ],
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(c),
                  style: FilledButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('Đã Hiểu', style: TextStyle(fontWeight: FontWeight.bold)),
                )
              ],
            );
          }
        );
      } else {
        if (!mounted) return;
        print("Lỗi định dạng trả về: $contentType");
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Lỗi xuất dữ liệu từ Server!'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Lỗi kết nối: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Xuất Báo Cáo', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thẻ Hướng dẫn
            Card(
              elevation: 0,
              color: isDark ? Colors.green.withOpacity(0.1) : Colors.green.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16), 
                side: BorderSide(color: isDark ? Colors.green.withOpacity(0.3) : Colors.green.shade200)
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.file_download, size: 50, color: Colors.green),
                    const SizedBox(height: 10),
                    const Text('Xuất dữ liệu Vi Phạm', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                    const SizedBox(height: 8),
                    Text(
                      'Hệ thống sẽ tải file Excel (.xlsx) trực tiếp vào thư mục Download trên điện thoại của bạn.', 
                      textAlign: TextAlign.center, 
                      style: TextStyle(color: isDark ? Colors.grey[400] : Colors.black54)
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 30),
            
            // Khu vực chọn tuần
            const Text('Chọn tuần cần xuất báo cáo:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface, 
                borderRadius: BorderRadius.circular(12), 
                border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300)
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _week,
                  icon: const Icon(Icons.calendar_month, color: Colors.green),
                  style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold),
                  items: List.generate(35, (i) => DropdownMenuItem(value: (i+1).toString(), child: Text('Tuần ${i+1}'))),
                  onChanged: (v) { setState(() => _week = v!); },
                ),
              ),
            ),

            const Spacer(),

            // Nút bấm Tải Xuống
            ElevatedButton.icon(
              onPressed: _isDownloading ? null : _downloadExcel,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isDownloading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                  : const Icon(Icons.download_rounded),
              label: Text(_isDownloading ? 'ĐANG TẢI XUỐNG...' : 'TẢI FILE EXCEL', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}