import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:churchpraise/services/highlight_service.dart';
import 'package:churchpraise/services/local_backup_service.dart';
import 'package:churchpraise/services/reading_plan_service.dart';
import 'package:churchpraise/services/score_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backup = LocalBackupService.instance;
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('local_backup_test');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// 새 기기처럼 저장소를 비우고 서비스를 다시 읽는다
  Future<void> freshDevice([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    await ScoreService.instance.init();
    ScoreService.instance.scores.value = [];
    await ScoreService.instance.init();
  }

  Future<File> makeBackupWithScore() async {
    final scoreFile = File('${tmp.path}/orig/score_1.pdf');
    await scoreFile.create(recursive: true);
    await scoreFile.writeAsBytes(List.generate(5000, (i) => i % 256));
    final scores = [
      CustomScore(
        id: 's_100',
        title: '주님의 마음',
        filePath: scoreFile.path,
        fileName: '주님의 마음.pdf',
        createdAt: DateTime(2026, 11, 1),
      ).toJson(),
      // 파일이 없는 악보는 백업에서 빠져야 함
      CustomScore(
        id: 's_200',
        title: '없는 파일',
        filePath: '${tmp.path}/orig/missing.png',
        fileName: 'missing.png',
        createdAt: DateTime(2026, 11, 2),
      ).toJson(),
    ];
    await freshDevice({
      'favorites_v2': '{"h_1":"2026-11-01T00:00:00.000"}',
      'contis_v1': '[]',
      'song_tags_v2': '{}',
      HighlightService.prefKey: '{"42:3:16":1}',
      ReadingPlanService.prefKey: '[0,1,2]',
      'anno_v1_s_100': '{"strokes":[1,2,3]}',
      'anno_v1_h1': '{"strokes":[4]}',
      'custom_scores_v1': jsonEncode(scores),
      'unrelated_setting': 'keep-out',
    });
    return backup.createBackupFile(Directory('${tmp.path}/out'),
        now: DateTime(2026, 11, 28, 9, 5));
  }

  test('백업 파일 이름과 구성 (설정 데이터 + 파일이 있는 내 악보만)', () async {
    final zip = await makeBackupWithScore();
    expect(zip.uri.pathSegments.last, '성경찬양_백업_2026-11-28_0905.zip');

    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final manifest = jsonDecode(utf8.decode(
        archive.findFile(LocalBackupService.manifestName)!.content));
    expect(manifest['app'], 'churchpraise');
    expect((manifest['data'] as Map).keys,
        containsAll(['favorites_v2', 'contis_v1', 'song_tags_v2']));
    expect((manifest['data'] as Map).containsKey('unrelated_setting'), isFalse);
    expect((manifest['annotations'] as Map).length, 2);
    final scores = manifest['scores'] as List;
    expect(scores, hasLength(1));
    expect(scores.first['entry'], 'scores/s_100.pdf');
    expect(archive.findFile('scores/s_100.pdf')!.content.length, 5000);
  });

  test('새 기기에서 복원하면 데이터·필기·내 악보 파일이 모두 돌아옴', () async {
    final zip = await makeBackupWithScore();
    final original = await File('${tmp.path}/orig/score_1.pdf').readAsBytes();

    await freshDevice();
    final scoresDir = Directory('${tmp.path}/device2/custom_scores');
    final r = await backup.restoreFromFile(zip, scoresDir: scoresDir);

    expect(r.restoredItems, 5);
    expect(r.annotations, 2);
    expect(r.addedScores, 1);
    expect(r.skippedScores, 0);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('favorites_v2'), '{"h_1":"2026-11-01T00:00:00.000"}');
    expect(prefs.getString(ReadingPlanService.prefKey), '[0,1,2]');
    expect(prefs.getString('anno_v1_s_100'), '{"strokes":[1,2,3]}');

    final restored = ScoreService.instance.findById('s_100')!;
    expect(restored.title, '주님의 마음');
    expect(restored.fileName, '주님의 마음.pdf');
    expect(restored.filePath.startsWith(scoresDir.path), isTrue);
    expect(await File(restored.filePath).readAsBytes(), original);
    expect(ReadingPlanService.instance.done.value, {0, 1, 2});
  });

  test('같은 악보가 이미 있으면 건너뛰고, 다시 복원해도 중복되지 않음', () async {
    final zip = await makeBackupWithScore();
    final scoresDir = Directory('${tmp.path}/same/custom_scores');
    final r = await backup.restoreFromFile(zip, scoresDir: scoresDir);
    expect(r.addedScores, 0);
    expect(r.skippedScores, 1);
    expect(ScoreService.instance.scores.value.where((s) => s.id == 's_100'),
        hasLength(1));
  });

  test('허용하지 않은 키와 엉뚱한 경로 이름은 무시', () async {
    final evil = File('${tmp.path}/evil.zip');
    final encoder = ZipFileEncoder()..create(evil.path);
    encoder.addArchiveFile(ArchiveFile.string(
        LocalBackupService.manifestName,
        jsonEncode({
          'app': 'churchpraise',
          'format': 1,
          'data': {'favorites_v2': '{}', 'admin_mode': 'true'},
          'annotations': {'anno_v1_x': '{}', 'theme': 'dark'},
          'scores': [
            {'id': 's_9', 'title': 't', 'fileName': 'a.pdf', 'entry': '../../outside.pdf'},
          ],
        })));
    encoder.addArchiveFile(ArchiveFile.string('../../outside.pdf', 'x'));
    await encoder.close();

    await freshDevice();
    final scoresDir = Directory('${tmp.path}/dev/custom_scores');
    await backup.restoreFromFile(evil, scoresDir: scoresDir);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('admin_mode'), isNull);
    expect(prefs.getString('theme'), isNull);
    expect(prefs.getString('anno_v1_x'), '{}');
    // 파일이 있었다면 앱이 정한 이름으로 악보 폴더 안에만 저장됨
    expect(File('${tmp.path}/outside.pdf').existsSync(), isFalse);
    for (final s in ScoreService.instance.scores.value) {
      expect(s.filePath.startsWith(scoresDir.path), isTrue);
    }
  });

  test('앱이 읽을 수 없는 데이터면 복원하지 않고 원래 값을 유지', () async {
    final bad = File('${tmp.path}/bad.zip');
    final encoder = ZipFileEncoder()..create(bad.path);
    encoder.addArchiveFile(ArchiveFile.string(
        LocalBackupService.manifestName,
        jsonEncode({
          'app': 'churchpraise',
          'format': 1,
          'data': {'favorites_v2': '{"h_1":true}', ReadingPlanService.prefKey: '[5]'},
        })));
    await encoder.close();

    await freshDevice({'favorites_v2': '{"h_2":"2026-11-01T00:00:00.000"}'});
    expect(backup.restoreFromFile(bad, scoresDir: tmp),
        throwsA(isA<InvalidBackupException>()));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('favorites_v2'), '{"h_2":"2026-11-01T00:00:00.000"}');
    expect(prefs.getString(ReadingPlanService.prefKey), isNull);
  });

  test('다른 앱 파일이나 zip이 아닌 파일은 거부', () async {
    final notZip = File('${tmp.path}/a.zip')..writeAsStringSync('hello');
    expect(backup.restoreFromFile(notZip, scoresDir: tmp),
        throwsA(isA<InvalidBackupException>()));

    final other = File('${tmp.path}/other.zip');
    final encoder = ZipFileEncoder()..create(other.path);
    encoder.addArchiveFile(ArchiveFile.string(
        LocalBackupService.manifestName, jsonEncode({'app': 'mytodo', 'format': 1})));
    await encoder.close();
    expect(backup.restoreFromFile(other, scoresDir: tmp),
        throwsA(isA<InvalidBackupException>()));
  });
}
