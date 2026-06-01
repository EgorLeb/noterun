import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import '../ml/inference_isolate.dart';
import '../game/sight_reading_generator.dart';
import '../game/sight_reading_tracker.dart';
import '../game/game_staff_painter.dart';
import '../game/level_progress.dart';
import '../services/api_service.dart';

class SightReadingScreen extends StatefulWidget {
  const SightReadingScreen({super.key});
  @override
  State<SightReadingScreen> createState() => _SightReadingScreenState();
}

class _SightReadingScreenState extends State<SightReadingScreen> {
  final _generator = SightReadingGenerator();
  final _tracker   = SightReadingTracker();
  InferenceIsolate? _isolate;
  final _stopwatch = Stopwatch();
  Timer?  _gameTimer;
  bool    _loading  = true;
  String  _status   = 'Загрузка модели…';
  bool    _gameOver = false;
  int     _bestScore = 0;

  final _hitEffects = <HitEffect>[];

  static const double _lookaheadSec   = 6.0;
  static const double _pastSec        = 2.5;
  static const double _startOffsetSec = 3.0;
  static const double _effectDurSec   = 0.55;
  double _pxPerSec = 120.0;

  @override
  void initState() {
    super.initState();
    _loadAndStart();
  }

  Future<void> _loadAndStart() async {
    _bestScore = await LevelProgress.getSightReadingBest();

    _isolate = InferenceIsolate(
      onNoteDetected: (pitch, backMs) {
        final hit = _tracker.onPitchDetected(pitch);
        if (hit != null) {
          _generator.onCorrect();
          _hitEffects.add(HitEffect(pitch: hit.note.pitch, noteSec: hit.note.startSec));
        }
      },
      onConfidenceUp: (pitch, level) {
        if (level >= 2) _tracker.onPitchDetected(pitch);
      },
      onError: (e) {
        if (mounted) setState(() => _status = 'Mic: $e');
      },
    );

    try {
      await _isolate!.start();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _status = 'Error: $e'; });
      return;
    }

    if (!mounted) return;
    setState(() { _loading = false; _status = 'Get ready…'; });
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    // Pre-generate initial notes
    for (int i = 0; i < 8; i++) {
      _tracker.addNotes(_generator.generateNext());
    }

    _stopwatch.start();
    _gameTimer = Timer.periodic(const Duration(milliseconds: 16), _onTick);
    setState(() => _status = '');
  }

  void _onTick(Timer _) {
    if (!mounted || _gameOver) return;

    final elapsed = _stopwatch.elapsedMilliseconds / 1000.0 - _startOffsetSec;
    final result  = _tracker.update(elapsed);

    if (result.missed.isNotEmpty) {
      Vibration.vibrate(duration: 100, amplitude: 200);
      _generator.onMiss();
    }

    // Generate more notes if needed
    final lastNote = _tracker.tracked.isEmpty ? 0.0 : _tracker.tracked.last.note.startSec;
    if (lastNote < elapsed + _lookaheadSec + 3.0) {
      _tracker.addNotes(_generator.generateNext());
    }

    // Prune old notes
    _tracker.prune(elapsed, _pastSec);

    // Hit effects
    for (final e in _hitEffects) {
      e.age = (e.age + 0.016 / _effectDurSec).clamp(0.0, 1.0);
    }
    _hitEffects.removeWhere((e) => e.age >= 1.0);

    setState(() {});

    if (_tracker.isGameOver) _endGame();
  }

  void _endGame() async {
    _gameOver = true;
    _gameTimer?.cancel();
    _isolate?.stop();
    _stopwatch.stop();
    await LevelProgress.reportSightReadingScore(_tracker.totalHits);
    _bestScore = await LevelProgress.getSightReadingBest();
    ApiService.submitScore('sight_reading', _tracker.totalHits);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
    _isolate?.stop();
    _stopwatch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    _pxPerSec = (size.width * 0.8) / _lookaheadSec;
    final elapsed = _stopwatch.elapsedMilliseconds / 1000.0 - _startOffsetSec;

    return Scaffold(
      body: Stack(children: [
        // Staff
        CustomPaint(
          painter: GameStaffPainter(
            notes:        _tracker.tracked,
            elapsedSec:   elapsed,
            pxPerSec:     _pxPerSec,
            lookaheadSec: _lookaheadSec,
            pastSec:      _pastSec,
            hitEffects:   List.unmodifiable(_hitEffects),
            quarterSec:   _generator.quarterSec,
          ),
          child: const SizedBox.expand(),
        ),

        // Top bar: [home][replay] ── BPM ── hearts + score
        if (!_loading)
          Positioned(top: 0, left: 0, right: 0,
            child: Row(children: [
              // Left: nav buttons
              IconButton(
                icon: const Icon(Icons.home_outlined, color: Colors.white54),
                tooltip: 'Меню',
                onPressed: () {
                  _gameTimer?.cancel();
                  _isolate?.stop();
                  Navigator.pop(context);
                },
              ),
              IconButton(
                icon: const Icon(Icons.replay, color: Colors.white54),
                tooltip: 'Заново',
                onPressed: () {
                  _gameTimer?.cancel();
                  _isolate?.stop();
                  Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const SightReadingScreen()));
                },
              ),
              // Center: BPM
              Expanded(
                child: !_gameOver ? Center(
                  child: Text('${_generator.bpm} BPM',
                    style: const TextStyle(fontSize: 14, color: Color(0xFF666677))),
                ) : const SizedBox.shrink(),
              ),
              // Right: hearts + score
              if (!_gameOver) ...[
                Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
                  final alive = i < _tracker.lives;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Icon(
                      alive ? Icons.favorite : Icons.favorite_border,
                      color: alive ? const Color(0xFFF44336) : const Color(0xFF444455),
                      size: 22,
                    ),
                  );
                })),
                const SizedBox(width: 12),
              ],
              Text('${_tracker.totalHits}',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold,
                  color: Color(0xFFFFD740),
                  shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
              const SizedBox(width: 12),
            ]),
          ),

        // Status
        if (_status.isNotEmpty)
          Center(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(color: Colors.black87,
                borderRadius: BorderRadius.circular(12)),
            child: Text(_status,
                style: const TextStyle(fontSize: 22, color: Colors.white)),
          )),

        if (_loading)
          const Center(child: CircularProgressIndicator(color: Color(0xFFFFD740))),

        // Game over overlay
        if (_gameOver)
          Center(child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2030),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFD740), width: 2),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Game Over',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold,
                      color: Color(0xFFF44336))),
              const SizedBox(height: 16),
              Text('${_tracker.totalHits}', style: const TextStyle(fontSize: 56,
                  fontWeight: FontWeight.bold, color: Color(0xFFFFD740))),
              const Text('нот сыграно', style: TextStyle(
                  fontSize: 14, color: Color(0xFF888888))),
              const SizedBox(height: 8),
              Text('Лучший: $_bestScore', style: const TextStyle(
                  fontSize: 16, color: Color(0xFF4CAF50))),
              const SizedBox(height: 24),
              Row(mainAxisSize: MainAxisSize.min, children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF444455)),
                    foregroundColor: Colors.white70,
                  ),
                  child: const Text('Меню'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const SightReadingScreen())),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD740),
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Ещё раз'),
                ),
              ]),
            ]),
          )),

      ]),
    );
  }
}
