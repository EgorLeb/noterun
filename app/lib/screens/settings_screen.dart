import 'package:flutter/material.dart';
import '../services/device_settings.dart';
import '../ml/inference_isolate.dart';

// ─── helpers ─────────────────────────────────────────────────────────────────

String _midiName(int midi) {
  const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  final octave = (midi ~/ 12) - 1;
  return '${names[midi % 12]}$octave';
}

String _fmtDelta(double d) {
  if (d == 0.0) return '0 (стандарт)';
  final s = d.toStringAsFixed(1);
  return d > 0 ? '+$s пт' : '$s пт';
}

// ─────────────────────────────────────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _pitchDelta = 0.0;
  bool   _loading    = true;

  // Live calibration
  InferenceIsolate? _calIsolate;
  bool              _calRunning  = false;
  int?              _lastPitch;          // last detected MIDI pitch
  DateTime?         _lastPitchTime;      // to fade out after silence

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _stopCal();
    super.dispose();
  }

  Future<void> _load() async {
    final delta = await DeviceSettings.getPitchDelta();
    if (mounted) setState(() { _pitchDelta = delta; _loading = false; });
  }

  // ── Calibration lifecycle ────────────────────────────────────────────────────

  Future<void> _startCal() async {
    await _stopCal();
    if (!mounted) return;
    setState(() { _calRunning = true; _lastPitch = null; });

    _calIsolate = InferenceIsolate(
      onNoteDetected: _onNote,
      onConfidenceUp: (_, __) {},
      onError: (e) {
        if (mounted) setState(() { _calRunning = false; });
      },
    );
    await _calIsolate!.start(pitchDeltaOverride: _pitchDelta);
  }

  Future<void> _stopCal() async {
    _calIsolate?.stop();
    _calIsolate = null;
    if (mounted) setState(() { _calRunning = false; });
  }

  void _onNote(int pitch, int backMs) {
    if (!mounted) return;
    setState(() {
      _lastPitch     = pitch;
      _lastPitchTime = DateTime.now();
    });
  }

  /// Restart isolate with updated delta (called when slider changes).
  Future<void> _restartCalWithDelta(double delta) async {
    if (!_calRunning) return;
    _calIsolate?.stop();
    _calIsolate = null;
    setState(() => _lastPitch = null);

    _calIsolate = InferenceIsolate(
      onNoteDetected: _onNote,
      onConfidenceUp: (_, __) {},
      onError: (_) {},
    );
    await _calIsolate!.start(pitchDeltaOverride: delta);
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.home_outlined, color: Colors.white54),
                onPressed: () { _stopCal(); Navigator.pop(context); },
              ),
              const SizedBox(width: 8),
              const Text('Настройки', style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
            ]),
          ),

          if (_loading)
            const Expanded(child: Center(
                child: CircularProgressIndicator(color: Color(0xFFFFD740))))
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  const SizedBox(height: 8),
                  _buildPitchBlock(),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Настройки сохраняются на этом устройстве и не привязаны к аккаунту.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF444455)),
                    ),
                  ),
                ],
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildPitchBlock() {
    final isC4 = _lastPitch == 60;
    final pitchName = _lastPitch != null ? _midiName(_lastPitch!) : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(children: [
            const Icon(Icons.tune, color: Color(0xFFFFD740), size: 22),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Настройка тона',
                  style: TextStyle(fontSize: 17,
                      fontWeight: FontWeight.bold, color: Colors.white)),
            ),
            // Current delta badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _pitchDelta == 0
                    ? const Color(0xFF333344)
                    : const Color(0xFFFFD740).withAlpha(30),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _pitchDelta == 0
                      ? const Color(0xFF444455)
                      : const Color(0xFFFFD740),
                ),
              ),
              child: Text(
                _fmtDelta(_pitchDelta),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _pitchDelta == 0
                      ? const Color(0xFF888888)
                      : const Color(0xFFFFD740),
                ),
              ),
            ),
          ]),

          const SizedBox(height: 6),
          const Text(
            'Нажмите "Начать проверку", сыграйте C4 и крутите ползунок '
            'пока приложение не распознает ноту правильно.',
            style: TextStyle(fontSize: 12, color: Color(0xFF888888)),
          ),
          const SizedBox(height: 16),

          // Start / Stop button
          Row(children: [
            Expanded(
              child: _calRunning
                  ? OutlinedButton.icon(
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text('Остановить'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white54,
                        side: const BorderSide(color: Color(0xFF444455)),
                      ),
                      onPressed: _stopCal,
                    )
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.mic, size: 18),
                      label: const Text('Начать проверку'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD740),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _startCal,
                    ),
            ),
          ]),

          // Live note indicator
          if (_calRunning) ...[
            const SizedBox(height: 20),
            Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: pitchName == null
                    ? const Text(
                        'Сыграйте C4...',
                        key: ValueKey('waiting'),
                        style: TextStyle(color: Color(0xFF555566), fontSize: 16),
                      )
                    : Column(
                        key: ValueKey(pitchName),
                        children: [
                          // Big note name
                          Text(
                            pitchName,
                            style: TextStyle(
                              fontSize: 52,
                              fontWeight: FontWeight.bold,
                              color: isC4
                                  ? Colors.greenAccent
                                  : const Color(0xFFFFD740),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(
                              isC4 ? Icons.check_circle : Icons.arrow_forward,
                              size: 16,
                              color: isC4
                                  ? Colors.greenAccent
                                  : const Color(0xFF888888),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isC4
                                  ? 'Верно!'
                                  : 'Ожидается C4 — крутите ползунок',
                              style: TextStyle(
                                fontSize: 13,
                                color: isC4
                                    ? Colors.greenAccent
                                    : const Color(0xFF888888),
                              ),
                            ),
                          ]),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ] else
            const SizedBox(height: 8),

          // ── Slider ────────────────────────────────────────────────────────
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor:    const Color(0xFFFFD740),
              inactiveTrackColor:  const Color(0xFF333344),
              thumbColor:          const Color(0xFFFFD740),
              overlayColor:        const Color(0x33FFD740),
              valueIndicatorColor: const Color(0xFFFFD740),
              valueIndicatorTextStyle: const TextStyle(
                  color: Colors.black, fontWeight: FontWeight.bold),
              showValueIndicator: ShowValueIndicator.always,
            ),
            child: Slider(
              value: _pitchDelta,
              min: -6.0,
              max:  6.0,
              divisions: 120,
              label: _pitchDelta == 0.0
                  ? '0'
                  : _pitchDelta > 0
                      ? '+${_pitchDelta.toStringAsFixed(1)}'
                      : _pitchDelta.toStringAsFixed(1),
              onChanged: (v) async {
                final d = (v * 10).round() / 10.0;
                setState(() { _pitchDelta = d; _lastPitch = null; });
                await DeviceSettings.setPitchDelta(d);
                await _restartCalWithDelta(d);
              },
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('-6', style: TextStyle(color: Color(0xFF666666), fontSize: 11)),
                Text('0',  style: TextStyle(color: Color(0xFF888888), fontSize: 11)),
                Text('+6', style: TextStyle(color: Color(0xFF666666), fontSize: 11)),
              ],
            ),
          ),

          const SizedBox(height: 12),

          if (_pitchDelta != 0.0)
            Center(
              child: TextButton(
                onPressed: () async {
                  setState(() { _pitchDelta = 0.0; _lastPitch = null; });
                  await DeviceSettings.setPitchDelta(0.0);
                  await _restartCalWithDelta(0.0);
                },
                child: const Text('Сбросить до стандарта',
                    style: TextStyle(color: Color(0xFF888888), fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }
}
