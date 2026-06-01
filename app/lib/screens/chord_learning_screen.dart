import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import '../ml/inference_isolate.dart';
import '../game/chord_data.dart';
import '../game/chord_staff_painter.dart';
import '../game/level_progress.dart';

class ChordLearningScreen extends StatefulWidget {
  final ChordDefinition chord;
  const ChordLearningScreen({super.key, required this.chord});

  @override
  State<ChordLearningScreen> createState() => _ChordLearningScreenState();
}

class _ChordLearningScreenState extends State<ChordLearningScreen> {
  Set<int> _played    = {};
  bool _complete      = false;
  bool _loading       = true;
  bool _finished      = false;
  String _status      = 'Загрузка…';
  int  _attempts      = 0; // wrong notes
  int  _completions   = 0;
  bool _debounce      = false;

  double _completionAge = 0.0;
  Timer? _animTimer;
  Timer? _debounceTimer;

  InferenceIsolate? _isolate;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    _isolate = InferenceIsolate(
      onNoteDetected: _onPitch,
      onConfidenceUp: (pitch, level) {
        if (level >= 2) _onPitch(pitch, 0);
      },
      onError: (e) {
        if (mounted) setState(() => _status = e);
      },
    );
    try {
      await _isolate!.start();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _status = 'Error: $e'; });
      return;
    }
    if (!mounted) return;
    setState(() { _loading = false; _status = ''; });
  }

  void _onPitch(int pitch, int backMs) {
    if (_loading || _finished || _debounce || _complete) return;

    final chord = widget.chord.pitches;

    if (chord.contains(pitch)) {
      if (_played.contains(pitch)) return; // already played this note
      setState(() => _played = {..._played, pitch});

      if (_played.length == chord.length) {
        // All notes played — chord complete!
        _complete = true;
        _completionAge = 0.0;
        _completions++;
        _debounce = true;

        _animTimer?.cancel();
        _animTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
          if (!mounted) return;
          setState(() => _completionAge = (_completionAge + 0.04).clamp(0.0, 1.0));
          if (_completionAge >= 1.0) {
            _animTimer?.cancel();
            // After 5 completions, show "done" screen; otherwise reset
            if (_completions >= 5) {
              _onFinish();
            } else {
              setState(() {
                _played    = {};
                _complete  = false;
                _completionAge = 0.0;
                _debounce  = false;
              });
            }
          }
        });
      }
    } else {
      // Wrong note
      if (_debounce) return;
      _attempts++;
      Vibration.vibrate(duration: 60, amplitude: 150);
      _debounce = true;
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _debounce = false);
      });
      setState(() {});
    }
  }

  void _onFinish() async {
    setState(() => _finished = true);
    _isolate?.stop();
    await LevelProgress.reportChordResult(
        widget.chord.key, attempts: _attempts);
  }

  @override
  void dispose() {
    _animTimer?.cancel();
    _debounceTimer?.cancel();
    _isolate?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chord = widget.chord;
    final remaining = chord.pitches.where((p) => !_played.contains(p)).length;

    return Scaffold(
      body: Stack(children: [
        // Staff
        CustomPaint(
          painter: ChordStaffPainter(
            pitches:       chord.pitches,
            played:        _played,
            completionAge: _completionAge,
            complete:      _complete,
          ),
          child: const SizedBox.expand(),
        ),

        // Top bar
        Positioned(top: 0, left: 0, right: 0,
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.home_outlined, color: Colors.white54),
              onPressed: () { _isolate?.stop(); Navigator.pop(context); },
            ),
            IconButton(
              icon: const Icon(Icons.replay, color: Colors.white54),
              onPressed: () {
                _isolate?.stop();
                Navigator.pushReplacement(context, MaterialPageRoute(
                  builder: (_) => ChordLearningScreen(chord: widget.chord)));
              },
            ),
            Expanded(
              child: Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(chord.name,
                    style: const TextStyle(fontSize: 16,
                        fontWeight: FontWeight.bold, color: Colors.white)),
                  Text(chord.description,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF888888))),
                ],
              )),
            ),
            // Completions counter
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                ...List.generate(5, (i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(
                    i < _completions ? Icons.circle : Icons.circle_outlined,
                    size: 12,
                    color: i < _completions
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFF444455),
                  ),
                )),
              ]),
            ),
          ]),
        ),

        // Hint: remaining notes
        if (!_loading && !_finished && !_complete)
          Positioned(bottom: 16, left: 0, right: 0,
            child: Center(child: Text(
              _played.isEmpty
                  ? 'Сыграй все ноты аккорда'
                  : 'Осталось нот: $remaining',
              style: TextStyle(
                fontSize: 14,
                color: _played.isEmpty
                    ? const Color(0xFF666677)
                    : const Color(0xFFFFD740),
              ),
            )),
          ),

        // Loading
        if (_loading)
          const Center(child: CircularProgressIndicator(color: Color(0xFFFFD740))),

        if (_status.isNotEmpty && !_loading)
          Center(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(color: Colors.black87,
                borderRadius: BorderRadius.circular(12)),
            child: Text(_status,
                style: const TextStyle(fontSize: 18, color: Colors.white)),
          )),

        // Completion overlay (after 5 times)
        if (_finished)
          Center(child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2030),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF4CAF50), width: 2),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle, size: 52, color: Color(0xFF4CAF50)),
              const SizedBox(height: 12),
              Text(chord.name,
                  style: const TextStyle(fontSize: 22,
                      fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 4),
              Text('${chord.symbol}', style: const TextStyle(
                  fontSize: 36, fontWeight: FontWeight.bold,
                  color: Color(0xFFFFD740))),
              const SizedBox(height: 8),
              Text('Лишних нот: $_attempts',
                  style: const TextStyle(fontSize: 14, color: Colors.white70)),
              const SizedBox(height: 24),
              Row(mainAxisSize: MainAxisSize.min, children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF444455)),
                    foregroundColor: Colors.white70,
                  ),
                  child: const Text('Назад'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) =>
                        ChordLearningScreen(chord: widget.chord))),
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
