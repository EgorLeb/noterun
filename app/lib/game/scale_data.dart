class ScaleDefinition {
  final String name;
  final String key;
  final List<int> ascending;

  const ScaleDefinition({required this.name, required this.key, required this.ascending});

  List<int> get descending => ascending.reversed.toList();
  List<int> get full => [...ascending, ...descending.skip(1)];
  int get totalNotes => full.length;
}

const scales = [
  ScaleDefinition(name: 'До мажор',   key: 'c_major',  ascending: [60, 62, 64, 65, 67, 69, 71, 72]),
  ScaleDefinition(name: 'Соль мажор', key: 'g_major',  ascending: [55, 57, 59, 60, 62, 64, 66, 67]),
  ScaleDefinition(name: 'Ре мажор',   key: 'd_major',  ascending: [62, 64, 66, 67, 69, 71, 73, 74]),
  ScaleDefinition(name: 'Фа мажор',   key: 'f_major',  ascending: [53, 55, 57, 58, 60, 62, 64, 65]),
  ScaleDefinition(name: 'Ля минор',   key: 'a_minor',  ascending: [57, 59, 60, 62, 64, 65, 67, 69]),
  ScaleDefinition(name: 'Ми минор',   key: 'e_minor',  ascending: [64, 66, 67, 69, 71, 72, 74, 76]),
];
