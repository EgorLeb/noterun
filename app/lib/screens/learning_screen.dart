import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import '../ml/inference_isolate.dart';
import '../game/scale_data.dart';
import '../game/learning_staff_painter.dart';
import '../game/level_progress.dart';

class LearningScreen extends StatefulWidget {
  final ScaleDefinition scale;
  const LearningScreen({super.key, required this.scale});

  @override
  State<LearningScreen> createState() => _LearningScreenState();
}

class _LearningScreenState extends State<LearningScreen> {
  late List<int> _fullScale;
  int  _currentIndex   = 0;
  int  _wrongAttempts  = 0;
  int  _streak         = 0;
  int  _bestStreak     = 0;
  bool _isPerfect      = true;
  bool _loading        = true;
  bool _finished       = false;
  String _status       = 'Загрузка модели…';

  LearningFeedback _feedback = LearningFeedback.none;
  double _feedbackAge = 0.0;
  Timer? _feedbackTimer;
  Timer? _animTimer;
  bool _debounce = false;

  InferenceIsolate? _isolate;

  @override
  void initState() {
    super.initState();
    _fullScale = widget.scale.full;
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

    // Animation timer for feedback effects
    _animTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_feedback != LearningFeedback.none) {
        setState(() {
          _feedbackAge = (_feedbackAge + 0.04).clamp(0.0, 1.0);
        });
      }
    });
  }

  void _onPitch(int pitch, int backMs) {
    if (_debounce || _finished || _loading) return;

    final target = _fullScale[_currentIndex];

    if (pitch == target) {
      _debounce = true;
      _streak++;
      if (_streak > _bestStreak) _bestStreak = _streak;

      setState(() {
        _feedback    = LearningFeedback.correct;
        _feedbackAge = 0.0;
      });

      _feedbackTimer?.cancel();
      _feedbackTimer = Timer(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        setState(() {
          _currentIndex++;
          _feedback = LearningFeedback.none;
          _debounce = false;
          if (_currentIndex >= _fullScale.length) _onComplete();
        });
      });
    } else {
      if (_feedback == LearningFeedback.wrong) return; // already showing
      _wrongAttempts++;
      _streak    = 0;
      _isPerfect = false;
      Vibration.vibrate(duration: 60, amplitude: 150);

      setState(() {
        _feedback    = LearningFeedback.wrong;
        _feedbackAge = 0.0;
      });

      _feedbackTimer?.cancel();
      _feedbackTimer = Timer(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        setState(() => _feedback = LearningFeedback.none);
      });
    }
  }

  void _onComplete() async {
    _finished = true;
    _isolate?.stop();
    await LevelProgress.reportScaleResult(
      widget.scale.key,
      perfect: _isPerfect,
      streak:  _bestStreak,
    );
  }

  @override
  void dispose() {
    _animTimer?.cancel();
    _feedbackTimer?.cancel();
    _isolate?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        // Staff
        CustomPaint(
          painter: LearningStaffPainter(
            scale:        _fullScale,
            currentIndex: _currentIndex,
            feedback:     _feedback,
            feedbackAge:  _feedbackAge,
          ),
          child: const SizedBox.expand(),
        ),

        // Top info
        if (!_loading && !_finished)
          Positioned(top: 10, left: 0, right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(widget.scale.name,
                    style: const TextStyle(fontSize: 18, color: Colors.white70,
                        fontWeight: FontWeight.bold)),
                const SizedBox(width: 24),
                Text('${_currentIndex} / ${_fullScale.length}',
                    style: const TextStyle(fontSize: 18, color: Color(0xFFFFD740),
                        fontWeight: FontWeight.bold)),
                const SizedBox(width: 24),
                if (_streak > 1) Text('$_streak подряд',
                    style: const TextStyle(fontSize: 14, color: Color(0xFF4CAF50))),
              ],
            ),
          ),

        // Loading
        if (_loading)
          const Center(child: CircularProgressIndicator(color: Color(0xFFFFD740))),

        if (_status.isNotEmpty && !_loading)
          Center(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(color: Colors.black87,
                borderRadius: BorderRadius.circular(12)),
            child: Text(_status,
                style: const TextStyle(fontSize: 22, color: Colors.white)),
          )),

        // Completion overlay
        if (_finished)
          Center(child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2030),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isPerfect ? const Color(0xFF4CAF50) : const Color(0xFFFFD740),
                width: 2,
              ),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                _isPerfect ? Icons.star : Icons.check_circle,
                size: 48,
                color: _isPerfect ? const Color(0xFFFFD740) : const Color(0xFF4CAF50),
              ),
              const SizedBox(height: 12),
              Text(
                _isPerfect ? 'Идеально!' : 'Гамма пройдена!',
                style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold,
                  color: _isPerfect ? const Color(0xFFFFD740) : const Color(0xFF4CAF50),
                ),
              ),
              const SizedBox(height: 8),
              Text('Ошибок: $_wrongAttempts  •  Лучшая серия: $_bestStreak',
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
                        LearningScreen(scale: widget.scale))),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD740),
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Ещё раз'),
                ),
              ]),
            ]),
          )),

        // Back + Replay buttons
        Positioned(top: 8, left: 8,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              icon: const Icon(Icons.home_outlined, color: Colors.white54),
              tooltip: 'Меню',
              onPressed: () {
                _isolate?.stop();
                Navigator.pop(context);
              },
            ),
            IconButton(
              icon: const Icon(Icons.replay, color: Colors.white54),
              tooltip: 'Заново',
              onPressed: () {
                _isolate?.stop();
                Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) =>
                      LearningScreen(scale: widget.scale)));
              },
            ),
          ]),
        ),
      ]),
    );
  }
}
