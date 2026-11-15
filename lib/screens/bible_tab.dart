import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/bible_service.dart';
import '../services/highlight_service.dart';
import '../services/reading_plan_service.dart';
import 'reading_plan_screen.dart';

/// 구약 파란색, 신약 빨간색 (권 선택 박스·배지 공통)
const Color kOldTestamentColor = Color(0xFF2F6FD6);
const Color kNewTestamentColor = Color(0xFFD64545);

class BibleTab extends StatefulWidget {
  final String searchQuery;
  const BibleTab({super.key, required this.searchQuery});

  @override
  State<BibleTab> createState() => _BibleTabState();
}

class _BibleTabState extends State<BibleTab> {
  int _bookIdx = 0; // 기본값: 창세기 (0)
  int _chapter = 1; // 기본값: 1장
  int? _highlightedVerse;
  double _fontSize = 18.0;
  bool _switchingVersion = false;
  final ItemScrollController _itemScroll = ItemScrollController();

  /// 여러 절 선택 (복사·형광펜용)
  final Set<int> _selected = {};
  int? _anchorVerse;

  static const _prefBookKey = 'bible_last_book_idx';
  static const _prefChapKey = 'bible_last_chapter';
  static const _prefFontKey = 'bible_font_size';

  @override
  void initState() {
    super.initState();
    _initBible();
    HighlightService.instance.ensureLoaded();
    ReadingPlanService.instance.ensureLoaded();
  }

  Future<void> _initBible() async {
    final prefs = await SharedPreferences.getInstance();
    final savedBook = prefs.getInt(_prefBookKey) ?? 0;
    final savedChap = prefs.getInt(_prefChapKey) ?? 1;
    final savedFont = prefs.getDouble(_prefFontKey) ?? 18.0;
    if (mounted) {
      setState(() {
        _bookIdx = savedBook.clamp(0, 65);
        _chapter = savedChap;
        _fontSize = savedFont.clamp(13.0, 32.0);
      });
    }
    await BibleService.instance.ensureLoaded();
    if (mounted) setState(() {});
  }

  Future<void> _savePosition() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefBookKey, _bookIdx);
    await prefs.setInt(_prefChapKey, _chapter);
  }

  Future<void> _changeFontSize(double delta) async {
    final next = (_fontSize + delta).clamp(13.0, 32.0);
    setState(() => _fontSize = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefFontKey, next);
  }

  void _selectBookAndChapter(int bookIndex, int chapter, {int? targetVerse}) {
    setState(() {
      _bookIdx = bookIndex;
      _chapter = chapter;
      _highlightedVerse = targetVerse;
      _selected.clear();
      _anchorVerse = null;
    });
    _savePosition();
    // 새 장을 그린 뒤 선택한 절(없으면 1절)로 이동
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_itemScroll.isAttached) return;
      final index = (targetVerse ?? 1) - 1;
      _itemScroll.jumpTo(index: index < 0 ? 0 : index);
    });
  }

  // ── 여러 절 선택 ─────────────────────────────
  void _toggleVerse(int verse) {
    setState(() {
      if (_selected.contains(verse)) {
        _selected.remove(verse);
        if (_anchorVerse == verse) _anchorVerse = null;
      } else {
        _selected.add(verse);
        _anchorVerse = verse;
      }
      _highlightedVerse = null;
    });
  }

  /// 길게 누르면 마지막으로 누른 절부터 이 절까지 한 번에 선택
  void _selectRangeTo(int verse) {
    setState(() {
      final from = _anchorVerse;
      if (from == null) {
        _selected.add(verse);
      } else {
        final a = from < verse ? from : verse;
        final b = from < verse ? verse : from;
        for (var v = a; v <= b; v++) {
          _selected.add(v);
        }
      }
      _anchorVerse = verse;
      _highlightedVerse = null;
    });
    HapticFeedback.selectionClick();
  }

  void _clearSelection() {
    setState(() {
      _selected.clear();
      _anchorVerse = null;
    });
  }

  void _copySelected(BibleBook book, int chapter, String versionLabel) {
    if (_selected.isEmpty) return;
    final sorted = _selected.toList()..sort();
    final verses = book.getChapterVerses(chapter);
    final lines = <String>[
      '${book.name} $chapter:${formatVerseRanges(sorted)} ($versionLabel)',
      for (final v in sorted)
        if (v >= 1 && v <= verses.length)
          '$v ${BibleBook.parseVerseText(verses[v - 1]).body}',
    ];
    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '${book.name} $chapter장 ${formatVerseRanges(sorted)}절을 복사했습니다'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
    _clearSelection();
  }

  Future<void> _highlightSelected(int chapter, int? colorIdx) async {
    if (_selected.isEmpty) return;
    final verses = _selected.toList();
    if (colorIdx == null) {
      await HighlightService.instance.clear(_bookIdx, chapter, verses);
    } else {
      await HighlightService.instance
          .setColor(_bookIdx, chapter, verses, colorIdx);
    }
    _clearSelection();
  }

  Future<void> _openReadingPlan() async {
    final picked = await Navigator.of(context).push<ChapterRef>(
      MaterialPageRoute(builder: (_) => const ReadingPlanScreen()),
    );
    if (picked != null) {
      _selectBookAndChapter(picked.bookIdx, picked.chapter);
    }
  }

  void _prevChapter() {
    final books = BibleService.instance.books;
    if (books.isEmpty) return;
    if (_chapter > 1) {
      _selectBookAndChapter(_bookIdx, _chapter - 1);
    } else if (_bookIdx > 0) {
      final prevBook = books[_bookIdx - 1];
      _selectBookAndChapter(_bookIdx - 1, prevBook.chapterCount);
    }
  }

  void _nextChapter() {
    final books = BibleService.instance.books;
    if (books.isEmpty) return;
    final curBook = books[_bookIdx];
    if (_chapter < curBook.chapterCount) {
      _selectBookAndChapter(_bookIdx, _chapter + 1);
    } else if (_bookIdx < books.length - 1) {
      _selectBookAndChapter(_bookIdx + 1, 1);
    }
  }

  Future<void> _openVersionPicker() async {
    final service = BibleService.instance;
    final current = service.version.value;
    final picked = await showModalBottomSheet<BibleVersion>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '성경 역본',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            for (final v in BibleVersion.values)
              ListTile(
                title: Text(v.label),
                subtitle: Text(_versionDescription(v)),
                trailing: v == current
                    ? Icon(Icons.check,
                        color: Theme.of(ctx).colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, v),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || picked == current) return;

    setState(() => _switchingVersion = true);
    try {
      await service.setVersion(picked);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${picked.label} 성경 데이터를 불러올 수 없습니다'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _switchingVersion = false);
    }
  }

  static String _versionDescription(BibleVersion v) {
    switch (v) {
      case BibleVersion.krvRevised:
        return '기본 역본';
      case BibleVersion.krv:
        return '1961년판';
      case BibleVersion.kjv:
        return 'King James Version (영어)';
    }
  }

  Future<void> _openBookChapterPicker() async {
    final books = BibleService.instance.books;
    if (books.isEmpty) return;

    final picked = await showModalBottomSheet<(int, int, int?)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BiblePickerSheet(
        initialBookIdx: _bookIdx,
        initialChapter: _chapter,
      ),
    );
    if (picked != null) {
      _selectBookAndChapter(picked.$1, picked.$2, targetVerse: picked.$3);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final service = BibleService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([
        service.loaded,
        service.version,
        HighlightService.instance.highlights,
        ReadingPlanService.instance.done,
      ]),
      builder: (context, _) {
        final versionLabel = service.version.value.label;
        if (!service.loaded.value) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text('$versionLabel 성경 데이터를 불러오는 중...'),
              ],
            ),
          );
        }

        final books = BibleService.instance.books;
        if (books.isEmpty) {
          return const Center(child: Text('성경 데이터를 불러올 수 없습니다'));
        }

        // 검색어가 입력된 경우 검색 결과 뷰 표시
        if (widget.searchQuery.trim().isNotEmpty) {
          return _buildSearchResults(context, widget.searchQuery);
        }

        final curBook = books[_bookIdx.clamp(0, books.length - 1)];
        final safeChapter = _chapter.clamp(1, curBook.chapterCount);
        final verses = curBook.getChapterVerses(safeChapter);

        final hasPrev = _bookIdx > 0 || safeChapter > 1;
        final hasNext =
            _bookIdx < books.length - 1 || safeChapter < curBook.chapterCount;

        return Column(
          children: [
            _buildReadingPlanBanner(cs),
            // 상단 성경 권/장 선택 & 이동 컨트롤 바
            Container(
              color: cs.surface,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  // 이전 장
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: '이전 장',
                    onPressed: hasPrev ? _prevChapter : null,
                    visualDensity: VisualDensity.compact,
                  ),
                  // 권 / 장 선택 버튼
                  Expanded(
                    child: InkWell(
                      onTap: _openBookChapterPicker,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: cs.primary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: curBook.isOldTestament
                                    ? kOldTestamentColor
                                    : kNewTestamentColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                curBook.isOldTestament ? '구약' : '신약',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '${curBook.name} $safeChapter장',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.arrow_drop_down,
                                size: 20, color: cs.primary),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 다음 장
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: '다음 장',
                    onPressed: hasNext ? _nextChapter : null,
                    visualDensity: VisualDensity.compact,
                  ),
                  // 역본 선택
                  InkWell(
                    onTap: _switchingVersion ? null : _openVersionPicker,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: cs.outline.withValues(alpha: 0.5)),
                      ),
                      child: _switchingVersion
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              versionLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.primary,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  // 글자 크기 조절
                  IconButton(
                    icon: const Icon(Icons.text_decrease, size: 19),
                    tooltip: '글자 작게',
                    onPressed:
                        _fontSize > 13 ? () => _changeFontSize(-2) : null,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.text_increase, size: 19),
                    tooltip: '글자 크게',
                    onPressed: _fontSize < 32 ? () => _changeFontSize(2) : null,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 절 목록
            Expanded(
              child: ScrollablePositionedList.builder(
                key: ValueKey('$_bookIdx:$safeChapter'),
                itemScrollController: _itemScroll,
                initialScrollIndex:
                    ((_highlightedVerse ?? 1) - 1).clamp(0, verses.length),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 36),
                itemCount: verses.length + 1,
                itemBuilder: (context, i) {
                  // 마지막 항목: 이전 장 / 다음 장 하단 네비게이션 버튼
                  if (i == verses.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 20, bottom: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: hasPrev ? _prevChapter : null,
                              icon: const Icon(Icons.chevron_left, size: 18),
                              label: const Text('이전 장'),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: hasNext ? _nextChapter : null,
                              icon: const Icon(Icons.chevron_right, size: 18),
                              label: const Text('다음 장'),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final verseNum = i + 1;
                  final parsed = BibleBook.parseVerseText(verses[i]);
                  final isHighlighted = _highlightedVerse == verseNum;
                  final isSelected = _selected.contains(verseNum);
                  final markColor = HighlightService.instance
                      .colorOf(_bookIdx, safeChapter, verseNum);
                  final isDark =
                      Theme.of(context).brightness == Brightness.dark;
                  Color bg = Colors.transparent;
                  if (markColor != null) {
                    bg = HighlightService.colors[markColor]
                        .withValues(alpha: isDark ? 0.35 : 0.55);
                  } else if (isHighlighted) {
                    bg = cs.primaryContainer.withValues(alpha: 0.45);
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (parsed.subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(
                              top: 12, bottom: 6, left: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              parsed.subtitle!,
                              style: TextStyle(
                                fontSize: (_fontSize - 3).clamp(12.0, 22.0),
                                fontWeight: FontWeight.bold,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ),
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _toggleVerse(verseNum),
                        onLongPress: () => _selectRangeTo(verseNum),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.symmetric(vertical: 1),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? cs.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 34,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    '$verseNum',
                                    style: TextStyle(
                                      fontSize:
                                          (_fontSize - 3).clamp(11.0, 22.0),
                                      fontWeight: FontWeight.bold,
                                      color: cs.primary,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  parsed.body,
                                  style: TextStyle(
                                    fontSize: _fontSize,
                                    height: 1.6,
                                    color: cs.onSurface,
                                    fontWeight: isHighlighted || isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (_selected.isNotEmpty)
              _buildSelectionBar(cs, curBook, safeChapter, versionLabel),
          ],
        );
      },
    );
  }

  /// 여러 절을 골랐을 때 아래에 나타나는 복사·형광펜 막대
  Widget _buildSelectionBar(
      ColorScheme cs, BibleBook book, int chapter, String versionLabel) {
    final sorted = _selected.toList()..sort();
    return Material(
      elevation: 8,
      color: cs.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${book.shortName} $chapter:${formatVerseRanges(sorted)} 선택',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '절을 길게 누르면 범위로 선택돼요',
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        _copySelected(book, chapter, versionLabel),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('복사'),
                  ),
                  IconButton(
                    tooltip: '선택 취소',
                    icon: const Icon(Icons.close),
                    onPressed: _clearSelection,
                  ),
                ],
              ),
              Row(
                children: [
                  const Icon(Icons.border_color, size: 18),
                  const SizedBox(width: 8),
                  for (var c = 0; c < HighlightService.colors.length; c++)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: InkResponse(
                        onTap: () => _highlightSelected(chapter, c),
                        radius: 22,
                        child: Tooltip(
                          message: '${HighlightService.colorNames[c]} 형광펜',
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: HighlightService.colors[c],
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: cs.outline.withValues(alpha: 0.4)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  TextButton.icon(
                    onPressed: () => _highlightSelected(chapter, null),
                    icon: const Icon(Icons.format_color_reset, size: 18),
                    label: const Text('지우기'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 성경 탭 맨 위의 2027 성경읽기표 안내 줄
  Widget _buildReadingPlanBanner(ColorScheme cs) {
    final plan = ReadingPlanService.instance;
    final today = plan.todayIndex();
    final doneCount = plan.done.value.length;
    String text;
    bool todayDone = false;
    if (today == null) {
      text = '2027 성경읽기표 · 1월 1일 시작 (하루 3~4장)';
    } else {
      final day = plan.days[today];
      todayDone = plan.done.value.contains(today);
      text =
          '오늘 읽기 ${ReadingPlanService.rangeLabel(day, BibleService.shortNames)} · $doneCount/${ReadingPlanService.totalDays}';
    }
    return Material(
      color: cs.secondaryContainer.withValues(alpha: 0.6),
      child: InkWell(
        onTap: _openReadingPlan,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            children: [
              Icon(Icons.event_note, size: 18, color: cs.onSecondaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSecondaryContainer,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (todayDone)
                Icon(Icons.check_circle, size: 18, color: cs.primary),
              Icon(Icons.chevron_right,
                  size: 18, color: cs.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context, String query) {
    final cs = Theme.of(context).colorScheme;
    final results = BibleService.instance.search(query);

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              '"$query"에 대한 성경 검색 결과가 없습니다\n예: "요 3:16", "시편 23", "사랑"',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, height: 1.6),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: cs.surfaceContainerLow,
          child: Text(
            '검색 결과 ${results.length}${results.length >= 200 ? '+' : ''}건 (터치하면 해당 장으로 이동)',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: results.length,
            itemBuilder: (context, i) {
              final r = results[i];
              final parsed = BibleBook.parseVerseText(r.text);
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 3),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: cs.outlineVariant),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    // 해당 권/장으로 이동 후 검색창 닫기는 부모에서 처리하거나 바로 선택
                    _selectBookAndChapter(
                      r.book.index,
                      r.chapter,
                      targetVerse: r.verse,
                    );
                    // 모달로 해당 장 전체 보기 지원
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _BibleChapterDetailScreen(
                          book: r.book,
                          chapter: r.chapter,
                          highlightVerse: r.verse,
                          fontSize: _fontSize,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                r.reference,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onPrimaryContainer,
                                ),
                              ),
                            ),
                            if (parsed.subtitle != null) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  parsed.subtitle!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          parsed.body,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── 성경 권 / 장 선택 바텀 시트 ─────────────────────
class _BiblePickerSheet extends StatefulWidget {
  final int initialBookIdx;
  final int initialChapter;

  const _BiblePickerSheet({
    required this.initialBookIdx,
    required this.initialChapter,
  });

  @override
  State<_BiblePickerSheet> createState() => _BiblePickerSheetState();
}

class _BiblePickerSheetState extends State<_BiblePickerSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  late int _selectedBookIdx;
  int? _selectedChapter;

  /// 0: 권 선택, 1: 장 선택, 2: 절 선택
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _selectedBookIdx = widget.initialBookIdx;
    final isNew = _selectedBookIdx >= 39;
    _tabCtrl = TabController(
      length: 2,
      vsync: this,
      initialIndex: isNew ? 1 : 0,
    );
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _pickBook(BibleBook b) {
    setState(() {
      _selectedBookIdx = b.index;
      if (b.chapterCount == 1) {
        // 한 장짜리 책(옵·몬·요이·요삼·유)은 바로 절 선택
        _selectedChapter = 1;
        _step = 2;
      } else {
        _step = 1;
      }
    });
  }

  void _pickChapter(int chap) {
    setState(() {
      _selectedChapter = chap;
      _step = 2;
    });
  }

  void _back() {
    setState(() {
      final book = BibleService.instance.books[_selectedBookIdx];
      _step = (_step == 2 && book.chapterCount > 1) ? 1 : 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final books = BibleService.instance.books;
    final selectedBook = books[_selectedBookIdx];

    String title;
    if (_step == 0) {
      title = '성경 선택';
    } else if (_step == 1) {
      title = '${selectedBook.name} · 장 선택';
    } else {
      title = '${selectedBook.name} $_selectedChapter장 · 절 선택';
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                if (_step > 0)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: '뒤로',
                    onPressed: _back,
                  ),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_step == 2)
                  TextButton(
                    onPressed: () => Navigator.pop(
                        context, (_selectedBookIdx, _selectedChapter!, null)),
                    child: const Text('장 처음부터'),
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          if (_step == 0) ...[
            TabBar(
              controller: _tabCtrl,
              tabs: const [
                Tab(text: '구약 (39권)'),
                Tab(text: '신약 (27권)'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildBookGrid(BibleService.instance.oldTestament),
                  _buildBookGrid(BibleService.instance.newTestament),
                ],
              ),
            ),
          ] else if (_step == 1) ...[
            const Divider(height: 1),
            Expanded(
              child: _buildNumberGrid(
                count: selectedBook.chapterCount,
                suffix: '장',
                isCurrent: (n) =>
                    _selectedBookIdx == widget.initialBookIdx &&
                    n == widget.initialChapter,
                onTap: _pickChapter,
              ),
            ),
          ] else ...[
            const Divider(height: 1),
            Expanded(
              child: _buildNumberGrid(
                count: selectedBook
                    .getChapterVerses(_selectedChapter ?? 1)
                    .length,
                suffix: '절',
                isCurrent: (_) => false,
                onTap: (v) => Navigator.pop(
                    context, (_selectedBookIdx, _selectedChapter!, v)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNumberGrid({
    required int count,
    required String suffix,
    required bool Function(int) isCurrent,
    required void Function(int) onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.25,
      ),
      itemCount: count,
      itemBuilder: (context, i) {
        final n = i + 1;
        final current = isCurrent(n);
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onTap(n),
          child: Container(
            decoration: BoxDecoration(
              color: current ? cs.primary : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              '$n$suffix',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: current ? cs.onPrimary : cs.onSurface,
              ),
            ),
          ),
        );
      },
    );
  }

  /// 권 선택: 구약은 파란색, 신약은 빨간색 네모 박스에 약어(창, 마, 요 …)를 크게 표시
  Widget _buildBookGrid(List<BibleBook> bookList) {
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.9,
      ),
      itemCount: bookList.length,
      itemBuilder: (context, i) {
        final b = bookList[i];
        final isSelected = b.index == _selectedBookIdx;
        final color =
            b.isOldTestament ? kOldTestamentColor : kNewTestamentColor;
        return Semantics(
          button: true,
          label: '${b.name} ${b.chapterCount}장',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _pickBook(b),
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? Colors.amber : Colors.transparent,
                  width: 3,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      b.shortName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      b.name,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── 검색 결과에서 특정 장 전체 보기 화면 ─────────────────
class _BibleChapterDetailScreen extends StatelessWidget {
  final BibleBook book;
  final int chapter;
  final int highlightVerse;
  final double fontSize;

  const _BibleChapterDetailScreen({
    required this.book,
    required this.chapter,
    required this.highlightVerse,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final verses = book.getChapterVerses(chapter);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${book.name} $chapter장',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 36),
        itemCount: verses.length,
        itemBuilder: (context, i) {
          final verseNum = i + 1;
          final parsed = BibleBook.parseVerseText(verses[i]);
          final isHighlighted = verseNum == highlightVerse;

          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isHighlighted
                  ? cs.primaryContainer.withValues(alpha: 0.55)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 34,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '$verseNum',
                      style: TextStyle(
                        fontSize: (fontSize - 3).clamp(11.0, 22.0),
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    parsed.body,
                    style: TextStyle(
                      fontSize: fontSize,
                      height: 1.6,
                      fontWeight:
                          isHighlighted ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
