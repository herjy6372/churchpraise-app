import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 성경 구절 형광펜 (권·장·절 위치 기준이라 역본을 바꿔도 같은 자리에 표시됨)
class HighlightService {
  static final instance = HighlightService._();
  HighlightService._();

  static const prefKey = 'bible_highlights_v1';

  static const List<Color> colors = [
    Color(0xFFFFE066), // 노랑
    Color(0xFF9BE09B), // 초록
    Color(0xFF8EC5FF), // 파랑
    Color(0xFFFFA8C5), // 분홍
  ];
  static const List<String> colorNames = ['노랑', '초록', '파랑', '분홍'];

  /// key: "권:장:절" (권은 0부터), value: 색 번호
  final highlights = ValueNotifier<Map<String, int>>({});
  bool _loaded = false;

  static String keyOf(int bookIdx, int chapter, int verse) =>
      '$bookIdx:$chapter:$verse';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefKey);
    final map = <String, int>{};
    if (raw != null) {
      try {
        (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) {
          if (v is int && v >= 0 && v < colors.length) map[k] = v;
        });
      } catch (_) {
        // 손상된 데이터는 무시
      }
    }
    highlights.value = map;
    _loaded = true;
  }

  Future<void> ensureLoaded() async {
    if (!_loaded) await init();
  }

  int? colorOf(int bookIdx, int chapter, int verse) =>
      highlights.value[keyOf(bookIdx, chapter, verse)];

  Future<void> setColor(
      int bookIdx, int chapter, Iterable<int> verses, int colorIdx) async {
    final next = Map<String, int>.from(highlights.value);
    for (final v in verses) {
      next[keyOf(bookIdx, chapter, v)] = colorIdx;
    }
    await _save(next);
  }

  Future<void> clear(int bookIdx, int chapter, Iterable<int> verses) async {
    final next = Map<String, int>.from(highlights.value);
    for (final v in verses) {
      next.remove(keyOf(bookIdx, chapter, v));
    }
    await _save(next);
  }

  Future<void> _save(Map<String, int> next) async {
    highlights.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, jsonEncode(next));
  }
}
