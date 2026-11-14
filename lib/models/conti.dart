class Conti {
  final String id;
  String title;
  final DateTime createdAt;
  List<String> songIds;

  Conti({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.songIds,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'songIds': List<String>.from(songIds),
      };

  factory Conti.fromJson(Map<String, dynamic> j) => Conti(
        id: j['id'] as String,
        title: j['title'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        songIds: List<String>.from(j['songIds'] as List),
      );
}
