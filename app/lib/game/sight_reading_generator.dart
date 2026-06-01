import 'dart:math';
import 'midi_note.dart';

class SightReadingGenerator {
  int    _totalGenerated = 0;
  int    _correctCount   = 0;
  double _quarterSec     = 1.0;   // starts slow
  double _nextStartSec   = 2.0;   // first note at 2s
  final  _rng            = Random();

  int    _lastPitch      = 60;    // C4

  // C major scale in octave 4
  static const _cMajor = [60, 62, 64, 65, 67, 69, 71];

  // Chord templates for difficulty 2 (arpeggios)
  static const _chords = [
    [60, 64, 67],  // C major
    [62, 65, 69],  // D minor
    [64, 67, 71],  // E minor
    [65, 69, 72],  // F major
    [67, 71, 74],  // G major
    [69, 72, 76],  // A minor
  ];

  double get quarterSec => _quarterSec;
  int get bpm => (60.0 / _quarterSec).round();

  int get _difficulty {
    if (_totalGenerated >= 25) return 2;
    if (_totalGenerated >= 10) return 1;
    return 0;
  }

  /// Generate the next batch of notes.
  List<MidiNote> generateNext() {
    final notes = <MidiNote>[];

    switch (_difficulty) {
      case 0: // Single notes from C major
        final pitch = _pickScaleNote();
        notes.add(MidiNote(
          pitch:    pitch,
          startSec: _nextStartSec,
          endSec:   _nextStartSec + _quarterSec * 0.9,
        ));
        _nextStartSec += _quarterSec;
        _lastPitch = pitch;
        break;

      case 1: // Melodic interval (two notes)
        final root  = _pickScaleNote();
        // Add a third or fifth above
        final intervals = [3, 4, 7]; // minor 3rd, major 3rd, fifth
        final interval  = intervals[_rng.nextInt(intervals.length)];
        final second    = root + interval;

        final gap = _quarterSec * 0.5;
        notes.add(MidiNote(
          pitch:    root,
          startSec: _nextStartSec,
          endSec:   _nextStartSec + gap * 0.9,
        ));
        notes.add(MidiNote(
          pitch:    second,
          startSec: _nextStartSec + gap,
          endSec:   _nextStartSec + gap + gap * 0.9,
        ));
        _nextStartSec += _quarterSec + gap;
        _lastPitch = second;
        break;

      case 2: // Arpeggio (3 notes)
        final chord = _chords[_rng.nextInt(_chords.length)];
        final gap   = _quarterSec * 0.33;
        for (int i = 0; i < chord.length; i++) {
          notes.add(MidiNote(
            pitch:    chord[i],
            startSec: _nextStartSec + gap * i,
            endSec:   _nextStartSec + gap * i + gap * 0.9,
          ));
        }
        _nextStartSec += _quarterSec + gap * 2;
        _lastPitch = chord.last;
        break;
    }

    _totalGenerated += notes.length;
    return notes;
  }

  int _pickScaleNote() {
    // Pick a note within a fifth of the last note
    final candidates = <int>[];
    for (final p in _cMajor) {
      if ((p - _lastPitch).abs() <= 7) candidates.add(p);
    }
    // Also consider octave above/below
    for (final p in _cMajor) {
      if ((p + 12 - _lastPitch).abs() <= 7) candidates.add(p + 12);
      if ((p - 12 - _lastPitch).abs() <= 7 && p - 12 >= 48) candidates.add(p - 12);
    }
    if (candidates.isEmpty) return _cMajor[_rng.nextInt(_cMajor.length)];
    return candidates[_rng.nextInt(candidates.length)];
  }

  void onCorrect() {
    _correctCount++;
    if (_correctCount >= 5) {
      _correctCount = 0;
      _quarterSec = (_quarterSec - 0.02).clamp(0.4, 2.0);
    }
  }

  void onMiss() {
    _correctCount = 0;
  }
}
