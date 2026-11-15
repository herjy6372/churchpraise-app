import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 앱에 내장된 성경 역본
enum BibleVersion {
  krvRevised('ko_rev', '개역개정', 'assets/bible/ko_rev.json'),
  krv('ko_krv', '개역한글', 'assets/bible/ko_krv.json'),
  kjv('en_kjv', 'KJV', 'assets/bible/en_kjv.json');

  final String id;
  final String label;
  final String assetPath;
  const BibleVersion(this.id, this.label, this.assetPath);

  static BibleVersion fromId(String? id) => BibleVersion.values.firstWhere(
        (v) => v.id == id,
        orElse: () => BibleVersion.krvRevised,
      );
}

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

  // 역본과 관계없이 화면에는 한글 책 이름을 사용
  static const List<String> _names = [
    '창세기', '출애굽기', '레위기', '민수기', '신명기', '여호수아', '사사기',
    '룻기', '사무엘상', '사무엘하', '열왕기상', '열왕기하', '역대상', '역대하',
    '에스라', '느헤미야', '에스더', '욥기', '시편', '잠언', '전도서', '아가',
    '이사야', '예레미야', '예레미야애가', '에스겔', '다니엘', '호세아', '요엘',
    '아모스', '오바댜', '요나', '미가', '나훔', '하박국', '스바냐', '학개',
    '스가랴', '말라기',
    '마태복음', '마가복음', '누가복음', '요한복음', '사도행전', '로마서',
    '고린도전서', '고린도후서', '갈라디아서', '에베소서', '빌립보서', '골로새서',
    '데살로니가전서', '데살로니가후서', '디모데전서', '디모데후서', '디도서',
    '빌레몬서', '히브리서', '야고보서', '베드로전서', '베드로후서', '요한1서',
    '요한2서', '요한3서', '유다서', '요한계시록',
  ];

  // KJV 장절 검색용 영어 책 이름 (66권 순서)
  static const List<String> _englishNames = [
    'Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy', 'Joshua',
    'Judges', 'Ruth', '1 Samuel', '2 Samuel', '1 Kings', '2 Kings',
    '1 Chronicles', '2 Chronicles', 'Ezra', 'Nehemiah', 'Esther', 'Job',
    'Psalms', 'Proverbs', 'Ecclesiastes', 'Song of Solomon', 'Isaiah',
    'Jeremiah', 'Lamentations', 'Ezekiel', 'Daniel', 'Hosea', 'Joel', 'Amos',
    'Obadiah', 'Jonah', 'Micah', 'Nahum', 'Habakkuk', 'Zephaniah', 'Haggai',
    'Zechariah', 'Malachi',
    'Matthew', 'Mark', 'Luke', 'John', 'Acts', 'Romans', '1 Corinthians',
    '2 Corinthians', 'Galatians', 'Ephesians', 'Philippians', 'Colossians',
    '1 Thessalonians', '2 Thessalonians', '1 Timothy', '2 Timothy', 'Titus',
    'Philemon', 'Hebrews', 'James', '1 Peter', '2 Peter', '1 John', '2 John',
    '3 John', 'Jude', 'Revelation',
  ];

  // KJV 장절 검색용 영어 약어 (공백·마침표 제거, 소문자)
  static const List<List<String>> _englishAbbrevs = [
    ['gen', 'gn'], ['ex', 'exod'], ['lev', 'lv'], ['num', 'nm'],
    ['deut', 'dt'], ['josh', 'jos'], ['judg', 'jdg'], ['ru', 'rth'],
    ['1sam', '1sa', '1sm'], ['2sam', '2sa', '2sm'], ['1kgs', '1ki', '1kg'],
    ['2kgs', '2ki', '2kg'], ['1chr', '1ch'], ['2chr', '2ch'], ['ezr'],
    ['neh'], ['esth', 'est'], ['jb'], ['ps', 'psa', 'psalm', 'pss'],
    ['prov', 'pr', 'prv'], ['eccl', 'ecc', 'qoh'], ['song', 'sos', 'ss'],
    ['isa', 'is'], ['jer'], ['lam'], ['ezek', 'eze'], ['dan', 'dn'],
    ['hos'], ['jl'], ['am'], ['obad', 'ob'], ['jon'], ['mic'], ['nah'],
    ['hab'], ['zeph', 'zep'], ['hag'], ['zech', 'zec'], ['mal'],
    ['matt', 'mt'], ['mk', 'mrk'], ['lk', 'luk'], ['jn', 'jhn'], ['ac'],
    ['rom', 'rm'], ['1cor', '1co'], ['2cor', '2co'], ['gal'], ['eph'],
    ['phil', 'php'], ['col'], ['1thess', '1th'], ['2thess', '2th'],
    ['1tim', '1ti'], ['2tim', '2ti'], ['tit'], ['phlm', 'phm'], ['heb'],
    ['jas', 'jm'], ['1pet', '1pe', '1pt'], ['2pet', '2pe', '2pt'],
    ['1jn', '1jo'], ['2jn', '2jo'], ['3jn', '3jo'], ['jud', 'jd'],
    ['rev', 're', 'rv'],
  ];

  static const _prefVersionKey = 'bible_version';

  final loaded = ValueNotifier<bool>(false);
  final version = ValueNotifier<BibleVersion>(BibleVersion.krvRevised);
  List<BibleBook> _books = [];
  Future<void>? _loading;

  List<BibleBook> get books => _books;
  List<BibleBook> get oldTestament =>
      _books.where((b) => b.isOldTestament).toList();
  List<BibleBook> get newTestament =>
      _books.where((b) => !b.isOldTestament).toList();

  /// 마지막으로 선택한 역본(기본: 개역개정)을 불러옵니다.
  Future<void> ensureLoaded() {
    if (loaded.value && _books.isNotEmpty) return Future.value();
    return _loading ??= () async {
      final prefs = await SharedPreferences.getInstance();
      final saved = BibleVersion.fromId(prefs.getString(_prefVersionKey));
      try {
        await _load(saved);
      } catch (_) {
        // 선택한 역본 파일이 없으면 기본 역본으로 되돌림
        if (saved == BibleVersion.krvRevised) rethrow;
        await _load(BibleVersion.krvRevised);
      }
    }()
        .whenComplete(() => _loading = null);
  }

  /// 역본을 바꾸고 선택을 저장합니다.
  Future<void> setVersion(BibleVersion next) async {
    if (next == version.value && _books.isNotEmpty) return;
    await _load(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefVersionKey, next.id);
  }

  Future<void> _load(BibleVersion v) async {
    final raw = await rootBundle.loadString(v.assetPath);
    final decoded = await compute(_parseBibleJson, raw);
    _books = decoded;
    version.value = v;
    loaded.value = true;
  }

  static List<BibleBook> _parseBibleJson(String raw) {
    final list = jsonDecode(raw) as List;
    final result = <BibleBook>[];
    for (var i = 0; i < list.length; i++) {
      final item = list[i] as Map<String, dynamic>;
      final name = i < _names.length ? _names[i] : item['name'] as String;
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

  static String _normalizeBookToken(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\s.]'), '');

  /// 장절 검색어의 책 이름과 일치하는 책을 찾습니다.
  /// 한글 이름(창, 창세기 등)은 모든 역본에서, 영어 이름(John, Jn 등)은
  /// KJV를 선택했을 때만 인식합니다. 결과는 항상 현재 역본의 책입니다.
  List<BibleBook> _matchBooks(String bookQuery) {
    final ko = bookQuery.replaceAll(' ', '');
    if (RegExp(r'[가-힣]').hasMatch(ko)) {
      // "요"처럼 약어와 정확히 같으면 그 책만, 아니면 이름 앞부분이 같은 책
      final exact =
          _books.where((b) => b.name == ko || b.shortName == ko).toList();
      if (exact.isNotEmpty) return exact;
      return _books.where((b) => b.name.startsWith(ko)).toList();
    }
    if (version.value != BibleVersion.kjv) return const [];

    final token = _normalizeBookToken(bookQuery);
    if (!RegExp(r'[a-z]').hasMatch(token)) return const [];
    final exact = <BibleBook>[];
    final prefix = <BibleBook>[];
    for (final b in _books) {
      final i = b.index;
      if (i >= _englishNames.length) continue;
      final full = _normalizeBookToken(_englishNames[i]);
      if (full == token || _englishAbbrevs[i].contains(token)) {
        exact.add(b);
      } else if (token.length >= 2 && full.startsWith(token)) {
        prefix.add(b);
      }
    }
    return exact.isNotEmpty ? exact : prefix;
  }

  /// 현재 선택된 역본 안에서만 장절·본문을 검색합니다.
  /// 예: "창 1:1", "요한복음 3:16", "시편 23", "사랑" / KJV: "John 3:16", "love"
  List<BibleSearchResult> search(String query, {int maxResults = 200}) {
    final q = query.trim();
    if (q.isEmpty || _books.isEmpty) return const [];

    // 1. 장:절 참조 패턴 검색 (예: "요 3:16", "요한복음 3장 16절", "1 John 4:8")
    final refPattern = RegExp(
      r'^((?:[1-3]\s*)?[가-힣A-Za-z][가-힣A-Za-z0-9\s.]*?)\s*(\d+)\s*(?:장)?'
      r'(?:\s*[:.]\s*|\s+)?(\d+)?\s*(?:절)?$',
    );
    final refMatch = refPattern.firstMatch(q);
    if (refMatch != null) {
      final bookQuery = refMatch.group(1)!.trim();
      final chapNum = int.tryParse(refMatch.group(2)!);
      final verseNum =
          refMatch.group(3) != null ? int.tryParse(refMatch.group(3)!) : null;

      final matchedBooks = _matchBooks(bookQuery);

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
