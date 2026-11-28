import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'conti_service.dart';
import 'favorites_service.dart';
import 'highlight_service.dart';
import 'reading_plan_service.dart';
import 'score_service.dart';
import 'tag_service.dart';

/// 파일 복원 결과
class LocalRestoreResult {
  final int restoredItems; // 즐겨찾기·콘티 등 되살린 항목 종류 수
  final int annotations; // 되살린 필기 수
  final int addedScores; // 새로 더한 내 악보 수
  final int skippedScores; // 이미 있어서 건너뛴 내 악보 수
  const LocalRestoreResult({
    required this.restoredItems,
    required this.annotations,
    required this.addedScores,
    required this.skippedScores,
  });
}

/// 백업 파일이 이 앱의 것이 아니거나 손상되었을 때
class InvalidBackupException implements Exception {
  final String message;
  const InvalidBackupException(this.message);
  @override
  String toString() => message;
}

/// 서버를 거치지 않고 기기 파일(.zip)로 백업·복원한다.
///
/// 백업 파일 구조
///   backup.json          설정 데이터(즐겨찾기·콘티·태그·형광펜·읽기표·필기)와 내 악보 목록
///   scores/<파일 이름>    내 악보 원본 파일(PDF·이미지)
class LocalBackupService {
  static final instance = LocalBackupService._();
  LocalBackupService._();

  static const _channel =
      MethodChannel('com.terablack.churchpraise/file_picker');

  static const appId = 'churchpraise';
  static const formatVersion = 1;
  static const manifestName = 'backup.json';
  static const annoPrefix = 'anno_v1_';
  static const _scoresKey = 'custom_scores_v1';

  /// 백업에 담고 복원할 때 되살리는 설정 키 (이 목록 밖의 키는 파일에 있어도 무시)
  static final List<String> dataKeys = [
    'favorites_v2',
    'contis_v1',
    'song_tags_v2',
    HighlightService.prefKey,
    ReadingPlanService.prefKey,
  ];

  /// 내 악보 파일 하나의 최대 크기 (손상·악의적 파일 방지)
  static const maxEntryBytes = 300 * 1024 * 1024;

  final busy = ValueNotifier<bool>(false);

  static String fileNameFor(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '성경찬양_백업_${now.year}-${two(now.month)}-${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}.zip';
  }

  // ───────────────────────── 백업 ─────────────────────────

  /// [outDir]에 백업 zip을 만들어 돌려준다.
  Future<File> createBackupFile(Directory outDir, {DateTime? now}) async {
    final time = now ?? DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    final data = <String, String>{};
    for (final key in dataKeys) {
      final v = prefs.getString(key);
      if (v != null) data[key] = v;
    }
    final annotations = <String, String>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(annoPrefix)) continue;
      final v = prefs.getString(key);
      if (v != null) annotations[key] = v;
    }

    // 내 악보: 실제 파일이 있는 것만 담는다
    final scores = <Map<String, dynamic>>[];
    final scoreFiles = <String, File>{};
    for (final s in _readScores(prefs)) {
      final f = File(s.filePath);
      if (!await f.exists()) continue;
      final entry = 'scores/${s.id}${_safeExt(s.filePath)}';
      scores.add({
        'id': s.id,
        'title': s.title,
        'fileName': s.fileName,
        'createdAt': s.createdAt.toIso8601String(),
        'entry': entry,
      });
      scoreFiles[entry] = f;
    }

    final manifest = {
      'app': appId,
      'format': formatVersion,
      'createdAt': time.toIso8601String(),
      'data': data,
      'annotations': annotations,
      'scores': scores,
    };

    if (!await outDir.exists()) await outDir.create(recursive: true);
    final out = File('${outDir.path}/${fileNameFor(time)}');
    if (await out.exists()) await out.delete();

    final encoder = ZipFileEncoder();
    encoder.create(out.path);
    try {
      encoder.addArchiveFile(
          ArchiveFile.string(manifestName, jsonEncode(manifest)));
      for (final e in scoreFiles.entries) {
        await encoder.addFile(e.value, e.key);
      }
    } finally {
      await encoder.close();
    }
    return out;
  }

  // ───────────────────────── 복원 ─────────────────────────

  /// 백업 zip을 읽어 설정 데이터를 덮어쓰고, 내 악보는 [scoresDir]에 풀어 목록에 더한다.
  Future<LocalRestoreResult> restoreFromFile(
    File zip, {
    required Directory scoresDir,
  }) async {
    final input = InputFileStream(zip.path);
    try {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeStream(input);
      } catch (_) {
        throw const InvalidBackupException('백업 파일을 열 수 없습니다. 손상되었거나 zip 파일이 아닙니다.');
      }

      final manifestFile = archive.findFile(manifestName);
      if (manifestFile == null || manifestFile.size > 50 * 1024 * 1024) {
        throw const InvalidBackupException('성경&찬양 백업 파일이 아닙니다.');
      }
      final Map<String, dynamic> manifest;
      try {
        manifest = jsonDecode(utf8.decode(manifestFile.content))
            as Map<String, dynamic>;
      } catch (_) {
        throw const InvalidBackupException('백업 내용을 읽을 수 없습니다.');
      }
      if (manifest['app'] != appId) {
        throw const InvalidBackupException('성경&찬양 백업 파일이 아닙니다.');
      }
      final format = manifest['format'];
      if (format is! int || format > formatVersion) {
        throw const InvalidBackupException('더 새 버전의 앱에서 만든 백업입니다. 앱을 업데이트한 뒤 다시 시도해 주세요.');
      }

      final prefs = await SharedPreferences.getInstance();

      // 1) 설정 데이터 (허용한 키만). 형식이 맞지 않아 앱이 읽지 못하면 원래 값으로 되돌린다.
      var restoredItems = 0;
      final snapshot = {for (final k in dataKeys) k: prefs.getString(k)};
      final data = manifest['data'];
      if (data is Map) {
        for (final key in dataKeys) {
          final v = data[key];
          if (v is String) {
            await prefs.setString(key, v);
            restoredItems++;
          }
        }
      }
      try {
        await _reloadServices();
      } catch (_) {
        for (final e in snapshot.entries) {
          if (e.value == null) {
            await prefs.remove(e.key);
          } else {
            await prefs.setString(e.key, e.value!);
          }
        }
        await _reloadServices();
        throw const InvalidBackupException('백업 데이터의 형식이 올바르지 않아 복원하지 않았습니다.');
      }

      // 2) 필기 (anno_v1_ 로 시작하는 키만)
      var annotations = 0;
      final anno = manifest['annotations'];
      if (anno is Map) {
        for (final e in anno.entries) {
          final k = e.key;
          final v = e.value;
          if (k is String && k.startsWith(annoPrefix) && v is String && _isJson(v)) {
            await prefs.setString(k, v);
            annotations++;
          }
        }
      }

      // 3) 내 악보 파일 (이미 같은 id가 있으면 건너뜀, 파일 이름은 앱이 새로 정함)
      if (!await scoresDir.exists()) await scoresDir.create(recursive: true);
      final existingIds = _readScores(prefs).map((s) => s.id).toSet();
      final restored = <CustomScore>[];
      var skipped = 0;
      final list = manifest['scores'];
      if (list is List) {
        var seq = 0;
        for (final item in list) {
          if (item is! Map) continue;
          final id = item['id'];
          final title = item['title'];
          final entry = item['entry'];
          if (id is! String || title is! String || entry is! String) continue;
          if (existingIds.contains(id)) {
            skipped++;
            continue;
          }
          final af = archive.findFile(entry);
          if (af == null || !af.isFile || af.size > maxEntryBytes) continue;

          final fileName = item['fileName'] is String ? item['fileName'] as String : '';
          final ext = _safeExt(entry);
          final dest = File(
              '${scoresDir.path}/score_${DateTime.now().millisecondsSinceEpoch}_${seq++}$ext');
          final out = OutputFileStream(dest.path);
          try {
            af.writeContent(out);
          } finally {
            await out.close();
          }
          restored.add(CustomScore(
            id: id,
            title: title,
            filePath: dest.path,
            fileName: fileName,
            createdAt: DateTime.tryParse(item['createdAt'] as String? ?? '') ??
                DateTime.now(),
          ));
          existingIds.add(id);
        }
      }

      final added = await ScoreService.instance.addRestoredScores(restored);

      return LocalRestoreResult(
        restoredItems: restoredItems,
        annotations: annotations,
        addedScores: added,
        skippedScores: skipped,
      );
    } finally {
      await input.close();
    }
  }

  // ───────────────────── 기기 저장 위치와 연결 ─────────────────────

  /// 백업 파일을 만들고, 사용자가 고른 위치(파일 앱·다운로드·드라이브 등)에 저장한다.
  /// 저장하면 true, 사용자가 취소하면 false.
  Future<bool> exportToUserLocation() async {
    busy.value = true;
    File? tmp;
    try {
      final tempPath = await _channel.invokeMethod<String>('getTempDir');
      if (tempPath == null) throw Exception('임시 폴더를 찾을 수 없습니다.');
      tmp = await createBackupFile(Directory('$tempPath/local_backup'));
      final saved = await _channel.invokeMethod<bool>('saveBackupFile', {
        'path': tmp.path,
        'name': tmp.uri.pathSegments.last,
      });
      return saved == true;
    } finally {
      try {
        if (tmp != null && await tmp.exists()) await tmp.delete();
      } catch (_) {}
      busy.value = false;
    }
  }

  /// 사용자가 고른 백업 파일로 복원한다. 취소하면 null.
  Future<LocalRestoreResult?> importFromUserLocation() async {
    final path = await _channel.invokeMethod<String>('pickBackupFile');
    if (path == null) return null;
    busy.value = true;
    final picked = File(path);
    try {
      final scoresPath = await _channel.invokeMethod<String>('getScoresDir');
      if (scoresPath == null) throw Exception('악보 폴더를 찾을 수 없습니다.');
      return await restoreFromFile(picked, scoresDir: Directory(scoresPath));
    } finally {
      try {
        if (await picked.exists()) await picked.delete();
      } catch (_) {}
      busy.value = false;
    }
  }

  // ───────────────────────── 내부 ─────────────────────────

  List<CustomScore> _readScores(SharedPreferences prefs) {
    final raw = prefs.getString(_scoresKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => CustomScore.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static bool _isJson(String v) {
    try {
      jsonDecode(v);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 확장자는 영문·숫자 1~5자만 허용 (그 밖이면 확장자 없음)
  static String _safeExt(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return '';
    final ext = name.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext) ? '.$ext' : '';
  }

  Future<void> _reloadServices() async {
    await FavoritesService.instance.init();
    await ContiService.instance.init();
    await TagService.instance.init();
    await HighlightService.instance.init();
    await ReadingPlanService.instance.init();
  }
}
