import 'package:shared_preferences/shared_preferences.dart';

class LevelProgress {
  static const int totalCampaignLevels  = 5;
  static const int unlockThresholdPct   = 95;

  static int starsForPct(int pct) {
    if (pct >= 95) return 3;
    if (pct >= 85) return 2;
    if (pct >= 70) return 1;
    return 0;
  }

  // ── Campaign levels (int index 1..totalCampaignLevels) ──────────────────────

  static Future<int> getMaxUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('campaign_max_unlocked') ?? 1;
  }

  static Future<int> getCampaignBest(int level) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('campaign_score_$level') ?? 0;
  }

  static Future<List<int>> getCampaignHistory(int level) async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('campaign_history_$level') ?? '';
    if (str.isEmpty) return [];
    return str.split(',').map(int.parse).toList();
  }

  static Future<int?> getCampaignTempo(int level) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('campaign_tempo_$level');
  }

  static Future<void> saveCampaignTempo(int level, int quarterMs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('campaign_tempo_$level', quarterMs);
  }

  /// Returns true if the next level was newly unlocked.
  static Future<bool> reportCampaignScore(int level, int pct) async {
    final prefs = await SharedPreferences.getInstance();

    final prev = prefs.getInt('campaign_score_$level') ?? 0;
    if (pct > prev) await prefs.setInt('campaign_score_$level', pct);

    final str = prefs.getString('campaign_history_$level') ?? '';
    final history = str.isEmpty ? <int>[] : str.split(',').map(int.parse).toList();
    history.add(pct);
    if (history.length > 5) history.removeAt(0);
    await prefs.setString('campaign_history_$level', history.join(','));

    if (pct >= unlockThresholdPct && level < totalCampaignLevels) {
      final current = prefs.getInt('campaign_max_unlocked') ?? 1;
      if (level + 1 > current) {
        await prefs.setInt('campaign_max_unlocked', level + 1);
        return true;
      }
    }
    return false;
  }

  // ── Piece-based progress (string ID) ────────────────────────────────────────

  static Future<int> getBestScoreForPiece(String id) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('piece_score_$id') ?? 0;
  }

  static Future<List<int>> getAttemptHistoryForPiece(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('piece_history_$id') ?? '';
    if (str.isEmpty) return [];
    return str.split(',').map(int.parse).toList();
  }

  static Future<int?> getSavedTempoForPiece(String id) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('piece_tempo_$id');
  }

  static Future<void> saveTempoForPiece(String id, int quarterMs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('piece_tempo_$id', quarterMs);
  }

  static Future<void> reportScoreForPiece(String id, int pct) async {
    final prefs = await SharedPreferences.getInstance();
    final prev = prefs.getInt('piece_score_$id') ?? 0;
    if (pct > prev) await prefs.setInt('piece_score_$id', pct);

    final str = prefs.getString('piece_history_$id') ?? '';
    final history = str.isEmpty ? <int>[] : str.split(',').map(int.parse).toList();
    history.add(pct);
    if (history.length > 5) history.removeAt(0);
    await prefs.setString('piece_history_$id', history.join(','));
  }

  // ── Scale learning ────────────────────────────────────────────────────────
  static Future<bool> isScaleCompleted(String scaleKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('scale_done_$scaleKey') ?? false;
  }

  static Future<bool> isScalePerfect(String scaleKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('scale_perfect_$scaleKey') ?? false;
  }

  static Future<void> reportScaleResult(String scaleKey, {required bool perfect, required int streak}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('scale_done_$scaleKey', true);
    if (perfect) await prefs.setBool('scale_perfect_$scaleKey', true);
    final prev = prefs.getInt('scale_streak_$scaleKey') ?? 0;
    if (streak > prev) await prefs.setInt('scale_streak_$scaleKey', streak);
  }

  // ── Sight-reading ─────────────────────────────────────────────────────────
  static Future<int> getSightReadingBest() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('sight_reading_best') ?? 0;
  }

  static Future<void> reportSightReadingScore(int score) async {
    final prefs = await SharedPreferences.getInstance();
    final prev = prefs.getInt('sight_reading_best') ?? 0;
    if (score > prev) await prefs.setInt('sight_reading_best', score);
  }

  // ── Chord learning ────────────────────────────────────────────────────────
  static Future<bool> isChordDone(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('chord_done_$key') ?? false;
  }

  static Future<void> reportChordResult(String key, {required int attempts}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('chord_done_$key', true);
    final prev = prefs.getInt('chord_attempts_$key') ?? 999;
    if (attempts < prev) await prefs.setInt('chord_attempts_$key', attempts);
  }
}
