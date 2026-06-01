import 'package:flutter/material.dart';
import '../game/chord_data.dart';
import '../game/level_progress.dart';
import 'chord_learning_screen.dart';

class ChordSelectScreen extends StatefulWidget {
  const ChordSelectScreen({super.key});
  @override
  State<ChordSelectScreen> createState() => _ChordSelectScreenState();
}

class _ChordSelectScreenState extends State<ChordSelectScreen> {
  final _done = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final c in chords) {
      _done[c.key] = await LevelProgress.isChordDone(c.key);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.home_outlined, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              const Text('Аккорды', style: TextStyle(fontSize: 22,
                  fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(width: 12),
              const Text('Сыграй все ноты аккорда', style: TextStyle(
                  fontSize: 12, color: Color(0xFF888888))),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: chords.length,
              itemBuilder: (_, i) {
                final c    = chords[i];
                final done = _done[c.key] ?? false;
                return _ChordCard(
                  chord: c,
                  done:  done,
                  onTap: () async {
                    await Navigator.push(context,
                      MaterialPageRoute(
                          builder: (_) => ChordLearningScreen(chord: c)));
                    _load();
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class _ChordCard extends StatelessWidget {
  final ChordDefinition chord;
  final bool done;
  final VoidCallback onTap;
  const _ChordCard({required this.chord, required this.done, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        color: const Color(0xFF1E2030),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(children: [
              // Symbol badge
              Container(
                width: 48, height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done
                      ? const Color(0xFF4CAF50).withAlpha(30)
                      : const Color(0xFFFFD740).withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: done
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFF444455),
                  ),
                ),
                child: Text(chord.symbol,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: done
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFFFD740),
                    )),
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(chord.name, style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold,
                      color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(
                    '${chord.description}  ·  ${chord.pitches.length} ноты',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                  ),
                ],
              )),
              if (done)
                const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 22)
              else
                const Icon(Icons.chevron_right, color: Color(0xFF444455), size: 22),
            ]),
          ),
        ),
      ),
    );
  }
}
