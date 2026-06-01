import 'dart:typed_data';
import 'midi_note.dart';

class MidiParser {
  static List<MidiNote> parse(Uint8List bytes) {
    int pos = 0;

    int readByte() => bytes[pos++];
    int readInt16() { final v = (bytes[pos] << 8) | bytes[pos+1]; pos += 2; return v; }
    int readInt32() {
      final v = (bytes[pos] << 24) | (bytes[pos+1] << 16) | (bytes[pos+2] << 8) | bytes[pos+3];
      pos += 4;
      return v;
    }
    int readVarLen() {
      int v = 0;
      while (true) {
        final b = readByte();
        v = (v << 7) | (b & 0x7F);
        if (b & 0x80 == 0) break;
      }
      return v;
    }

    // Header
    pos = 4; // skip "MThd"
    readInt32(); // length = 6
    final format = readInt16();
    final numTracks = readInt16();
    final tpb = readInt16(); // ticks per beat

    int usBeat = 500000; // default 120 BPM
    final noteOns = <int, List<_NoteOn>>{}; // pitch → list of pending note-ons
    final result = <MidiNote>[];

    for (int t = 0; t < numTracks; t++) {
      // skip "MTrk"
      pos += 4;
      final trackLen = readInt32();
      final trackEnd = pos + trackLen;

      int absTickTrack = 0;
      int runningStatus = 0;

      while (pos < trackEnd) {
        final delta = readVarLen();
        absTickTrack += delta;
        final timeSec = absTickTrack / tpb * (usBeat / 1000000.0);

        int status = bytes[pos];
        if (status & 0x80 != 0) {
          runningStatus = status;
          pos++;
        } else {
          status = runningStatus;
        }

        final type = status & 0xF0;
        if (type == 0x90) {
          // Note on
          final pitch = readByte();
          final vel   = readByte();
          if (vel > 0) {
            noteOns.putIfAbsent(pitch, () => []).add(_NoteOn(absTickTrack, timeSec));
          } else {
            // velocity=0 = note off
            _closeNote(noteOns, result, pitch, timeSec);
          }
        } else if (type == 0x80) {
          // Note off
          final pitch = readByte();
          readByte(); // velocity
          _closeNote(noteOns, result, pitch, timeSec);
        } else if (status == 0xFF) {
          // Meta event
          final metaType = readByte();
          final metaLen  = readVarLen();
          if (metaType == 0x51 && metaLen == 3) {
            usBeat = (bytes[pos] << 16) | (bytes[pos+1] << 8) | bytes[pos+2];
          }
          pos += metaLen;
        } else if (type == 0xC0 || type == 0xD0) {
          readByte();
        } else if (type == 0xA0 || type == 0xB0 || type == 0xE0) {
          readByte(); readByte();
        } else {
          // Unknown — skip to track end
          pos = trackEnd;
        }
      }
      pos = trackEnd;
    }

    result.sort((a, b) => a.startSec.compareTo(b.startSec));
    return result;
  }

  static void _closeNote(Map<int, List<_NoteOn>> noteOns, List<MidiNote> result,
      int pitch, double endSec) {
    final list = noteOns[pitch];
    if (list != null && list.isNotEmpty) {
      final on = list.removeAt(0);
      result.add(MidiNote(pitch: pitch, startSec: on.timeSec, endSec: endSec));
    }
  }
}

class _NoteOn {
  final int tick;
  final double timeSec;
  _NoteOn(this.tick, this.timeSec);
}
