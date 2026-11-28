import 'dart:convert';
import 'dart:io';

import 'package:churchpraise/services/score_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.terablack.churchpraise/file_picker');
  final service = ScoreService.instance;
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('score_relink_test');
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Map<String, dynamic> score(String id, String path) => CustomScore(
        id: id,
        title: id,
        filePath: path,
        fileName: '$id.pdf',
        createdAt: DateTime(2026, 11, 1),
      ).toJson();

  test('앱 폴더 경로가 바뀌어도 같은 파일 이름으로 다시 찾아 경로를 고침', () async {
    // 새 앱 폴더에 실제 파일이 있고, 저장된 경로는 예전 앱 폴더를 가리키는 상황
    final newDir = Directory('${tmp.path}/NEW-UUID/Documents/custom_scores')
      ..createSync(recursive: true);
    File('${newDir.path}/score_1.pdf').writeAsStringSync('pdf');
    File('${newDir.path}/score_2.png').writeAsStringSync('png');
    const oldDir = '/var/mobile/Containers/Data/Application/OLD-UUID/Documents/custom_scores';

    SharedPreferences.setMockInitialValues({
      'custom_scores_v1': jsonEncode([
        score('s_1', '$oldDir/score_1.pdf'),
        score('s_2', '${newDir.path}/score_2.png'), // 이미 맞는 경로
        score('s_3', '$oldDir/score_missing.pdf'), // 어디에도 없는 파일
      ]),
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getScoresDir') return newDir.path;
      return null;
    });

    service.scores.value = [];
    await service.init();

    expect(service.findById('s_1')!.filePath, '${newDir.path}/score_1.pdf');
    expect(service.findById('s_2')!.filePath, '${newDir.path}/score_2.png');
    expect(service.findById('s_3')!.filePath, '$oldDir/score_missing.pdf');

    // 고친 경로가 저장되어 다음 실행에도 유지됨
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('custom_scores_v1')!) as List;
    expect(saved.first['filePath'], '${newDir.path}/score_1.pdf');
    expect(await service.relinkMovedFiles(scoresDir: newDir.path), 0);
  });

  test('네이티브 채널이 없으면 목록을 그대로 둠', () async {
    SharedPreferences.setMockInitialValues({
      'custom_scores_v1': jsonEncode([score('s_9', '/nowhere/score_9.pdf')]),
    });
    service.scores.value = [];
    await service.init();
    expect(service.findById('s_9')!.filePath, '/nowhere/score_9.pdf');
  });
}
