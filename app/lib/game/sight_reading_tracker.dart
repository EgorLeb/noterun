import 'midi_note.dart';
import 'score_tracker.dart';

class SightReadingTracker {
  final List<TrackedNote> tracked = [];
  final double hitWindowBefore;
  final double hitWindowAfter;
  int lives     = 3;
  int totalHits = 0;

  SightReadingTracker({
    this.hitWindowBefore = 0.4,
    this.hitWindowAfter  = 0.6,
  });

  void addNotes(List<MidiNote> notes) {
    for (final n in notes) {
      tracked.add(TrackedNote(n));
    }
  }

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
          lives--;
        }
      }
    }
    return (opened: justOpened, missed: justMissed);
  }

  TrackedNote? onPitchDetected(int midiPitch) {
    TrackedNote? best;
    for (final t in tracked) {
      if (t.state == NoteState.inWindow && t.note.pitch == midiPitch) {
        best ??= t;
      }
    }
    if (best != null) {
      best.state = NoteState.hit;
      totalHits++;
    }
    return best;
  }

  bool get isGameOver => lives <= 0;

  /// Prune old notes to avoid unbounded memory growth.
  void prune(double elapsedSec, double keepPastSec) {
    tracked.removeWhere((t) =>
      (t.state == NoteState.hit || t.state == NoteState.missed)
      && t.note.endSec < elapsedSec - keepPastSec - 1.0);
  }
}
