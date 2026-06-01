import 'package:flutter/material.dart';
import '../game/level_progress.dart';
import '../main.dart' show routeObserver;
import '../services/api_service.dart';
import 'auth_screen.dart';
import 'game_screen.dart';
import 'leaderboard_screen.dart';
import 'scale_select_screen.dart';
import 'chord_select_screen.dart';
import 'settings_screen.dart';
import 'sight_reading_screen.dart';

// ── Campaign level definitions ────────────────────────────────────────────────
class _CampaignLevel {
  final int    index;
  final String name;
  final String pieceId;
  final String midiAsset;
  final int    originalQuarterMs;
  final int    defaultQuarterMs;  // pre-selected difficulty
  const _CampaignLevel({
    required this.index,
    required this.name,
    required this.pieceId,
    required this.midiAsset,
    required this.originalQuarterMs,
    required this.defaultQuarterMs,
  });
}

const _campaignLevels = [
  _CampaignLevel(index: 1, name: 'Ёлочка',          pieceId: 'elochka',
      midiAsset: 'assets/midi/elochka.mid',      originalQuarterMs: 500, defaultQuarterMs: 800),
  _CampaignLevel(index: 2, name: 'Мэри и ягнёнок',  pieceId: 'mary',
      midiAsset: 'assets/midi/mary.mid',         originalQuarterMs: 500, defaultQuarterMs: 700),
  _CampaignLevel(index: 3, name: 'Звёздочка',        pieceId: 'twinkle',
      midiAsset: 'assets/midi/twinkle.mid',      originalQuarterMs: 500, defaultQuarterMs: 600),
  _CampaignLevel(index: 4, name: 'Новогодняя',       pieceId: 'jingle',
      midiAsset: 'assets/midi/jingle_bells.mid', originalQuarterMs: 400, defaultQuarterMs: 550),
  _CampaignLevel(index: 5, name: 'Ода к радости',    pieceId: 'ode',
      midiAsset: 'assets/midi/ode_to_joy.mid',   originalQuarterMs: 500, defaultQuarterMs: 500),
];

// ── Piece catalogue ───────────────────────────────────────────────────────────
class _PieceData {
  final String id;
  final String name;
  final String subtitle;
  final String midiAsset;
  final int originalQuarterMs;

  const _PieceData({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.midiAsset,
    required this.originalQuarterMs,
  });
}

const _pieces = [
  _PieceData(id: 'elochka',   name: 'Ёлочка',          subtitle: 'Рус. народная',
             midiAsset: 'assets/midi/elochka.mid',     originalQuarterMs: 500),
  _PieceData(id: 'twinkle',   name: 'Звёздочка',        subtitle: 'Нар. / Моцарт',
             midiAsset: 'assets/midi/twinkle.mid',     originalQuarterMs: 500),
  _PieceData(id: 'ode',       name: 'Ода к радости',    subtitle: 'Бетховен',
             midiAsset: 'assets/midi/ode_to_joy.mid',  originalQuarterMs: 500),
  _PieceData(id: 'jingle',    name: 'Новогодняя',       subtitle: 'Jingle Bells',
             midiAsset: 'assets/midi/jingle_bells.mid',originalQuarterMs: 400),
  _PieceData(id: 'mary',      name: 'Мэри и ягнёнок',  subtitle: 'Нар.',
             midiAsset: 'assets/midi/mary.mid',        originalQuarterMs: 500),
  _PieceData(id: 'birthday',  name: 'С Днём Рождения', subtitle: 'Нар.',
             midiAsset: 'assets/midi/birthday.mid',    originalQuarterMs: 600),
];

// ── Screen ────────────────────────────────────────────────────────────────────
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});
  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with RouteAware {
  Map<String, int> _bestScores     = {};
  int              _maxUnlocked    = 1;
  List<int>        _campaignBests  = List.filled(LevelProgress.totalCampaignLevels, 0);
  String?          _username;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() => _loadProgress();

  void _loadProgress() async {
    final scores = <String, int>{};
    for (final p in _pieces) {
      scores[p.id] = await LevelProgress.getBestScoreForPiece(p.id);
    }
    final maxUnlocked = await LevelProgress.getMaxUnlocked();
    final bests = <int>[];
    for (int i = 1; i <= LevelProgress.totalCampaignLevels; i++) {
      bests.add(await LevelProgress.getCampaignBest(i));
    }
    final username = await ApiService.getUsername();
    if (mounted) setState(() {
      _bestScores    = scores;
      _maxUnlocked   = maxUnlocked;
      _campaignBests = bests;
      _username      = username;
    });
  }

  Future<void> _openCampaignLevel(_CampaignLevel lvl) async {
    final savedTempo = await LevelProgress.getCampaignTempo(lvl.index);
    if (!mounted) return;
    final selectedMs = await showDialog<int>(
      context: context,
      builder: (_) => _TempoPickerDialog(
        pieceName:         'Уровень ${lvl.index} — ${lvl.name}',
        originalQuarterMs: lvl.originalQuarterMs,
        savedQuarterMs:    savedTempo ?? lvl.defaultQuarterMs,
      ),
    );
    if (selectedMs == null || !mounted) return;
    await LevelProgress.saveCampaignTempo(lvl.index, selectedMs);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => GameScreen(
        piece:             'Уровень ${lvl.index} — ${lvl.name}',
        midiAsset:         lvl.midiAsset,
        originalQuarterMs: lvl.originalQuarterMs,
        selectedQuarterMs: selectedMs,
        pieceId:           lvl.pieceId,
        campaignLevel:     lvl.index,
      ),
    ));
  }

  Future<void> _openTempoPicker(_PieceData piece) async {
    final savedTempo = await LevelProgress.getSavedTempoForPiece(piece.id);

    if (!mounted) return;
    final selectedMs = await showDialog<int>(
      context: context,
      builder: (_) => _TempoPickerDialog(
        pieceName:         piece.name,
        originalQuarterMs: piece.originalQuarterMs,
        savedQuarterMs:    savedTempo,
      ),
    );
    if (selectedMs == null || !mounted) return;

    await LevelProgress.saveTempoForPiece(piece.id, selectedMs);

    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => GameScreen(
        piece:             piece.name,
        midiAsset:         piece.midiAsset,
        originalQuarterMs: piece.originalQuarterMs,
        selectedQuarterMs: selectedMs,
        pieceId:           piece.id,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
        child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(alignment: Alignment.centerRight, children: [
              const SizedBox(width: 360,
                child: Center(child: Text('NoteRun',
                    style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold,
                        color: Color(0xFFFFD740))))),
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Color(0xFF555566)),
                tooltip: 'Настройки',
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ]),
            if (_username != null) ...[
              const SizedBox(height: 6),
              Text('Привет, $_username!',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF888888))),
            ],
            const SizedBox(height: 4),
            // Profile / logout row
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (_username != null)
                TextButton.icon(
                  onPressed: () async {
                    await ApiService.logout();
                    if (!mounted) return;
                    Navigator.pushReplacement(context,
                        MaterialPageRoute(builder: (_) => const AuthScreen()));
                  },
                  icon: const Icon(Icons.logout, size: 14, color: Color(0xFF555566)),
                  label: const Text('Выйти',
                      style: TextStyle(fontSize: 12, color: Color(0xFF555566))),
                )
              else
                TextButton.icon(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AuthScreen())),
                  icon: const Icon(Icons.login, size: 14, color: Color(0xFF888888)),
                  label: const Text('Войти',
                      style: TextStyle(fontSize: 12, color: Color(0xFF888888))),
                ),
            ]),
            const SizedBox(height: 24),

            _MenuCard(
              icon: Icons.school,
              title: 'Гаммы',
              subtitle: 'Учись играть гаммы нота за нотой',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ScaleSelectScreen())),
            ),

            const SizedBox(height: 12),

            _MenuCard(
              icon: Icons.piano,
              title: 'Аккорды',
              subtitle: 'Сыграй все ноты трезвучия',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ChordSelectScreen())),
            ),

            const SizedBox(height: 12),

            _MenuCard(
              icon: Icons.visibility,
              title: 'Чтение с листа',
              subtitle: 'Бесконечный режим — 3 жизни',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SightReadingScreen())),
              trailingIcon: _username != null ? Icons.leaderboard : null,
              onTrailingTap: _username != null ? () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LeaderboardScreen(
                      mode: 'sight_reading', title: 'Лидеры — Чтение с листа'))) : null,
            ),

            const SizedBox(height: 28),
            const Text('КАМПАНИЯ', style: TextStyle(
                color: Color(0xFF888888), fontSize: 12,
                letterSpacing: 1.5)),
            const SizedBox(height: 12),

            for (final lvl in _campaignLevels) ...[
              _CampaignLevelCard(
                lvl:       lvl,
                unlocked:  lvl.index <= _maxUnlocked,
                bestScore: _campaignBests.length >= lvl.index
                    ? _campaignBests[lvl.index - 1] : 0,
                onTap:     lvl.index <= _maxUnlocked
                    ? () => _openCampaignLevel(lvl) : null,
              ),
              if (lvl.index < _campaignLevels.length)
                const SizedBox(height: 10),
            ],

            const SizedBox(height: 28),
            const Text('СВОБОДНАЯ ИГРА', style: TextStyle(
                color: Color(0xFF888888), fontSize: 12,
                letterSpacing: 1.5)),
            const SizedBox(height: 12),

            for (final piece in _pieces) ...[
              _PieceCard(
                piece:     piece,
                bestScore: _bestScores[piece.id] ?? 0,
                onTap:     () => _openTempoPicker(piece),
              ),
              const SizedBox(height: 10),
            ],

            const SizedBox(height: 8),
          ],
        ),
        ),
        ),
      ),
    );
  }
}

// ── Campaign level card ───────────────────────────────────────────────────────
class _CampaignLevelCard extends StatelessWidget {
  final _CampaignLevel lvl;
  final bool unlocked;
  final int bestScore;
  final VoidCallback? onTap;

  const _CampaignLevelCard({
    required this.lvl,
    required this.unlocked,
    required this.bestScore,
    this.onTap,
  });

  Color _scoreColor(int pct) {
    if (pct >= 95) return const Color(0xFF4CAF50);
    if (pct >= 70) return const Color(0xFFFFD740);
    return const Color(0xFFF44336);
  }

  @override
  Widget build(BuildContext context) {
    final stars     = LevelProgress.starsForPct(bestScore);
    final hasScore  = bestScore > 0;
    final cardColor = unlocked ? const Color(0xFF1E2030) : const Color(0xFF141420);
    final textColor = unlocked ? Colors.white : const Color(0xFF555566);
    final accent    = unlocked ? const Color(0xFFFFD740) : const Color(0xFF555566);

    return SizedBox(
      width: 360,
      child: Card(
        color: cardColor,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(children: [
              // Level number badge
              Container(
                width: 40, height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withAlpha(unlocked ? 30 : 15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accent.withAlpha(unlocked ? 180 : 80)),
                ),
                child: Text('${lvl.index}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                        color: accent)),
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lvl.name, style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold,
                      color: textColor)),
                  const SizedBox(height: 2),
                  Text(
                    unlocked
                        ? (hasScore
                            ? 'Лучший: $bestScore%'
                            : 'Нажми чтобы играть')
                        : 'Нужно 95% на предыдущем уровне',
                    style: TextStyle(
                        fontSize: 11,
                        color: unlocked
                            ? const Color(0xFF888888)
                            : const Color(0xFF444455)),
                  ),
                ],
              )),
              if (unlocked && hasScore) ...[
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  _StarsRow(stars: stars, size: 16),
                  const SizedBox(height: 2),
                  Text('$bestScore%',
                      style: TextStyle(fontSize: 13,
                          color: _scoreColor(bestScore))),
                ]),
              ] else if (!unlocked) ...[
                Icon(Icons.lock, color: const Color(0xFF555566), size: 22),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Piece card ────────────────────────────────────────────────────────────────
class _PieceCard extends StatelessWidget {
  final _PieceData piece;
  final int bestScore;
  final VoidCallback onTap;

  const _PieceCard({
    required this.piece,
    required this.bestScore,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final stars = LevelProgress.starsForPct(bestScore);
    final hasScore = bestScore > 0;

    return SizedBox(
      width: 360,
      child: Card(
        color: const Color(0xFF1E2030),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Row(children: [
              const Icon(Icons.music_note, size: 32, color: Color(0xFFFFD740)),
              const SizedBox(width: 16),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(piece.name, style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold,
                      color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(piece.subtitle, style: const TextStyle(
                      fontSize: 12, color: Color(0xFF888888))),
                ],
              )),
              if (hasScore) ...[
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  _StarsRow(stars: stars, size: 16),
                  const SizedBox(height: 2),
                  Text('$bestScore%', style: TextStyle(
                      fontSize: 13,
                      color: bestScore >= 95 ? const Color(0xFF4CAF50)
                           : bestScore >= 70 ? const Color(0xFFFFD740)
                           : const Color(0xFFF44336))),
                ]),
              ],
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Color(0xFF444455), size: 20),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Stars row ─────────────────────────────────────────────────────────────────
class _StarsRow extends StatelessWidget {
  final int stars;
  final double size;
  const _StarsRow({required this.stars, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
      final filled = i < stars;
      return Icon(
        filled ? Icons.star : Icons.star_border,
        color: filled ? const Color(0xFFFFD740) : const Color(0xFF444455),
        size: size,
      );
    }));
  }
}

// ── Tempo picker dialog ───────────────────────────────────────────────────────
enum _Diff { easy, normal, hard, custom }

class _TempoPickerDialog extends StatefulWidget {
  final String pieceName;
  final int originalQuarterMs;
  final int? savedQuarterMs;
  const _TempoPickerDialog({
    required this.pieceName,
    required this.originalQuarterMs,
    this.savedQuarterMs,
  });
  @override
  State<_TempoPickerDialog> createState() => _TempoPickerDialogState();
}

class _TempoPickerDialogState extends State<_TempoPickerDialog> {
  static const _presets = {
    _Diff.easy:   800,
    _Diff.normal: 500,
    _Diff.hard:   330,
  };
  static const _diffLabels = {
    _Diff.easy:   'Легко',
    _Diff.normal: 'Нормально',
    _Diff.hard:   'Сложно',
  };
  static const _diffColors = {
    _Diff.easy:   Color(0xFF4CAF50),
    _Diff.normal: Color(0xFFFFD740),
    _Diff.hard:   Color(0xFFF44336),
  };

  static const int _minMs = 300;
  static const int _maxMs = 2500;

  _Diff _selected = _Diff.normal;
  int   _customMs = 500;
  bool  _showCustom = false;

  int get _quarterMs => _selected == _Diff.custom ? _customMs : _presets[_selected]!;
  int get _bpm => (60000 / _quarterMs).round();

  @override
  void initState() {
    super.initState();
    final saved = widget.savedQuarterMs ?? widget.originalQuarterMs;
    _customMs = saved;
    final match = _presets.entries
        .where((e) => (e.value - saved).abs() <= 10)
        .map((e) => e.key)
        .firstOrNull;
    _selected = match ?? _Diff.custom;
    if (_selected == _Diff.custom) _showCustom = true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E2030),
      title: Text(widget.pieceName,
          style: const TextStyle(color: Colors.white, fontSize: 18)),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 4),

          Row(children: [
            for (final d in [_Diff.easy, _Diff.normal, _Diff.hard]) ...[
              Expanded(child: _DiffButton(
                label:    _diffLabels[d]!,
                bpm:      (60000 / _presets[d]!).round(),
                color:    _diffColors[d]!,
                selected: _selected == d,
                onTap: () => setState(() { _selected = d; _showCustom = false; }),
              )),
              if (d != _Diff.hard) const SizedBox(width: 8),
            ],
          ]),

          const SizedBox(height: 12),

          InkWell(
            onTap: () => setState(() {
              _showCustom = !_showCustom;
              if (_showCustom) _selected = _Diff.custom;
              else if (_selected == _Diff.custom) _selected = _Diff.normal;
            }),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(children: [
                Icon(
                  _showCustom ? Icons.expand_less : Icons.expand_more,
                  color: const Color(0xFF888888), size: 20,
                ),
                const SizedBox(width: 4),
                const Text('Свой темп', style: TextStyle(
                    color: Color(0xFF888888), fontSize: 13)),
                if (_selected == _Diff.custom) ...[
                  const Spacer(),
                  Text('$_bpm BPM  ·  $_quarterMs ms',
                      style: const TextStyle(color: Color(0xFFFFD740), fontSize: 13)),
                ],
              ]),
            ),
          ),

          if (_showCustom) ...[
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor:   const Color(0xFFFFD740),
                inactiveTrackColor: const Color(0xFF444444),
                thumbColor:         const Color(0xFFFFD740),
                overlayColor:       const Color(0x33FFD740),
              ),
              child: Slider(
                value: _customMs.toDouble(),
                min:   _minMs.toDouble(),
                max:   _maxMs.toDouble(),
                divisions: (_maxMs - _minMs) ~/ 50,
                onChanged: (v) => setState(() {
                  _customMs  = v.round();
                  _selected  = _Diff.custom;
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Быстро',   style: TextStyle(color: Color(0xFF666666), fontSize: 11)),
                const Text('Медленно', style: TextStyle(color: Color(0xFF666666), fontSize: 11)),
              ]),
            ),
          ],
        ])),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена', style: TextStyle(color: Color(0xFF888888))),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _quarterMs),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFD740),
            foregroundColor: Colors.black,
          ),
          child: const Text('Играть'),
        ),
      ],
    );
  }
}

class _DiffButton extends StatelessWidget {
  final String label;
  final int bpm;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _DiffButton({required this.label, required this.bpm, required this.color,
      required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(40) : const Color(0xFF151722),
          border: Border.all(
            color: selected ? color : const Color(0xFF333344),
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          Text(label, style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold,
              color: selected ? color : const Color(0xFF888899))),
          const SizedBox(height: 2),
          Text('$bpm BPM', style: TextStyle(
              fontSize: 11,
              color: selected ? color.withAlpha(200) : const Color(0xFF555566))),
        ]),
      ),
    );
  }
}

// ── Generic menu card ─────────────────────────────────────────────────────────
class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final IconData? trailingIcon;
  final VoidCallback? onTrailingTap;
  const _MenuCard({required this.icon, required this.title,
      required this.subtitle, this.onTap,
      this.trailingIcon, this.onTrailingTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      child: Card(
        color: onTap == null ? const Color(0xFF1A1A1A) : const Color(0xFF1E2030),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.only(left: 24, right: 8, top: 14, bottom: 14),
            child: Row(children: [
              Icon(icon, size: 36,
                  color: onTap == null ? Colors.grey : const Color(0xFFFFD740)),
              const SizedBox(width: 20),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: onTap == null ? Colors.grey : Colors.white)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(
                      fontSize: 13, color: Color(0xFF888888))),
                ],
              )),
              if (trailingIcon != null)
                IconButton(
                  icon: Icon(trailingIcon, color: const Color(0xFF888888), size: 22),
                  onPressed: onTrailingTap,
                  tooltip: 'Лидерборд',
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
