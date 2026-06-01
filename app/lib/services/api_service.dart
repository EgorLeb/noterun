import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _base = String.fromEnvironment('API_HOST',
    defaultValue: 'http://89.169.171.219:8000');

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override String toString() => message;
}

class UserInfo {
  final String token;
  final String userId;
  final String username;
  UserInfo({required this.token, required this.userId, required this.username});
}

class LeaderboardRow {
  final int rank;
  final String username;
  final int score;
  final bool isMe;
  final String updatedAt;
  LeaderboardRow({
    required this.rank, required this.username, required this.score,
    required this.isMe, required this.updatedAt,
  });
  factory LeaderboardRow.fromJson(Map<String, dynamic> j) => LeaderboardRow(
    rank: j['rank'], username: j['username'], score: j['score'],
    isMe: j['is_me'], updatedAt: j['updated_at'],
  );
}

class ApiService {
  static const _tokenKey    = 'api_token';
  static const _usernameKey = 'api_username';
  static const _userIdKey   = 'api_user_id';

  // ── Auth ──────────────────────────────────────────────────────────────────

  static Future<UserInfo> register(String email, String username, String password) async {
    final res = await http.post(
      Uri.parse('$_base/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'username': username, 'password': password}),
    );
    if (res.statusCode != 200) {
      final msg = _extractError(res.body);
      throw ApiException(msg);
    }
    final j = jsonDecode(res.body);
    await _saveToken(j['access_token'], j['user_id'], j['username']);
    return UserInfo(token: j['access_token'], userId: j['user_id'], username: j['username']);
  }

  static Future<UserInfo> login(String email, String password) async {
    final res = await http.post(
      Uri.parse('$_base/auth/login'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'username': email, 'password': password},
    );
    if (res.statusCode != 200) {
      final msg = _extractError(res.body);
      throw ApiException(msg);
    }
    final j = jsonDecode(res.body);
    await _saveToken(j['access_token'], j['user_id'], j['username']);
    return UserInfo(token: j['access_token'], userId: j['user_id'], username: j['username']);
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_userIdKey);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_usernameKey);
  }

  static Future<bool> isLoggedIn() async => (await getToken()) != null;

  // ── Progress ──────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getProgress() async {
    final token = await getToken();
    if (token == null) return {};
    final res = await http.get(
      Uri.parse('$_base/progress'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) return {};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<void> syncProgress({
    required Map<String, dynamic> campaign,
    required Map<String, dynamic> scales,
    required Map<String, dynamic> chords,
    required int sightReadingBest,
  }) async {
    final token = await getToken();
    if (token == null) return;
    await http.post(
      Uri.parse('$_base/progress'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'campaign':      campaign,
        'scales':        scales,
        'chords':        chords,
        'sight_reading': {'best': sightReadingBest},
      }),
    );
  }

  // ── Leaderboard ───────────────────────────────────────────────────────────

  static Future<void> submitScore(String mode, int score) async {
    final token = await getToken();
    if (token == null) return;
    await http.post(
      Uri.parse('$_base/leaderboard/submit'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'mode': mode, 'score': score}),
    );
  }

  static Future<List<LeaderboardRow>> getLeaderboard(String mode) async {
    final token = await getToken();
    if (token == null) return [];
    final res = await http.get(
      Uri.parse('$_base/leaderboard/$mode'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) return [];
    final list = jsonDecode(res.body) as List;
    return list.map((j) => LeaderboardRow.fromJson(j)).toList();
  }

  // ── LLM Analysis (async queue + polling) ────────────────────────────────

  /// Submit analysis job, then poll until done. Returns advice text or null.
  static Future<String?> analyzeGame({
    required String pieceName,
    required int bpm,
    required double hitPct,
    required List<String> missedNotes,
    required List<String> lateNotes,
    required int avgDelayMs,
  }) async {
    final token = await getToken();
    if (token == null) return null;
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    try {
      // 1. Submit
      final submit = await http.post(
        Uri.parse('$_base/analyze'),
        headers: headers,
        body: jsonEncode({
          'piece_name':   pieceName,
          'bpm':          bpm,
          'hit_pct':      hitPct,
          'missed_notes': missedNotes,
          'late_notes':   lateNotes,
          'avg_delay_ms': avgDelayMs,
        }),
      );
      if (submit.statusCode != 200) return null;
      final taskId = jsonDecode(submit.body)['task_id'] as String;

      // 2. Poll every 3 sec, up to 3 min
      for (int i = 0; i < 60; i++) {
        await Future.delayed(const Duration(seconds: 3));
        final poll = await http.get(
          Uri.parse('$_base/analyze/$taskId'),
          headers: headers,
        );
        if (poll.statusCode != 200) break;
        final j = jsonDecode(poll.body);
        if (j['status'] == 'done')   return j['advice'] as String?;
        if (j['status'] == 'error')  return null;
        // pending / running → keep polling
      }
    } catch (_) {}
    return null;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Future<void> _saveToken(String token, String userId, String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userIdKey, userId);
    await prefs.setString(_usernameKey, username);
  }

  static String _extractError(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        final d = j['detail'];
        if (d is String) return d;
        if (d is List && d.isNotEmpty) return d.first['msg'] ?? 'Ошибка';
      }
    } catch (_) {}
    return 'Ошибка сервера';
  }
}
