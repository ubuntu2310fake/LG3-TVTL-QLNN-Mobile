import 'localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'tvtl_service.dart';

class AiConsultingScreen extends StatefulWidget {
  const AiConsultingScreen({super.key});

  @override
  State<AiConsultingScreen> createState() => _AiConsultingScreenState();
}

class _AiConsultingScreenState extends State<AiConsultingScreen> {
  final TextEditingController _promptCtrl = TextEditingController();
  bool _isLoading = false;
  String? _adviceResult;

  Future<void> _submitPrompt() async {
    if (_promptCtrl.text.trim().isEmpty) return;
    
    FocusScope.of(context).unfocus();
    
    setState(() {
      _isLoading = true;
      _adviceResult = null; 
    });

    await TvtlService.ensurePythonLogin();
    final result = await TvtlService.askAIBot(_promptCtrl.text.trim());

    if (mounted) {
      setState(() {
        _isLoading = false;
        _adviceResult = result ?? (LocalizationService().currentLanguage == 'vi' ? "Xin lỗi, hiện tại AI không thể kết nối. Vui lòng thử lại sau." : "Sorry, AI is currently unreachable. Please try again later.");
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(LocalizationService().currentLanguage == 'vi' ? 'Góc Tư Vấn AI' : 'AI Counseling Corner', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: isDark ? Colors.purple.withValues(alpha: 0.1) : Colors.purple.shade50,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              LocalizationService().currentLanguage == 'vi' ? 'Hãy chia sẻ vấn đề của bạn, AI Tâm lý học đường sẽ đưa ra lời khuyên dành cho bạn.' : 'Please share your problems, School Psychology AI will give you advice.',
              style: TextStyle(color: Colors.blueGrey, fontSize: 14),
            ),
            SizedBox(height: 15),
            
            TextField(
              controller: _promptCtrl,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: LocalizationService().currentLanguage == 'vi' ? 'Ví dụ: Dạo này em cảm thấy áp lực học tập quá...' : 'Example: I have been feeling very stressed about my studies lately...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
            ),
            SizedBox(height: 15),
            
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: _isLoading ? null : _submitPrompt,
                icon: _isLoading 
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Icon(Icons.send),
                label: Text(_isLoading ? LocalizationService().currentLanguage == 'vi' ? 'ĐANG PHÂN TÍCH...' : 'ANALYZING...' : LocalizationService().currentLanguage == 'vi' ? 'GỬI CHO AI' : 'SEND TO AI', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                style: FilledButton.styleFrom(backgroundColor: Colors.purple),
              ),
            ),
            SizedBox(height: 30),

            if (_adviceResult != null)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? Colors.purple.withValues(alpha: 0.1) : Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.purple.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.psychology, color: Colors.purple),
                        SizedBox(width: 8),
                        Text(LocalizationService().currentLanguage == 'vi' ? 'AI Khuyên bạn:' : 'AI Advice:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple, fontSize: 16)),
                      ],
                    ),
                    const Divider(color: Colors.black12, height: 20),
                    MarkdownBody(
                      data: _adviceResult!,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 15, height: 1.5),
                        h3: TextStyle(color: Colors.purple, fontSize: 18, fontWeight: FontWeight.bold),
                        listBullet: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                        strong: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}