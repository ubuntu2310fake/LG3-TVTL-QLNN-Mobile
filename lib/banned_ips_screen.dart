import 'localization_service.dart';
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
        title: Text(LocalizationService().currentLanguage == 'vi' ? 'Xác nhận' : 'Confirm'), content: Text(LocalizationService().currentLanguage == 'vi' ? 'Bạn muốn mở khóa cho IP $ip?' : 'Do you want to unban IP $ip?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Hủy' : 'Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Mở khóa' : 'Mo khoa', style: TextStyle(color: Colors.red))),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? '✅ Đã mở khóa IP!' : '✅ Da mo khoa IP!'), backgroundColor: Colors.green));
        _fetchIps();
      }
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(LocalizationService().currentLanguage == 'vi' ? 'Lịch sử khóa IP' : 'Banned IPs History', style: TextStyle(fontWeight: FontWeight.bold))),
      body: _isLoading 
        ? Center(child: CircularProgressIndicator())
        : _ips.isEmpty 
          ? Center(child: Text(LocalizationService().currentLanguage == 'vi' ? 'Không có IP nào bị khóa.' : 'No banned IPs found.'))
          : RefreshIndicator(
              onRefresh: _fetchIps,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _ips.length,
                itemBuilder: (context, index) {
                  final item = _ips[index];
                  bool isExpired = item['is_expired'] ?? false;
                  
                  // Lấy chuỗi IP và xác định xem có phải IPv6 không (chứa dấu hai chấm)
                  String ipAddress = item['ip_address'] ?? '';
                  bool isIpv6 = ipAddress.contains(':');
                  
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
                            crossAxisAlignment: CrossAxisAlignment.start, // Đẩy lên trên cùng nếu text bị rớt dòng
                            children: [
                              // FIX LỖI OVERFLOW: Bọc vào Expanded để nó tự giới hạn chiều rộng
                              Expanded(
                                child: Text(
                                  ipAddress, 
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold, 
                                    fontSize: isIpv6 ? 13 : 18, // Thu nhỏ nếu là IPv6
                                    letterSpacing: isIpv6 ? 0.5 : 1 // Giảm khoảng cách chữ cho IPv6
                                  ),
                                  maxLines: 2, // Cho phép rớt xuống 2 dòng nếu quá dài
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(width: 10), // Giữ khoảng cách an toàn với nút Badge
                              
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: isExpired ? Colors.green.shade50 : Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                                child: Text(isExpired ? LocalizationService().currentLanguage == 'vi' ? 'Đã hết hạn' : 'Da het han' : LocalizationService().currentLanguage == 'vi' ? 'Đang khóa' : 'Dang khoa', style: TextStyle(color: isExpired ? Colors.green : Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                              )
                            ],
                          ),
                          const Divider(),
                          Text(LocalizationService().currentLanguage == 'vi' ? 'Lý do: ${item["reason"]}' : 'Reason: ${item["reason"]}', style: TextStyle(color: Colors.grey.shade700)),
                          Text(LocalizationService().currentLanguage == 'vi' ? 'Ngày khóa: ${item["banned_at"]}' : 'Banned at: ${item["banned_at"]}'),
                          Text(LocalizationService().currentLanguage == 'vi' ? 'Hết hạn: ${item["expires_at"]}' : 'Expires at: ${item["expires_at"]}', style: TextStyle(fontWeight: FontWeight.bold, color: isExpired ? Colors.green : Colors.orange.shade700)),
                          if (!isExpired) ...[
                            SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => _unbanIp(item['id'], item['ip_address']),
                                icon: Icon(Icons.lock_open, color: Colors.red),
                                label: Text('MỞ KHÓA NGAY', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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