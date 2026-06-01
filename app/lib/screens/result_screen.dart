import 'dart:math';
import 'package:flutter/material.dart';
import '../game/score_tracker.dart';
import '../game/level_progress.dart';
import '../services/api_service.dart';
import 'game_screen.dart';

class ResultScreen extends StatefulWidget {
  final String piece;
  final int hits;
  final int total;
  final List<TrackedNote> notes;
  final String pieceId;
  final String midiAsset;
  final int originalQuarterMs;
  final int selectedQuarterMs;
  final int? campaignLevel;

  const ResultScreen({super.key,
    required this.piece,
    required this.hits,
    required this.total,
    required this.notes,
    required this.pieceId,
    required this.midiAsset,
    required this.originalQuarterMs,
    required this.selectedQuarterMs,
    this.campaignLevel,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with SingleTickerProviderStateMixin {
  List<int> _history       = [];
  bool      _newUnlock     = false;
  int       _unlockedLevel = 0;
  late AnimationController _starCtrl;
  late Animation<double>   _starAnim;

  String? _advice;
  bool    _adviceLoading = false;

  int get _pct => widget.total > 0
      ? (widget.hits / widget.total * 100).round() : 0;

  @override
  void initState() {
    super.initState();
    _starCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _starAnim = CurvedAnimation(parent: _starCtrl, curve: Curves.elasticOut);
    _saveProgress();
  }

  @override
  void dispose() { _starCtrl.dispose(); super.dispose(); }

  static const _noteNames = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'];
  String _midiName(int midi) =>
      '${_noteNames[midi % 12]}${(midi ~/ 12) - 1}';

  Future<void> _loadAdvice() async {
    setState(() { _adviceLoading = true; _advice = null; });
    final missed = widget.notes
        .where((n) => n.state == NoteState.missed)
        .map((n) => _midiName(n.note.pitch))
        .toSet().toList();
    final late_ = <String>[];  // timing data not tracked at this level
    final avgDelay = 0;
    final bpm = widget.originalQuarterMs > 0
        ? (60000 / widget.selectedQuarterMs).round() : 0;

    final advice = await ApiService.analyzeGame(
      pieceName:   widget.piece,
      bpm:         bpm,
      hitPct:      _pct.toDouble(),
      missedNotes: missed,
      lateNotes:   late_,
      avgDelayMs:  avgDelay,
    );
    if (mounted) setState(() { _advice = advice ?? 'Нет доступа к анализу. Войдите в аккаунт.'; _adviceLoading = false; });
  }

  Future<void> _saveProgress() async {
    // Always save free-play progress
    await LevelProgress.reportScoreForPiece(widget.pieceId, _pct);
    final history = await LevelProgress.getAttemptHistoryForPiece(widget.pieceId);

    // Also save campaign progress if applicable
    bool unlocked = false;
    final lvl = widget.campaignLevel;
    if (lvl != null) {
      unlocked = await LevelProgress.reportCampaignScore(lvl, _pct);
    }

    if (!mounted) return;
    setState(() {
      _history       = history;
      _newUnlock     = unlocked;
      _unlockedLevel = (lvl ?? 0) + 1;
    });
    _starCtrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    final pct   = _pct;
    final stars = LevelProgress.starsForPct(pct);
    final color = pct >= 95 ? const Color(0xFF4CAF50)
                : pct >= 70 ? const Color(0xFFFFD740)
                : const Color(0xFFF44336);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(children: [
            // ── Left: score + buttons ─────────────────────────────────────
            Expanded(
              flex: 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(widget.piece, style: const TextStyle(
                      fontSize: 14, color: Color(0xFF999999))),
                  const SizedBox(height: 6),
                  ScaleTransition(
                    scale: _starAnim,
                    child: _StarsRow(stars: stars, size: 32),
                  ),
                  const SizedBox(height: 4),
                  Text('$pct%', style: TextStyle(fontSize: 52,
                      fontWeight: FontWeight.bold, color: color)),
                  Text('${widget.hits} из ${widget.total} нот',
                      style: const TextStyle(fontSize: 15, color: Colors.white)),

                  const SizedBox(height: 8),

                  // Unlock banner
                  if (_newUnlock) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B5E20),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF4CAF50), width: 1.5),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.lock_open, color: Color(0xFF4CAF50), size: 14),
                        const SizedBox(width: 5),
                        Text('Уровень $_unlockedLevel открыт!',
                            style: const TextStyle(color: Color(0xFF4CAF50),
                                fontSize: 12, fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  ] else if (widget.campaignLevel != null &&
                      _pct < LevelProgress.unlockThresholdPct &&
                      widget.campaignLevel! < LevelProgress.totalCampaignLevels) ...[
                    Text('Нужно ${LevelProgress.unlockThresholdPct}% для следующего уровня',
                        style: const TextStyle(fontSize: 10, color: Color(0xFF555566))),
                  ],

                  const SizedBox(height: 14),

                  // Buttons inline
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    OutlinedButton.icon(
                      onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF444455)),
                        foregroundColor: Colors.white70,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      icon: const Icon(Icons.home_outlined, size: 16),
                      label: const Text('Меню', style: TextStyle(fontSize: 13)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pushReplacement(context,
                        MaterialPageRoute(builder: (_) => GameScreen(
                          piece:             widget.piece,
                          midiAsset:         widget.midiAsset,
                          originalQuarterMs: widget.originalQuarterMs,
                          selectedQuarterMs: widget.selectedQuarterMs,
                          pieceId:           widget.pieceId,
                          campaignLevel:     widget.campaignLevel,
                        ))),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD740),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      ),
                      icon: const Icon(Icons.replay, size: 16),
                      label: const Text('Ещё раз',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ]),

                  const SizedBox(height: 10),

                  // ── AI Advice button ────────────────────────────────────
                  if (_advice == null && !_adviceLoading)
                    TextButton.icon(
                      onPressed: _loadAdvice,
                      icon: const Icon(Icons.auto_awesome, size: 15,
                          color: Color(0xFF888899)),
                      label: const Text('Анализ ИИ',
                          style: TextStyle(fontSize: 12, color: Color(0xFF888899))),
                    )
                  else if (_adviceLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 14, height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Color(0xFF888899))),
                            SizedBox(width: 8),
                            Text('Анализирую...', style: TextStyle(
                                fontSize: 12, color: Color(0xFF888899))),
                          ]),
                    )
                  else if (_advice != null)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1C2E),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF333344)),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.auto_awesome, size: 14,
                                color: Color(0xFFFFD740)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_advice!,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.white70,
                                      height: 1.5)),
                            ),
                          ]),
                    ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // ── Right: chart ─────────────────────────────────────────────
            if (_history.length > 1)
              Expanded(
                flex: 5,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('История попыток', style: TextStyle(
                        color: Color(0xFF555566), fontSize: 10, letterSpacing: 1.0)),
                    const SizedBox(height: 4),
                    Flexible(
                      child: _AttemptChartPainted(history: _history),
                    ),
                  ],
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

// ── Stars row ──────────────────────────────────────────────────────────────────
class _StarsRow extends StatelessWidget {
  final int stars;
  final double size;
  const _StarsRow({required this.stars, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
      final filled = i < stars;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Icon(
          filled ? Icons.star : Icons.star_border,
          color: filled ? const Color(0xFFFFD740) : const Color(0xFF333344),
          size: size,
        ),
      );
    }));
  }
}

// ── Attempt chart via CustomPaint — fits any available height ────────────────
class _AttemptChartPainted extends StatelessWidget {
  final List<int> history;
  const _AttemptChartPainted({required this.history});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ChartPainter(history),
      child: const SizedBox.expand(),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<int> history;
  _ChartPainter(this.history);

  Color _barColor(int pct) {
    if (pct >= 95) return const Color(0xFF4CAF50);
    if (pct >= 85) return const Color(0xFF8BC34A);
    if (pct >= 70) return const Color(0xFFFFD740);
    if (pct >= 40) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;

    final n       = history.length;
    final barGap  = 10.0;
    final maxBarW = 28.0;
    final barW    = min(maxBarW, (size.width - barGap * (n - 1)) / n);
    final totalW  = barW * n + barGap * (n - 1);
    final startX  = (size.width - totalW) / 2;
    final labelH  = 14.0;
    final chartH  = size.height - labelH - 4;

    for (int i = 0; i < n; i++) {
      final pct    = history[i];
      final isLast = i == n - 1;
      final color  = _barColor(pct);
      final barH   = max(4.0, chartH * pct / 100.0);
      final x      = startX + i * (barW + barGap);
      final y      = labelH + 4 + chartH - barH;

      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barW, barH),
        const Radius.circular(3),
      );
      canvas.drawRRect(barRect, Paint()..color = isLast ? color : color.withAlpha(100));
      if (isLast) {
        canvas.drawRRect(barRect, Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
      }

      final tp = TextPainter(
        text: TextSpan(text: '$pct%', style: TextStyle(
          fontSize: 9,
          color: isLast ? color : color.withAlpha(150),
          fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
        )),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + barW / 2 - tp.width / 2, 0));
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}

// ── Note grid ──────────────────────────────────────────────────────────────────
class _NoteGrid extends StatelessWidget {
  final List<TrackedNote> notes;
  const _NoteGrid({required this.notes});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 5, runSpacing: 5,
      alignment: WrapAlignment.center,
      children: notes.map((t) {
        final color = t.state == NoteState.hit    ? const Color(0xFF4CAF50)
                    : t.state == NoteState.missed ? const Color(0xFFF44336)
                    : Colors.grey;
        const noteNames = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'];
        final name = noteNames[t.note.pitch % 12];
        return Container(
          width: 36, height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withAlpha(45),
            border: Border.all(color: color, width: 1.5),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(name, style: TextStyle(color: color,
              fontSize: 11, fontWeight: FontWeight.bold)),
        );
      }).toList(),
    );
  }
}
