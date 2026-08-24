import 'dart:convert';
import 'package:flutter/material.dart';
import 'localization_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/liquid_glass_container.dart';
import 'config.dart';

class StudentViolationsScreen extends StatefulWidget {
  const StudentViolationsScreen({super.key});
  @override
  State<StudentViolationsScreen> createState() => _StudentViolationsScreenState();
}

class _StudentViolationsScreenState extends State<StudentViolationsScreen> {
  bool _isLoading = true;
  int _week = 0;
  List _myVios = [];
  List _classVios = [];
  int _totalMinus = 0;
  List _matrixData = [];
  int _matrixTotal = 0;

  @override
  void initState() { super.initState(); _fetchData(); }

  Future<void> _fetchData([int? weekParam]) async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    
    // Đã trỏ đúng về student_violations_api
    String url = '${AppConfig.baseUrl}/api/student_violations_api';
    if (weekParam != null) url += '?week=$weekParam';
    
    try {
      final res = await http.get(Uri.parse(url), headers: {'Cookie': 'PHPSESSID=${prefs.getString('phpsessid')}'});
      final data = jsonDecode(res.body);
      if (data['status'] == 'success') {
        setState(() {
          _week = data['week']; _myVios = data['my_vios']; _classVios = data['class_vios'];
          _totalMinus = data['total_minus']; _matrixData = data['matrix_data'];
          _matrixTotal = data['matrix_total']; _isLoading = false;
        });
      }
    } catch (e) { setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(LocalizationService().currentLanguage == 'vi' ? 'Lỗi Vi Phạm Của Tôi' : 'My Violations', style: TextStyle(fontWeight: FontWeight.bold))),
      body: _isLoading ? Center(child: CircularProgressIndicator()) : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(icon: Icon(Icons.chevron_left), onPressed: () => _fetchData(_week - 1)),
              Container(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(20)), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Tuần $_week' : 'Tuan $_week', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              IconButton(icon: Icon(Icons.chevron_right), onPressed: () => _fetchData(_week + 1)),
            ],
          ),
          SizedBox(height: 20),

          Text('LỖI CỦA TÔI', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
          SizedBox(height: 10),
          if (_myVios.isEmpty) 
            LiquidGlassContainer(
              padding: const EdgeInsets.all(15), 
              borderRadius: BorderRadius.circular(10),
              child: Row(children: [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 10), Text(LocalizationService().currentLanguage == 'vi' ? 'Tuyệt vời! Bạn không có vi phạm.' : 'Tuyet voi! Ban khong co vi pham.', style: TextStyle(color: Colors.green))])
            )
          else 
            ..._myVios.map((v) => LiquidGlassContainer(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(title: Text(v['recorded_violation_name'], style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(v['date_created']), trailing: Text('-${v['recorded_points']}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18)))
            )),
          
          SizedBox(height: 25),
          Text('LỖI CHUNG CỦA LỚP', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
          SizedBox(height: 10),
          if (_classVios.isEmpty)
             LiquidGlassContainer(
               padding: const EdgeInsets.all(15), 
               borderRadius: BorderRadius.circular(10), 
               child: Row(children: [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 10), Text(LocalizationService().currentLanguage == 'vi' ? 'Lớp không có lỗi chung.' : 'The class has no common violations.', style: TextStyle(color: Colors.green))])
             )
          else
             ..._classVios.map((v) => LiquidGlassContainer(
               margin: const EdgeInsets.only(bottom: 8),
               child: ListTile(title: Text(v['recorded_violation_name'], style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(v['date_created']), trailing: Text('-${v['recorded_points']}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 18)))
             )),

          SizedBox(height: 25),

          Text(LocalizationService().currentLanguage == 'vi' ? 'SỔ ĐẦU BÀI' : 'SO DAU BAI', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          SizedBox(height: 10),
          LiquidGlassContainer(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 20,
                columns: [
                  DataColumn(label: Text(LocalizationService().currentLanguage == 'vi' ? 'Thứ' : 'Day')), DataColumn(label: Text('SS')), DataColumn(label: Text('VS')),
                  DataColumn(label: Text('CSVC')), DataColumn(label: Text('TB')), DataColumn(label: Text('XE')),
                  DataColumn(label: Text('DP')), DataColumn(label: Text('SV')), DataColumn(label: Text('THE')),
                  DataColumn(label: Text('DT')), DataColumn(label: Text(LocalizationService().currentLanguage == 'vi' ? 'Tổng' : 'Tong')),
                ],
                rows: _matrixData.map<DataRow>((row) {
                  List<DataCell> cells = [DataCell(Text(row['label'].toString(), style: const TextStyle(fontWeight: FontWeight.bold)))];
                  for (var score in row['scores']) {
                    cells.add(DataCell(Text(score['val'].toString(), style: TextStyle(color: score['val'] < score['max'] ? Colors.red : Colors.black, fontWeight: score['val'] < score['max'] ? FontWeight.bold : FontWeight.normal))));
                  }
                  cells.add(DataCell(Text(row['total'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))));
                  return DataRow(cells: cells);
                }).toList(),
              ),
            ),
          ),
          ..._matrixData.where((row) => row['notes'] != null && row['notes'].toString().isNotEmpty).map((row) => 
            LiquidGlassContainer(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, size: 16, color: Colors.red),
                  SizedBox(width: 8),
                  Expanded(child: Text('${row['label']}: ${row['notes']}', style: const TextStyle(color: Colors.red, fontSize: 13, fontStyle: FontStyle.italic))),
                ],
              )
            )
          ),
          Padding(padding: EdgeInsets.only(top: 8, right: 8), child: Align(alignment: Alignment.centerRight, child: Text(LocalizationService().currentLanguage == 'vi' ? 'TỔNG ĐIỂM: $_matrixTotal' : 'TONG DIEM: $_matrixTotal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.blue)))),
        ],
      ),
    );
  }
}