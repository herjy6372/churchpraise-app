import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ParsedVerseText {
  final String? subtitle;
  final String body;
  const ParsedVerseText({this.subtitle, required this.body});
}

class BibleBook {
  final int index; // 0~65
  final String name;
  final String shortName;
  final List<List<String>> chapters;

  const BibleBook({
    required this.index,
    required this.name,
    required this.shortName,
    required this.chapters,
  });

  bool get isOldTestament => index < 39;

  int get chapterCount => chapters.length;

  List<String> getChapterVerses(int chapterNumber) {
    if (chapterNumber < 1 || chapterNumber > chapters.length) return const [];
    return chapters[chapterNumber - 1];
  }

  static final _subtitlePattern = RegExp(r'^<([^>]+)>\s*(.*)$');

  static ParsedVerseText parseVerseText(String raw) {
    final m = _subtitlePattern.firstMatch(raw);
    if (m != null) {
      return ParsedVerseText(
        subtitle: m.group(1)?.trim(),
        body: m.group(2)?.trim() ?? '',
      );
    }
    return ParsedVerseText(body: raw.trim());
  }
}

class BibleSearchResult {
  final BibleBook book;
  final int chapter; // 1-based
  final int verse; // 1-based
  final String text;

  const BibleSearchResult({
    required this.book,
    required this.chapter,
    required this.verse,
    required this.text,
  });

  String get reference => '${book.name} $chapter:$verse';
  String get shortReference => '${book.shortName} $chapter:$verse';
}

class BibleService {
  static final instance = BibleService._();
  BibleService._();

  static const List<String> _shortNames = [
    // 구약 39권
    '창', '출', '레', '민', '신', '수', '삿', '룻', '삼상', '삼하',
    '왕상', '왕하', '대상', '대하', '스', '느', '에', '욥', '시', '잠',
    '전', '아', '사', '렘', '애', '겔', '단', '호', '욜', '암',
    '옵', '욘', '미', '나', '합', '습', '학', '슥', '말',
    // 신약 27권
    '마', '막', '눅', '요', '행', '롬', '고전', '고후', '갈', '엡',
    '빌', '골', '살전', '살후', '딤전', '딤후', '딛', '몬', '히', '약',
    '벧전', '벧후', '요일', '요이', '요삼', '유', '계',
  ];

  final loaded = ValueNotifier<bool>(false);
  List<BibleBook> _books = [];

  List<BibleBook> get books => _books;
  List<BibleBook> get oldTestament =>
      _books.where((b) => b.isOldTestament).toList();
  List<BibleBook> get newTestament =>
      _books.where((b) => !b.isOldTestament).toList();

  Future<void> ensureLoaded() async {
    if (loaded.value && _books.isNotEmpty) return;
    final raw = await rootBundle.loadString('assets/bible/ko_rev.json');
    final decoded = await compute(_parseBibleJson, raw);
    _books = decoded;
    loaded.value = true;
  }

  static List<BibleBook> _parseBibleJson(String raw) {
    final list = jsonDecode(raw) as List;
    final result = <BibleBook>[];
    for (var i = 0; i < list.length; i++) {
      final item = list[i] as Map<String, dynamic>;
      final name = item['name'] as String;
      final shortName = i < _shortNames.length ? _shortNames[i] : name;
      final chaptersRaw = item['chapters'] as List;
      final chapters = chaptersRaw
          .map((c) => (c as List).map((v) => (v as String?) ?? '').toList())
          .toList();
      result.add(
        BibleBook(
          index: i,
          name: name,
          shortName: shortName,
          chapters: chapters,
        ),
      );
    }
    return result;
  }

  // 예: "창 1:1", "요한복음 3:16", "시편 23", "사랑" 등 검색
  List<BibleSearchResult> search(String query, {int maxResults = 200}) {
    final q = query.trim();
    if (q.isEmpty || _books.isEmpty) return const [];

    // 1. 장:절 참조 패턴 검색 (예: "요 3:16", "요한복음 3장 16절", "창세기 1장")
    final refPattern = RegExp(
      r'^([가-힣0-9]+)\s*(\d+)(?:장|\s*:\s*|\s+)?(\d+)?(?:절)?$',
    );
    final refMatch = refPattern.firstMatch(q);
    if (refMatch != null) {
      final bookQuery = refMatch.group(1)!;
      final chapNum = int.tryParse(refMatch.group(2)!);
      final verseNum =
          refMatch.group(3) != null ? int.tryParse(refMatch.group(3)!) : null;

      final matchedBooks = _books.where((b) =>
          b.name == bookQuery ||
          b.shortName == bookQuery ||
          b.name.startsWith(bookQuery));

      if (matchedBooks.isNotEmpty && chapNum != null) {
        final results = <BibleSearchResult>[];
        for (final b in matchedBooks) {
          final verses = b.getChapterVerses(chapNum);
          if (verses.isEmpty) continue;
          if (verseNum != null) {
            if (verseNum >= 1 && verseNum <= verses.length) {
              results.add(
                BibleSearchResult(
                  book: b,
                  chapter: chapNum,
                  verse: verseNum,
                  text: verses[verseNum - 1],
                ),
              );
            }
          } else {
            for (var vIdx = 0; vIdx < verses.length; vIdx++) {
              results.add(
                BibleSearchResult(
                  book: b,
                  chapter: chapNum,
                  verse: vIdx + 1,
                  text: verses[vIdx],
                ),
              );
              if (results.length >= maxResults) return results;
            }
          }
        }
        if (results.isNotEmpty) return results;
      }
    }

    // 2. 본문 키워드 검색
    final results = <BibleSearchResult>[];
    final lowerQ = q.toLowerCase();
    for (final b in _books) {
      for (var cIdx = 0; cIdx < b.chapters.length; cIdx++) {
        final verses = b.chapters[cIdx];
        for (var vIdx = 0; vIdx < verses.length; vIdx++) {
          final vText = verses[vIdx];
          if (vText.toLowerCase().contains(lowerQ)) {
            results.add(
              BibleSearchResult(
                book: b,
                chapter: cIdx + 1,
                verse: vIdx + 1,
                text: vText,
              ),
            );
            if (results.length >= maxResults) return results;
          }
        }
      }
    }
    return results;
  }
}
