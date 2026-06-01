import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:mic_stream/mic_stream.dart';
import '../services/device_settings.dart';
import 'mel_extractor.dart';
import 'note_detector.dart';
import 'onnx_transcriber.dart';

// ── Messages UI → Worker ──────────────────────────────────────────────────────
class _AudioChunk { final List<int> bytes; _AudioChunk(this.bytes); }
class _StopCmd    {}

// ── Messages Worker → UI ──────────────────────────────────────────────────────
class _ReadyMsg  {}
class _NoteEvent { final int pitch, backMs; _NoteEvent(this.pitch, this.backMs); }
class _ConfEvent { final int pitch, level;  _ConfEvent(this.pitch, this.level);  }
class _DebugEvent{ final double maxP;       _DebugEvent(this.maxP);              }
class _ErrorEvent{ final String msg;        _ErrorEvent(this.msg);               }

class _StartupArgs {
  final SendPort    toMain;
  final RootIsolateToken token;
  final Uint8List   acousticBytes;
  final Uint8List   gruBytes;
  final double      pitchDelta;
  _StartupArgs(this.toMain, this.token, this.acousticBytes, this.gruBytes,
      {this.pitchDelta = 0.0});
}

// ── Public API ─────────────────────────────────────────────────────────────────
/// Runs mel-extraction + ONNX inference in a background isolate.
/// Mic capture stays on the main isolate (platform channel limitation),
/// raw audio bytes are sent to the worker via SendPort.
class InferenceIsolate {
  final void Function(int pitch, int backMs)  onNoteDetected;
  final void Function(int pitch, int level)   onConfidenceUp;
  final void Function(double maxP)?           onDebug;
  final void Function(String err)?            onError;

  ReceivePort?          _fromWorker;
  SendPort?             _toWorker;
  Isolate?              _isolate;
  StreamSubscription?   _msgSub;
  StreamSubscription?   _micSub;
  bool                  _stopped = false;

  InferenceIsolate({
    required this.onNoteDetected,
    required this.onConfidenceUp,
    this.onDebug,
    this.onError,
  });

  Future<void> start({double? pitchDeltaOverride}) async {
    _stopped = false;

    // ── 1. Load model bytes on main isolate (rootBundle works here) ──────────
    final acousticData = await rootBundle.load('assets/models/acoustic.onnx');
    final gruData      = await rootBundle.load('assets/models/gru_frame.onnx');
    final acousticBytes = acousticData.buffer.asUint8List();
    final gruBytes      = gruData.buffer.asUint8List();

    // ── 2. Spawn worker isolate ───────────────────────────────────────────────
    final pitchDelta = pitchDeltaOverride ?? await DeviceSettings.getPitchDelta();
    final token = RootIsolateToken.instance!;
    _fromWorker = ReceivePort();

    final readyCompleter = Completer<void>();

    _msgSub = _fromWorker!.listen((msg) {
      if (_stopped) return;
      if (msg is SendPort) {
        _toWorker = msg;
      } else if (msg is _ReadyMsg) {
        if (!readyCompleter.isCompleted) readyCompleter.complete();
      } else if (msg is _NoteEvent) {
        onNoteDetected(msg.pitch, msg.backMs);
      } else if (msg is _ConfEvent) {
        onConfidenceUp(msg.pitch, msg.level);
      } else if (msg is _DebugEvent) {
        onDebug?.call(msg.maxP);
      } else if (msg is _ErrorEvent) {
        onError?.call(msg.msg);
      }
    });

    _isolate = await Isolate.spawn(
      _workerMain,
      _StartupArgs(_fromWorker!.sendPort, token, acousticBytes, gruBytes,
          pitchDelta: pitchDelta),
      errorsAreFatal: false,
      debugName: 'InferenceWorker',
    );

    // Wait for worker to finish loading sessions
    await readyCompleter.future;

    // ── 3. Start mic on main isolate, pipe bytes to worker ───────────────────
    final micStream = await MicStream.microphone(
      sampleRate:    16000,
      channelConfig: ChannelConfig.CHANNEL_IN_MONO,
      audioFormat:   AudioFormat.ENCODING_PCM_16BIT,
    );

    _micSub = micStream.listen(
      (bytes) => _toWorker?.send(_AudioChunk(bytes)),
      onError: (e) => onError?.call('Mic: $e'),
    );
  }

  void stop() {
    _stopped = true;
    _micSub?.cancel();
    _toWorker?.send(_StopCmd());
    _msgSub?.cancel();
    _fromWorker?.close();
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _micSub     = null;
    _toWorker   = null;
    _msgSub     = null;
    _fromWorker = null;
    _isolate    = null;
  }
}

// ── Worker isolate ─────────────────────────────────────────────────────────────
Future<void> _workerMain(_StartupArgs args) async {
  // BackgroundIsolateBinaryMessenger lets us call OrtSession.fromBuffer()
  // via MethodChannel from this isolate. We do NOT need mic_stream or
  // rootBundle here — those stay on the main isolate.
  BackgroundIsolateBinaryMessenger.ensureInitialized(args.token);

  final receivePort = ReceivePort();
  args.toMain.send(receivePort.sendPort);

  OnnxTranscriber? transcriber;
  NoteProcessor?   processor;

  try {
    // Create ONNX sessions from pre-loaded bytes (no rootBundle needed)
    transcriber = OnnxTranscriber.fromBytes(args.acousticBytes, args.gruBytes);

    processor = NoteProcessor(
      transcriber:    transcriber,
      melExtractor:   MelExtractor(),
      pitchDelta:     args.pitchDelta,
      onNoteDetected: (p, ms) => args.toMain.send(_NoteEvent(p, ms)),
      onConfidenceUp: (p, l)  => args.toMain.send(_ConfEvent(p, l)),
      onDebug:        (v)     => args.toMain.send(_DebugEvent(v)),
      onError:        (e)     => args.toMain.send(_ErrorEvent(e)),
    );

    args.toMain.send(_ReadyMsg());

    // Process incoming audio chunks until StopCmd
    await for (final msg in receivePort) {
      if (msg is _AudioChunk) {
        processor.feed(msg.bytes);
      } else if (msg is _StopCmd) {
        break;
      }
    }
  } catch (e, st) {
    args.toMain.send(_ErrorEvent('Worker: $e\n$st'));
  } finally {
    transcriber?.close();
    receivePort.close();
  }
}
