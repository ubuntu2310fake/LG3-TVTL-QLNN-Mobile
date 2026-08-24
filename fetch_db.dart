import 'dart:convert';
import 'dart:io';

void main() async {
  const dbPath = 'flutter_knowledge_base.json';
  
  print('Fetching packages from pub.dev...');
  final url = Uri.parse('https://pub.dev/api/package-names');
  final httpClient = HttpClient();
  
  List<String> packages = [];
  try {
    final request = await httpClient.getUrl(url);
    request.headers.set('User-Agent', 'Mozilla/5.0');
    final response = await request.close();
    
    final stringData = await response.transform(utf8.decoder).join();
    final data = json.decode(stringData);
    if (data['packages'] != null) {
      packages = List<String>.from(data['packages']);
      print('Fetched ${packages.length} packages.');
    }
  } catch (e) {
    print('Error fetching packages: $e');
  } finally {
    httpClient.close();
  }

  final standards = [
    {
      "title": "Effective Dart",
      "content": "Tuân thủ các quy chuẩn của Effective Dart. Sử dụng flutter_lints cho các quy tắc phân tích mã chuẩn."
    },
    {
      "title": "Quản lý trạng thái (State Management)",
      "content": "Sử dụng các giải pháp như Provider, Riverpod, BLoC, hoặc GetX tùy thuộc vào quy mô dự án."
    },
    {
      "title": "Cấu trúc dự án (Project Structure)",
      "content": "Tổ chức file theo tính năng (feature-first) hoặc theo layer (layered architecture). Feature-first được khuyến khích cho các dự án lớn."
    },
    {
      "title": "Tối ưu UI",
      "content": "Tách các widget có thể tái sử dụng. Tránh các phương thức build quá lớn. Sử dụng const constructors ở mọi nơi có thể để tối ưu hóa việc rebuild."
    },
    {
      "title": "Null Safety",
      "content": "Đảm bảo strict null safety được bật và sử dụng đúng cách trên toàn bộ dự án."
    },
    {
      "title": "Material 3",
      "content": "Áp dụng Material 3 guidelines cho UI hiện đại. Đặt useMaterial3: true trong ThemeData."
    },
    {
      "title": "Kiểm thử (Testing)",
      "content": "Viết Unit Tests cho logic, Widget Tests cho các UI component, và Integration Tests cho toàn bộ luồng ứng dụng."
    },
    {
      "title": "Xử lý lỗi (Error Handling)",
      "content": "Luôn sử dụng try-catch hoặc dọn dẹp lỗi. Tích hợp các công cụ báo cáo lỗi như Firebase Crashlytics hoặc Sentry."
    }
  ];

  final dbContent = {
    "flutter_standards": standards,
    "flutter_plugins": packages
  };

  final file = File(dbPath);
  await file.writeAsString(json.encode(dbContent));
  print('JSON Database successfully created at $dbPath');
}
