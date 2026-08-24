import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'localization_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChessMatchScreen extends StatefulWidget {
  
  final int matchId;
  const ChessMatchScreen({super.key, required this.matchId});

  @override
  State<ChessMatchScreen> createState() => _ChessMatchScreenState();
}

class _ChessMatchScreenState extends State<ChessMatchScreen> {
  final ChessBoardController _controller = ChessBoardController();
  Timer? _pollingTimer;
  Map<String, dynamic>? _matchData;
  bool _isMyTurn = false;
  String _myColor = 'w';

  @override
  void initState() {
    super.initState();
    _fetchState();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchState());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchState() async {
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chess_api.php'),
        headers: {'Cookie': 'PHPSESSID=${await _getSession()}'},
        body: {'action': 'get_state', 'match_id': widget.matchId.toString()},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['status'] == 'success') {
          final match = data['match'];
          if (!mounted) return;
          setState(() {
            _matchData = match;
            _isMyTurn = match['is_your_turn'];
            _myColor = match['your_color'];
          });
          
          final fen = match['fen'] ?? '';
          if (fen.isNotEmpty && fen != _controller.getFen()) {
            _controller.loadFen(fen);
          }
        }
      }
    } catch (e) {
      debugPrint('Error polling chess: $e');
    }
  }

  Future<void> _makeMove() async {
    final fen = _controller.getFen();
    try {
      await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chess_api.php'),
        headers: {'Cookie': 'PHPSESSID=${await _getSession()}'},
        body: {
          'action': 'move',
          'match_id': widget.matchId.toString(),
          'fen': fen,
          'game_status': _controller.isGameOver() ? 'FINISHED' : 'PLAYING'
        },
      );
      _fetchState();
    } catch (e) {
      debugPrint('Error making move: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(LocalizationService().currentLanguage == 'vi' ? 'Trận đấu Cờ Vua' : 'Chess Match')),
      body: _matchData == null
          ? Center(child: CircularProgressIndicator())
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_matchData!['status'] != 'PLAYING')
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(LocalizationService().currentLanguage == 'vi' ? 'Trận đấu đã kết thúc!' : 'Game Over!', style: TextStyle(fontSize: 20, color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(_isMyTurn ? LocalizationService().currentLanguage == 'vi' ? 'Lượt của bạn' : 'Your Turn' : LocalizationService().currentLanguage == 'vi' ? 'Đang đợi đối thủ...' : 'Waiting for opponent...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                ChessBoard(
                  controller: _controller,
                  boardColor: BoardColor.brown,
                  boardOrientation: _myColor == 'w' ? PlayerColor.white : PlayerColor.black,
                  onMove: () {
                    _makeMove();
                  },
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    await http.post(
                      Uri.parse('${AppConfig.baseUrl}/api/chess_api.php'),
                      headers: {'Cookie': 'PHPSESSID=${await _getSession()}'},
                      body: {'action': 'resign', 'match_id': widget.matchId.toString()},
                    );
                    _fetchState();
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: Text(LocalizationService().currentLanguage == 'vi' ? 'Đầu hàng' : 'Resign', style: TextStyle(color: Colors.white)),
                )
              ],
            ),
    );
  }
}

Future<String> _getSession() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('phpsessid') ?? '';
}
