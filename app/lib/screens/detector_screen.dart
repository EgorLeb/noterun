import 'dart:async';
import 'package:flutter/material.dart';
import '../ml/inference_isolate.dart';
import '../staff_painter.dart';

class DetectorScreen extends StatefulWidget {
  const DetectorScreen({super.key});
  @override
  State<DetectorScreen> createState() => _DetectorScreenState();
}

class _DetectorScreenState extends State<DetectorScreen> {
  InferenceIsolate? _isolate;
  bool _listening  = false;
  bool _starting   = false;
  String _status   = 'Ready — tap Listen';
  String _debugInfo = '';

  final _notes = <ActiveNote>[];
  Timer? _repaintTimer;

  @override
  void initState() {
    super.initState();
    _repaintTimer = Timer.periodic(const Duration(milliseconds: 32), (_) {
      if (mounted) setState(() {
        _notes.removeWhere(
          (n) => DateTime.now().difference(n.arrivedAt).inMilliseconds > 8000,
        );
      });
    });
  }

  Future<void> _startListening() async {
    setState(() { _starting = true; _status = 'Loading model…'; _notes.clear(); });

    _isolate = InferenceIsolate(
      onNoteDetected: (pitch, backMs) {
        if (!mounted) return;
        setState(() {
          final onsetTime = DateTime.now().subtract(Duration(milliseconds: backMs));
          final hasDup = _notes.any((n) =>
              n.pitch == pitch &&
              onsetTime.difference(n.arrivedAt).abs().inMilliseconds < 350);
          if (!hasDup) _notes.add(ActiveNote(pitch, backMs: backMs));
        });
      },
      onConfidenceUp: (pitch, level) {
        if (!mounted) return;
        setState(() {
          final now = DateTime.now();
          final match = _notes
              .where((n) => n.pitch == pitch &&
                  now.difference(n.arrivedAt).inMilliseconds < 8000)
              .fold<ActiveNote?>(null, (best, n) =>
                  best == null || n.arrivedAt.isAfter(best.arrivedAt) ? n : best);
          if (match != null && match.confidence < level) match.confidence = level;
        });
      },
      onDebug: (maxP) {
        if (mounted) setState(() {
          _debugInfo = 'max P(note): ${(maxP * 100).toStringAsFixed(1)}%';
        });
      },
      onError: (err) {
        if (mounted) setState(() {
          _status = 'Error: $err';
          _listening = false;
          _starting  = false;
        });
      },
    );

    try {
      await _isolate!.start();
      if (mounted) setState(() {
        _listening = true;
        _starting  = false;
        _status    = 'Listening…';
      });
    } catch (e) {
      if (mounted) setState(() { _status = 'Failed: $e'; _starting = false; });
    }
  }

  void _stopListening() {
    _isolate?.stop();
    _isolate = null;
    setState(() { _listening = false; _status = 'Ready — tap Listen'; });
  }

  @override
  void dispose() {
    _repaintTimer?.cancel();
    _isolate?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        Expanded(child: CustomPaint(
          painter: StaffPainter(List.from(_notes)),
          child: const SizedBox.expand(),
        )),
        Container(
          height: 52, color: const Color(0xFF1A1A1A),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.home_outlined, color: Colors.white54),
              tooltip: 'Меню',
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_status,
                    style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 12)),
                if (_debugInfo.isNotEmpty)
                  Text(_debugInfo,
                      style: const TextStyle(color: Color(0xFF66BB6A), fontSize: 11)),
              ],
            )),
            ElevatedButton(
              onPressed: _starting ? null
                  : (_listening ? _stopListening : _startListening),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD740),
                foregroundColor: Colors.black,
              ),
              child: _starting
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : Text(_listening ? 'Stop' : 'Listen'),
            ),
          ]),
        ),
      ]),
    );
  }
}
