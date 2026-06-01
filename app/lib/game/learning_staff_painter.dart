import 'dart:math';
import 'package:flutter/material.dart';

const _noteNames = ['C','C#','D','Eb','E','F','F#','G','Ab','A','Bb','B'];
const _accidental = [0, 1, 0, -1, 0, 0, 1, 0, -1, 0, -1, 0];
const _diatonic  = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6];
const _b4Steps   = 34;

bool _hasAccidental(int pitch) => _accidental[pitch % 12] != 0;

double _pitchToY(int pitch, double centerY, double spacing) {
  final steps = (pitch ~/ 12 - 1) * 7 + _diatonic[pitch % 12];
  return centerY - (steps - _b4Steps) * spacing / 2.0;
}

String _noteName(int pitch) => '${_noteNames[pitch % 12]}${pitch ~/ 12 - 1}';

enum LearningFeedback { none, correct, wrong }

class LearningStaffPainter extends CustomPainter {
  final List<int> scale;
  final int currentIndex;
  final LearningFeedback feedback;
  final double feedbackAge; // 0..1

  const LearningStaffPainter({
    required this.scale,
    required this.currentIndex,
    required this.feedback,
    this.feedbackAge = 0.0,
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

    // Layout notes horizontally
    final leftPad  = w * 0.15;
    final rightPad = w * 0.10;
    final usableW  = w - leftPad - rightPad;

    // Show past notes (played), current target, and next few
    final visibleBefore = 4;
    final visibleAfter  = 4;
    final firstVis = (currentIndex - visibleBefore).clamp(0, scale.length);
    final lastVis  = (currentIndex + visibleAfter + 1).clamp(0, scale.length);
    final visCount = lastVis - firstVis;
    if (visCount <= 0) return;

    final noteSpacing = (usableW / (visCount + 1)).clamp(30.0, 100.0);
    final startX = w / 2 - (currentIndex - firstVis) * noteSpacing;

    for (int i = firstVis; i < lastVis; i++) {
      final pitch = scale[i];
      final cx = startX + (i - firstVis) * noteSpacing;
      final cy = _pitchToY(pitch, centerY, spacing);

      Color color;
      double alpha = 1.0;

      if (i < currentIndex) {
        // Past: green, fading
        color = const Color(0xFF4CAF50);
        final dist = currentIndex - i;
        alpha = (1.0 - dist * 0.2).clamp(0.3, 0.8);
      } else if (i == currentIndex) {
        // Target
        if (feedback == LearningFeedback.correct) {
          color = const Color(0xFF4CAF50);
          alpha = 1.0;
        } else if (feedback == LearningFeedback.wrong) {
          color = const Color(0xFFF44336);
          alpha = 1.0;
        } else {
          color = const Color(0xFFFFD740);
          alpha = 1.0;
        }
      } else {
        // Future: dim
        color = Colors.white;
        alpha = 0.25;
      }

      _drawNote(canvas, cx, cy, pitch, spacing, noteRx, noteRy,
          alpha, color, staffTop, staffBot, centerY,
          isTarget: i == currentIndex);
    }

    // Feedback flash ring on target
    if (feedback != LearningFeedback.none && currentIndex < scale.length) {
      final cx = startX + (currentIndex - firstVis) * noteSpacing;
      final cy = _pitchToY(scale[currentIndex], centerY, spacing);
      final ringColor = feedback == LearningFeedback.correct
          ? const Color(0xFF4CAF50)
          : const Color(0xFFF44336);
      final ringRadius = spacing * (0.5 + feedbackAge * 2.0);
      final ringAlpha  = ((1.0 - feedbackAge) * 180).round().clamp(0, 255);
      canvas.drawCircle(Offset(cx, cy), ringRadius,
        Paint()..color = ringColor.withAlpha(ringAlpha)
               ..style = PaintingStyle.stroke
               ..strokeWidth = 3.0 * (1.0 - feedbackAge) + 0.5,
      );
    }

    // Progress bar at bottom
    final barY     = h - 20;
    final barH     = 6.0;
    final barLeft  = w * 0.15;
    final barRight = w * 0.85;
    final barW     = barRight - barLeft;
    final progress = scale.isEmpty ? 0.0 : currentIndex / scale.length;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(barLeft, barY, barW, barH), const Radius.circular(3)),
      Paint()..color = const Color(0xFF333344),
    );
    if (progress > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(barLeft, barY, barW * progress, barH),
            const Radius.circular(3)),
        Paint()..color = const Color(0xFF4CAF50),
      );
    }
  }

  void _drawNote(Canvas canvas, double cx, double cy, int pitch,
      double spacing, double noteRx, double noteRy, double alpha, Color color,
      double staffTop, double staffBot, double centerY,
      {bool isTarget = false}) {
    final a = (alpha * 255).round().clamp(0, 255);
    final c = color.withAlpha(a);

    // Ledger lines
    final lp = Paint()..color = Colors.white.withAlpha((a * 0.7).round())..strokeWidth = 1.2;
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
    final rx = isTarget ? noteRx * 1.15 : noteRx;
    final ry = isTarget ? noteRy * 1.15 : noteRy;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(-15 * pi / 180);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
      Paint()..color = c,
    );
    canvas.restore();

    // Accidental (sharp / flat)
    final acc = _accidental[pitch % 12];
    if (acc != 0) {
      final accText = acc > 0 ? '♯' : '♭';
      final tp = TextPainter(
        text: TextSpan(text: accText,
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

    // Label
    if (isTarget || alpha > 0.5) {
      final labelSize = spacing * 0.55;
      final lp2 = TextPainter(
        text: TextSpan(text: _noteName(pitch),
            style: TextStyle(fontSize: labelSize,
                color: c.withAlpha((a * 0.8).round()),
                fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      lp2.paint(canvas, Offset(cx - lp2.width / 2,
          stemUp ? cy + noteRy + 2 : cy - noteRy - labelSize - 2));
    }
  }

  @override
  bool shouldRepaint(LearningStaffPainter old) => true;
}
