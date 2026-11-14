class Song {
  final String id;
  final String title;
  final String assetPath;
  final int? hymnNumber;
  final String? youtubeUrl;
  final bool isLocalFile;

  const Song({
    required this.id,
    required this.title,
    required this.assetPath,
    this.hymnNumber,
    this.youtubeUrl,
    this.isLocalFile = false,
  });

  bool get isHymn => hymnNumber != null;

  bool get isPdf => assetPath.toLowerCase().endsWith('.pdf');

  String get shortLabel => isHymn ? '${hymnNumber!}장' : title;
}

