import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:image_picker/image_picker.dart'; 
import 'tvtl_service.dart';

class HumanChatRoomScreen extends StatefulWidget {
  final String partnerId;
  final String partnerName;
  final String partnerAvatar;

  const HumanChatRoomScreen({super.key, required this.partnerId, required this.partnerName, required this.partnerAvatar});

  @override
  State<HumanChatRoomScreen> createState() => _HumanChatRoomScreenState();
}

class _HumanChatRoomScreenState extends State<HumanChatRoomScreen> {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final ImagePicker _picker = ImagePicker(); 

  List<dynamic> _messages = [];
  bool _isLoading = true;
  Timer? _pollingTimer;
  Map<String, dynamic>? _replyingToMessage; 

  @override
  void initState() {
    super.initState();
    _loadMessages(forceScroll: true);
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadMessages(forceScroll: false));
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMessages({required bool forceScroll}) async {
    final msgs = await TvtlService.getChatHistory(partnerId: widget.partnerId);
    if (!mounted) return;
    
    if (_messages.length != msgs.length || _isLoading) {
      setState(() { _messages = msgs; _isLoading = false; });
      if (forceScroll) _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _sendMessage({String? contentOverride}) async {
    String text = contentOverride ?? _msgCtrl.text.trim();
    if (text.isEmpty) return;
    
    if (contentOverride == null) _msgCtrl.clear();

    int? replyId = _replyingToMessage?['id']; 
    setState(() { _replyingToMessage = null; });

    setState(() {
      _messages.add({
        'sender_id': 'me', 'content': text, 'created_at': DateTime.now().toIso8601String(),
        if (text.startsWith('[IMG]:')) 'reactions': null,
      }); 
    });
    _scrollToBottom();

    await TvtlService.sendMessage(text, partnerId: widget.partnerId, replyId: replyId);
    await _loadMessages(forceScroll: true);
  }

  Future<void> _pickAndSendImage() async {
    FocusScope.of(context).unfocus(); 
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image == null || !mounted) return;

    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    String? imgUrlPrefix = await TvtlService.uploadChatFile(image.path);
    if (mounted) Navigator.pop(context); 

    if (imgUrlPrefix != null) {
      await _sendMessage(contentOverride: imgUrlPrefix);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload ảnh thất bại, vui lòng thử lại.')));
    }
  }

  void _showMessageOptions(Map<String, dynamic> msg) {
    bool isMe = msg['sender_id'].toString() != widget.partnerId;
    String rawContent = msg['content'].toString();
    bool isImage = rawContent.startsWith('[IMG]:');
    String displayContent = isImage ? 'đã gửi một ảnh' : (rawContent.length > 50 ? '${rawContent.substring(0, 50)}...' : rawContent);

    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(15),
              child: Text(displayContent, style: const TextStyle(color: Colors.grey, fontSize: 13, fontStyle: FontStyle.italic), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Divider(height: 1),
            if (!isImage)
              ListTile(leading: const Icon(Icons.copy, color: Colors.blue), title: const Text('Chép văn bản'), onTap: () {
                Clipboard.setData(ClipboardData(text: rawContent)); 
                Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã chép vào bộ nhớ')));
              }),
            ListTile(leading: const Icon(Icons.reply, color: Colors.deepOrange), title: const Text('Trả lời'), onTap: () {
              Navigator.pop(context);
              setState(() { _replyingToMessage = msg; }); 
              _msgCtrl.clear(); 
              FocusScope.of(context).requestFocus(); 
            }),
            if (isMe)
              ListTile(leading: const Icon(Icons.delete_forever, color: Colors.red), title: const Text('Xóa ở phía tôi', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)), onTap: () {
                Navigator.pop(context); _deleteMessage(msg['id']);
              }),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteMessage(dynamic messageId) async {
    bool ok = await TvtlService.deleteMessage(messageId.toInt());
    if (ok) { await _loadMessages(forceScroll: false); } 
    else if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể xóa tin nhắn này.'))); }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0, title: Row(children: [CircleAvatar(backgroundImage: NetworkImage(widget.partnerAvatar), radius: 18, backgroundColor: Colors.grey.shade200), const SizedBox(width: 10), Expanded(child: Text(widget.partnerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis))]),
        elevation: 1, 
      ),
      backgroundColor: isDark ? Theme.of(context).colorScheme.background : const Color(0xFFF0F2F5),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollCtrl, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      bool isMe = msg['sender_id'].toString() != widget.partnerId;
                      String rawContent = msg['content'].toString();
                      bool isImage = rawContent.startsWith('[IMG]:');
                      
                      bool hasReply = msg['reply_content'] != null && msg['reply_content'].toString().isNotEmpty;
                      String replyRaw = msg['reply_content']?.toString() ?? '';
                      bool replyIsImage = replyRaw.startsWith('[IMG]:');
                      String replyDisplay = replyIsImage ? 'Mục: Hình ảnh' : replyRaw;

                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          child: GestureDetector(
                            onLongPress: () => _showMessageOptions(msg), 
                            child: Container(
                              padding: EdgeInsets.all(isImage ? 3 : 10),
                              decoration: BoxDecoration(
                                color: isImage ? Colors.transparent : (isMe ? const Color(0xFF0084FF) : (isDark ? Colors.grey[800] : Colors.white)), 
                                borderRadius: BorderRadius.circular(18), 
                                boxShadow: isImage ? null : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 3, offset: const Offset(0, 1))]
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (hasReply)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(color: isMe ? Colors.white.withOpacity(0.15) : (isDark ? Colors.white10 : Colors.black.withOpacity(0.05)), borderRadius: BorderRadius.circular(12)),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(width: 2, height: 20, color: isMe ? Colors.white70 : Colors.blue.shade300),
                                          const SizedBox(width: 8),
                                          Flexible(child: Text(replyDisplay, style: TextStyle(color: isMe ? Colors.white70 : Colors.blueGrey, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                        ],
                                      ),
                                    ),
                                  
                                  isImage
                                      ? ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.network('${TvtlService.pythonBaseUrl}${rawContent.replaceAll('[IMG]:', '')}', fit: BoxFit.cover, loadingBuilder: (_, c, l) => l == null ? c : Container(height: 150, width: 150, color: Colors.grey.shade300, child: const Center(child: CircularProgressIndicator())), errorBuilder: (_, e, s) => const Icon(Icons.broken_image, color: Colors.grey, size: 50)))
                                      : Text(rawContent, style: TextStyle(color: isMe ? Colors.white : (isDark ? Colors.white : Colors.black87), fontSize: 15, height: 1.3)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                
                // --- THANH CHAT BOTTOM ---
                Container(
                  padding: const EdgeInsets.only(left: 10, right: 10, bottom: 20, top: 10),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: const Border(top: BorderSide(color: Colors.black12))),
                  child: Column(
                    children: [
                      if (_replyingToMessage != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10, left: 5, right: 5),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(color: isDark ? Colors.grey[800] : Colors.grey.shade100, borderRadius: BorderRadius.circular(12), border: const Border(left: BorderSide(color: Colors.deepOrange, width: 3))),
                          child: Row(
                            children: [
                              const Icon(Icons.reply, color: Colors.deepOrange, size: 16),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _replyingToMessage!['content'].toString().startsWith('[IMG]:') ? 'Mục: Hình ảnh' : _replyingToMessage!['content'].toString(),
                                  style: TextStyle(color: isDark ? Colors.grey[300] : Colors.blueGrey.shade700, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => setState(() { _replyingToMessage = null; }), 
                                child: Icon(Icons.close, color: Colors.grey.shade600, size: 20),
                              )
                            ],
                          ),
                        ),
                      
                      Row(
                        children: [
                          IconButton(icon: const Icon(Icons.image, color: Colors.blue), onPressed: _pickAndSendImage), 
                          
                          Expanded(
                            child: TextField(
                              controller: _msgCtrl, textInputAction: TextInputAction.send, onSubmitted: (_) => _sendMessage(),
                              decoration: InputDecoration(hintText: 'Nhắn tin...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), filled: true, fillColor: isDark ? Colors.grey[800] : Colors.grey.shade100, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), isDense: true),
                            ),
                          ),
                          const SizedBox(width: 5),
                          IconButton(icon: const Icon(Icons.send, color: Color(0xFF0084FF)), onPressed: () => _sendMessage()),
                        ],
                      ),
                    ],
                  ),
                )
              ],
            ),
    );
  }
}