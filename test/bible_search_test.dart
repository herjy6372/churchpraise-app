import 'dart:io';

import 'package:churchpraise/services/bible_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 성경 데이터(assets/bible/*.json)는 저작권 문제로 저장소에 없으므로,
// 파일이 있을 때만 실행합니다.
final _hasBibleAssets = BibleVersion.values
    .every((v) => File(v.assetPath).existsSync());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = BibleService.instance;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('역본별 검색', skip: _hasBibleAssets ? false : '성경 데이터 없음', () {
    test('개역개정: 한글 장절·본문 검색은 개역개정 본문만 반환', () async {
      await service.setVersion(BibleVersion.krvRevised);

      final ref = service.search('요 3:16');
      expect(ref, hasLength(1));
      expect(ref.first.reference, '요한복음 3:16');
      expect(ref.first.text, contains('하나님이 세상을 이처럼 사랑하사'));

      final gen = service.search('창 1:2').single.text;
      expect(gen, contains('하나님의 영은')); // 개역개정 표현

      expect(service.search('사랑'), isNotEmpty);
      // 영어 장절·본문은 개역개정에서 찾지 않음
      expect(service.search('John 3:16'), isEmpty);
      expect(service.search('love'), isEmpty);
    });

    test('개역한글: 같은 장절이 개역한글 본문으로 나옴', () async {
      await service.setVersion(BibleVersion.krv);

      final gen = service.search('창세기 1장 2절').single.text;
      expect(gen, contains('하나님의 신은')); // 개역한글 표현
      expect(gen, isNot(contains('하나님의 영은')));

      expect(service.search('John 3:16'), isEmpty);
      expect(service.search('love'), isEmpty);
    });

    test('KJV: 영어 장절·본문 검색은 KJV 본문만 반환', () async {
      await service.setVersion(BibleVersion.kjv);

      for (final q in ['John 3:16', 'jn 3:16', 'Jn. 3:16', '요 3:16']) {
        final r = service.search(q);
        expect(r, hasLength(1), reason: q);
        expect(r.first.text, startsWith('For God so loved the world'),
            reason: q);
      }

      expect(service.search('1 John 4:8').single.text, contains('God is love'));
      expect(service.search('Ps 23').length, 6);
      expect(service.search('Song of Solomon 2:1').single.text,
          contains('rose of Sharon'));

      final love = service.search('love');
      expect(love, isNotEmpty);
      expect(love.every((r) => r.text.toLowerCase().contains('love')), isTrue);

      // 한글 본문 검색어는 KJV에서 찾지 않음
      expect(service.search('사랑'), isEmpty);
    });

    test('비교 역본: 같은 권·장을 함께 불러오고, 기본 역본과 같아지면 해제', () async {
      await service.setVersion(BibleVersion.krvRevised);
      await service.setCompareVersion(BibleVersion.kjv);
      expect(service.compareVersion.value, BibleVersion.kjv);
      // 요한복음(42) 3장 16절
      expect(service.compareChapterVerses(42, 3)[15],
          startsWith('For God so loved the world'));
      expect(service.books[42].getChapterVerses(3)[15], contains('하나님이 세상을'));

      // 기본 역본을 KJV로 바꾸면 비교가 꺼짐
      await service.setVersion(BibleVersion.kjv);
      expect(service.compareVersion.value, isNull);
      expect(service.compareChapterVerses(42, 3), isEmpty);

      // 비교 끄기
      await service.setVersion(BibleVersion.krvRevised);
      await service.setCompareVersion(BibleVersion.krv);
      await service.setCompareVersion(null);
      expect(service.compareVersion.value, isNull);
    });

    test('역본을 바꾸면 같은 검색어 결과도 바뀜', () async {
      await service.setVersion(BibleVersion.kjv);
      final kjv = service.search('창 1:1').single.text;
      await service.setVersion(BibleVersion.krvRevised);
      final rev = service.search('창 1:1').single.text;
      expect(kjv, startsWith('In the beginning'));
      expect(rev, contains('태초에'));
    });
  });
}
