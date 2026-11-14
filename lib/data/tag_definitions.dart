class TagCategory {
  static const timeSignature = '박자';
  static const key           = '조성';
  static const rhythm        = '리듬';
  static const theme         = '주제';
  static const bpm           = 'BPM';

  static const all = [timeSignature, key, rhythm, theme, bpm];
}

class TagDefinitions {
  static const Map<String, List<String>> options = {
    TagCategory.timeSignature: ['4/4', '3/4', '6/8', '2/4'],
    TagCategory.key:           ['C', 'D♭', 'D', 'E♭', 'E', 'F', 'F#', 'G', 'A♭', 'A', 'B♭', 'B'],
    TagCategory.rhythm:        ['8비트', '16비트'],
    TagCategory.theme:         ['감사', '은혜', '성령', '고난', '사랑'],
    TagCategory.bpm:           ['80', '84', '88', '92', '96', '100'],
  };

  static List<String> optionsFor(String category) => options[category] ?? [];
}
