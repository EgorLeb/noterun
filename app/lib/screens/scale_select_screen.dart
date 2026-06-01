import 'package:flutter/material.dart';
import '../game/scale_data.dart';
import '../game/level_progress.dart';
import 'learning_screen.dart';

class ScaleSelectScreen extends StatefulWidget {
  const ScaleSelectScreen({super.key});
  @override
  State<ScaleSelectScreen> createState() => _ScaleSelectScreenState();
}

class _ScaleSelectScreenState extends State<ScaleSelectScreen> {
  final _completed = <String, bool>{};
  final _perfect   = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    for (final s in scales) {
      _completed[s.key] = await LevelProgress.isScaleCompleted(s.key);
      _perfect[s.key]   = await LevelProgress.isScalePerfect(s.key);
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
                icon: const Icon(Icons.arrow_back, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              const Text('Гаммы', style: TextStyle(fontSize: 22,
                  fontWeight: FontWeight.bold, color: Colors.white)),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: scales.length,
              itemBuilder: (_, i) {
                final s = scales[i];
                final done    = _completed[s.key] ?? false;
                final perfect = _perfect[s.key]   ?? false;
                return _ScaleCard(
                  name:      s.name,
                  noteCount: s.totalNotes,
                  completed: done,
                  perfect:   perfect,
                  onTap: () async {
                    await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => LearningScreen(scale: s)));
                    _loadProgress();
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

class _ScaleCard extends StatelessWidget {
  final String name;
  final int noteCount;
  final bool completed;
  final bool perfect;
  final VoidCallback onTap;

  const _ScaleCard({
    required this.name,
    required this.noteCount,
    required this.completed,
    required this.perfect,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        child: Card(
          color: const Color(0xFF1E2030),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(children: [
                Icon(Icons.music_note, size: 32,
                    color: perfect ? const Color(0xFFFFD740)
                         : completed ? const Color(0xFF4CAF50)
                         : Colors.white54),
                const SizedBox(width: 16),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 18,
                        fontWeight: FontWeight.bold, color: Colors.white)),
                    Text('$noteCount нот (вверх и вниз)',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
                  ],
                )),
                if (perfect)
                  const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.star, color: Color(0xFFFFD740), size: 20),
                    SizedBox(width: 4),
                    Text('Идеально', style: TextStyle(
                        color: Color(0xFFFFD740), fontSize: 12, fontWeight: FontWeight.bold)),
                  ])
                else if (completed)
                  const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 22),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
