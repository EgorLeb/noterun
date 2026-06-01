import 'dart:math';
import 'package:flutter/material.dart';

const _noteNames  = ['C','C#','D','Eb','E','F','F#','G','Ab','A','Bb','B'];
const _accidental = [0, 1, 0, -1, 0, 0, 1, 0, -1, 0, -1, 0];
const _diatonic   = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6];
const _b4Steps    = 34;

double _pitchToY(int pitch, double centerY, double spacing) {
  final steps = (pitch ~/ 12 - 1) * 7 + _diatonic[pitch % 12];
  return centerY - (steps - _b4Steps) * spacing / 2.0;
}

String _noteName(int pitch) => '${_noteNames[pitch % 12]}${pitch ~/ 12 - 1}';

/// Paints a chord: all notes stacked at center, each colored by play state.
class ChordStaffPainter extends CustomPainter {
  final List<int> pitches;        // all chord tones
  final Set<int> played;          // pitches already played correctly
  final double completionAge;     // 0..1 — flash animation when chord done
  final bool complete;

  const ChordStaffPainter({
    required this.pitches,
    required this.played,
    this.completionAge = 0.0,
    this.complete = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height, w = size.width;
    final spacing  = h * 0.055;
    final centerY  = h * 0.45;
    final staffTop = centerY - spacing * 2;
    final staffBot = staffTop + spacing * 4;
    final noteRx   = spacing * 0.60;
    final noteRy   = spacing * 0.38;

    // Background
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h),
        Paint()..color = const Color(0xFF111318));

    // Staff lines
    final staffPaint = Paint()..color = Colors.white..strokeWidth = 1.2;
    for (int i = 0; i <= 4; i++) {
      canvas.drawLine(Offset(24, staffTop + i * spacing),
          Offset(w - 24, staffTop + i * spacing), staffPaint);
    }

    // Treble clef
    final clefSize = spacing * 4.5;
    final clefPainter = TextPainter(
      text: TextSpan(text: '\u{1D11E}',
          style: TextStyle(fontSize: clefSize, color: Colors.white)),
      textDirection: TextDirection.ltr,
    )..layout();
    final staffMidY = (staffTop + staffBot) / 2;
    clefPainter.paint(canvas, Offset(28, staffMidY - clefSize * 0.52));

    // Draw all chord notes at center-x
    final cx = w * 0.55;

    // Pre-sort pitches descending (highest first) for offset detection
    final sortedPitches = List<int>.from(pitches)..sort((a, b) => b.compareTo(a));

    // Detect step-adjacent notes (need horizontal offset)
    final offsetRight = <int>{};
    for (int i = 0; i < sortedPitches.length - 1; i++) {
      final stepsA = (sortedPitches[i]   ~/ 12 - 1) * 7 + _diatonic[sortedPitches[i]   % 12];
      final stepsB = (sortedPitches[i+1] ~/ 12 - 1) * 7 + _diatonic[sortedPitches[i+1] % 12];
      if ((stepsA - stepsB).abs() == 1) {
        offsetRight.add(sortedPitches[i]); // push higher note right
      }
    }

    for (final pitch in pitches) {
      final cy   = _pitchToY(pitch, centerY, spacing);
      final hit  = played.contains(pitch);
      final color = complete
          ? const Color(0xFF4CAF50)
          : hit
              ? const Color(0xFF4CAF50)
              : const Color(0xFFFFD740);
      final alpha = complete ? ((1.0 - completionAge * 0.3) * 255).round().clamp(0, 255) : 255;

      final noteX = offsetRight.contains(pitch) ? cx + noteRx * 1.6 : cx;

      _drawNote(canvas, noteX, cy, pitch, spacing, noteRx, noteRy,
          color.withAlpha(alpha), staffTop, staffBot, centerY, hit || complete);
    }

    // Completion ring
    if (complete && completionAge < 1.0) {
      final ringRadius = spacing * (0.8 + completionAge * 3.0);
      final ringAlpha  = ((1.0 - completionAge) * 200).round().clamp(0, 255);
      canvas.drawCircle(Offset(cx, centerY), ringRadius,
        Paint()
          ..color = const Color(0xFF4CAF50).withAlpha(ringAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0 * (1.0 - completionAge) + 0.5,
      );
    }
  }

  void _drawNote(Canvas canvas, double cx, double cy, int pitch,
      double spacing, double noteRx, double noteRy,
      Color c, double staffTop, double staffBot, double centerY,
      bool isPlayed) {

    // Ledger lines
    final lp = Paint()
      ..color = Colors.white.withAlpha(180)
      ..strokeWidth = 1.2;
    final lw = noteRx * 1.6;
    if (cy > staffBot + spacing * 0.4) {
      double y = staffBot + spacing;
      while (y <= cy + noteRy) {
        canvas.drawLine(Offset(cx - lw, y), Offset(cx + lw, y), lp);
        y += spacing;
      }
    }
    if (cy < staffTop - spacing * 0.4) {
      double y = staffTop - spacing;
      while (y >= cy - noteRy) {
        canvas.drawLine(Offset(cx - lw, y), Offset(cx + lw, y), lp);
        y -= spacing;
      }
    }

    // Oval
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(-15 * pi / 180);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: noteRx * 2, height: noteRy * 2),
      Paint()..color = c,
    );
    canvas.restore();

    // Accidental
    final acc = _accidental[pitch % 12];
    if (acc != 0) {
      final tp = TextPainter(
        text: TextSpan(text: acc > 0 ? '♯' : '♭',
            style: TextStyle(fontSize: spacing * 0.85, color: c)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - noteRx - tp.width - 3, cy - tp.height / 2));
    }

    // Stem
    final stemUp = cy >= centerY;
    canvas.drawLine(
      Offset(stemUp ? cx + noteRx - 0.5 : cx - noteRx + 0.5, cy),
      Offset(stemUp ? cx + noteRx - 0.5 : cx - noteRx + 0.5,
             stemUp ? cy - spacing * 3.5 : cy + spacing * 3.5),
      Paint()..color = c..strokeWidth = 1.5,
    );

    // Note name label
    final labelSize = spacing * 0.55;
    final lp2 = TextPainter(
      text: TextSpan(text: _noteName(pitch),
          style: TextStyle(fontSize: labelSize,
              color: c.withAlpha(200),
              fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    lp2.paint(canvas, Offset(cx - lp2.width / 2,
        stemUp ? cy + noteRy + 2 : cy - noteRy - labelSize - 2));
  }

  @override
  bool shouldRepaint(ChordStaffPainter old) => true;
}
