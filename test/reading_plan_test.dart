import 'dart:io';

import 'package:churchpraise/services/bible_service.dart';
import 'package:churchpraise/services/highlight_service.dart';
import 'package:churchpraise/services/reading_plan_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('2027 성경읽기표', () {
    final plan = ReadingPlanService.instance;

    test('365일 동안 창세기 1장 ~ 요한계시록 22장 1,189장을 빠짐없이 순서대로 읽음', () {
      expect(ReadingPlanService.chapterCounts.length, 66);
      expect(ReadingPlanService.chapterCounts.reduce((a, b) => a + b), 1189);
      expect(plan.days.length, 365);

      final all = plan.days.expand((d) => d.chapters).toList();
      expect(all.length, 1189);
      expect(all.toSet().length, 1189); // 중복 없음
      expect(all.first, const ChapterRef(0, 1));
      expect(all.last, const ChapterRef(65, 22));

      // 하루 3~4장, 날짜는 2027-01-01 ~ 2027-12-31
      for (final d in plan.days) {
        expect(d.chapters.length, inInclusiveRange(3, 4));
      }
      expect(plan.days.first.date, DateTime(2027, 1, 1));
      expect(plan.days.last.date, DateTime(2027, 12, 31));
    });

    test('오늘 날짜에 맞는 날을 찾음', () {
      expect(plan.todayIndex(DateTime(2026, 12, 31)), isNull);
      expect(plan.todayIndex(DateTime(2027, 1, 1, 23, 59)), 0);
      expect(plan.todayIndex(DateTime(2027, 3, 1)), 59);
      expect(plan.todayIndex(DateTime(2027, 12, 31)), 364);
      expect(plan.todayIndex(DateTime(2028, 5, 1)), 364);
    });

    test('분량 표기', () {
      final names = BibleService.shortNames;
      expect(ReadingPlanService.rangeLabel(plan.days.first, names), '창 1장~3장');
      // 책이 바뀌는 날은 "창 50장 ~ 출 2장"처럼 표시
      final crossing = plan.days.firstWhere(
          (d) => d.chapters.first.bookIdx != d.chapters.last.bookIdx);
      expect(ReadingPlanService.rangeLabel(crossing, names),
          matches(RegExp(r'^\S+ \d+장 ~ \S+ \d+장$')));
      expect(ReadingPlanService.rangeLabel(plan.days.last, names),
          matches(RegExp(r'^계 \d+장~22장$')));
    });

    test('읽음 체크가 저장되고 다시 불러와짐', () async {
      await plan.init();
      await plan.setDone(0, true);
      await plan.setDone(5, true);
      await plan.setDone(5, false);
      await plan.init();
      expect(plan.done.value, {0});
    });

    test('장 수가 실제 성경 데이터와 일치',
        skip: File('assets/bible/ko_rev.json').existsSync()
            ? false
            : '성경 데이터 없음', () async {
      await BibleService.instance.ensureLoaded();
      final books = BibleService.instance.books;
      for (var i = 0; i < 66; i++) {
        expect(books[i].chapterCount, ReadingPlanService.chapterCounts[i],
            reason: books[i].name);
      }
    });
  });

  group('여러 절 선택', () {
    test('절 범위 표기', () {
      expect(formatVerseRanges([3]), '3');
      expect(formatVerseRanges([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]), '1~10');
      expect(formatVerseRanges([8, 7, 5, 3, 2, 1]), '1~3, 5, 7~8');
    });

    test('형광펜 색 저장·지우기', () async {
      final hl = HighlightService.instance;
      await hl.init();
      await hl.setColor(42, 3, [16, 17, 18], 2);
      await hl.clear(42, 3, [17]);
      await hl.init(); // 저장된 값 다시 불러오기
      expect(hl.colorOf(42, 3, 16), 2);
      expect(hl.colorOf(42, 3, 17), isNull);
      expect(hl.colorOf(42, 3, 18), 2);
    });
  });
}
