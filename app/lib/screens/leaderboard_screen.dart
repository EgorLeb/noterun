import 'package:flutter/material.dart';
import '../services/api_service.dart';

class LeaderboardScreen extends StatefulWidget {
  final String mode;        // "sight_reading" | "campaign_1" .. "campaign_5"
  final String title;
  const LeaderboardScreen({super.key, required this.mode, required this.title});
  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<LeaderboardRow> _rows = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final rows = await ApiService.getLeaderboard(widget.mode);
      if (mounted) setState(() { _rows = rows; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Нет связи'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.home_outlined, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.title,
                    style: const TextStyle(fontSize: 20,
                        fontWeight: FontWeight.bold, color: Colors.white)),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white54),
                onPressed: _load,
              ),
            ]),
          ),

          if (_loading)
            const Expanded(child: Center(
                child: CircularProgressIndicator(color: Color(0xFFFFD740))))
          else if (_error.isNotEmpty)
            Expanded(child: Center(child: Text(_error,
                style: const TextStyle(color: Colors.white54))))
          else if (_rows.isEmpty)
            const Expanded(child: Center(child: Text('Пока никого нет',
                style: TextStyle(color: Colors.white54))))
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _rows.length,
                itemBuilder: (_, i) {
                  final row = _rows[i];
                  final isTop3 = row.rank <= 3;
                  final medalColor = row.rank == 1
                      ? const Color(0xFFFFD740)
                      : row.rank == 2
                          ? const Color(0xFFBDBDBD)
                          : const Color(0xFFCD7F32);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: row.isMe
                          ? const Color(0xFF1B3A1B)
                          : const Color(0xFF1E2030),
                      borderRadius: BorderRadius.circular(10),
                      border: row.isMe
                          ? Border.all(color: const Color(0xFF4CAF50), width: 1.5)
                          : null,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(children: [
                        // Rank
                        SizedBox(width: 32,
                          child: isTop3
                              ? Icon(Icons.emoji_events,
                                  color: medalColor, size: 22)
                              : Text('${row.rank}',
                                  style: const TextStyle(
                                      color: Color(0xFF666677), fontSize: 14)),
                        ),
                        const SizedBox(width: 12),
                        // Username
                        Expanded(child: Text(
                          row.isMe ? '${row.username} (ты)' : row.username,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: row.isMe
                                ? FontWeight.bold : FontWeight.normal,
                            color: row.isMe
                                ? const Color(0xFF4CAF50) : Colors.white,
                          ),
                        )),
                        // Score
                        Text('${row.score}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isTop3 ? medalColor : const Color(0xFFFFD740),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(row.updatedAt,
                          style: const TextStyle(
                              fontSize: 10, color: Color(0xFF555566))),
                      ]),
                    ),
                  );
                },
              ),
            ),
        ]),
      ),
    );
  }
}
