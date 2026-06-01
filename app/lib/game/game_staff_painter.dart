import 'dart:math';
import 'package:flutter/material.dart';
import 'score_tracker.dart';
import 'midi_note.dart';

// ── Music theory helpers ──────────────────────────────────────────────────────

const _noteNames = ['C','C#','D','Eb','E','F','F#','G','Ab','A','Bb','B'];
// Diatonic step from C within an octave:
// C=0, D=1, E=2, F=3, G=4, A=5, B=6
const _diatonic  = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6];

// Accidental for each chromatic pitch class: 0=natural, 1=sharp, -1=flat
const _accidental = [0, 1, 0, -1, 0, 0, 1, 0, -1, 0, -1, 0];
//                   C  C#  D  Eb  E  F  F#  G  Ab  A  Bb  B

// B4 = MIDI 71, used as staff center reference
// steps = (71 ~/ 12 - 1) * 7 + _diatonic[11] = 4*7 + 6 = 34
const _b4Steps = 34;

// Middle line of treble clef staff = B4
double _pitchToY(int pitch, double centerY, double spacing) {
  final steps = (pitch ~/ 12 - 1) * 7 + _diatonic[pitch % 12];
  return centerY - (steps - _b4Steps) * spacing / 2.0;
}

String _noteName(int pitch) => '${_noteNames[pitch % 12]}${pitch ~/ 12 - 1}';

// Note duration type
enum _NoteType { whole, half, quarter, eighth, sixteenth }

_NoteType _noteTypeFromDuration(double durSec, double quarterSec) {
  final beats = durSec / quarterSec;
  if (beats >= 3.0) return _NoteType.whole;
  if (beats >= 1.5) return _NoteType.half;
  if (beats >= 0.75) return _NoteType.quarter;
  if (beats >= 0.375) return _NoteType.eighth;
  return _NoteType.sixteenth;
}

// ── Hit effect data ───────────────────────────────────────────────────────────
class HitEffect {
  final int pitch;
  final double noteSec;
  double age;
  HitEffect({required this.pitch, required this.noteSec}) : age = 0.0;
}

// ── Main painter ──────────────────────────────────────────────────────────────
class GameStaffPainter extends CustomPainter {
  final List<TrackedNote> notes;
  final double elapsedSec;
  final double pxPerSec;
  final double lookaheadSec;
  final double pastSec;
  final List<HitEffect> hitEffects;
  final double quarterSec;

  static const Color _colorHit      = Color(0xFF4CAF50);
  static const Color _colorMissed   = Color(0xFFF44336);
  static const Color _colorActive   = Color(0xFFFFD740);
  static const Color _colorIncoming = Colors.white;

  const GameStaffPainter({
    required this.notes,
    required this.elapsedSec,
    required this.pxPerSec,
    required this.lookaheadSec,
    this.pastSec = 2.5,
    this.hitEffects = const [],
    this.quarterSec = 0.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height, w = size.width;
    final spacing  = h * 0.050;
    final centerY  = h * 0.50;
    final staffTop = centerY - spacing * 2;
    final staffBot = staffTop + spacing * 4;
    final noteRx   = spacing * 0.58;
    final noteRy   = spacing * 0.38;
    final clefSize = spacing * 4.5;
    final nowX     = w * 0.28;

    // Background
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h),
        Paint()..color = const Color(0xFF111318));

    // ── Staff lines ─────────────────────────────────────────────────────────
    final staffPaint = Paint()..color = Colors.white..strokeWidth = 1.2;
    for (int i = 0; i <= 4; i++) {
      canvas.drawLine(Offset(8, staffTop + i * spacing),
          Offset(w - 8, staffTop + i * spacing), staffPaint);
    }

    // ── Treble clef ─────────────────────────────────────────────────────────
    final clefPainter = TextPainter(
      text: TextSpan(
        text: '\u{1D11E}',
        style: TextStyle(fontSize: clefSize, color: Colors.white),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final staffMidY = (staffTop + staffBot) / 2;
    clefPainter.paint(canvas, Offset(4, staffMidY - clefSize * 0.52));

    // ── Now line ────────────────────────────────────────────────────────────
    canvas.drawLine(
      Offset(nowX, staffTop - spacing * 2),
      Offset(nowX, staffBot + spacing * 2),
      Paint()..color = const Color(0x55FFD740)..strokeWidth = 6,
    );
    canvas.drawLine(
      Offset(nowX, staffTop - spacing * 2),
      Offset(nowX, staffBot + spacing * 2),
      Paint()..color = const Color(0xFFFFD740)..strokeWidth = 1.5,
    );

    // ── Hit effects ─────────────────────────────────────────────────────────
    for (final e in hitEffects) {
      _drawHitEffect(canvas, e, nowX, centerY, spacing);
    }

    // ── Notes ───────────────────────────────────────────────────────────────
    for (final t in notes) {
      final noteX = nowX + (t.note.startSec - elapsedSec) * pxPerSec;
      if (noteX > w + noteRx * 2) continue;
      if (noteX < nowX - pastSec * pxPerSec - noteRx * 2) continue;

      final age = elapsedSec - t.note.startSec;
      double alpha = 1.0;
      if (age > 0) alpha = (1.0 - age / pastSec).clamp(0.0, 1.0);
      final distFromRight = w - noteX;
      if (distFromRight < 60) alpha *= (distFromRight / 60).clamp(0.0, 1.0);
      final clefFadeZone = nowX * 0.55;
      if (noteX < clefFadeZone) alpha *= (noteX / clefFadeZone).clamp(0.0, 1.0);
      if (alpha <= 0) continue;

      Color color;
      switch (t.state) {
        case NoteState.hit:      color = _colorHit;
        case NoteState.missed:   color = _colorMissed;
        case NoteState.inWindow: color = _colorActive;
        case NoteState.incoming: color = _colorIncoming;
      }

      final cy = _pitchToY(t.note.pitch, centerY, spacing);
      final noteType = _noteTypeFromDuration(t.note.durationSec, quarterSec);

      _drawNote(canvas, noteX, cy, t.note.pitch, spacing, noteRx, noteRy,
          alpha, color, staffTop, staffBot, centerY, noteType,
          isMissed: t.state == NoteState.missed);
    }
  }

  // ── Hit effect ──────────────────────────────────────────────────────────────
  void _drawHitEffect(Canvas canvas, HitEffect e,
      double nowX, double centerY, double spacing) {
    final ex = nowX + (e.noteSec - elapsedSec) * pxPerSec;
    final ey = _pitchToY(e.pitch, centerY, spacing);
    final t  = e.age;

    final ringRadius = spacing * (0.4 + t * 2.8);
    final ringAlpha  = ((1.0 - t) * 200).round().clamp(0, 255);
    final ringWidth  = (3.5 * (1.0 - t) + 0.5).clamp(0.5, 4.0);
    canvas.drawCircle(Offset(ex, ey), ringRadius,
      Paint()..color = _colorHit.withAlpha(ringAlpha)
             ..style = PaintingStyle.stroke..strokeWidth = ringWidth);

    for (int i = 0; i < 8; i++) {
      final angle = i * pi / 4.0;
      final dist  = spacing * t * 3.2;
      final pAlpha = ((1.0 - t) * 200).round().clamp(0, 255);
      final pRadius = (3.5 * (1.0 - t) + 0.5).clamp(0.5, 4.0);
      canvas.drawCircle(
        Offset(ex + cos(angle) * dist, ey + sin(angle) * dist),
        pRadius, Paint()..color = _colorHit.withAlpha(pAlpha));
    }

    final flashAlpha = ((1.0 - t * 3).clamp(0.0, 1.0) * 160).round();
    if (flashAlpha > 0) {
      canvas.drawCircle(Offset(ex, ey), spacing * 0.6,
        Paint()..color = const Color(0xFF80FF80).withAlpha(flashAlpha));
    }
  }

  // ── Draw a single note ──────────────────────────────────────────────────────
  void _drawNote(Canvas canvas, double cx, double cy, int pitch,
      double spacing, double noteRx, double noteRy, double alpha, Color color,
      double staffTop, double staffBot, double centerY, _NoteType noteType,
      {bool isMissed = false}) {

    final a = (alpha * 255).round().clamp(0, 255);
    final c = color.withAlpha(a);
    final pc = pitch % 12;
    final acc = _accidental[pc]; // 1=sharp, -1=flat, 0=natural

    // ── Ledger lines ──────────────────────────────────────────────────────
    final lp = Paint()..color = Colors.white.withAlpha((a * 0.8).round())..strokeWidth = 1.2;
    final lw = noteRx * 1.7;
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

    // ── Accidental (sharp / flat) ─────────────────────────────────────────
    if (acc != 0) {
      final accText = acc > 0 ? '♯' : '♭';
      final accSize = spacing * 0.85;
      final tp = TextPainter(
        text: TextSpan(text: accText,
            style: TextStyle(fontSize: accSize, color: c)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - noteRx - tp.width - 3, cy - tp.height / 2));
    }

    // ── Note head ─────────────────────────────────────────────────────────
    final bool filled = noteType == _NoteType.quarter
                     || noteType == _NoteType.eighth
                     || noteType == _NoteType.sixteenth;
    final bool hasStem = noteType != _NoteType.whole;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(-15 * pi / 180);

    if (filled) {
      // Filled oval
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: noteRx * 2, height: noteRy * 2),
        Paint()..color = c,
      );
    } else {
      // Open oval (hollow): stroke only with thicker line
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: noteRx * 2, height: noteRy * 2),
        Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 1.8,
      );
      // For whole notes: slightly wider oval
      if (noteType == _NoteType.whole) {
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero,
              width: noteRx * 2.3, height: noteRy * 2),
          Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 1.5,
        );
      }
    }
    canvas.restore();

    // ── Miss cross ────────────────────────────────────────────────────────
    if (isMissed) {
      final xP = Paint()..color = _colorMissed.withAlpha(a)..strokeWidth = 2;
      canvas.drawLine(Offset(cx - noteRx, cy - noteRy),
          Offset(cx + noteRx, cy + noteRy), xP);
      canvas.drawLine(Offset(cx + noteRx, cy - noteRy),
          Offset(cx - noteRx, cy + noteRy), xP);
    }

    // ── Stem ──────────────────────────────────────────────────────────────
    // Rule: notes on/below B4 (middle line) → stem up (right side)
    //       notes above B4 → stem down (left side)
    if (hasStem) {
      final stemUp = cy >= centerY; // cy >= B4 line → below or on middle → stem up
      final stemX = stemUp ? cx + noteRx - 0.5 : cx - noteRx + 0.5;
      final stemLen = spacing * 3.5;
      final stemEndY = stemUp ? cy - stemLen : cy + stemLen;

      canvas.drawLine(
        Offset(stemX, cy),
        Offset(stemX, stemEndY),
        Paint()..color = c..strokeWidth = 1.5,
      );

      // ── Flag for eighth/sixteenth notes ─────────────────────────────────
      if (noteType == _NoteType.eighth || noteType == _NoteType.sixteenth) {
        _drawFlag(canvas, stemX, stemEndY, stemUp, spacing, c);
      }
      if (noteType == _NoteType.sixteenth) {
        final offset = stemUp ? spacing * 0.7 : -spacing * 0.7;
        _drawFlag(canvas, stemX, stemEndY + offset, stemUp, spacing, c);
      }

      // ── Dot for dotted notes would go here (future) ─────────────────────
    }

    // ── Note name label (subtle, below/above) ─────────────────────────────
    final labelSize = spacing * 0.52;
    final lp2 = TextPainter(
      text: TextSpan(text: _noteName(pitch),
          style: TextStyle(fontSize: labelSize,
              color: c.withAlpha((a * 0.5).round()),
              fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();

    final stemUp = cy >= centerY;
    final labelY = stemUp ? cy + noteRy + 3 : cy - noteRy - labelSize - 3;
    lp2.paint(canvas, Offset(cx - lp2.width / 2, labelY));
  }

  // ── Flag drawing ────────────────────────────────────────────────────────────
  void _drawFlag(Canvas canvas, double stemX, double stemEndY,
      bool stemUp, double spacing, Color c) {
    final path = Path();
    final flagLen = spacing * 1.8;
    final flagCurve = spacing * 0.6;

    if (stemUp) {
      // Flag curves right and down from stem top
      path.moveTo(stemX, stemEndY);
      path.cubicTo(
        stemX + flagCurve, stemEndY + flagLen * 0.3,
        stemX + flagCurve * 1.2, stemEndY + flagLen * 0.6,
        stemX + flagCurve * 0.3, stemEndY + flagLen,
      );
    } else {
      // Flag curves right and up from stem bottom
      path.moveTo(stemX, stemEndY);
      path.cubicTo(
        stemX + flagCurve, stemEndY - flagLen * 0.3,
        stemX + flagCurve * 1.2, stemEndY - flagLen * 0.6,
        stemX + flagCurve * 0.3, stemEndY - flagLen,
      );
    }

    canvas.drawPath(path, Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(GameStaffPainter old) => true;
}
