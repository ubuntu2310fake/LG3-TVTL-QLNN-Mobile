import 'localization_service.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class ConsultingTestScreen extends StatefulWidget {
  const ConsultingTestScreen({super.key});

  @override
  State<ConsultingTestScreen> createState() => _ConsultingTestScreenState();
}

class _ConsultingTestScreenState extends State<ConsultingTestScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Dio _dio = Dio();
  String _sessionId = '';

  // Data states
  Map<String, dynamic> _discData = {};
  Map<String, dynamic> _mtvtData = {};
  Map<String, dynamic> _hollandData = {};
  Map<String, dynamic> _miData = {};
  bool _isLoadingData = true;
  
  List<dynamic> _historyData = [];
  bool _isLoadingHistory = false;

  String _aiAdvice = '';
  bool _isLoadingAI = false;

  // Answers states
  final Map<String, bool> _hollandAnswers = {};
  final Map<String, bool> _miAnswers = {};
  final Map<String, bool> _discAnswers = {};
  final Map<String, bool> _mtvtAnswers = {};

  final Color primaryColor = const Color(0xFF005FBA);
  final Color primaryHover = const Color(0xFF005A9E);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _initData();
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionId = prefs.getString('phpsessid') ?? '';
    
    await Future.wait([
      _fetchQuestions(),
      _fetchHistory(),
    ]);
  }

  Future<void> _fetchQuestions() async {
    try {
      final lang = LocalizationService().currentLanguage;
      final response = await _dio.get('${AppConfig.baseUrl}/api/consulting_questions_api.php?lang=$lang');
      if (response.statusCode == 200) {
        final data = response.data is String ? jsonDecode(response.data) : response.data;
        setState(() {
          _discData = data['discData'] ?? {};
          _mtvtData = data['mtvtDb'] ?? {};
          _hollandData = data['hollandData'] ?? {};
          _miData = data['miData'] ?? {};
          _isLoadingData = false;
        });
      }
    } catch (e) {
      setState(() => _isLoadingData = false);
    }
  }

  Future<void> _fetchHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final response = await _dio.post(
        '${AppConfig.baseUrl}/consulting_test.php?local_api=history',
        options: Options(
          headers: {'Cookie': 'PHPSESSID=$_sessionId'},
        ),
      );
      if (response.statusCode == 200) {
        final data = response.data is String ? jsonDecode(response.data) : response.data;
        if (data['success'] == true) {
          setState(() {
            _historyData = data['data'] ?? [];
          });
        }
      }
    } catch (e) {
      // Handle error
    } finally {
      setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _saveTest(String testType, Map<String, dynamic> resultData) async {
    try {
      final response = await _dio.post(
        '${AppConfig.baseUrl}/consulting_test.php?local_api=save_test',
        data: {
          'test_type': testType,
          'result_data': resultData,
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Cookie': 'PHPSESSID=$_sessionId',
          },
        ),
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Lưu kết quả thành công!' : 'Saved successfully!')));
        _fetchHistory();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Lỗi khi lưu kết quả' : 'Error saving results')));
    }
  }

  Future<void> _deleteHistory(int id) async {
    try {
      final response = await _dio.post(
        '${AppConfig.baseUrl}/consulting_test.php?local_api=delete',
        data: {'id': id},
        options: Options(headers: {'Cookie': 'PHPSESSID=$_sessionId'}),
      );
      if (response.statusCode == 200) {
        _fetchHistory();
      }
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _deleteAllHistory() async {
    try {
      final response = await _dio.post(
        '${AppConfig.baseUrl}/consulting_test.php?local_api=delete_all',
        data: {},
        options: Options(headers: {'Cookie': 'PHPSESSID=$_sessionId'}),
      );
      if (response.statusCode == 200) {
        _fetchHistory();
      }
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _callAIProxy() async {
    setState(() => _isLoadingAI = true);
    try {
      final historySummary = _historyData.map((e) => "${e['test_type']}: ${e['result_data']}").join('\n');
      final prompt = LocalizationService().currentLanguage == 'vi' ? "Dưới đây là điểm số trắc nghiệm nghề nghiệp của tôi. Hãy tư vấn cho tôi:\n$historySummary" : "Below are my career assessment scores. Please advise me:\n$historySummary";
      
      final response = await _dio.post(
        '${AppConfig.baseUrl}/consulting_test.php?local_api=ai_proxy',
        data: {
          'user_text': prompt,
          'lang': LocalizationService().currentLanguage,
        },
        options: Options(headers: {'Cookie': 'PHPSESSID=$_sessionId'}),
      );
      if (response.statusCode == 200) {
        final data = response.data is String ? jsonDecode(response.data) : response.data;
        setState(() {
          _aiAdvice = data['advice'] ?? (LocalizationService().currentLanguage == 'vi' ? 'Không nhận được phản hồi từ AI' : 'No response from AI');
        });
      }
    } catch (e) {
      setState(() {
        _aiAdvice = LocalizationService().currentLanguage == 'vi' ? 'Lỗi kết nối AI: $e' : 'AI connection error: $e';
      });
    } finally {
      setState(() => _isLoadingAI = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF000000) : const Color(0xFFF5F7FA);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(LocalizationService().currentLanguage == 'vi' ? 'Đánh giá Nghề nghiệp' : 'Career Assessment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: primaryColor,
          unselectedLabelColor: isDark ? const Color(0xFFA3A3A3) : const Color(0xFF616161),
          indicatorColor: primaryColor,
          tabs: [
            Tab(text: 'Holland (RIASEC)'),
            Tab(text: LocalizationService().currentLanguage == 'vi' ? 'Đa trí tuệ (MI)' : 'Multiple Intelligences (MI)'),
            Tab(text: LocalizationService().currentLanguage == 'vi' ? 'Hành vi (DISC)' : 'Behavioral (DISC)'),
            Tab(text: LocalizationService().currentLanguage == 'vi' ? 'Động lực (MTVT)' : 'Motivators (MTVT)'),
            Tab(text: LocalizationService().currentLanguage == 'vi' ? '🕒 Lịch sử' : '🕒 History'),
            Tab(text: LocalizationService().currentLanguage == 'vi' ? '🤖 Góc tư vấn' : '🤖 Counseling Corner'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHollandTab(isDark),
          _buildMITab(isDark),
          _buildDISCTab(isDark),
          _buildMTVTTab(isDark),
          _buildHistoryTab(isDark),
          _buildAITab(isDark),
        ],
      ),
    );
  }

  Widget _buildHollandTab(bool isDark) {
    if (_isLoadingData) return Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(LocalizationService().currentLanguage == 'vi' ? 'Trắc nghiệm Holland (RIASEC)' : 'Holland Test (RIASEC)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        SizedBox(height: 10),
        ..._hollandData.keys.map((group) {
          final List<dynamic> questions = _hollandData[group] ?? [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(LocalizationService().currentLanguage == 'vi' ? 'Nhóm $group' : 'Group $group', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              ...questions.map((q) => CheckboxListTile(
                title: Text(q['text'].toString()),
                value: _hollandAnswers['${q['code']}'] ?? false,
                onChanged: (v) => setState(() => _hollandAnswers['${q['code']}'] = v ?? false),
              )),
            ],
          );
        }),
        SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {
            Map<String, int> scores = {'R':0, 'I':0, 'A':0, 'S':0, 'E':0, 'C':0};
            _hollandData.forEach((group, questions) {
              for (var q in questions) {
                if (_hollandAnswers['${q['code']}'] == true) {
                  scores[group] = (scores[group] ?? 0) + 1;
                }
              }
            });
            _saveTest('HOLLAND', scores);
          },
          style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
          child: Text(LocalizationService().currentLanguage == 'vi' ? 'Lưu vào Hệ thống & Xem kết quả' : 'Save & View Results', style: TextStyle(color: Colors.white)),
        )
      ],
    );
  }

  Widget _buildMITab(bool isDark) {
    if (_isLoadingData) return Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(LocalizationService().currentLanguage == 'vi' ? 'Trắc nghiệm Đa trí tuệ (MI)' : 'Multiple Intelligences (MI)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        SizedBox(height: 10),
        ..._miData.keys.map((group) {
          final List<dynamic> questions = _miData[group] ?? [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(LocalizationService().currentLanguage == 'vi' ? 'Nhóm $group' : 'Group $group', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              ...questions.map((q) => CheckboxListTile(
                title: Text(q['text'].toString()),
                value: _miAnswers['${q['code']}'] ?? false,
                onChanged: (v) => setState(() => _miAnswers['${q['code']}'] = v ?? false),
              )),
            ],
          );
        }),
        SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {
            Map<String, int> scores = {};
            _miData.forEach((group, questions) {
              scores[group] = 0;
              for (var q in questions) {
                if (_miAnswers['${q['code']}'] == true) {
                  scores[group] = (scores[group] ?? 0) + 1;
                }
              }
            });
            _saveTest('MI', scores);
          },
          style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
          child: Text(LocalizationService().currentLanguage == 'vi' ? 'Lưu vào Hệ thống & Xem kết quả' : 'Save & View Results', style: TextStyle(color: Colors.white)),
        )
      ],
    );
  }

  Widget _buildDISCTab(bool isDark) {
    if (_isLoadingData) return Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(LocalizationService().currentLanguage == 'vi' ? 'Nhận diện Hành vi (DISC)' : 'Behavioral Test (DISC)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ..._discData.keys.map((group) {
          final List<dynamic> questions = _discData[group] ?? [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(LocalizationService().currentLanguage == 'vi' ? 'Nhóm $group' : 'Group $group', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              ...questions.map((q) => CheckboxListTile(
                title: Text(q.toString()),
                value: _discAnswers['$group-$q'] ?? false,
                onChanged: (v) => setState(() => _discAnswers['$group-$q'] = v ?? false),
              )),
            ],
          );
        }),
        ElevatedButton(
          onPressed: () {
            Map<String, int> scores = {};
            _discData.forEach((group, questions) {
              scores[group] = 0;
              for (var q in questions) {
                if (_discAnswers['$group-$q'] == true) {
                  scores[group] = (scores[group] ?? 0) + 1;
                }
              }
            });
            _saveTest('DISC', scores);
          },
          style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
          child: Text(LocalizationService().currentLanguage == 'vi' ? 'Lưu vào Hệ thống & Xem kết quả' : 'Save & View Results', style: TextStyle(color: Colors.white)),
        )
      ],
    );
  }

  Widget _buildMTVTTab(bool isDark) {
    if (_isLoadingData) return Center(child: CircularProgressIndicator());
    final isVi = LocalizationService().currentLanguage == 'vi';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(isVi ? 'Bài test Động lực (MTVT)' : 'Motivators Test (MTVT)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        SizedBox(height: 10),
        ..._mtvtData.keys.map((group) {
          final hList = _mtvtData[group]['h'] ?? [];
          final lList = _mtvtData[group]['l'] ?? [];
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isVi ? 'Động lực: $group' : 'Motivator: $group', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: primaryColor)),
                  SizedBox(height: 10),
                  Text(isVi ? 'ĐỘNG LỰC CAO' : 'HIGH MOTIVATION', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                  ...hList.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final q = entry.value;
                    return CheckboxListTile(
                      title: Text(q.toString(), style: TextStyle(fontSize: 14)),
                      value: _mtvtAnswers['${group}_h_$idx'] ?? false,
                      onChanged: (v) => setState(() => _mtvtAnswers['${group}_h_$idx'] = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    );
                  }),
                  SizedBox(height: 10),
                  Text(isVi ? 'ĐỘNG LỰC THẤP' : 'LOW MOTIVATION', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  ...lList.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final q = entry.value;
                    return CheckboxListTile(
                      title: Text(q.toString(), style: TextStyle(fontSize: 14)),
                      value: _mtvtAnswers['${group}_l_$idx'] ?? false,
                      onChanged: (v) => setState(() => _mtvtAnswers['${group}_l_$idx'] = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    );
                  }),
                ],
              ),
            ),
          );
        }),
        ElevatedButton(
          onPressed: () {
            Map<String, int> scores = {};
            _mtvtData.forEach((group, _) { scores[group] = 50; });
            _mtvtData.forEach((group, items) {
              final hList = items['h'] ?? [];
              for (int i=0; i<hList.length; i++) {
                if (_mtvtAnswers['${group}_h_$i'] == true) scores[group] = (scores[group] ?? 50) + 5;
              }
              final lList = items['l'] ?? [];
              for (int i=0; i<lList.length; i++) {
                if (_mtvtAnswers['${group}_l_$i'] == true) scores[group] = (scores[group] ?? 50) - 5;
              }
            });
            _saveTest('MTVT', scores);
          },
          style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
          child: Text(isVi ? 'Lưu vào Hệ thống & Xem kết quả' : 'Save & View Results', style: TextStyle(color: Colors.white)),
        ),
        SizedBox(height: 20),
      ],
    );
  }

  Widget _buildHistoryTab(bool isDark) {
    final cardBg = isDark ? const Color(0xFF121212) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF1D1D1F);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: _fetchHistory,
                icon: Icon(Icons.refresh),
                label: Text(LocalizationService().currentLanguage == 'vi' ? 'Làm mới' : 'Refresh'),
              ),
              ElevatedButton.icon(
                onPressed: _deleteAllHistory,
                icon: Icon(Icons.delete),
                label: Text(LocalizationService().currentLanguage == 'vi' ? 'Xóa tất cả' : 'Delete All'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingHistory
              ? Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _historyData.length,
                  itemBuilder: (context, index) {
                    final item = _historyData[index];
                    return Card(
                      color: cardBg,
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        title: Text('${item['test_type']}', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                        subtitle: Text('${item['created_at']}\n${item['result_data']}', style: TextStyle(color: textColor)),
                        trailing: IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteHistory(item['id']),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAITab(bool isDark) {
    final textColor = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF1D1D1F);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: _isLoadingAI ? null : _callAIProxy,
            icon: _isLoadingAI ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Icon(Icons.auto_awesome),
            label: Text(LocalizationService().currentLanguage == 'vi' ? 'Gọi AI Phân tích' : 'Call AI Analysis'),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12)
            ),
          ),
          SizedBox(height: 20),
          Expanded(
            child: _aiAdvice.isEmpty
                ? Center(child: Text(LocalizationService().currentLanguage == 'vi' ? 'Bấm nút để gọi AI tư vấn' : 'Click to get AI advice', style: TextStyle(color: textColor)))
                : SingleChildScrollView(
                    child: MarkdownBody(
                      data: _aiAdvice,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(color: textColor, fontSize: 15),
                        h3: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
                        listBullet: TextStyle(color: textColor),
                        strong: TextStyle(color: textColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                    // Alternatively use flutter_markdown:
                    // MarkdownBody(data: _aiAdvice)
                  ),
          )
        ],
      ),
    );
  }
}