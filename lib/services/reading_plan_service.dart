import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 성경 한 장의 위치 (권은 0부터)
class ChapterRef {
  final int bookIdx;
  final int chapter;
  const ChapterRef(this.bookIdx, this.chapter);

  @override
  bool operator ==(Object other) =>
      other is ChapterRef && other.bookIdx == bookIdx && other.chapter == chapter;

  @override
  int get hashCode => Object.hash(bookIdx, chapter);
}

/// 읽기표의 하루 분량
class ReadingDay {
  final int index; // 0~364
  final DateTime date;
  final List<ChapterRef> chapters;
  const ReadingDay(this.index, this.date, this.chapters);
}

/// 2027년 성경읽기표: 창세기 1장부터 요한계시록 22장까지 1,189장을
/// 2027년 1월 1일 ~ 12월 31일(365일)에 고르게 나눔 (하루 3~4장)
class ReadingPlanService {
  static final instance = ReadingPlanService._();
  ReadingPlanService._();

  static const int year = 2027;
  static const int totalDays = 365;
  static const prefKey = 'reading_plan_2027_done';

  /// 66권 장 수 (개역 성경 기준, 합계 1,189장)
  static const List<int> chapterCounts = [
    50, 40, 27, 36, 34, 24, 21, 4, 31, 24, 22, 25, 29, 36, 10, 13, 10, 42,
    150, 31, 12, 8, 66, 52, 5, 48, 12, 14, 3, 9, 1, 4, 7, 3, 3, 3, 2, 14, 4,
    28, 16, 24, 21, 28, 16, 16, 13, 6, 6, 4, 4, 5, 3, 6, 4, 3, 1, 13, 5, 5,
    3, 5, 1, 1, 1, 22,
  ];

  static final DateTime startDate = DateTime(year, 1, 1);

  late final List<ReadingDay> days = _buildDays();

  /// 읽음 체크한 날 (index)
  final done = ValueNotifier<Set<int>>({});
  bool _loaded = false;

  static List<ReadingDay> _buildDays() {
    final all = <ChapterRef>[];
    for (var b = 0; b < chapterCounts.length; b++) {
      for (var c = 1; c <= chapterCounts[b]; c++) {
        all.add(ChapterRef(b, c));
      }
    }
    final result = <ReadingDay>[];
    for (var d = 0; d < totalDays; d++) {
      final from = d * all.length ~/ totalDays;
      final to = (d + 1) * all.length ~/ totalDays;
      result.add(ReadingDay(
        d,
        DateTime(year, 1, 1 + d),
        all.sublist(from, to),
      ));
    }
    return result;
  }

  /// 오늘에 해당하는 날 (2027년 이전이면 null, 이후면 마지막 날)
  int? todayIndex([DateTime? now]) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final diff = today.difference(startDate).inDays;
    if (diff < 0) return null;
    return diff >= totalDays ? totalDays - 1 : diff;
  }

  bool get isBeforeStart => todayIndex() == null;

  /// 예: "창 1장~3장", "창 50장 ~ 출 2장", "옵 1장"
  static String rangeLabel(ReadingDay day, List<String> shortNames) {
    final first = day.chapters.first;
    final last = day.chapters.last;
    final a = shortNames[first.bookIdx];
    if (first.bookIdx == last.bookIdx) {
      return first.chapter == last.chapter
          ? '$a ${first.chapter}장'
          : '$a ${first.chapter}장~${last.chapter}장';
    }
    final b = shortNames[last.bookIdx];
    return '$a ${first.chapter}장 ~ $b ${last.chapter}장';
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefKey);
    final set = <int>{};
    if (raw != null) {
      try {
        for (final v in jsonDecode(raw) as List) {
          if (v is int && v >= 0 && v < totalDays) set.add(v);
        }
      } catch (_) {
        // 손상된 데이터는 무시
      }
    }
    done.value = set;
    _loaded = true;
  }

  Future<void> ensureLoaded() async {
    if (!_loaded) await init();
  }

  Future<void> setDone(int dayIndex, bool value) async {
    final next = Set<int>.from(done.value);
    value ? next.add(dayIndex) : next.remove(dayIndex);
    done.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, jsonEncode(next.toList()..sort()));
  }
}
