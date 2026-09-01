import 'dart:convert';
import 'package:flutter/material.dart';
import 'localization_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/liquid_glass_container.dart';
import 'config.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  bool _isLoading = true;
  String _filterType = 'week';
  String _filterValue = '';
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

      String url = '${AppConfig.baseUrl}/api/ranking_api';
      if (_filterValue.isNotEmpty) url += '?$_filterType=$_filterValue';

      final response = await AppConfig.client.get(Uri.parse(url), headers: {'Cookie': 'PHPSESSID=$sessionId'});
      final data = jsonDecode(response.body);

      if (data['status'] == 'success') {
        Map<String, dynamic> rawGroups = data['grouped_ranking'];
        setState(() {
          if (_filterValue.isEmpty && _filterType == 'week' && data['current_week'] != null) {
            _filterValue = data['current_week'].toString(); 
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
    if (rank == 1) return Icon(Icons.workspace_premium, color: Colors.amber, size: 30);
    if (rank == 2) return Icon(Icons.workspace_premium, color: Colors.grey, size: 28);
    if (rank == 3) return Icon(Icons.workspace_premium, color: Color(0xFFCD7F32), size: 26); 
    
    return Container(width: 28, height: 28, alignment: Alignment.center,
      decoration: BoxDecoration(color: Colors.grey.shade200, shape: BoxShape.circle),
      child: Text(rank.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
    );
  }

  List<DropdownMenuItem<String>> _getFilterItems() {
    if (_filterType == 'week') return List.generate(35, (i) => (i + 1).toString()).map((w) => DropdownMenuItem(value: w, child: Text(LocalizationService().currentLanguage == 'vi' ? 'Tuần $w' : 'Week $w'))).toList();
    if (_filterType == 'month') return List.generate(12, (i) => (i + 1).toString()).map((m) => DropdownMenuItem(value: m, child: Text(LocalizationService().currentLanguage == 'vi' ? 'Tháng $m' : 'Month $m'))).toList();
    if (_filterType == 'semester') return ['1', '2'].map((s) => DropdownMenuItem(value: s, child: Text(LocalizationService().currentLanguage == 'vi' ? 'Học kỳ $s' : 'Semester $s'))).toList();
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text(LocalizationService().currentLanguage == 'vi' ? 'Bảng Xếp Hạng' : 'Ranking', style: TextStyle(fontWeight: FontWeight.bold))),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Text(LocalizationService().currentLanguage == 'vi' ? 'Chọn thời gian: ' : 'Select time: ', style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10), 
                          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(8)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _filterType, 
                              isExpanded: true, 
                              items: [
                                DropdownMenuItem(value: 'week', child: Text(LocalizationService().currentLanguage == 'vi' ? 'Tuần' : 'Week')),
                                DropdownMenuItem(value: 'month', child: Text(LocalizationService().currentLanguage == 'vi' ? 'Tháng' : 'Month')),
                                DropdownMenuItem(value: 'semester', child: Text(LocalizationService().currentLanguage == 'vi' ? 'Kỳ' : 'Semester')),
                                DropdownMenuItem(value: 'year', child: Text(LocalizationService().currentLanguage == 'vi' ? 'Năm' : 'Year')),
                              ],
                              onChanged: (val) { 
                                if (val != null) {
                                  setState(() {
                                    _filterType = val;
                                    _filterValue = '';
                                  }); 
                                  if (val == 'year') _fetchRankingData();
                                }
                              },
                            )
                          ),
                        )
                      ),
                      SizedBox(width: 10),
                      if (_filterType != 'year') Expanded(
                        flex: 3,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10), 
                          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(8)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _filterValue.isEmpty ? null : _filterValue, 
                              hint: Text(LocalizationService().currentLanguage == 'vi' ? 'Chọn' : 'Select'),
                              isExpanded: true, 
                              items: _getFilterItems(),
                              onChanged: (val) { 
                                if (val != null) {
                                  setState(() => _filterValue = val); 
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
                    ? Center(child: Text(LocalizationService().currentLanguage == 'vi' ? "Chưa có dữ liệu cho tuần này" : "No data for this week"))
                    : RefreshIndicator(
                        onRefresh: _fetchRankingData,
                        child: ListView.builder(
                          padding: const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 120), // FIX: Prevent bottom nav overlap
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
                                      SizedBox(width: 8),
                                      Text(LocalizationService().currentLanguage == 'vi' ? 'Nhóm Thi Đua $groupName' : 'Competition Group $groupName', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
                                    ],
                                  )
                                ),
                                ...classes.map((cls) {
                                  final tbScore = double.tryParse(cls['tb'].toString()) ?? 0.0;
                                  bool isMyClass = cls['class_name'] == _myClassName;

                                  return LiquidGlassContainer(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: isMyClass ? Theme.of(context).colorScheme.primary : (isDark ? Colors.grey.shade800 : Colors.grey.shade200), width: isMyClass ? 2 : 1),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      child: Row(
                                        children: [
                                          Container(width: 35, alignment: Alignment.center, child: _getRankWidget(cls['rank'])),
                                          SizedBox(width: 12),
                                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                              Text(cls['class_name'], style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isMyClass ? Theme.of(context).colorScheme.primary : (isDark ? Colors.white : Colors.black87))),
                                              SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Text(LocalizationService().currentLanguage == 'vi' ? 'NN: ${cls['nn'] ?? 0}' : 'Behav: ${cls['nn'] ?? 0}', style: const TextStyle(fontSize: 13, color: Colors.blueGrey, fontWeight: FontWeight.w600)),
                                                  Text('  •  ', style: TextStyle(color: Colors.grey)),
                                                  Text(LocalizationService().currentLanguage == 'vi' ? 'HT: ${cls['ht'] ?? 0}' : 'Acad: ${cls['ht'] ?? 0}', style: const TextStyle(fontSize: 13, color: Colors.blueGrey, fontWeight: FontWeight.w600)),
                                                ],
                                              ),
                                              SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  Text(LocalizationService().currentLanguage == 'vi' ? 'VPBS: ${cls['vpbs'] ?? 0}' : 'Pen: ${cls['vpbs'] ?? 0}', style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                                                  Text(' • ', style: TextStyle(color: Colors.grey)),
                                                  Text(LocalizationService().currentLanguage == 'vi' ? 'Tổng tiết: ${cls["tong_tiet"] ?? 0}' : 'Total periods: ${cls["tong_tiet"] ?? 0}', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                                                  Text(' • ', style: TextStyle(color: Colors.grey)),
                                                  Text(LocalizationService().currentLanguage == 'vi' ? 'Thưởng: ${cls["diem_thuong"] ?? 0}' : 'Bonus: ${cls["diem_thuong"] ?? 0}', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                                                ],
                                              )
                                          ])),
                                          Container(width: 65, padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8), alignment: Alignment.center,
                                            decoration: BoxDecoration(color: _getScoreColor(tbScore).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                                            child: Text(cls['tb'], style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _getScoreColor(tbScore))),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                                SizedBox(height: 10),
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