import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class BannedIpsScreen extends StatefulWidget {
  const BannedIpsScreen({super.key});

  @override
  State<BannedIpsScreen> createState() => _BannedIpsScreenState();
}

class _BannedIpsScreenState extends State<BannedIpsScreen> {
  bool _isLoading = true;
  List<dynamic> _ips = [];

  @override
  void initState() {
    super.initState();
    _fetchIps();
  }

  Future<void> _fetchIps() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      final response = await http.get(
        Uri.parse('https://qlnn.testifiyonline.xyz/api/banned_ips_api'),
        headers: {'Cookie': 'PHPSESSID=$sessionId'},
      );
      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        setState(() { _ips = data['data']; _isLoading = false; });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _unbanIp(int id, String ip) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xác nhận'), content: Text('Bạn muốn mở khóa cho IP $ip?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Mở khóa', style: TextStyle(color: Colors.red))),
        ],
      )
    );
    if (confirm != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      final response = await http.post(
        Uri.parse('https://qlnn.testifiyonline.xyz/api/banned_ips_api'),
        headers: {'Cookie': 'PHPSESSID=$sessionId', 'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'unban', 'id': id}),
      );
      final data = jsonDecode(response.body);
      if (data['status'] == 'success' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Đã mở khóa IP!'), backgroundColor: Colors.green));
        _fetchIps();
      }
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử khóa IP', style: TextStyle(fontWeight: FontWeight.bold))),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _ips.isEmpty 
          ? const Center(child: Text('Không có IP nào bị khóa.'))
          : RefreshIndicator(
              onRefresh: _fetchIps,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _ips.length,
                itemBuilder: (context, index) {
                  final item = _ips[index];
                  bool isExpired = item['is_expired'] ?? false;
                  
                  return Card(
                    elevation: 1, margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isExpired ? Colors.green.shade200 : Colors.red.shade200)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(item['ip_address'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: isExpired ? Colors.green.shade50 : Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                                child: Text(isExpired ? 'Đã hết hạn' : 'Đang khóa', style: TextStyle(color: isExpired ? Colors.green : Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                              )
                            ],
                          ),
                          const Divider(),
                          Text('Lý do: ${item['reason']}', style: TextStyle(color: Colors.grey.shade700)),
                          Text('Ngày khóa: ${item['banned_at']}'),
                          Text('Hết hạn: ${item['expires_at']}', style: TextStyle(fontWeight: FontWeight.bold, color: isExpired ? Colors.green : Colors.orange.shade700)),
                          if (!isExpired) ...[
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => _unbanIp(item['id'], item['ip_address']),
                                icon: const Icon(Icons.lock_open, color: Colors.red),
                                label: const Text('MỞ KHÓA NGAY', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                style: TextButton.styleFrom(backgroundColor: Colors.red.shade50),
                              ),
                            )
                          ]
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}