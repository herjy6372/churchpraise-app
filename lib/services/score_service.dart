import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

class CustomScore {
  final String id;
  String title;
  final String filePath;
  final String fileName;
  final DateTime createdAt;

  CustomScore({
    required this.id,
    required this.title,
    required this.filePath,
    required this.fileName,
    required this.createdAt,
  });

  bool get isPdf => filePath.toLowerCase().endsWith('.pdf');

  Song toSong() => Song(
        id: id,
        title: title,
        assetPath: filePath,
        isLocalFile: true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'filePath': filePath,
        'fileName': fileName,
        'createdAt': createdAt.toIso8601String(),
      };

  static CustomScore fromJson(Map<String, dynamic> json) => CustomScore(
        id: json['id'] as String,
        title: json['title'] as String,
        filePath: json['filePath'] as String,
        fileName: (json['fileName'] as String?) ?? '',
        createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
            DateTime.now(),
      );
}

class PickedScoreFile {
  final String path;
  final String name;
  const PickedScoreFile({required this.path, required this.name});
}

class ScoreService {
  static final instance = ScoreService._();
  ScoreService._();

  static const _key = 'custom_scores_v1';
  static const _channel = MethodChannel('com.terablack.churchpraise/file_picker');

  late SharedPreferences _prefs;
  final scores = ValueNotifier<List<CustomScore>>([]);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _load();
    await relinkMovedFiles();
  }

  /// 저장된 경로에 파일이 없으면, 현재 내 악보 폴더에서 같은 파일 이름을 찾아 경로를 고친다.
  /// iOS는 앱을 다시 설치하거나 백업에서 기기를 옮기면 앱 폴더의 전체 경로가 바뀌어
  /// 예전에 저장한 전체 경로로는 파일을 찾지 못하기 때문이다. 고친 개수를 돌려준다.
  Future<int> relinkMovedFiles({String? scoresDir}) async {
    if (scores.value.isEmpty) return 0;
    final dir = scoresDir ?? await _currentScoresDir();
    if (dir == null) return 0;
    var fixed = 0;
    final list = scores.value.map((s) {
      if (File(s.filePath).existsSync()) return s;
      final candidate = '$dir/${s.filePath.split('/').last}';
      if (candidate == s.filePath || !File(candidate).existsSync()) return s;
      fixed++;
      return CustomScore(
        id: s.id,
        title: s.title,
        filePath: candidate,
        fileName: s.fileName,
        createdAt: s.createdAt,
      );
    }).toList();
    if (fixed > 0) {
      scores.value = list;
      await _save();
    }
    return fixed;
  }

  Future<String?> _currentScoresDir() async {
    try {
      return await _channel.invokeMethod<String>('getScoresDir');
    } catch (_) {
      return null; // 테스트 환경 등 네이티브 채널이 없을 때
    }
  }

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      scores.value = list
          .map((e) => CustomScore.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      scores.value = [];
    }
  }

  Future<void> _save() async {
    await _prefs.setString(
      _key,
      jsonEncode(scores.value.map((s) => s.toJson()).toList()),
    );
  }

  Future<PickedScoreFile?> pickFile() async {
    final res = await _channel.invokeMethod<Map<Object?, Object?>>('pickScoreFile');
    if (res == null) return null;
    final path = res['path'] as String?;
    final name = res['name'] as String?;
    if (path == null) return null;
    return PickedScoreFile(path: path, name: name ?? path.split('/').last);
  }

  Future<CustomScore> addScore({
    required String title,
    required String filePath,
    required String fileName,
  }) async {
    final score = CustomScore(
      id: 's_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      filePath: filePath,
      fileName: fileName,
      createdAt: DateTime.now(),
    );
    scores.value = [score, ...scores.value];
    await _save();
    return score;
  }

  Future<void> updateTitle(String id, String newTitle) async {
    final list = scores.value.toList();
    final idx = list.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    list[idx].title = newTitle;
    scores.value = List.from(list);
    await _save();
  }

  Future<void> delete(String id) async {
    final idx = scores.value.indexWhere((s) => s.id == id);
    if (idx != -1) {
      final item = scores.value[idx];
      try {
        final f = File(item.filePath);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    }
    scores.value = scores.value.where((s) => s.id != id).toList();
    await _save();
  }

  /// 파일 백업에서 불러온 악보를 목록에 더한다. 같은 id가 이미 있으면 건너뛴다.
  /// 더한 개수를 돌려준다.
  Future<int> addRestoredScores(List<CustomScore> restored) async {
    final existing = scores.value.map((s) => s.id).toSet();
    final added = restored.where((s) => !existing.contains(s.id)).toList();
    if (added.isEmpty) return 0;
    final merged = [...scores.value, ...added]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    scores.value = merged;
    await _save();
    return added.length;
  }

  CustomScore? findById(String id) {
    for (final s in scores.value) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<Song> search(String query) {
    final all = scores.value.map((s) => s.toSong()).toList();
    if (query.trim().isEmpty) return all;
    final q = query.trim().toLowerCase();
    return all.where((s) => s.title.toLowerCase().contains(q)).toList();
  }
}
