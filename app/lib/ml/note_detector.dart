import 'dart:async';
import 'dart:typed_data';
import 'package:mic_stream/mic_stream.dart';
import 'mel_extractor.dart';
import 'onnx_transcriber.dart';

// ── NoteProcessor ──────────────────────────────────────────────────────────────
// Same logic as NoteDetector but WITHOUT mic capture.
// Designed to run in a background isolate: accepts raw PCM bytes via feed().
class NoteProcessor {
  final OnnxTranscriber transcriber;
  final MelExtractor melExtractor;
  final void Function(int pitch, int backMs) onNoteDetected;
  final void Function(int pitch, int level) onConfidenceUp;
  final void Function(String error)? onError;
  final void Function(double maxP)? onDebug;

  static const int _l1Frames = 5;
  static const int _l2Frames = 10;
  static const int _l3Frames = 25;
  static const int _samplesPerFrame = 512;
  static const int _l1Samples = _l1Frames * _samplesPerFrame;
  static const int _l2Samples = _l2Frames * _samplesPerFrame;
  static const int _l3Samples = _l3Frames * _samplesPerFrame;
  static const int _minDur  = 1;
  static const int _minGap  = 2;
  static const int _offHyst = 2;
  static const int _msPerFrame = MelExtractor.hopLength * 1000 ~/ MelExtractor.sampleRate;
  static const int _pitchShift = 0;
  final double pitchDelta;

  final _durCounters = List<int>.filled(88, 0);
  final _gapCounters = List<int>.filled(88, 0);
  final _offCounters = List<int>.filled(88, 0);
  final _noteActive  = List<bool>.filled(88, false);
  final _confirmed   = List<bool>.filled(88, false);
  final _accumSamples = <int>[];
  final _l2Buffer = <int>[];
  final _l3Buffer = <int>[];
  OrtState? _l2Snapshot;
  OrtState? _l3Snapshot;
  int _l1CountSinceL2 = 0;
  int _l1CountSinceL3 = 0;

  NoteProcessor({
    required this.transcriber,
    required this.melExtractor,
    required this.onNoteDetected,
    required this.onConfidenceUp,
    this.pitchDelta = 0.0,
    this.onError,
    this.onDebug,
  }) {
    transcriber.reset();
  }

  /// Feed raw 16-bit PCM bytes from the mic stream.
  void feed(List<int> bytes) {
    for (int i = 0; i + 1 < bytes.length; i += 2) {
      int s = ((bytes[i + 1] & 0xFF) << 8) | (bytes[i] & 0xFF);
      if (s >= 0x8000) s -= 0x10000;
      _accumSamples.add(s);
      _l2Buffer.add(s);
      _l3Buffer.add(s);
    }
    if (_l2Buffer.length > _l2Samples)
      _l2Buffer.removeRange(0, _l2Buffer.length - _l2Samples);
    if (_l3Buffer.length > _l3Samples)
      _l3Buffer.removeRange(0, _l3Buffer.length - _l3Samples);

    while (_accumSamples.length >= _l1Samples) {
      final chunk = Int16List.fromList(_accumSamples.sublist(0, _l1Samples));
      _accumSamples.removeRange(0, _l1Samples);
      _processL1(chunk);
    }
  }

  void _processL1(Int16List chunk) {
    try {
      final melFlat = melExtractor.extract(chunk);
      final frames  = melFlat.length ~/ MelExtractor.nMels;
      if (frames == 0) return;

      if (_l1CountSinceL2 == 0) _l2Snapshot = transcriber.saveState();
      if (_l1CountSinceL3 == 0) _l3Snapshot = transcriber.saveState();

      final preds = transcriber.processChunk(melFlat, frames);
      onDebug?.call(transcriber.lastMaxNoteP);
      _trackNotes(preds, frames);

      _l1CountSinceL2++;
      _l1CountSinceL3++;

      if (_l1CountSinceL2 >= _l2Frames ~/ _l1Frames) {
        _l1CountSinceL2 = 0;
        if (_l2Buffer.length >= _l2Samples && _l2Snapshot != null)
          _runSlow(Int16List.fromList(_l2Buffer), _l2Snapshot!, level: 2);
      }
      if (_l1CountSinceL3 >= _l3Frames ~/ _l1Frames) {
        _l1CountSinceL3 = 0;
        if (_l3Buffer.length >= _l3Samples && _l3Snapshot != null)
          _runSlow(Int16List.fromList(_l3Buffer), _l3Snapshot!, level: 3);
      }
    } catch (e) {
      onError?.call('Inference: $e');
    }
  }

  void _runSlow(Int16List audio, OrtState snapshot, {required int level}) {
    try {
      final melFlat = melExtractor.extract(audio);
      final frames  = melFlat.length ~/ MelExtractor.nMels;
      if (frames == 0) return;
      final preds = transcriber.processChunkFromState(melFlat, frames, snapshot);
      final seen = <int>{};
      for (int f = 0; f < frames; f++)
        for (int p = 0; p < 88; p++)
          if (preds[f * 88 + p] > 0) seen.add(p);
      for (final p in seen) {
        if (!_confirmed[p]) {
          _confirmed[p]  = true;
          _noteActive[p] = true;
          onNoteDetected((p + 21 + _pitchShift + pitchDelta).round(), 0);
        }
        onConfidenceUp((p + 21 + _pitchShift + pitchDelta).round(), level);
      }
    } catch (_) {}
  }

  void _trackNotes(Int32List preds, int frames) {
    for (int f = 0; f < frames; f++) {
      final frameBackMs = (frames - 1 - f) * _msPerFrame;
      for (int p = 0; p < 88; p++) {
        final isOn = preds[f * 88 + p] > 0;
        if (isOn) {
          _offCounters[p] = 0;
          if (!_noteActive[p]) {
            _durCounters[p]++;
            if (_durCounters[p] >= _minDur && !_confirmed[p]) {
              _confirmed[p]  = true;
              _noteActive[p] = true;
              _gapCounters[p] = 0;
              final onsetBackMs = frameBackMs + (_durCounters[p] - 1) * _msPerFrame;
              onNoteDetected((p + 21 + _pitchShift + pitchDelta).round(), onsetBackMs);
            }
          } else {
            _gapCounters[p] = 0;
          }
        } else {
          _offCounters[p]++;
          if (_offCounters[p] >= _offHyst) {
            if (_noteActive[p]) {
              _gapCounters[p]++;
              if (_gapCounters[p] >= _minGap) {
                _noteActive[p]  = false;
                _confirmed[p]   = false;
                _durCounters[p] = 0;
                _gapCounters[p] = 0;
              }
            } else {
              _durCounters[p] = 0;
              _confirmed[p]   = false;
            }
          }
        }
      }
    }
  }
}

class NoteDetector {
  final OnnxTranscriber transcriber;
  final MelExtractor melExtractor;
  final void Function(int pitch, int backMs) onNoteDetected;
  final void Function(int pitch, int level) onConfidenceUp;
  final void Function(String error)? onError;
  final void Function(double maxP)? onDebug;

  // Level 1: 5 frames  = 160 ms — fast (minimum: nFft=2048 needs ≥5 frames)
  // Level 2: 10 frames = 320 ms — medium, from snapshot
  // Level 3: 25 frames = 800 ms — slow, from snapshot
  static const int _l1Frames = 5;
  static const int _l2Frames = 10;
  static const int _l3Frames = 25;

  static const int _samplesPerFrame = 512;
  static const int _l1Samples = _l1Frames * _samplesPerFrame;  // 1024
  static const int _l2Samples = _l2Frames * _samplesPerFrame;  // 2560
  static const int _l3Samples = _l3Frames * _samplesPerFrame;  // 10240

  static const int _minDur  = 1;
  static const int _minGap  = 2;
  static const int _offHyst = 2;

  // Note tracking (driven by level 1 — the authoritative main path)
  final _durCounters = List<int>.filled(88, 0);
  final _gapCounters = List<int>.filled(88, 0);
  final _offCounters = List<int>.filled(88, 0);
  final _noteActive  = List<bool>.filled(88, false);
  final _confirmed   = List<bool>.filled(88, false);

  StreamSubscription? _subscription;
  final _accumSamples = <int>[];

  // Rolling audio buffers for replay
  final _l2Buffer = <int>[];  // last _l2Samples
  final _l3Buffer = <int>[];  // last _l3Samples

  // Snapshots of GRU state at the start of each window
  OrtState? _l2Snapshot;
  OrtState? _l3Snapshot;

  // Counters to know when to trigger slow levels
  int _l1CountSinceL2 = 0;
  int _l1CountSinceL3 = 0;

  NoteDetector({
    required this.transcriber,
    required this.melExtractor,
    required this.onNoteDetected,
    required this.onConfidenceUp,
    this.pitchDelta = 0.0,
    this.onError,
    this.onDebug,
  });

  Future<void> start() async {
    _reset();
    try {
      final stream = await MicStream.microphone(
        sampleRate: 16000,
        channelConfig: ChannelConfig.CHANNEL_IN_MONO,
        audioFormat: AudioFormat.ENCODING_PCM_16BIT,
      );
      _subscription = stream.listen(
        _onAudioData,
        onError: (e) => onError?.call('Mic error: $e'),
      );
    } catch (e) {
      onError?.call('Mic init failed: $e');
    }
  }

  void _onAudioData(List<int> bytes) {
    for (int i = 0; i + 1 < bytes.length; i += 2) {
      int s = ((bytes[i + 1] & 0xFF) << 8) | (bytes[i] & 0xFF);
      if (s >= 0x8000) s -= 0x10000;
      _accumSamples.add(s);
      _l2Buffer.add(s);
      _l3Buffer.add(s);
    }
    if (_l2Buffer.length > _l2Samples) _l2Buffer.removeRange(0, _l2Buffer.length - _l2Samples);
    if (_l3Buffer.length > _l3Samples) _l3Buffer.removeRange(0, _l3Buffer.length - _l3Samples);

    while (_accumSamples.length >= _l1Samples) {
      final chunk = Int16List.fromList(_accumSamples.sublist(0, _l1Samples));
      _accumSamples.removeRange(0, _l1Samples);
      _processL1(chunk);
    }
  }

  void _processL1(Int16List chunk) {
    try {
      final melFlat = melExtractor.extract(chunk);
      final frames  = melFlat.length ~/ MelExtractor.nMels;
      if (frames == 0) return;

      // Save snapshots at the start of each slow window
      if (_l1CountSinceL2 == 0) _l2Snapshot = transcriber.saveState();
      if (_l1CountSinceL3 == 0) _l3Snapshot = transcriber.saveState();

      final preds = transcriber.processChunk(melFlat, frames);
      onDebug?.call(transcriber.lastMaxNoteP);
      _trackNotes(preds, frames);

      _l1CountSinceL2++;
      _l1CountSinceL3++;

      if (_l1CountSinceL2 >= _l2Frames ~/ _l1Frames) {
        _l1CountSinceL2 = 0;
        if (_l2Buffer.length >= _l2Samples && _l2Snapshot != null) {
          _runSlow(Int16List.fromList(_l2Buffer), _l2Snapshot!, level: 2);
        }
      }

      if (_l1CountSinceL3 >= _l3Frames ~/ _l1Frames) {
        _l1CountSinceL3 = 0;
        if (_l3Buffer.length >= _l3Samples && _l3Snapshot != null) {
          _runSlow(Int16List.fromList(_l3Buffer), _l3Snapshot!, level: 3);
        }
      }
    } catch (e) {
      onError?.call('Inference: $e');
      stop();
    }
  }

  void _runSlow(Int16List audioChunk, OrtState snapshot, {required int level}) {
    try {
      final melFlat = melExtractor.extract(audioChunk);
      final frames  = melFlat.length ~/ MelExtractor.nMels;
      if (frames == 0) return;

      final preds = transcriber.processChunkFromState(melFlat, frames, snapshot);

      // Collect pitches seen in this slow window
      final seen = <int>{};
      for (int f = 0; f < frames; f++) {
        for (int p = 0; p < 88; p++) {
          if (preds[f * 88 + p] > 0) seen.add(p);
        }
      }

      for (final p in seen) {
        if (!_confirmed[p]) {
          // New note missed by L1 — add it
          _confirmed[p]  = true;
          _noteActive[p] = true;
          onNoteDetected((p + 21 + _pitchShift + pitchDelta).round(), 0);
        }
        // Upgrade confidence for this pitch regardless
        onConfidenceUp((p + 21 + _pitchShift + pitchDelta).round(), level);
      }
    } catch (_) {
      // slow level errors are non-fatal
    }
  }

  // ms per mel frame: hopLength / sampleRate * 1000
  static const int _msPerFrame = MelExtractor.hopLength * 1000 ~/ MelExtractor.sampleRate; // 32ms

  // The model systematically outputs pitches one octave too high relative to
  // standard MIDI / scientific pitch notation — compensate by -12.
  static const int _pitchShift = 0;
  final double pitchDelta;

  void _trackNotes(Int32List preds, int frames) {
    for (int f = 0; f < frames; f++) {
      // How many ms ago was this frame relative to "now" (end of chunk)?
      final frameBackMs = (frames - 1 - f) * _msPerFrame;

      for (int p = 0; p < 88; p++) {
        final isOn = preds[f * 88 + p] > 0;
        if (isOn) {
          _offCounters[p] = 0;
          if (!_noteActive[p]) {
            _durCounters[p]++;
            if (_durCounters[p] >= _minDur && !_confirmed[p]) {
              _confirmed[p]   = true;
              _noteActive[p]  = true;
              _gapCounters[p] = 0;
              // Pass onset time: backtrack to the first "on" frame
              final onsetBackMs = frameBackMs + (_durCounters[p] - 1) * _msPerFrame;
              onNoteDetected((p + 21 + _pitchShift + pitchDelta).round(), onsetBackMs);
            }
          } else {
            _gapCounters[p] = 0;
          }
        } else {
          _offCounters[p]++;
          if (_offCounters[p] >= _offHyst) {
            if (_noteActive[p]) {
              _gapCounters[p]++;
              if (_gapCounters[p] >= _minGap) {
                _noteActive[p]  = false;
                _confirmed[p]   = false;
                _durCounters[p] = 0;
                _gapCounters[p] = 0;
              }
            } else {
              _durCounters[p] = 0;
              _confirmed[p]   = false;
            }
          }
        }
      }
    }
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _accumSamples.clear();
    _l2Buffer.clear();
    _l3Buffer.clear();
  }

  void _reset() {
    transcriber.reset();
    _durCounters.fillRange(0, 88, 0);
    _gapCounters.fillRange(0, 88, 0);
    _offCounters.fillRange(0, 88, 0);
    _noteActive.fillRange(0, 88, false);
    _confirmed.fillRange(0, 88, false);
    _accumSamples.clear();
    _l2Buffer.clear();
    _l3Buffer.clear();
    _l2Snapshot = null;
    _l3Snapshot = null;
    _l1CountSinceL2 = 0;
    _l1CountSinceL3 = 0;
  }
}
