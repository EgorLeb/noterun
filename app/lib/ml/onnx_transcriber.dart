import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

/// Snapshot of GRU autoregressive state at a point in time.
class OrtState {
  final Float32List h;
  final Float32List prevEmb;
  OrtState(Float32List h, Float32List prevEmb)
      : h       = Float32List.fromList(h),
        prevEmb = Float32List.fromList(prevEmb);
}

class OnnxTranscriber {
  late OrtSession _acousticSession;
  late OrtSession _gruSession;

  var _h       = Float32List(384);
  var _prevEmb = Float32List(176);

  static const _embTable = [
    [0.46147, -0.95309],
    [0.57806, -1.27359],
    [-1.02670, 2.03502],
    [-1.30429, 3.05424],
    [-1.07403, -1.03931],
  ];

  double lastMaxNoteP = 0.0;

  OnnxTranscriber._();

  /// Normal factory — loads model files from assets (main isolate only).
  static Future<OnnxTranscriber> create() async {
    final t = OnnxTranscriber._();
    await t._init();
    return t;
  }

  /// Factory for background isolates — accepts pre-loaded bytes so
  /// rootBundle (which needs ServicesBinding) is never called here.
  static OnnxTranscriber fromBytes(Uint8List acousticBytes, Uint8List gruBytes) {
    final t    = OnnxTranscriber._();
    OrtEnv.instance.init();
    final opts = OrtSessionOptions();
    t._acousticSession = OrtSession.fromBuffer(acousticBytes, opts);
    t._gruSession      = OrtSession.fromBuffer(gruBytes, opts);
    return t;
  }

  Future<void> _init() async {
    OrtEnv.instance.init();
    final opts          = OrtSessionOptions();
    final acousticBytes = await _loadAsset('assets/models/acoustic.onnx');
    final gruBytes      = await _loadAsset('assets/models/gru_frame.onnx');
    _acousticSession    = OrtSession.fromBuffer(acousticBytes, opts);
    _gruSession         = OrtSession.fromBuffer(gruBytes, opts);
  }

  Future<Uint8List> _loadAsset(String path) async {
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List();
  }

  // ── State management ──────────────────────────────────────────────────────

  OrtState saveState() => OrtState(_h, _prevEmb);

  void restoreState(OrtState s) {
    _h       = Float32List.fromList(s.h);
    _prevEmb = Float32List.fromList(s.prevEmb);
  }

  void reset() {
    _h       = Float32List(384);
    _prevEmb = Float32List(176);
  }

  // ── Inference ─────────────────────────────────────────────────────────────

  /// Normal inference — advances internal state.
  Int32List processChunk(Float32List melFlat, int timeSteps) {
    return _runInference(melFlat, timeSteps, _h, _prevEmb, updateState: true);
  }

  /// Inference from a saved snapshot — does NOT change internal state.
  Int32List processChunkFromState(Float32List melFlat, int timeSteps, OrtState snapshot) {
    final hCopy      = Float32List.fromList(snapshot.h);
    final prevCopy   = Float32List.fromList(snapshot.prevEmb);
    return _runInference(melFlat, timeSteps, hCopy, prevCopy, updateState: false);
  }

  Int32List _runInference(
    Float32List melFlat,
    int timeSteps,
    Float32List h,
    Float32List prevEmb, {
    required bool updateState,
  }) {
    final result = Int32List(timeSteps * 88);
    lastMaxNoteP = 0.0;

    // --- Acoustic model ---
    final melTensor  = OrtValueTensor.createTensorWithDataList(melFlat, [1, timeSteps, 229]);
    final aOuts      = _acousticSession.run(OrtRunOptions(), {'mel': melTensor}, ['features']);
    melTensor.release();

    final featTensor = aOuts?[0] as OrtValueTensor?;
    if (featTensor == null) return result;

    final featData = featTensor.value as List;
    featTensor.release();

    final featFlat = Float32List(timeSteps * 256);
    for (int t = 0; t < timeSteps; t++) {
      final frame = featData[0][t] as List;
      for (int d = 0; d < 256 && d < frame.length; d++) {
        featFlat[t * 256 + d] = (frame[d] as num).toDouble();
      }
    }

    // --- GRU frame-by-frame ---
    for (int i = 0; i < timeSteps; i++) {
      final frameF = Float32List.fromList(featFlat.sublist(i * 256, i * 256 + 256));

      final frameTensor = OrtValueTensor.createTensorWithDataList(frameF,        [1, 1, 256]);
      final hTensor     = OrtValueTensor.createTensorWithDataList(Float32List.fromList(h),       [1, 1, 384]);
      final embTensor   = OrtValueTensor.createTensorWithDataList(Float32List.fromList(prevEmb), [1, 1, 176]);

      final gruOuts = _gruSession.run(
        OrtRunOptions(),
        {'acoustic_i': frameTensor, 'prev_emb': embTensor, 'h': hTensor},
        ['logits', 'h_new'],
      );
      frameTensor.release(); hTensor.release(); embTensor.release();

      final logitsTensor = gruOuts?[0] as OrtValueTensor?;
      final hNewTensor   = gruOuts?[1] as OrtValueTensor?;

      if (hNewTensor != null) {
        final hNewData = hNewTensor.value as List;
        for (int k = 0; k < 384; k++) {
          h[k] = (hNewData[0][0][k] as num).toDouble();
        }
        hNewTensor.release();
      }

      if (logitsTensor != null) {
        final logitsData = logitsTensor.value as List;
        for (int p = 0; p < 88; p++) {
          final logits = logitsData[0][0][p] as List;
          double maxL = double.negativeInfinity;
          for (int c = 0; c < 5; c++) {
            final v = (logits[c] as num).toDouble();
            if (v > maxL) maxL = v;
          }
          double sum = 0.0;
          final exps = List<double>.generate(5, (c) {
            final e = exp((logits[c] as num).toDouble() - maxL);
            sum += e;
            return e;
          });
          int best = 0;
          double bestP = exps[0];
          for (int c = 1; c < 5; c++) {
            if (exps[c] > bestP) { bestP = exps[c]; best = c; }
          }
          final p0    = exps[0] / sum;
          final pNote = 1.0 - p0;
          if (pNote > lastMaxNoteP) lastMaxNoteP = pNote;
          result[i * 88 + p] = best;

          // Update prevEmb
          prevEmb[p * 2]     = _embTable[best][0];
          prevEmb[p * 2 + 1] = _embTable[best][1];
        }
        logitsTensor.release();
      }
    }

    // Write back to main state if this was the primary inference path
    if (updateState) {
      _h       = h;
      _prevEmb = prevEmb;
    }

    return result;
  }

  void close() {
    _acousticSession.release();
    _gruSession.release();
  }
}
