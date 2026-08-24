import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

// ============================================================================
// 1. LÕI CUSTOM CONTROLLER (VẼ GẠCH ĐỎ NGAY TRONG LÚC GÕ CHỮ)
// ============================================================================
class GrammarTextController extends TextEditingController {
  List<_MatchIssue> issues = [];

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (issues.isEmpty) {
      return TextSpan(style: style, text: text);
    }

    List<InlineSpan> spans = [];
    int currentPos = 0;

    for (var issue in issues) {
      if (issue.start >= currentPos && issue.end <= text.length) {
        spans.add(TextSpan(text: text.substring(currentPos, issue.start), style: style));
        
        spans.add(TextSpan(
          text: text.substring(issue.start, issue.end),
          style: style?.copyWith(
            color: Colors.redAccent,
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.wavy,
            decorationColor: Colors.redAccent,
            backgroundColor: const Color(0x22F44336),
          ),
        ));
        currentPos = issue.end;
      }
    }
    if (currentPos < text.length) {
      spans.add(TextSpan(text: text.substring(currentPos), style: style));
    }

    return TextSpan(style: style, children: spans);
  }
}

// ============================================================================
// 2. MÀN HÌNH CHÍNH
// ============================================================================
class GrammarCheckScreen extends StatefulWidget {
  const GrammarCheckScreen({super.key});

  @override
  State<GrammarCheckScreen> createState() => _GrammarCheckScreenState();
}

class _GrammarCheckScreenState extends State<GrammarCheckScreen> {
  late GrammarTextController _textController;
  
  bool _isScanning = false;
  String _currentLang = 'en'; 
  
  List<dynamic> _apiIssues = []; 
  
  String _lastText = '';
  bool _isProgrammaticEdit = false; 
  bool _isSheetOpen = false;

  @override
  void initState() {
    super.initState();
    _textController = GrammarTextController();
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_isProgrammaticEdit) return; 

    if (_textController.text != _lastText) {
      if (_textController.issues.isNotEmpty) {
        setState(() {
          _textController.issues.clear();
        });
      }
      _lastText = _textController.text;
    } 
    else {
      if (!_isSheetOpen && _textController.issues.isNotEmpty && _textController.selection.isValid) {
        
        int start = _textController.selection.start;
        int end = _textController.selection.end;
        
        for (var issue in _textController.issues) {
          if ((start >= issue.start && start <= issue.end) || (end >= issue.start && end <= issue.end)) {
            
            // 1. KHÓA THEO DÕI: Tránh việc code tự hiểu lầm là người dùng đang gõ
            _isProgrammaticEdit = true;
            
            // 2. TRIỆT TIÊU VÙNG BÔI ĐEN: Ép vùng chọn dồn về 1 điểm (cuối chữ bị lỗi)
            // Cú chốt này khiến 2 giọt nước xanh bị "khai tử" hoàn toàn khi tắt BottomSheet
            _textController.selection = TextSelection.collapsed(offset: issue.end);
            
            // 3. TẮT BÀN PHÍM
            FocusManager.instance.primaryFocus?.unfocus(); 
            
            // 4. MỞ KHÓA & HIỆN POPUP
            _isProgrammaticEdit = false;

            _showCorrectionSheet(issue);
            break;
          }
        }
      }
    }
  }

  Future<void> _scanText() async {
    if (_textController.text.trim().isEmpty) return;
    setState(() {
      _isScanning = true;
      _textController.issues.clear(); 
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';

      Dio dio = Dio();
      if (sessionId.isNotEmpty) dio.options.headers['Cookie'] = 'PHPSESSID=$sessionId';

      final res = await dio.post(
        '${AppConfig.baseUrl}/grammar_check.php?local_api=1',
        data: {'user_text': _textController.text, 'language': _currentLang},
      );

      if (res.statusCode == 200 && res.data['status'] == 'success') {
        _apiIssues = res.data['issues'] ?? [];
        if (_apiIssues.isEmpty) {
          _showMsg('Hoàn hảo! Không phát hiện lỗi nào.', Colors.green);
        } else {
          _processMatches(); 
          _showMsg('Phát hiện ${_textController.issues.length} lỗi. Chạm vào chữ gạch đỏ để sửa.', Colors.orange);
        }
      } else {
        _showMsg(res.data['msg'] ?? 'Lỗi từ máy chủ AI', Colors.red);
      }
    } catch (e) {
      _showMsg('Lỗi kết nối đến máy chủ API', Colors.red);
    }
    setState(() => _isScanning = false);
  }

  void _processMatches() {
    List<_MatchIssue> newIssues = [];
    String text = _textController.text;

    for (var issue in _apiIssues) {
      String wrong = issue['wrong'];
      String correct = issue['correct'];
      String explanation = issue['explanation'] ?? '';
      
      RegExp regExp = RegExp(r'\b' + RegExp.escape(wrong) + r'\b', caseSensitive: false, unicode: true);
      Iterable<RegExpMatch> matches = regExp.allMatches(text);
      
      for (var match in matches) {
        newIssues.add(_MatchIssue(wrong, correct, match.start, match.end, explanation));
      }
    }
    newIssues.sort((a, b) => a.start.compareTo(b.start));
    
    setState(() {
      _textController.issues = newIssues;
      _lastText = _textController.text;
    });
  }

  void _fixIssue(_MatchIssue issue) {
    Navigator.pop(context); 
    
    _isProgrammaticEdit = true; 
    
    String currentText = _textController.text;
    String newText = currentText.replaceRange(issue.start, issue.end, issue.correct);
    
    int lengthDiff = issue.correct.length - issue.wrong.length;
    
    setState(() {
      _textController.text = newText;
      _textController.issues.remove(issue);
      
      for (var m in _textController.issues) {
        if (m.start > issue.start) {
          m.start += lengthDiff;
          m.end += lengthDiff;
        }
      }
      
      _lastText = newText;
    });

    _textController.selection = TextSelection.collapsed(offset: issue.start + issue.correct.length);
    _isProgrammaticEdit = false; 

    if (_textController.issues.isEmpty) {
      _showMsg('Đã sửa xong toàn bộ lỗi!', Colors.green);
    }
  }

  void _showMsg(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  void _showCorrectionSheet(_MatchIssue issue) {
    _isSheetOpen = true; 
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor, // Hỗ trợ màu nền theo Theme
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.blue),
                SizedBox(width: 8),
                Text('Đề xuất từ AI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Text(issue.wrong, style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.red, fontSize: 18)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Icon(Icons.arrow_right_alt, color: Colors.grey)),
                Text(issue.correct, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 18)),
              ],
            ),
            if (issue.explanation.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(issue.explanation, style: TextStyle(fontSize: 14, color: isDark ? Colors.grey.shade300 : Colors.black87, fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 25),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Bỏ qua', style: TextStyle(color: Colors.grey)),
                  ),
                ),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
                    onPressed: () => _fixIssue(issue),
                    child: const Text('Sửa lỗi này'),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    ).then((_) {
      _isSheetOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Theme.of(context).scaffoldBackgroundColor : Colors.grey.shade50,
      appBar: AppBar(title: const Text('Trợ lý Grammar AI')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300)
              ),
              child: Row(
                children: [
                  const Icon(Icons.language, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _currentLang,
                        dropdownColor: Theme.of(context).cardColor,
                        items: const [
                          DropdownMenuItem(value: 'en', child: Text('English (Tiếng Anh)')),
                          DropdownMenuItem(value: 'vi', child: Text('Vietnamese (Tiếng Việt)')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              _currentLang = v;
                              _textController.issues.clear(); 
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // KHUNG NHẬP LIỆU (Tự đổi màu sáng/tối)
            TextField(
              controller: _textController,
              maxLines: 12,
              style: TextStyle(fontSize: 16, color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: _currentLang == 'en' ? 'Type your English paragraph here (Ex: I loves Duong)...' : 'Nhập đoạn văn (VD: hôm lay tôi nàm bài suất xắc)...',
                hintStyle: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey.shade400),
                filled: true,
                fillColor: Theme.of(context).cardColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: _isScanning ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.auto_awesome),
                label: Text(_isScanning ? 'Đang phân tích AI...' : 'Quét lỗi (Scan)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                onPressed: _isScanning ? null : _scanText,
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _MatchIssue {
  final String wrong;
  final String correct;
  int start;
  int end;
  String explanation;
  _MatchIssue(this.wrong, this.correct, this.start, this.end, this.explanation);
}