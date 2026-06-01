import 'dart:math';
import 'package:flutter/material.dart';

const _noteNames = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'];
const _diatonic  = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6];
const _b4Steps   = 34;  // B4(71): (71//12-1)*7+diatonic[11]=4*7+6=34

bool _isBlack(int pitch) => [1, 3, 6, 8, 10].contains(pitch % 12);
String _noteName(int pitch) => '${_noteNames[pitch % 12]}${pitch ~/ 12 - 1}';

double _pitchToY(int pitch, double centerY, double spacing) {
  final steps = (pitch ~/ 12 - 1) * 7 + _diatonic[pitch % 12];
  return centerY - (steps - _b4Steps) * spacing / 2.0;
}

String detectChord(List<int> pitches) {
  if (pitches.isEmpty) return '';
  if (pitches.length == 1) return _noteName(pitches[0]);
  final classes = pitches.map((p) => p % 12).toSet();
  const templates = [
    ([0, 4, 7],     ''),
    ([0, 3, 7],     'm'),
    ([0, 4, 7, 10], '7'),
    ([0, 4, 7, 11], 'maj7'),
    ([0, 3, 7, 10], 'm7'),
    ([0, 3, 6],     'dim'),
    ([0, 4, 8],     'aug'),
    ([0, 5, 7],     'sus4'),
    ([0, 2, 7],     'sus2'),
  ];
  for (int root = 0; root < 12; root++) {
    if (!classes.contains(root)) continue;
    final norm = classes.map((c) => (c - root + 12) % 12).toSet();
    for (final (tmpl, suffix) in templates) {
      if (norm.containsAll(tmpl)) return '${_noteNames[root]}$suffix';
    }
  }
  return pitches.map((p) => _noteNames[p % 12]).join(' ');
}

// ─────────────────────────────────────────────────────────────────────────────

class ActiveNote {
  final int pitch;
  final DateTime arrivedAt;
  int confidence; // 1 = L1 only (faint), 2 = L2 confirmed, 3 = L3 confirmed (solid)

  /// [backMs] — сколько миллисекунд назад реально зазвучала нота
  /// (вычисляется из позиции фрейма внутри L1-чанка, ±32ms точность)
  ActiveNote(this.pitch, {int backMs = 0})
      : arrivedAt = DateTime.now().subtract(Duration(milliseconds: backMs)),
        confidence = 1;
}

class StaffPainter extends CustomPainter {
  final List<ActiveNote> notes;

  // How many milliseconds of history to show across the full width
  static const double _windowMs  = 8000;
  // Fade out in the last N ms before disappearing
  static const double _fadeMs    = 1500;

  StaffPainter(this.notes);

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height, w = size.width;
    final spacing  = h * 0.055;
    final centerY  = h * 0.50;
    final staffTop = centerY - spacing * 2;
    final staffBot = staffTop + spacing * 4;
    final noteRx   = spacing * 0.60;
    final noteRy   = spacing * 0.37;
    final clefSize = spacing * 5.5;
    final clefX    = clefSize * 0.45 + 12;

    // Background
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h),
        Paint()..color = const Color(0xFF111318));

    // Staff lines (full width)
    final staffPaint = Paint()..color = Colors.white..strokeWidth = 1.5;
    for (int i = 0; i <= 4; i++) {
      final y = staffTop + i * spacing;
      canvas.drawLine(Offset(clefX, y), Offset(w - 8, y), staffPaint);
    }

    // Treble clef
    final clefPainter = TextPainter(
      text: TextSpan(
        text: '\u{1D11E}',
        style: TextStyle(fontSize: clefSize, color: Colors.white),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    clefPainter.paint(canvas, Offset(4, staffBot - clefSize * 0.72));

    // "Now" line — right side
    final nowX = w - 24.0;
    canvas.drawLine(
      Offset(nowX, staffTop - spacing * 2),
      Offset(nowX, staffBot + spacing * 2),
      Paint()
        ..color = const Color(0x55FFD740)
        ..strokeWidth = 6,
    );
    canvas.drawLine(
      Offset(nowX, staffTop - spacing * 2),
      Offset(nowX, staffBot + spacing * 2),
      Paint()
        ..color = const Color(0xFFFFD740)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    final usableW = nowX - clefX;
    final pxPerMs = usableW / _windowMs;

    final now = DateTime.now();
    final visible = notes.where(
        (n) => now.difference(n.arrivedAt).inMilliseconds < _windowMs).toList();

    if (visible.isEmpty) {
      final hp = TextPainter(
        text: TextSpan(text: 'Play something…',
            style: TextStyle(fontSize: spacing * 0.8, color: const Color(0xFF555555))),
        textDirection: TextDirection.ltr,
      )..layout();
      hp.paint(canvas, Offset(w / 2 - hp.width / 2, h * 0.85));
      return;
    }

    for (final n in visible) {
      final ageMs = now.difference(n.arrivedAt).inMilliseconds.toDouble();
      final cx = nowX - ageMs * pxPerMs;
      if (cx < clefX - noteRx) continue;

      // Fade over time
      final timeFade = ageMs > _windowMs - _fadeMs
          ? (1.0 - (ageMs - (_windowMs - _fadeMs)) / _fadeMs).clamp(0.0, 1.0)
          : 1.0;

      // Confidence: 1→faint, 2→medium, 3→full
      final confBrightness = n.confidence == 1 ? 0.35 : n.confidence == 2 ? 0.65 : 1.0;

      final alpha = timeFade * confBrightness;
      final cy = _pitchToY(n.pitch, centerY, spacing);
      _drawNote(canvas, cx, cy, n.pitch, spacing, noteRx, noteRy,
          alpha, staffTop, staffBot, centerY);
    }
  }

  void _drawNote(Canvas canvas, double cx, double cy, int pitch,
      double spacing, double noteRx, double noteRy, double alpha,
      double staffTop, double staffBot, double centerY) {
    final a = (alpha * 255).round();

    // Ledger lines
    final lp = Paint()..color = Colors.white.withAlpha(a)..strokeWidth = 1.5;
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
      Paint()..color = Colors.white.withAlpha(a),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: noteRx * 2, height: noteRy * 2),
      Paint()
        ..color = const Color(0xFF333333).withAlpha(a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    canvas.restore();

    // Sharp
    if (_isBlack(pitch)) {
      final tp = TextPainter(
        text: TextSpan(text: '♯',
            style: TextStyle(fontSize: spacing * 0.85, color: Colors.white.withAlpha(a))),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - noteRx - tp.width - 2, cy - tp.height / 2));
    }

    // Stem
    final stemUp = cy >= centerY;
    canvas.drawLine(
      Offset(stemUp ? cx + noteRx - 0.5 : cx - noteRx + 0.5, cy),
      Offset(stemUp ? cx + noteRx - 0.5 : cx - noteRx + 0.5,
             stemUp ? cy - spacing * 3.5 : cy + spacing * 3.5),
      Paint()..color = Colors.white.withAlpha(a)..strokeWidth = 1.5,
    );

    // Label
    final labelSize = spacing * 0.62;
    final lp2 = TextPainter(
      text: TextSpan(text: _noteName(pitch),
          style: TextStyle(fontSize: labelSize,
              color: const Color(0xFFBBBBBB).withAlpha(a),
              fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    lp2.paint(canvas, Offset(cx - lp2.width / 2,
        stemUp ? cy + noteRy + 2 : cy - noteRy - labelSize - 2));
  }

  @override
  bool shouldRepaint(StaffPainter old) => true;
}
