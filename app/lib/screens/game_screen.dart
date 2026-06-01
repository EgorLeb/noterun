import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import '../ml/inference_isolate.dart';
import '../game/midi_parser.dart';
import '../game/midi_note.dart';
import '../game/score_tracker.dart';
import '../game/game_staff_painter.dart';
import 'result_screen.dart';

class GameScreen extends StatefulWidget {
  final String piece;
  final String midiAsset;
  final int originalQuarterMs;
  final int selectedQuarterMs;
  final String pieceId;
  final int? campaignLevel; // null = free play

  const GameScreen({super.key,
    required this.piece,
    required this.midiAsset,
    required this.originalQuarterMs,
    required this.selectedQuarterMs,
    required this.pieceId,
    this.campaignLevel,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  List<MidiNote>    _midiNotes  = [];
  ScoreTracker?     _tracker;
  InferenceIsolate? _isolate;
  final _stopwatch  = Stopwatch();
  Timer?            _gameTimer;
  bool              _loading    = true;
  String            _status     = 'Loading model…';

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
    try {
      final data  = await rootBundle.load(widget.midiAsset);
      final bytes = data.buffer.asUint8List();
      final raw   = MidiParser.parse(bytes);
      final scale = widget.selectedQuarterMs / widget.originalQuarterMs;
      final notes = raw.map((n) => MidiNote(
        pitch:    n.pitch,
        startSec: n.startSec * scale,
        endSec:   n.endSec   * scale,
      )).toList();

      if (!mounted) return;
      setState(() { _midiNotes = notes; _tracker = ScoreTracker(notes); });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _status = 'MIDI error: $e'; });
      return;
    }

    _isolate = InferenceIsolate(
      onNoteDetected: (pitch, backMs) {
        final hit = _tracker?.onPitchDetected(pitch);
        if (hit != null) {
          _hitEffects.add(HitEffect(pitch: hit.note.pitch, noteSec: hit.note.startSec));
        }
      },
      onConfidenceUp: (pitch, level) {
        if (level >= 2) _tracker?.onPitchDetected(pitch);
      },
      onError: (e) {
        if (mounted) setState(() => _status = 'Mic: $e');
      },
    );

    try {
      await _isolate!.start();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _status = 'Model error: $e'; });
      return;
    }

    if (!mounted) return;
    setState(() { _loading = false; _status = 'Get ready…'; });
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    _stopwatch.start();
    _gameTimer = Timer.periodic(const Duration(milliseconds: 16), _onTick);
    setState(() => _status = '');
  }

  void _onTick(Timer _) {
    if (!mounted) return;
    final tracker = _tracker;
    if (tracker == null) return;

    final elapsed = _stopwatch.elapsedMilliseconds / 1000.0 - _startOffsetSec;
    final result = tracker.update(elapsed);
    if (result.missed.isNotEmpty) {
      Vibration.vibrate(duration: 100, amplitude: 200);
    }

    // Advance and prune hit effects
    for (final e in _hitEffects) {
      e.age = (e.age + 0.016 / _effectDurSec).clamp(0.0, 1.0);
    }
    _hitEffects.removeWhere((e) => e.age >= 1.0);

    setState(() {});

    final lastNote = _midiNotes.isEmpty ? 0.0 : _midiNotes.last.endSec;
    if (elapsed > lastNote + _pastSec && tracker.isFinished) {
      _endGame();
    }
  }

  void _endGame() {
    _gameTimer?.cancel();
    _isolate?.stop();
    _stopwatch.stop();
    if (!mounted) return;
    final tracker = _tracker!;
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => ResultScreen(
        piece:             widget.piece,
        hits:              tracker.hits,
        total:             tracker.totalNotes,
        notes:             tracker.tracked,
        pieceId:           widget.pieceId,
        midiAsset:         widget.midiAsset,
        originalQuarterMs: widget.originalQuarterMs,
        selectedQuarterMs: widget.selectedQuarterMs,
        campaignLevel:     widget.campaignLevel,
      ),
    ));
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
    final tracker = _tracker;
    final hits    = tracker?.hits       ?? 0;
    final total   = tracker?.totalNotes ?? 0;

    return Scaffold(
      body: Stack(children: [
        if (tracker != null)
          CustomPaint(
            painter: GameStaffPainter(
              notes:        tracker.tracked,
              elapsedSec:   elapsed,
              pxPerSec:     _pxPerSec,
              lookaheadSec: _lookaheadSec,
              pastSec:      _pastSec,
              hitEffects:   List.unmodifiable(_hitEffects),
              quarterSec:   widget.selectedQuarterMs / 1000.0,
            ),
            child: const SizedBox.expand(),
          ),

        if (!_loading)
          Positioned(top: 12, right: 16,
            child: Text('$hits / $total',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold,
                color: Color(0xFFFFD740),
                shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
            ),
          ),

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

        Positioned(top: 8, left: 8,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
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
              tooltip: 'Ещё раз',
              onPressed: () {
                _gameTimer?.cancel();
                _isolate?.stop();
                Navigator.pushReplacement(context, MaterialPageRoute(
                  builder: (_) => GameScreen(
                    piece:             widget.piece,
                    midiAsset:         widget.midiAsset,
                    originalQuarterMs: widget.originalQuarterMs,
                    selectedQuarterMs: widget.selectedQuarterMs,
                    pieceId:           widget.pieceId,
                    campaignLevel:     widget.campaignLevel,
                  ),
                ));
              },
            ),
          ]),
        ),
      ]),
    );
  }
}
