class ChordDefinition {
  final String name;       // "До мажор"
  final String symbol;     // "C"
  final String key;        // storage key
  final List<int> pitches; // MIDI pitches, e.g. [60, 64, 67]
  final String description;// "мажорное трезвучие"

  const ChordDefinition({
    required this.name,
    required this.symbol,
    required this.key,
    required this.pitches,
    required this.description,
  });
}

const chords = [
  // Major triads
  ChordDefinition(name: 'До мажор',   symbol: 'C',  key: 'c_maj',
      pitches: [60, 64, 67], description: 'мажорное трезвучие'),
  ChordDefinition(name: 'Соль мажор', symbol: 'G',  key: 'g_maj',
      pitches: [55, 59, 62], description: 'мажорное трезвучие'),
  ChordDefinition(name: 'Ре мажор',   symbol: 'D',  key: 'd_maj',
      pitches: [62, 66, 69], description: 'мажорное трезвучие'),
  ChordDefinition(name: 'Фа мажор',   symbol: 'F',  key: 'f_maj',
      pitches: [53, 57, 60], description: 'мажорное трезвучие'),
  // Minor triads
  ChordDefinition(name: 'Ля минор',   symbol: 'Am', key: 'a_min',
      pitches: [57, 60, 64], description: 'минорное трезвучие'),
  ChordDefinition(name: 'Ми минор',   symbol: 'Em', key: 'e_min',
      pitches: [52, 55, 59], description: 'минорное трезвучие'),
  ChordDefinition(name: 'Ре минор',   symbol: 'Dm', key: 'd_min',
      pitches: [50, 53, 57], description: 'минорное трезвучие'),
  ChordDefinition(name: 'Си минор',   symbol: 'Bm', key: 'b_min',
      pitches: [59, 62, 66], description: 'минорное трезвучие'),
  // Seventh chords
  ChordDefinition(name: 'До септ.',   symbol: 'C7', key: 'c_dom7',
      pitches: [60, 64, 67, 70], description: 'доминантовый септаккорд'),
  ChordDefinition(name: 'Соль септ.', symbol: 'G7', key: 'g_dom7',
      pitches: [55, 59, 62, 65], description: 'доминантовый септаккорд'),
];
