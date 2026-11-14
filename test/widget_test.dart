// 데이터 레이어 단위 테스트.
// 루트 위젯(ChurchPraiseApp)은 Firebase 초기화에 의존하므로,
// 외부 의존성이 없는 정적 데이터 로직을 검증한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:churchpraise/data/hymn_data.dart';
import 'package:churchpraise/data/responsive_reading_data.dart';
import 'package:churchpraise/services/bible_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BibleService', () {
    test('개역개정 66권 전체(구약 39권, 신약 27권)가 정상 로드된다', () async {
      await BibleService.instance.ensureLoaded();
      expect(BibleService.instance.books.length, 66);
      expect(BibleService.instance.oldTestament.length, 39);
      expect(BibleService.instance.newTestament.length, 27);
      expect(BibleService.instance.books.first.name, '창세기');
      expect(BibleService.instance.books.last.name, '요한계시록');
    });

    test('장:절 참조 및 키워드 검색이 동작한다', () async {
      await BibleService.instance.ensureLoaded();
      final refRes = BibleService.instance.search('창 1:1');
      expect(refRes, isNotEmpty);
      expect(refRes.first.text, contains('태초에 하나님이 천지를 창조하시니라'));

      final kwRes = BibleService.instance.search('여호와는 나의 목자시니');
      expect(kwRes, isNotEmpty);
      expect(kwRes.first.reference, '시편 23:1');
    });
  });

  group('ResponsiveReadingData', () {
    test('교독문은 1번부터 137번까지 모두 존재한다', () {
      expect(ResponsiveReadingData.readings.length, 137);
      expect(ResponsiveReadingData.readings.first.number, 1);
      expect(ResponsiveReadingData.readings.last.number, 137);
    });

    test('번호 및 제목으로 교독문을 검색할 수 있다', () {
      final result = ResponsiveReadingData.search('시편 23편');
      expect(result, isNotEmpty);
      expect(result.any((r) => r.number == 13), isTrue);
    });

    test('주기도문 개역개정 본문이 포함되어 있다', () {
      expect(ResponsiveReadingData.lordsPrayerLines, isNotEmpty);
      expect(
        ResponsiveReadingData.lordsPrayerLines.first,
        contains('하늘에 계신 우리 아버지여'),
      );
    });
  });

  group('HymnData', () {
    test('빈 검색어는 645곡 전체를 반환한다', () {
      expect(HymnData.search('').length, 645);
    });

    test('숫자 검색은 해당 장만 반환한다', () {
      expect(HymnData.search('25장'), [25]);
      expect(HymnData.search('25'), [25]);
    });

    test('assetPath는 3자리로 패딩된다', () {
      expect(HymnData.getAssetPath(1), 'assets/hymns_pdf/001.pdf');
      expect(HymnData.getAssetPath(645), 'assets/hymns_pdf/645.pdf');
    });
  });
}
