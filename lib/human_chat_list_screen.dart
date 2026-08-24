import 'package:flutter/material.dart';
import 'localization_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tvtl_service.dart';
import 'human_chat_room_screen.dart';
import 'config.dart';

class HumanChatListScreen extends StatefulWidget {
  const HumanChatListScreen({super.key});

  @override
  State<HumanChatListScreen> createState() => _HumanChatListScreenState();
}

class _HumanChatListScreenState extends State<HumanChatListScreen> {
  bool _isLoading = true;
  String _role = 'STUDENT';
  
  // Dữ liệu Tab Thầy Cô / Quản lý
  List<dynamic> _contacts = [];
  
  // Dữ liệu Tab Bạn Bè
  Map<String, dynamic> _friendsData = {'friends': [], 'requests': [], 'sent': []};
  List<dynamic>? _searchResults;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _role = prefs.getString('role') ?? 'STUDENT';

    await TvtlService.ensurePythonLogin();

    if (_role == 'TEACHER' || _role == 'ADMIN') {
      _contacts = await TvtlService.getConversations() ?? [];
    } else {
      _contacts = await TvtlService.getTeachers() ?? [];
      final fData = await TvtlService.getFriendsData();
      if (fData != null) _friendsData = fData;
    }

    if (mounted) setState(() => _isLoading = false);
  }

  // --- Xử lý sự kiện Bạn Bè ---
  Future<void> _search() async {
    if (_searchCtrl.text.trim().isEmpty) {
      setState(() => _searchResults = null);
      return;
    }
    setState(() => _isLoading = true);
    final results = await TvtlService.searchFriends(_searchCtrl.text.trim());
    setState(() {
      _searchResults = results ?? [];
      _isLoading = false;
    });
  }

  Future<void> _handleAddFriend(int targetId) async {
    await TvtlService.requestFriend(targetId);
    _search(); // Load lại kết quả tìm kiếm
    _initData(); // Load lại danh sách đang chờ
  }

  Future<void> _handleRespond(int reqId, String action) async {
    await TvtlService.respondFriend(reqId, action);
    _initData();
  }

  // --- Hàm build giao diện ---
  String _fixAvatarUrl(String url) {
    if (url.isEmpty || url.length < 5) return '${AppConfig.baseUrl}/static/default.png';
    if (!url.startsWith('http')) return '${TvtlService.pythonBaseUrl}/$url'.replaceAll('//static', '/static');
    return url;
  }

  Widget _buildContactTile(dynamic user, String subText, {Widget? trailing, VoidCallback? onTap}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundImage: NetworkImage(_fixAvatarUrl(user['avatar'] ?? '')),
        backgroundColor: Colors.grey.shade200,
      ),
      title: Text(user['full_name'] ?? (LocalizationService().currentLanguage == 'vi' ? 'Không tên' : 'Unknown name'), style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
      subtitle: Text(subText, style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey.shade600, fontSize: 13)),
      trailing: trailing,
      onTap: onTap,
    );
  }

  // TAB 1: THẦY CÔ / TIN NHẮN
  Widget _buildTeachersTab() {
    if (_contacts.isEmpty) return Center(child: Text(LocalizationService().currentLanguage == 'vi' ? 'Không có liên hệ.' : 'No contacts.'));
    return ListView.builder(
      itemCount: _contacts.length,
      itemBuilder: (context, index) {
        final c = _contacts[index];
        final idStr = (c['id'] ?? c['partner_id'] ?? c['student_id']).toString();
        final unread = c['unread'] ?? 0;
        return _buildContactTile(
          c, 
          _role == 'STUDENT' ? LocalizationService().currentLanguage == 'vi' ? 'Giáo viên Tâm lý' : 'Counselor' : LocalizationService().currentLanguage == 'vi' ? 'Học sinh' : 'Students',
          trailing: unread > 0 
              ? CircleAvatar(radius: 12, backgroundColor: Colors.red, child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 12)))
              : Icon(Icons.chevron_right, color: Colors.grey),
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => HumanChatRoomScreen(
              partnerId: idStr, partnerName: c['full_name'] ?? c['partner_name'], partnerAvatar: _fixAvatarUrl(c['avatar'] ?? ''),
            ))).then((_) => _initData());
          }
        );
      },
    );
  }

  // TAB 2: BẠN BÈ
  Widget _buildFriendsTab() {
    return Column(
      children: [
        // Khung tìm kiếm
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: LocalizationService().currentLanguage == 'vi' ? 'Nhập tên hoặc Mã HS...' : 'Search name or Student ID...',
                    prefixIcon: Icon(Icons.search),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 15),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              SizedBox(width: 8),
              FilledButton(onPressed: _search, child: Text(LocalizationService().currentLanguage == 'vi' ? 'Tìm' : 'Search')),
            ],
          ),
        ),

        Expanded(
          child: _searchResults != null
              ? _buildSearchResults()
              : _buildFriendsLists(),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults!.isEmpty) return Center(child: Text(LocalizationService().currentLanguage == 'vi' ? 'Không tìm thấy học sinh nào.' : 'No students found.'));
    return ListView.builder(
      itemCount: _searchResults!.length,
      itemBuilder: (context, index) {
        final u = _searchResults![index];
        Widget actionBtn;
        
        if (u['relation'] == 'friend') {
          actionBtn = TextButton(onPressed: () => _openChat(u), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Nhắn tin' : 'Chat'));
        } else if (u['relation'] == 'sent') {
          actionBtn = TextButton(onPressed: null, child: Text(LocalizationService().currentLanguage == 'vi' ? 'Đã gửi' : 'Sent'));
        } else if (u['relation'] == 'received') {
          actionBtn = TextButton(onPressed: null, child: Text(LocalizationService().currentLanguage == 'vi' ? 'Kiểm tra lời mời' : 'Check invitations'));
        } else {
          actionBtn = FilledButton.tonal(onPressed: () => _handleAddFriend(u['id']), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Kết bạn' : 'Add Friend'));
        }

        return _buildContactTile(u, LocalizationService().currentLanguage == 'vi' ? 'Mã HS: ${u["username"] ?? ""}' : 'Code: ${u["username"] ?? ""}', trailing: actionBtn);
      },
    );
  }

  Widget _buildFriendsLists() {
    final requests = _friendsData['requests'] as List? ?? [];
    final sent = _friendsData['sent'] as List? ?? [];
    final friends = _friendsData['friends'] as List? ?? [];

    return ListView(
      children: [
        if (requests.isNotEmpty) ...[
          Padding(padding: EdgeInsets.fromLTRB(15, 15, 15, 5), child: Text(LocalizationService().currentLanguage == 'vi' ? 'LỜI MỜI KẾT BẠN' : 'FRIEND REQUESTS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange))),
          ...requests.map((r) => _buildContactTile(
            r, LocalizationService().currentLanguage == 'vi' ? 'Mã HS: ${r["username"]}' : 'Code: ${r["username"]}',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: Icon(Icons.check_circle, color: Colors.green), onPressed: () => _handleRespond(r['req_id'], 'accept')),
                IconButton(icon: Icon(Icons.cancel, color: Colors.red), onPressed: () => _handleRespond(r['req_id'], 'reject')),
              ],
            )
          )),
          const Divider(),
        ],
        
        if (sent.isNotEmpty) ...[
          Padding(padding: EdgeInsets.fromLTRB(15, 15, 15, 5), child: Text(LocalizationService().currentLanguage == 'vi' ? 'ĐÃ GỬI LỜI MỜI' : 'SENT REQUESTS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey))),
          ...sent.map((s) => _buildContactTile(
            s, LocalizationService().currentLanguage == 'vi' ? 'Đã gửi lời mời' : 'Friend request sent',
            trailing: OutlinedButton(
              onPressed: null, 
              child: Text(LocalizationService().currentLanguage == 'vi' ? 'Đã gửi' : 'Sent')
            ),
          )),
          const Divider(),
        ],

        Padding(padding: EdgeInsets.fromLTRB(15, 15, 15, 5), child: Text(LocalizationService().currentLanguage == 'vi' ? 'DANH SÁCH BẠN BÈ' : 'FRIENDS LIST', style: TextStyle(fontWeight: FontWeight.bold))),
        if (friends.isEmpty) Padding(padding: EdgeInsets.all(15), child: Text(LocalizationService().currentLanguage == 'vi' ? 'Chưa có bạn bè nào. Hãy tìm kiếm và kết bạn nhé!' : 'No friends yet. Search and add some friends!', style: TextStyle(color: Colors.grey))),
        ...friends.map((f) => _buildContactTile(
          f, LocalizationService().currentLanguage == 'vi' ? 'Bạn bè' : 'Friend',
          trailing: IconButton(icon: Icon(Icons.chat_bubble, color: Colors.blue), onPressed: () => _openChat(f)),
          onTap: () => _openChat(f)
        )),
      ],
    );
  }

  void _openChat(dynamic user) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => HumanChatRoomScreen(
      partnerId: user['id'].toString(), 
      partnerName: user['full_name'], 
      partnerAvatar: _fixAvatarUrl(user['avatar'] ?? ''),
    ))).then((_) => _initData());
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _contacts.isEmpty) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Nếu là GV thì chỉ hiện list bình thường (không tab)
    if (_role == 'TEACHER' || _role == 'ADMIN') {
      return Scaffold(
        appBar: AppBar(title: Text(LocalizationService().currentLanguage == 'vi' ? 'Hộp thư Giáo viên' : 'Teacher Inbox')),
        body: _buildTeachersTab(),
      );
    }

    // Nếu là HS thì xài Tab
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(LocalizationService().currentLanguage == 'vi' ? 'Chat' : 'Chat'),
          bottom: TabBar(
            tabs: [
              Tab(icon: Icon(Icons.support_agent), text: LocalizationService().currentLanguage == 'vi' ? 'Thầy Cô' : 'Teachers'),
              Tab(icon: Icon(Icons.people), text: LocalizationService().currentLanguage == 'vi' ? 'Bạn Bè' : 'Friends'),
            ],
          ),
        ),
        body: _isLoading 
            ? Center(child: CircularProgressIndicator()) 
            : TabBarView(
                children: [
                  _buildTeachersTab(),
                  _buildFriendsTab(),
                ],
              ),
      ),
    );
  }
}