import 'package:flutter/material.dart';

class HollandTestScreen extends StatefulWidget {
  const HollandTestScreen({super.key});

  @override
  State<HollandTestScreen> createState() => _HollandTestScreenState();
}

class _HollandTestScreenState extends State<HollandTestScreen> {
  // Bộ câu hỏi mẫu (Bạn có thể thêm nhiều hơn)
  final List<Map<String, dynamic>> _questions = [
    {'q': 'Tôi thích sửa chữa máy móc, đồ điện tử.', 'type': 'R'},
    {'q': 'Tôi thích các hoạt động thể thao, làm việc ngoài trời.', 'type': 'R'},
    {'q': 'Tôi thích làm các thí nghiệm khoa học.', 'type': 'I'},
    {'q': 'Tôi thích phân tích các vấn đề phức tạp.', 'type': 'I'},
    {'q': 'Tôi thích sáng tác nghệ thuật, vẽ, âm nhạc.', 'type': 'A'},
    {'q': 'Tôi có trí tưởng tượng phong phú.', 'type': 'A'},
    {'q': 'Tôi thích giảng giải, hướng dẫn người khác.', 'type': 'S'},
    {'q': 'Tôi thích tham gia các hoạt động tình nguyện.', 'type': 'S'},
    {'q': 'Tôi thích thuyết phục, đàm phán với người khác.', 'type': 'E'},
    {'q': 'Tôi thích khởi xướng và quản lý các dự án.', 'type': 'E'},
    {'q': 'Tôi thích công việc liên quan đến tính toán, sổ sách.', 'type': 'C'},
    {'q': 'Tôi là người làm việc có quy củ, ngăn nắp.', 'type': 'C'},
  ];

  final Map<int, bool> _answers = {};
  bool _showResult = false;
  List<MapEntry<String, int>> _topTraits = [];

  void _calculateResult() {
    Map<String, int> scores = {'R': 0, 'I': 0, 'A': 0, 'S': 0, 'E': 0, 'C': 0};
    _answers.forEach((index, isYes) {
      if (isYes) scores[_questions[index]['type']] = (scores[_questions[index]['type']] ?? 0) + 1;
    });

    var sortedScores = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    setState(() {
      _topTraits = sortedScores.take(3).toList();
      _showResult = true;
    });
  }

  String _getTraitName(String code) {
    switch (code) {
      case 'R': return 'Kỹ thuật (Realistic)';
      case 'I': return 'Nghiên cứu (Investigative)';
      case 'A': return 'Nghệ thuật (Artistic)';
      case 'S': return 'Xã hội (Social)';
      case 'E': return 'Quản lý (Enterprising)';
      case 'C': return 'Nghiệp vụ (Conventional)';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trắc nghiệm Holland (Nghề nghiệp)')),
      body: _showResult ? _buildResult() : _buildQuiz(),
    );
  }

  Widget _buildQuiz() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Hãy chọn "Đúng" với những câu mô tả đúng về bạn:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 20),
        ..._questions.asMap().entries.map((e) => Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: CheckboxListTile(
            title: Text(e.value['q']),
            value: _answers[e.key] ?? false,
            activeColor: Colors.blue,
            onChanged: (val) => setState(() => _answers[e.key] = val!),
          ),
        )),
        const SizedBox(height: 20),
        FilledButton(onPressed: _calculateResult, child: const Text('XEM KẾT QUẢ')),
      ],
    );
  }

  Widget _buildResult() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.psychology, size: 80, color: Colors.blue),
          const SizedBox(height: 20),
          const Text('ĐẶC ĐIỂM NỔI TRỘI CỦA BẠN LÀ:', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          ..._topTraits.map((t) => Container(
            margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade200)),
            child: Text(_getTraitName(t.key), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
          )),
          const Spacer(),
          OutlinedButton(onPressed: () => setState(() { _showResult = false; _answers.clear(); }), child: const Text('Làm lại bài test')),
        ],
      ),
    );
  }
}