import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';
import 'localization_service.dart';
import 'tvtl_service.dart';
import 'human_chat_room_screen.dart';

class PublicProfileScreen extends StatefulWidget {
  final String studentCode;
  const PublicProfileScreen({Key? key, required this.studentCode}) : super(key: key);

  @override
  _PublicProfileScreenState createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  bool _isLoading = true;
  bool _isActionLoading = false;
  Map<String, dynamic>? _studentData;
  int? _targetUserId;
  bool _isSelf = false;
  bool _isLoggedIn = false;
  String _relation = 'none'; // 'none', 'sent', 'received', 'friend'
  int? _reqId;
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    _fetchPublicProfile();
  }

  Future<void> _fetchPublicProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString('phpsessid') ?? '';
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/public_profile_api.php?code=${widget.studentCode}'),
        headers: {'Cookie': 'PHPSESSID=$sessionId'},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['status'] == 'success') {
          setState(() {
            _studentData = data['student'];
            _targetUserId = data['target_user_id'] != null ? int.tryParse(data['target_user_id'].toString()) : null;
            _isSelf = data['is_self'] == true;
            _relation = data['relation'] ?? 'none';
            _reqId = data['req_id'] != null ? int.tryParse(data['req_id'].toString()) : null;
            _isLoggedIn = data['is_logged_in'] == true;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMsg = data['msg'] ?? (LocalizationService().currentLanguage == 'vi' ? 'Không tìm thấy hồ sơ' : 'Profile not found');
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMsg = LocalizationService().currentLanguage == 'vi' ? 'Lỗi máy chủ: ${res.statusCode}' : 'Server error: ${res.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = LocalizationService().currentLanguage == 'vi' ? 'Lỗi kết nối mạng' : 'Network connection error';
        _isLoading = false;
      });
    }
  }

  Future<void> _handleFriendAction(String action) async {
    if (_targetUserId == null) return;
    setState(() => _isActionLoading = true);

    bool ok = false;
    if (action == 'request') {
      ok = await TvtlService.requestFriend(_targetUserId!);
    } else if (action == 'cancel') {
      ok = await TvtlService.cancelFriendRequest(_targetUserId!);
    } else if (action == 'accept' && _reqId != null) {
      ok = await TvtlService.respondFriend(_reqId!, 'accept');
    } else if (action == 'reject' && _reqId != null) {
      ok = await TvtlService.respondFriend(_reqId!, 'reject');
    } else if (action == 'unfriend') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(LocalizationService().currentLanguage == 'vi' ? 'Hủy kết bạn' : 'Unfriend'),
          content: Text(LocalizationService().currentLanguage == 'vi' 
            ? 'Bạn có chắc chắn muốn hủy kết bạn với người này?' 
            : 'Are you sure you want to unfriend this user?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(LocalizationService().currentLanguage == 'vi' ? 'Hủy' : 'Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true), 
              child: Text(LocalizationService().currentLanguage == 'vi' ? 'Hủy kết bạn' : 'Unfriend'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        ok = await TvtlService.unfriend(_targetUserId!);
      } else {
        if (mounted) setState(() => _isActionLoading = false);
        return;
      }
    }

    if (mounted) {
      setState(() => _isActionLoading = false);
      if (ok) {
        _fetchPublicProfile();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LocalizationService().currentLanguage == 'vi' ? 'Thao tác thất bại, vui lòng thử lại!' : 'Action failed, please try again!'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  void _launchURL(String urlString) async {
    if (urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocalizationService().currentLanguage == 'vi' ? 'Không thể mở liên kết' : 'Cannot open link')));
    }
  }

  Widget _buildSocialBtn(String title, IconData icon, Color color, String urlString) {
    if (urlString.isEmpty) return SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: Icon(icon, size: 24),
          label: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          onPressed: () => _launchURL(urlString),
        ),
      ),
    );
  }

  Widget _buildFriendshipWidget(String avatarUrl) {
    if (!_isLoggedIn || _isSelf || _targetUserId == null) return const SizedBox.shrink();
    
    if (_isActionLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12.0),
        child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))),
      );
    }

    bool isVi = LocalizationService().currentLanguage == 'vi';

    if (_relation == 'none') {
      return Padding(
        padding: const EdgeInsets.only(top: 14.0),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Theme.of(context).primaryColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          icon: const Icon(Icons.person_add_rounded, size: 20),
          label: Text(isVi ? 'Gửi kết bạn' : 'Add Friend', style: const TextStyle(fontWeight: FontWeight.bold)),
          onPressed: () => _handleFriendAction('request'),
        ),
      );
    } else if (_relation == 'sent') {
      return Padding(
        padding: const EdgeInsets.only(top: 14.0),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber.shade700,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          icon: const Icon(Icons.pending_actions_rounded, size: 20),
          label: Text(isVi ? 'Đã gửi lời mời (Hủy)' : 'Request Sent (Cancel)', style: const TextStyle(fontWeight: FontWeight.bold)),
          onPressed: () => _handleFriendAction('cancel'),
        ),
      );
    } else if (_relation == 'received') {
      return Padding(
        padding: const EdgeInsets.only(top: 14.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              icon: const Icon(Icons.check, size: 18),
              label: Text(isVi ? 'Đồng ý' : 'Accept', style: const TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => _handleFriendAction('accept'),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              icon: const Icon(Icons.close, size: 18),
              label: Text(isVi ? 'Từ chối' : 'Decline', style: const TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => _handleFriendAction('reject'),
            ),
          ],
        ),
      );
    } else if (_relation == 'friend') {
      return Padding(
        padding: const EdgeInsets.only(top: 14.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Theme.of(context).primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              icon: const Icon(Icons.chat_bubble_rounded, size: 18),
              label: Text(isVi ? 'Nhắn tin' : 'Message', style: const TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HumanChatRoomScreen(
                      partnerId: _targetUserId.toString(),
                      partnerName: _studentData!['name'] ?? '',
                      partnerAvatar: avatarUrl,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              icon: const Icon(Icons.person_remove_rounded, size: 18),
              label: Text(isVi ? 'Hủy kết bạn' : 'Unfriend', style: const TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => _handleFriendAction('unfriend'),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(LocalizationService().currentLanguage == 'vi' ? 'Hồ sơ học sinh' : 'Student Profile')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMsg.isNotEmpty || _studentData == null) {
      return Scaffold(
        appBar: AppBar(title: Text(LocalizationService().currentLanguage == 'vi' ? 'Lỗi' : 'Error')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 60, color: Colors.red),
              SizedBox(height: 16),
              Text(_errorMsg, style: TextStyle(fontSize: 18)),
            ],
          ),
        ),
      );
    }

    String avatarUrl = _studentData!['image_url'] ?? '';
    if (avatarUrl.isNotEmpty && !avatarUrl.startsWith('http')) {
      avatarUrl = '${AppConfig.baseUrl}/$avatarUrl';
    }
    
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(LocalizationService().currentLanguage == 'vi' ? 'Hồ sơ công khai' : 'Public Profile', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header Section
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
              ),
              padding: EdgeInsets.only(bottom: 25, top: 20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.white,
                    backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl.isEmpty ? Icon(Icons.person, size: 60, color: Colors.grey) : null,
                  ),
                  SizedBox(height: 16),
                  Text(
                    _studentData!['name'] ?? '',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "${_studentData!['class_name'] ?? ''} - ${_studentData!['code'] ?? ''}",
                    style: TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                  _buildFriendshipWidget(avatarUrl),
                ],
              ),
            ),
            
            SizedBox(height: 30),
            
            // Social Links Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  Text(LocalizationService().currentLanguage == 'vi' ? 'Kết nối với tôi' : 'Connect with me', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                  SizedBox(height: 20),
                  _buildSocialBtn('Facebook', Icons.facebook, Color(0xFF1877F2), _studentData!['facebook_url'] ?? ''),
                  _buildSocialBtn('Zalo', Icons.chat, Color(0xFF0068FF), _studentData!['zalo_url'] ?? ''),
                  _buildSocialBtn('TikTok', Icons.music_note, Colors.black, _studentData!['tiktok_url'] ?? ''),
                  _buildSocialBtn('Instagram', Icons.camera_alt, Color(0xFFE4405F), _studentData!['instagram_url'] ?? ''),
                  _buildSocialBtn('YouTube', Icons.play_circle, Color(0xFFFF0000), _studentData!['youtube_url'] ?? ''),
                  _buildSocialBtn('GitHub', Icons.code, Color(0xFF333333), _studentData!['github_url'] ?? ''),
                  _buildSocialBtn('Threads', Icons.alternate_email, Colors.black, _studentData!['threads_url'] ?? ''),
                ],
              ),
            ),
            SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
