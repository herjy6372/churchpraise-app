import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/bible_service.dart';

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
  final ScrollController _scrollCtrl = ScrollController();

  static const _prefBookKey = 'bible_last_book_idx';
  static const _prefChapKey = 'bible_last_chapter';
  static const _prefFontKey = 'bible_font_size';

  @override
  void initState() {
    super.initState();
    _initBible();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
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
    });
    _savePosition();
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.jumpTo(0);
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

    final picked = await showModalBottomSheet<(int, int)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BiblePickerSheet(
        initialBookIdx: _bookIdx,
        initialChapter: _chapter,
      ),
    );
    if (picked != null) {
      _selectBookAndChapter(picked.$1, picked.$2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final service = BibleService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([service.loaded, service.version]),
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
                                    ? cs.secondaryContainer
                                    : cs.tertiaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                curBook.isOldTestament ? '구약' : '신약',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: curBook.isOldTestament
                                      ? cs.onSecondaryContainer
                                      : cs.onTertiaryContainer,
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
              child: ListView.builder(
                controller: _scrollCtrl,
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
                        onTap: () {
                          setState(() {
                            _highlightedVerse =
                                isHighlighted ? null : verseNum;
                          });
                        },
                        onLongPress: () {
                          final copyText =
                              '${curBook.name} $safeChapter:$verseNum ${parsed.body} ($versionLabel)';
                          Clipboard.setData(ClipboardData(text: copyText));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  '${curBook.name} $safeChapter장 $verseNum절 말씀이 복사되었습니다'),
                              duration: const Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: isHighlighted
                                ? cs.primaryContainer.withValues(alpha: 0.45)
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
                                    fontWeight: isHighlighted
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
          ],
        );
      },
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
  bool _pickingChapter = false;

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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final books = BibleService.instance.books;
    final selectedBook = books[_selectedBookIdx];

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
                if (_pickingChapter)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => setState(() => _pickingChapter = false),
                  ),
                Expanded(
                  child: Text(
                    _pickingChapter
                        ? '${selectedBook.name} - 장 선택 (${selectedBook.chapterCount}장)'
                        : '성경 선택',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          if (!_pickingChapter) ...[
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
          ] else ...[
            const Divider(height: 1),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.25,
                ),
                itemCount: selectedBook.chapterCount,
                itemBuilder: (context, i) {
                  final chap = i + 1;
                  final isCurrent = _selectedBookIdx == widget.initialBookIdx &&
                      chap == widget.initialChapter;
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () =>
                        Navigator.pop(context, (_selectedBookIdx, chap)),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? cs.primary
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$chap장',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isCurrent ? cs.onPrimary : cs.onSurface,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBookGrid(List<BibleBook> bookList) {
    final cs = Theme.of(context).colorScheme;
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.3,
      ),
      itemCount: bookList.length,
      itemBuilder: (context, i) {
        final b = bookList[i];
        final isSelected = b.index == _selectedBookIdx;
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (b.chapterCount == 1) {
              Navigator.pop(context, (b.index, 1));
            } else {
              setState(() {
                _selectedBookIdx = b.index;
                _pickingChapter = true;
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? cs.primaryContainer
                  : cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? cs.primary : Colors.transparent,
                width: 1.5,
              ),
            ),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    b.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected
                          ? cs.onPrimaryContainer
                          : cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${b.chapterCount}',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
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
