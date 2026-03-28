import 'package:flutter/material.dart';
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
        _adviceResult = result ?? "Xin lỗi, hiện tại AI không thể kết nối. Vui lòng thử lại sau.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Góc Tư Vấn AI', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: isDark ? Colors.purple.withOpacity(0.1) : Colors.purple.shade50,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Hãy chia sẻ vấn đề của bạn, AI Tâm lý học đường sẽ đưa ra lời khuyên dành cho bạn.',
              style: TextStyle(color: Colors.blueGrey, fontSize: 14),
            ),
            const SizedBox(height: 15),
            
            TextField(
              controller: _promptCtrl,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Ví dụ: Dạo này em cảm thấy áp lực học tập quá...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
            ),
            const SizedBox(height: 15),
            
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: _isLoading ? null : _submitPrompt,
                icon: _isLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send),
                label: Text(_isLoading ? 'ĐANG PHÂN TÍCH...' : 'GỬI CHO AI', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                style: FilledButton.styleFrom(backgroundColor: Colors.purple),
              ),
            ),
            const SizedBox(height: 30),

            if (_adviceResult != null)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? Colors.purple.withOpacity(0.1) : Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.purple.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.psychology, color: Colors.purple),
                        SizedBox(width: 8),
                        Text('AI Khuyên bạn:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple, fontSize: 16)),
                      ],
                    ),
                    const Divider(color: Colors.black12, height: 20),
                    Text(_adviceResult!, style: TextStyle(fontSize: 15, height: 1.5, color: isDark ? Colors.white70 : Colors.black87)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}