import "localization_service.dart";
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'dart:convert';

// Fallback config since exact imports aren't fully known
class AppConfig {
  static const String baseUrl = 'http://127.0.0.1/lg3tvtl';
}

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  final Dio _dio = Dio();
  bool _isLoading = false;
  List<dynamic> _newsList = [];
  String _selectedCategory = 'all';

  final Map<String, String> _categories = {
    'all': LocalizationService().currentLanguage == 'vi' ? 'Tất cả' : 'All',
    'thong_bao': LocalizationService().currentLanguage == 'vi' ? 'Thông báo' : 'Announcement',
    'tin_tuc': LocalizationService().currentLanguage == 'vi' ? 'Tin tức sự kiện' : 'News & Events',
    'tuyen_sinh': LocalizationService().currentLanguage == 'vi' ? 'Tuyển sinh' : 'Admission',
  };

  final Map<String, IconData> _categoryIcons = {
    'all': Icons.all_inclusive,
    'thong_bao': Icons.campaign_outlined,
    'tin_tuc': Icons.newspaper_outlined,
    'tuyen_sinh': Icons.school_outlined,
  };

  @override
  void initState() {
    super.initState();
    _fetchNews();
  }

  Future<void> _fetchNews() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _dio.get(
        '${AppConfig.baseUrl}/api/news_api.php',
        queryParameters: {
          'action': 'list',
          'category': _selectedCategory,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data is String ? jsonDecode(response.data) : response.data;
        if (data['status'] == 'success') {
          setState(() {
            _newsList = data['data'] ?? [];
          });
        }
      }
    } catch (e) {
      // Handle error implicitly
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildFilterTabs() {
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final key = _categories.keys.elementAt(index);
          final title = _categories[key]!;
          final icon = _categoryIcons[key]!;
          final isSelected = _selectedCategory == key;

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedCategory = key;
              });
              _fetchNews();
            },
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF005FBA) : Colors.white,
                border: Border.all(
                  color: isSelected ? const Color(0xFF005FBA) : const Color(0xFFE2E8F0),
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: isSelected ? Colors.white : const Color(0xFF475569),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF475569),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(
          'TIN TỨC & THÔNG BÁO',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF005FBA),
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF005FBA)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchNews,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              // Add news modal
            },
          )
        ],
      ),
      body: Column(
        children: [
          _buildFilterTabs(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF005FBA)))
                : RefreshIndicator(
                    color: const Color(0xFF005FBA),
                    onRefresh: _fetchNews,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _newsList.length,
                      itemBuilder: (context, index) {
                        return _buildNewsCard(_newsList[index]);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewsCard(dynamic news) {
    final title = news['title'] ?? (LocalizationService().currentLanguage == 'vi' ? 'Không có tiêu đề' : 'No title');
    final createdAt = news['created_at'] ?? '';
    final author = news['full_name'] ?? 'Admin';
    final views = news['views']?.toString() ?? '0';

    String? thumbnailUrl = news['thumbnail_url'];
    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
      thumbnailUrl = '${AppConfig.baseUrl}/$thumbnailUrl';
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NewsDetailScreen(news: news),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (thumbnailUrl != null)
              Image.network(
                thumbnailUrl,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 160,
                  width: double.infinity,
                  color: const Color(0xFFE2E8F0),
                  child: const Icon(Icons.image_not_supported, color: Colors.grey),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1D1D1F),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 13, color: Color(0xFF475569)),
                      const SizedBox(width: 4),
                      Text(createdAt, style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                      const SizedBox(width: 12),
                      const Icon(Icons.person_outline, size: 13, color: Color(0xFF475569)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          author,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.visibility_outlined, size: 13, color: Color(0xFF475569)),
                      const SizedBox(width: 4),
                      Text(views, style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NewsDetailScreen extends StatelessWidget {
  final dynamic news;
  const NewsDetailScreen({super.key, required this.news});

  String _stripHtmlTags(String htmlString) {
    RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
    return htmlString.replaceAll(exp, '');
  }

  @override
  Widget build(BuildContext context) {
    final title = news['title'] ?? '';
    final content = news['content'] ?? '';
    final createdAt = news['created_at'] ?? '';
    final author = news['full_name'] ?? 'Admin';
    final views = news['views']?.toString() ?? '0';

    String plainTextContent = _stripHtmlTags(content);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          LocalizationService().currentLanguage == 'vi' ? 'Chi tiết bài viết' : 'Article Details',
          style: TextStyle(
            color: Color(0xFF005FBA),
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF005FBA)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete, color: Color(0xFFD93025)),
            onPressed: () {
              // Delete logic
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1D1D1F),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.only(bottom: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time, size: 14, color: Color(0xFF475569)),
                  const SizedBox(width: 4),
                  Text(createdAt, style: const TextStyle(fontSize: 13, color: Color(0xFF475569))),
                  const SizedBox(width: 16),
                  const Icon(Icons.person_outline, size: 14, color: Color(0xFF475569)),
                  const SizedBox(width: 4),
                  Text(author, style: const TextStyle(fontSize: 13, color: Color(0xFF475569))),
                  const SizedBox(width: 16),
                  const Icon(Icons.visibility_outlined, size: 14, color: Color(0xFF475569)),
                  const SizedBox(width: 4),
                  Text(views, style: const TextStyle(fontSize: 13, color: Color(0xFF475569))),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              plainTextContent,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF1D1D1F),
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            const Divider(color: Color(0xFFE2E8F0)),
            Text(
              LocalizationService().currentLanguage == 'vi' ? 'Tệp đính kèm' : 'Attachments',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            // Mock attachments section
            const SizedBox(height: 12),
            const Divider(color: Color(0xFFE2E8F0)),
            Text(
              LocalizationService().currentLanguage == 'vi' ? 'Bình luận' : 'Comments',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            // Mock comments section
          ],
        ),
      ),
    );
  }
}