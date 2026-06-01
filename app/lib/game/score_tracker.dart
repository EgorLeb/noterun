import 'midi_note.dart';

enum NoteState { incoming, inWindow, hit, missed }

class TrackedNote {
  final MidiNote note;
  NoteState state;
  TrackedNote(this.note) : state = NoteState.incoming;
}

class ScoreTracker {
  final List<TrackedNote> tracked;
  final double hitWindowBefore; // seconds before beat to open window
  final double hitWindowAfter;  // seconds after beat to close window

  ScoreTracker(List<MidiNote> notes, {
    this.hitWindowBefore = 0.3,
    this.hitWindowAfter  = 0.5,
  }) : tracked = notes.map((n) => TrackedNote(n)).toList();

  int get totalNotes => tracked.length;
  int get hits   => tracked.where((t) => t.state == NoteState.hit).length;
  int get misses => tracked.where((t) => t.state == NoteState.missed).length;

  /// Call every frame with current elapsed time.
  ({List<TrackedNote> opened, List<TrackedNote> missed}) update(double elapsedSec) {
    final justOpened = <TrackedNote>[];
    final justMissed = <TrackedNote>[];
    for (final t in tracked) {
      if (t.state == NoteState.incoming) {
        if (elapsedSec >= t.note.startSec - hitWindowBefore) {
          t.state = NoteState.inWindow;
          justOpened.add(t);
        }
      } else if (t.state == NoteState.inWindow) {
        if (elapsedSec > t.note.startSec + hitWindowAfter) {
          t.state = NoteState.missed;
          justMissed.add(t);
        }
      }
    }
    return (opened: justOpened, missed: justMissed);
  }

  /// Call when ML detects a pitch. Returns the hit note or null if no match.
  TrackedNote? onPitchDetected(int midiPitch) {
    TrackedNote? best;
    for (final t in tracked) {
      if (t.state == NoteState.inWindow && t.note.pitch == midiPitch) {
        best ??= t;
      }
    }
    if (best != null) best.state = NoteState.hit;
    return best;
  }

  bool get isFinished => tracked.every(
      (t) => t.state == NoteState.hit || t.state == NoteState.missed);
}
