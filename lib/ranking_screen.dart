import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  bool _isLoading = true;
  String _week = '';
  Map<String, List<dynamic>> _groupedRanking = {};
  String _myClassName = '';

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _myClassName = prefs.getString('class_name') ?? '');
    _fetchRankingData();
  }

  Future<void> _fetchRankingData() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';

      String url = 'https://qlnn.testifiyonline.xyz/api/ranking_api';
      if (_week.isNotEmpty) url += '?week=$_week';

      final response = await http.get(Uri.parse(url), headers: {'Cookie': 'PHPSESSID=$sessionId'});
      final data = jsonDecode(response.body);

      if (data['status'] == 'success') {
        Map<String, dynamic> rawGroups = data['grouped_ranking'];
        setState(() {
          if (_week.isEmpty && data['current_week'] != null) {
            _week = data['current_week'].toString(); 
          }
          _groupedRanking = rawGroups.map((key, value) => MapEntry(key, List<dynamic>.from(value)));
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _getScoreColor(double score) {
    if (score >= 9.0) return Colors.green; 
    if (score >= 7.0) return Colors.orange;
    return Colors.red;
  }

  Widget _getRankWidget(int rank) {
    if (rank == 1) return const Icon(Icons.workspace_premium, color: Colors.amber, size: 30);
    if (rank == 2) return const Icon(Icons.workspace_premium, color: Colors.grey, size: 28);
    if (rank == 3) return const Icon(Icons.workspace_premium, color: Color(0xFFCD7F32), size: 26); 
    
    return Container(width: 28, height: 28, alignment: Alignment.center,
      decoration: BoxDecoration(color: Colors.grey.shade200, shape: BoxShape.circle),
      child: Text(rank.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Bảng Xếp Hạng', style: TextStyle(fontWeight: FontWeight.bold))),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Text('Chọn thời gian: ', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10), 
                          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(8)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _week.isEmpty ? null : _week, 
                              hint: const Text('Chọn tuần'),
                              isExpanded: true, 
                              items: List.generate(35, (i) => (i + 1).toString()).map((w) => DropdownMenuItem(value: w, child: Text('Tuần $w'))).toList(),
                              onChanged: (val) { 
                                if (val != null) {
                                  setState(() => _week = val); 
                                  _fetchRankingData(); 
                                }
                              },
                            )
                          ),
                        )
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: _groupedRanking.isEmpty 
                    ? const Center(child: Text("Chưa có dữ liệu cho tuần này"))
                    : RefreshIndicator(
                        onRefresh: _fetchRankingData,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _groupedRanking.keys.length,
                          itemBuilder: (context, index) {
                            String groupName = _groupedRanking.keys.elementAt(index);
                            List<dynamic> classes = _groupedRanking[groupName]!;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 15, bottom: 10, left: 4),
                                  child: Row(
                                    children: [
                                      Icon(Icons.emoji_events, color: Theme.of(context).colorScheme.primary, size: 20),
                                      const SizedBox(width: 8),
                                      Text('Nhóm Thi Đua $groupName', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
                                    ],
                                  )
                                ),
                                ...classes.map((cls) {
                                  final tbScore = double.tryParse(cls['tb'].toString()) ?? 0.0;
                                  bool isMyClass = cls['class_name'] == _myClassName;

                                  return Card(
                                    elevation: isMyClass ? 4 : 1,
                                    margin: const EdgeInsets.only(bottom: 8),
                                    color: isMyClass ? Theme.of(context).colorScheme.primary.withOpacity(0.08) : null,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: BorderSide(color: isMyClass ? Theme.of(context).colorScheme.primary : (isDark ? Colors.grey.shade800 : Colors.grey.shade200), width: isMyClass ? 2 : 1),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      child: Row(
                                        children: [
                                          Container(width: 35, alignment: Alignment.center, child: _getRankWidget(cls['rank'])),
                                          const SizedBox(width: 12),
                                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                              Text(cls['class_name'], style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isMyClass ? Theme.of(context).colorScheme.primary : (isDark ? Colors.white : Colors.black87))),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Text('NN: ${cls['nn']}', style: const TextStyle(fontSize: 13, color: Colors.blueGrey, fontWeight: FontWeight.w600)),
                                                  const Text('  •  ', style: TextStyle(color: Colors.grey)),
                                                  Text('HT: ${cls['ht']}', style: const TextStyle(fontSize: 13, color: Colors.blueGrey, fontWeight: FontWeight.w600)),
                                                ],
                                              )
                                          ])),
                                          Container(width: 65, padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8), alignment: Alignment.center,
                                            decoration: BoxDecoration(color: _getScoreColor(tbScore).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                                            child: Text(cls['tb'], style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _getScoreColor(tbScore))),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                                const SizedBox(height: 10),
                              ],
                            );
                          },
                        ),
                      ),
                )
              ],
            ),
    );
  }
}