import 'dart:math';
import 'dart:typed_data';

class MelExtractor {
  static const int sampleRate = 16000;
  static const int hopLength  = 512;
  static const int nFft       = 2048;
  static const int nMels      = 229;
  static const int nFreqs     = nFft ~/ 2 + 1; // 1025
  static const double fMin    = 0.0;    // librosa default
  static const double fMax    = 8000.0; // sr/2

  late final Float32List _hannWindow;
  late final List<Float32List> _melFilterbank;

  MelExtractor() {
    _hannWindow    = _buildHann();
    _melFilterbank = _buildMelFilterbank();
  }

  Float32List _buildHann() {
    final w = Float32List(nFft);
    for (int n = 0; n < nFft; n++) {
      w[n] = 0.5 * (1.0 - cos(2.0 * pi * n / nFft));
    }
    return w;
  }

  List<Float32List> _buildMelFilterbank() {
    // Slaney mel scale — matches librosa default (htk=False)
    // Linear below 1000 Hz, logarithmic above
    const fSp       = 200.0 / 3.0;   // linear slope
    const minLogHz  = 1000.0;
    const minLogMel = minLogHz / fSp; // = 15.0
    final logStep   = log(6.4) / 27.0;

    double hzToMel(double hz) {
      if (hz < minLogHz) return hz / fSp;
      return minLogMel + log(hz / minLogHz) / logStep;
    }
    double melToHz(double mel) {
      if (mel < minLogMel) return mel * fSp;
      return minLogHz * exp(logStep * (mel - minLogMel));
    }

    final melMin = hzToMel(fMin);
    final melMax = hzToMel(fMax);

    final melPoints = List<double>.generate(
        nMels + 2, (i) => melMin + i * (melMax - melMin) / (nMels + 1));
    final hzPoints = melPoints.map(melToHz).toList();
    final bins = hzPoints
        .map((hz) => (hz / sampleRate * nFft).round().clamp(0, nFreqs - 1))
        .toList();

    final fb = List<Float32List>.generate(nMels, (_) => Float32List(nFreqs));
    for (int m = 0; m < nMels; m++) {
      final left = bins[m], center = bins[m + 1], right = bins[m + 2];
      for (int k = left; k < center; k++) {
        if (center != left) fb[m][k] = (k - left) / (center - left);
      }
      for (int k = center; k < right; k++) {
        if (right != center) fb[m][k] = (right - k) / (right - center);
      }
      final norm = 2.0 / (hzPoints[m + 2] - hzPoints[m]);
      for (int k = 0; k < nFreqs; k++) {
        fb[m][k] *= norm;
      }
    }
    return fb;
  }

  /// Extract log-mel spectrogram from 16-bit PCM.
  /// Returns Float32List [frames * nMels].
  Float32List extract(Int16List pcm) {
    final audio = Float32List(pcm.length);
    for (int i = 0; i < pcm.length; i++) {
      audio[i] = pcm[i] / 32768.0;
    }

    final numFrames = max(0, (audio.length - nFft) ~/ hopLength + 1);
    final result    = Float32List(numFrames * nMels);

    final real = Float64List(nFft);
    final imag = Float64List(nFft);

    for (int frame = 0; frame < numFrames; frame++) {
      final start = frame * hopLength;
      for (int i = 0; i < nFft; i++) {
        final idx = start + i;
        real[i] = idx < audio.length ? audio[idx] * _hannWindow[i] : 0.0;
        imag[i] = 0.0;
      }
      _fft(real, imag);

      final baseIdx = frame * nMels;
      for (int m = 0; m < nMels; m++) {
        double acc = 0.0;
        final filter = _melFilterbank[m];
        for (int k = 0; k < nFreqs; k++) {
          acc += filter[k] * (real[k] * real[k] + imag[k] * imag[k]);
        }
        result[baseIdx + m] = log(acc < 1e-5 ? 1e-5 : acc);
      }
    }
    return result;
  }

  void _fft(Float64List real, Float64List imag) {
    final n = real.length;
    int j = 0;
    for (int i = 1; i < n; i++) {
      int bit = n >> 1;
      while (j & bit != 0) { j ^= bit; bit >>= 1; }
      j ^= bit;
      if (i < j) {
        double tmp = real[i]; real[i] = real[j]; real[j] = tmp;
        tmp = imag[i]; imag[i] = imag[j]; imag[j] = tmp;
      }
    }
    for (int len = 2; len <= n; len <<= 1) {
      final half  = len >> 1;
      final angle = -2.0 * pi / len;
      final wRe   = cos(angle), wIm = sin(angle);
      for (int start = 0; start < n; start += len) {
        double curRe = 1.0, curIm = 0.0;
        for (int k = 0; k < half; k++) {
          final uRe = real[start + k],     uIm = imag[start + k];
          final vRe = real[start+k+half] * curRe - imag[start+k+half] * curIm;
          final vIm = real[start+k+half] * curIm + imag[start+k+half] * curRe;
          real[start + k]      = uRe + vRe;
          imag[start + k]      = uIm + vIm;
          real[start + k+half] = uRe - vRe;
          imag[start + k+half] = uIm - vIm;
          final nextRe = curRe * wRe - curIm * wIm;
          curIm = curRe * wIm + curIm * wRe;
          curRe = nextRe;
        }
      }
    }
  }
}
