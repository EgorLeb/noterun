class MidiNote {
  final int pitch;       // MIDI 0-127
  final double startSec;
  final double endSec;

  const MidiNote({required this.pitch, required this.startSec, required this.endSec});

  double get durationSec => endSec - startSec;
}
