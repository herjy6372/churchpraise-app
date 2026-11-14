import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import '../models/song.dart';
import '../models/conti.dart';
import '../data/hymn_data.dart';
import '../data/responsive_reading_data.dart';
import '../services/app_settings.dart';
import '../services/conti_service.dart';
import '../services/favorites_service.dart';
import '../services/score_service.dart';
import '../services/tag_service.dart';
import '../services/sync_service.dart';
import '../widgets/tag_editor_sheet.dart';
import 'bible_tab.dart';
import 'conti_editor_screen.dart';
import 'responsive_reading_screen.dart';
import 'viewer_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Map<String, String> _activeFilters = {};
  String? _timeSignatureFilter; // null=전체, '4/4' 등

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim());
    });
    FavoritesService.instance.favorites.addListener(_refresh);
    TagService.instance.tags.addListener(_refresh);
    ContiService.instance.contis.addListener(_refresh);
    ScoreService.instance.scores.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _searchController.dispose();
    FavoritesService.instance.favorites.removeListener(_refresh);
    TagService.instance.tags.removeListener(_refresh);
    ContiService.instance.contis.removeListener(_refresh);
    ScoreService.instance.scores.removeListener(_refresh);
    super.dispose();
  }

  // ── 데이터 ─────────────────────────────────
  List<Song> get _filteredHymns {
    var songs = HymnData.search(_searchQuery)
        .map((n) => Song(
              id: 'h_$n',
              title: HymnData.getTitle(n),
              assetPath: HymnData.getAssetPath(n),
              hymnNumber: n,
              youtubeUrl: HymnData.getYoutubeUrl(n),
            ))
        .toList();
    for (final entry in _activeFilters.entries) {
      songs = songs
          .where((s) =>
              TagService.instance.getTag(s.id, entry.key) == entry.value)
          .toList();
    }
    if (_timeSignatureFilter != null) {
      songs = songs
          .where(
              (s) => TagService.instance.getTag(s.id, '박자') == _timeSignatureFilter)
          .toList();
    }
    return songs;
  }

  List<Song> get _filteredScores {
    var songs = ScoreService.instance.search(_searchQuery);
    for (final entry in _activeFilters.entries) {
      songs = songs
          .where((s) =>
              TagService.instance.getTag(s.id, entry.key) == entry.value)
          .toList();
    }
    if (_timeSignatureFilter != null) {
      songs = songs
          .where(
              (s) => TagService.instance.getTag(s.id, '박자') == _timeSignatureFilter)
          .toList();
    }
    return songs;
  }

  List<Song> get _allFavorites {
    final sortedIds = FavoritesService.instance.sortedByDate();
    var songs = sortedIds
        .map((id) {
          if (id.startsWith('h_')) {
            final num = int.tryParse(id.substring(2));
            if (num != null) {
              return Song(
                id: id,
                title: HymnData.getTitle(num),
                assetPath: HymnData.getAssetPath(num),
                hymnNumber: num,
                youtubeUrl: HymnData.getYoutubeUrl(num),
              );
            }
          } else if (id.startsWith('s_')) {
            final entry = ScoreService.instance.findById(id);
            if (entry != null) return entry.toSong();
          }
          return null;
        })
        .whereType<Song>()
        .toList();
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      songs = songs
          .where((s) =>
              s.title.toLowerCase().contains(q) ||
              (s.hymnNumber?.toString().contains(q) ?? false))
          .toList();
    }
    return songs;
  }

  // ── 액션 ────────────────────────────────────
  void _openTagEditor(Song song) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => TagEditorSheet(song: song),
    );
  }

  void _openViewer(Song song, List<Song> list) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ViewerScreen(initialSong: song, songList: list),
      ),
    );
  }

  Future<void> _pickAndAddScore() async {
    try {
      final picked = await ScoreService.instance.pickFile();
      if (picked == null || !mounted) return;

      final defaultTitle = picked.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      final ctrl = TextEditingController(text: defaultTitle);

      final title = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('악보 추가'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '선택된 파일: ${picked.name}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '악보 제목',
                  hintText: '곡 제목을 입력하세요',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                final t = ctrl.text.trim();
                Navigator.pop(ctx, t.isEmpty ? defaultTitle : t);
              },
              child: const Text('추가'),
            ),
          ],
        ),
      );

      if (title == null) {
        // 취소된 경우 복사된 임시 파일 정리
        try {
          final f = File(picked.path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
        return;
      }

      final created = await ScoreService.instance.addScore(
        title: title,
        filePath: picked.path,
        fileName: picked.name,
      );

      if (mounted) {
        final song = created.toSong();
        _openViewer(song, _filteredScores);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('파일 불러오기 실패: $e')),
        );
      }
    }
  }

  void _showScoreOptions(Song song) {
    final score = ScoreService.instance.findById(song.id);
    if (score == null) {
      _openTagEditor(song);
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  score.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('제목 수정'),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final ctrl = TextEditingController(text: score.title);
                  final newTitle = await showDialog<String>(
                    context: context,
                    builder: (dCtx) => AlertDialog(
                      title: const Text('악보 제목 수정'),
                      content: TextField(
                        controller: ctrl,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: '악보 제목',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dCtx),
                          child: const Text('취소'),
                        ),
                        FilledButton(
                          onPressed: () =>
                              Navigator.pop(dCtx, ctrl.text.trim()),
                          child: const Text('저장'),
                        ),
                      ],
                    ),
                  );
                  if (newTitle != null && newTitle.isNotEmpty) {
                    await ScoreService.instance
                        .updateTitle(score.id, newTitle);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.label_outline),
                title: const Text('태그 편집'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _openTagEditor(song);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title:
                    const Text('삭제', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dCtx) => AlertDialog(
                      title: const Text('악보 삭제'),
                      content: Text('"${score.title}" 악보를 삭제하시겠습니까?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dCtx, false),
                          child: const Text('취소'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(dCtx, true),
                          child: const Text('삭제',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await ScoreService.instance.delete(score.id);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLoginPrompt() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Google 로그인'),
        content: const Text('로그인하면 데이터를 백업하고 복원할 수 있습니다.\n로그인하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('나중에'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _openSettings();
            },
            child: const Text('로그인'),
          ),
        ],
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  int get _filterCount => _activeFilters.length;

  bool get _showSearchAndFilter => true;
  bool get _showYoutubeAndTagFilter =>
      _currentIndex == 1 || _currentIndex == 2;

  String get _searchHint {
    switch (_currentIndex) {
      case 0:
        return '성경 말씀 또는 장절 검색 (예: 요 3:16, 사랑)...';
      case 1:
        return '찬송가 제목 또는 장수로 검색...';
      case 2:
        return '등록한 악보 제목으로 검색...';
      case 3:
        return '교독문 번호(1~137), 제목, 본문 검색...';
      case 4:
        return '콘티 제목 또는 곡명으로 검색...';
      case 5:
        return '내 악보 제목 또는 장수로 검색...';
      default:
        return '제목 또는 번호로 검색...';
    }
  }

  // ── 빌드 ────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final hymns = _filteredHymns;
    final scores = _filteredScores;
    final favs = _allFavorites;

    return Scaffold(
      appBar: AppBar(
        title: const Text('찬양집',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
        actions: [
          // 테마 토글
          ValueListenableBuilder<ThemeMode>(
            valueListenable: AppSettings.instance.themeMode,
            builder: (context, mode, child) => IconButton(
              icon: Icon(AppSettings.instance.themeIcon),
              tooltip: AppSettings.instance.themeLabel,
              onPressed: AppSettings.instance.cycleTheme,
            ),
          ),
          // 계정 버튼
          ValueListenableBuilder<User?>(
            valueListenable: SyncService.instance.currentUser,
            builder: (context, user, _) {
              if (user != null) {
                return GestureDetector(
                  onTap: _openSettings,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: CircleAvatar(
                      radius: 15,
                      backgroundImage: user.photoURL != null
                          ? NetworkImage(user.photoURL!)
                          : null,
                      child: user.photoURL == null
                          ? const Icon(Icons.person, size: 16)
                          : null,
                    ),
                  ),
                );
              }
              return IconButton(
                icon: const Icon(Icons.login),
                tooltip: '로그인',
                onPressed: () => _showLoginPrompt(),
              );
            },
          ),
          // 설정
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '설정',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          // 검색바
          if (_showSearchAndFilter) ...[
            Container(
              color: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: _searchHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _searchController.clear,
                        )
                      : null,
                  filled: true,
                  fillColor:
                      Theme.of(context).colorScheme.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
            ),
            const Divider(height: 1),
            // 박자 필터 칩 바 (새찬송가/악보 탭에서만)
            if (_showYoutubeAndTagFilter)
              _TimeSignatureFilterBar(
                selected: _timeSignatureFilter,
                onChanged: (v) => setState(() => _timeSignatureFilter = v),
              ),
            if (_showYoutubeAndTagFilter) const Divider(height: 1),
          ],
          // 활성 필터 칩
          if (_filterCount > 0 && _showYoutubeAndTagFilter)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                children: [
                  ..._activeFilters.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _ActiveFilterChip(
                        label: '${e.key}: ${e.value}',
                        onRemove: () =>
                            setState(() => _activeFilters.remove(e.key)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // 탭 콘텐츠
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                // 0: 성경 (개역개정 66권)
                BibleTab(searchQuery: _searchQuery),
                // 1: 새찬송가
                _SongTabView(
                  songs: hymns,
                  emptyMessage: '검색 결과가 없습니다',
                  onTap: (song) => _openViewer(song, hymns),
                  onLongPress: _openTagEditor,
                ),
                // 2: 악보 (사용자 이미지 / PDF 뷰어)
                _CustomScoreTabView(
                  songs: scores,
                  hasQuery: _searchQuery.isNotEmpty || _timeSignatureFilter != null,
                  onAddPressed: _pickAndAddScore,
                  onTap: (song) => _openViewer(song, scores),
                  onLongPress: _showScoreOptions,
                ),
                // 3: 예배문 (교독문 1~137번 + 주기도문)
                _LiturgicalTab(searchQuery: _searchQuery),
                // 4: 내 콘티
                _ContiTab(
                    onOpenViewer: _openViewer, searchQuery: _searchQuery),
                // 5: 내 악보
                _MyScoreTab(
                  songs: favs,
                  onTap: (song) => _openViewer(song, favs),
                  onLongPress: (song) => song.isLocalFile
                      ? _showScoreOptions(song)
                      : _openTagEditor(song),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _currentIndex == 2
          ? FloatingActionButton.extended(
              onPressed: _pickAndAddScore,
              backgroundColor: const Color(0xFF5C56C9),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.upload_file),
              label: const Text('악보 올리기',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            )
          : _currentIndex == 4
              ? FloatingActionButton(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const ContiEditorScreen()),
                    );
                  },
                  backgroundColor: const Color(0xFF5C56C9),
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.add),
                )
              : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          setState(() {
            _currentIndex = i;
            _searchController.clear();
            _timeSignatureFilter = null;
          });
        },
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.book_outlined,
                color: _currentIndex == 0
                    ? const Color(0xFF5C56C9)
                    : Colors.grey.shade500),
            selectedIcon:
                const Icon(Icons.book, color: Color(0xFF5C56C9)),
            label: '성경',
          ),
          NavigationDestination(
            icon: Icon(Icons.music_note_outlined,
                color: _currentIndex == 1
                    ? const Color(0xFF5C56C9)
                    : Colors.grey.shade500),
            selectedIcon:
                const Icon(Icons.music_note, color: Color(0xFF5C56C9)),
            label: '새찬송가',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined,
                color: _currentIndex == 2
                    ? const Color(0xFF5C56C9)
                    : Colors.grey.shade500),
            selectedIcon:
                const Icon(Icons.library_music, color: Color(0xFF5C56C9)),
            label: '악보',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined,
                color: _currentIndex == 3
                    ? const Color(0xFF5C56C9)
                    : Colors.grey.shade500),
            selectedIcon:
                const Icon(Icons.auto_stories, color: Color(0xFF5C56C9)),
            label: '예배문',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined,
                color: _currentIndex == 4
                    ? const Color(0xFF5C56C9)
                    : Colors.grey.shade500),
            selectedIcon:
                const Icon(Icons.menu_book, color: Color(0xFF5C56C9)),
            label: '내 콘티',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_border,
                color: _currentIndex == 5
                    ? const Color(0xFF5C56C9)
                    : Colors.grey.shade500),
            selectedIcon:
                const Icon(Icons.star, color: Color(0xFF5C56C9)),
            label: '내 악보',
          ),
        ],
      ),
    );
  }
}

// ── 악보 (PDF / 이미지) 썸네일 ────────────────────
class _PdfThumb extends StatefulWidget {
  final String assetPath;
  final bool isLocalFile;
  const _PdfThumb({required this.assetPath, this.isLocalFile = false});

  @override
  State<_PdfThumb> createState() => _PdfThumbState();
}

class _PdfThumbState extends State<_PdfThumb> {
  static final Map<String, Uint8List?> _cache = {};

  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _PdfThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath ||
        oldWidget.isLocalFile != widget.isLocalFile) {
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final path = widget.assetPath;
    if (_cache.containsKey(path)) {
      if (mounted) {
        setState(() {
          _bytes = _cache[path];
          _loading = false;
        });
      }
      return;
    }

    if (widget.isLocalFile) {
      final f = File(path);
      if (!await f.exists()) {
        _cache[path] = null;
        if (mounted) setState(() => _loading = false);
        return;
      }
      if (!path.toLowerCase().endsWith('.pdf')) {
        try {
          final bytes = await f.readAsBytes();
          _cache[path] = bytes;
          if (mounted) {
            setState(() {
              _bytes = bytes;
              _loading = false;
            });
          }
          return;
        } catch (_) {
          _cache[path] = null;
          if (mounted) setState(() => _loading = false);
          return;
        }
      }
      try {
        final doc = await PdfDocument.openFile(path);
        final page = await doc.getPage(1);
        final render = await page.render(
          width: 120,
          height: 120 * page.height / page.width,
          format: PdfPageImageFormat.png,
          backgroundColor: '#ffffff',
        );
        await page.close();
        await doc.close();
        final bytes = render?.bytes;
        _cache[path] = bytes;
        if (mounted) {
          setState(() {
            _bytes = bytes;
            _loading = false;
          });
        }
      } catch (_) {
        _cache[path] = null;
        if (mounted) setState(() => _loading = false);
      }
      return;
    }

    try {
      await rootBundle.load(path);
    } catch (_) {
      _cache[path] = null;
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final doc = await PdfDocument.openAsset(path);
      final page = await doc.getPage(1);
      final render = await page.render(
        width: 120,
        height: 120 * page.height / page.width,
        format: PdfPageImageFormat.png,
        backgroundColor: '#ffffff',
      );
      await page.close();
      await doc.close();
      final bytes = render?.bytes;
      _cache[path] = bytes;
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _loading = false;
        });
      }
    } catch (_) {
      _cache[path] = null;
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: const Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
        ),
      );
    }
    if (_bytes == null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Center(
          child: Icon(Icons.hourglass_bottom,
              size: 18, color: Colors.grey.shade400),
        ),
      );
    }
    return Image.memory(_bytes!, fit: BoxFit.cover);
  }
}

// ── 박자 필터 칩 바 ───────────────────────────
class _TimeSignatureFilterBar extends StatelessWidget {
  final String? selected;
  final void Function(String?) onChanged;

  const _TimeSignatureFilterBar(
      {required this.selected, required this.onChanged});

  static const _signatures = [
    '4/4',
    '3/4',
    '6/8',
    '2/4',
    '3/2',
    '6/4',
    '2/2',
    '4/2',
    '3/8',
    '9/8',
    '9/4',
    '5/4',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          _SigChip(
            label: '전체',
            selected: selected == null,
            onTap: () => onChanged(null),
          ),
          const SizedBox(width: 6),
          ..._signatures.map((sig) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _SigChip(
                  label: '박자 $sig',
                  selected: selected == sig,
                  onTap: () => onChanged(selected == sig ? null : sig),
                ),
              )),
        ],
      ),
    );
  }
}

class _SigChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SigChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.12)
              : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ── 활성 필터 칩 ─────────────────────────────
class _ActiveFilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _ActiveFilterChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Chip(
      label: Text(label,
          style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer)),
      backgroundColor: cs.primaryContainer,
      deleteIcon: Icon(Icons.close, size: 14, color: cs.onPrimaryContainer),
      onDeleted: onRemove,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

// ── 공통 리스트 아이템 ───────────────────────
class _SongListItem extends StatelessWidget {
  final Song song;
  final bool showDate;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _SongListItem({
    required this.song,
    this.showDate = false,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isFav = FavoritesService.instance.isFavorite(song.id);
    final songTags = TagService.instance.getTagsFor(song.id);
    final addedDate =
        showDate ? FavoritesService.instance.addedDate(song.id) : null;
    final hasYoutube = song.youtubeUrl != null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              // PDF / 이미지 썸네일
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: _PdfThumb(
                    assetPath: song.assetPath,
                    isLocalFile: song.isLocalFile,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 텍스트 영역
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.isHymn
                          ? '${song.hymnNumber!}장  ${song.title}'
                          : song.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (song.isLocalFile) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            song.isPdf ? Icons.picture_as_pdf : Icons.image_outlined,
                            size: 12,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            song.isPdf ? 'PDF 악보' : '이미지 악보',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (songTags.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        children: songTags.entries.map((e) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${e.key} ${e.value}',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: cs.onPrimaryContainer,
                                  fontWeight: FontWeight.w600),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    if (addedDate != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              color: Colors.amber, size: 13),
                          const SizedBox(width: 3),
                          Text(
                            FavoritesService.instance.formatDate(addedDate),
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.primary.withValues(alpha: 0.7)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // 즐겨찾기 별
              if (isFav)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child:
                      Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                ),
              // YouTube 버튼
              if (hasYoutube)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () async {
                      final uri = Uri.parse(song.youtubeUrl!);
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_circle, size: 16, color: Colors.red),
                          SizedBox(width: 4),
                          Text('YouTube',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red)),
                        ],
                      ),
                    ),
                  ),
                ),
              // 악보 버튼
              GestureDetector(
                onTap: onTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        song.isPdf ? Icons.picture_as_pdf : Icons.image,
                        size: 16,
                        color: cs.onPrimaryContainer,
                      ),
                      const SizedBox(width: 4),
                      Text('악보',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.onPrimaryContainer)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 새찬송가 탭 뷰 ────────────────────────────
class _SongTabView extends StatelessWidget {
  final List<Song> songs;
  final String emptyMessage;
  final void Function(Song) onTap;
  final void Function(Song) onLongPress;

  const _SongTabView({
    required this.songs,
    required this.emptyMessage,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(emptyMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade400, height: 1.6)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      itemCount: songs.length,
      itemBuilder: (context, i) {
        final song = songs[i];
        return _SongListItem(
          song: song,
          onTap: () => onTap(song),
          onLongPress: () => onLongPress(song),
        );
      },
    );
  }
}

// ── 사용자 업로드 악보 탭 뷰 ────────────────────
class _CustomScoreTabView extends StatelessWidget {
  final List<Song> songs;
  final bool hasQuery;
  final VoidCallback onAddPressed;
  final void Function(Song) onTap;
  final void Function(Song) onLongPress;

  const _CustomScoreTabView({
    required this.songs,
    required this.hasQuery,
    required this.onAddPressed,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      if (hasQuery) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text('검색 결과가 없습니다',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade400, height: 1.6)),
            ],
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.library_music_outlined,
                  size: 72, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(
                '등록된 악보가 없습니다\n이미지(JPG, PNG) 또는 PDF 악보 파일을 올려\n뷰어로 편리하게 보고 필기해보세요',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade500, height: 1.6),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAddPressed,
                icon: const Icon(Icons.upload_file),
                label: const Text('이미지 / PDF 악보 올리기'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF5C56C9),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      itemCount: songs.length,
      itemBuilder: (context, i) {
        final song = songs[i];
        return _SongListItem(
          song: song,
          onTap: () => onTap(song),
          onLongPress: () => onLongPress(song),
        );
      },
    );
  }
}

// ── 예배문 탭 (교독문 1~137번 & 주기도문) ────────
class _LiturgicalTab extends StatefulWidget {
  final String searchQuery;
  const _LiturgicalTab({required this.searchQuery});

  @override
  State<_LiturgicalTab> createState() => _LiturgicalTabState();
}

class _LiturgicalTabState extends State<_LiturgicalTab> {
  int _subIndex = 0; // 0: 교독문, 1: 주기도문
  double _prayerFontSize = 20.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final readings = ResponsiveReadingData.search(widget.searchQuery);

    return Column(
      children: [
        // 상단 세그먼트 선택 바 (교독문 | 주기도문)
        Container(
          width: double.infinity,
          color: cs.surface,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(
                value: 0,
                icon: Icon(Icons.menu_book_outlined, size: 18),
                label: Text('교독문 (1~137번)',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              ButtonSegment<int>(
                value: 1,
                icon: Icon(Icons.volunteer_activism_outlined, size: 18),
                label: Text('주기도문',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
            selected: {_subIndex},
            onSelectionChanged: (s) => setState(() => _subIndex = s.first),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _subIndex == 0
              ? _buildResponsiveReadingsList(context, readings)
              : _buildLordsPrayerView(context),
        ),
      ],
    );
  }

  Widget _buildResponsiveReadingsList(
      BuildContext context, List<ResponsiveReading> readings) {
    final cs = Theme.of(context).colorScheme;
    if (readings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('검색 결과가 없습니다',
                style: TextStyle(color: Colors.grey.shade400)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: readings.length,
      itemBuilder: (context, i) {
        final r = readings[i];
        final firstVerse = r.verses.isNotEmpty ? r.verses.first.text : '';
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
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ResponsiveReadingDetailScreen(
                    initialIndex: i,
                    readings: readings,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${r.number}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${r.number}번. ${r.title}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        if (firstVerse.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            firstVerse,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: Colors.grey.shade400),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLordsPrayerView(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.auto_stories,
                          size: 20, color: cs.onPrimaryContainer),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ResponsiveReadingData.lordsPrayerTitle,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '마태복음 6:9-13',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.text_decrease),
                      tooltip: '글자 작게',
                      onPressed: _prayerFontSize > 14
                          ? () => setState(() => _prayerFontSize -= 2)
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.text_increase),
                      tooltip: '글자 크게',
                      onPressed: _prayerFontSize < 32
                          ? () => setState(() => _prayerFontSize += 2)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: cs.outlineVariant),
                const SizedBox(height: 20),
                ...ResponsiveReadingData.lordsPrayerLines.asMap().entries.map(
                  (entry) {
                    final isLast = entry.key ==
                        ResponsiveReadingData.lordsPrayerLines.length - 1;
                    return Padding(
                      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          fontSize: _prayerFontSize,
                          height: 1.65,
                          fontWeight:
                              isLast ? FontWeight.w700 : FontWeight.w500,
                          color: isLast ? cs.primary : cs.onSurface,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── 내 악보 탭 ───────────────────────────────
class _MyScoreTab extends StatelessWidget {
  final List<Song> songs;
  final void Function(Song) onTap;
  final void Function(Song) onLongPress;

  const _MyScoreTab({
    required this.songs,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.star_border, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              '내 악보가 없습니다\n악보를 열고 ☆을 눌러 추가하세요',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, height: 1.6),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      itemCount: songs.length,
      itemBuilder: (context, i) {
        final song = songs[i];
        return _SongListItem(
          song: song,
          showDate: true,
          onTap: () => onTap(song),
          onLongPress: () => onLongPress(song),
        );
      },
    );
  }
}

// ── 내 콘티 탭 ───────────────────────────────
class _ContiTab extends StatelessWidget {
  final void Function(Song, List<Song>) onOpenViewer;
  final String searchQuery;
  const _ContiTab({required this.onOpenViewer, this.searchQuery = ''});

  List<Song> _resolveSongs(Conti conti) {
    return conti.songIds
        .map((id) => resolveSongId(id))
        .whereType<Song>()
        .toList();
  }

  void _openEditor(BuildContext context, {Conti? existing}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContiEditorScreen(existing: existing),
      ),
    );
  }

  void _showOptions(BuildContext context, Conti conti) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ContiOptionsSheet(
        conti: conti,
        onEdit: () {
          Navigator.pop(context);
          _openEditor(context, existing: conti);
        },
        onDelete: () async {
          Navigator.pop(context);
          await ContiService.instance.delete(conti.id);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var contis = ContiService.instance.contis.value;
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      contis = contis.where((c) {
        if (c.title.toLowerCase().contains(q)) return true;
        final songs = _resolveSongs(c);
        return songs.any((s) =>
            s.title.toLowerCase().contains(q) ||
            (s.hymnNumber?.toString().contains(q) ?? false));
      }).toList();
    }
    if (contis.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              '콘티가 없습니다\n+ 버튼으로 새 콘티를 만들어보세요',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, height: 1.6),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      itemCount: contis.length,
      itemBuilder: (context, i) {
        final conti = contis[i];
        final songs = _resolveSongs(conti);
        return _ContiCard(
          conti: conti,
          songs: songs,
          onTap: () {
            if (songs.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('콘티에 찬양이 없습니다')),
              );
              return;
            }
            onOpenViewer(songs.first, songs);
          },
          onLongPress: () => _showOptions(context, conti),
          onEdit: () => _openEditor(context, existing: conti),
        );
      },
    );
  }
}

// ── 콘티 카드 ────────────────────────────────
class _ContiCard extends StatelessWidget {
  final Conti conti;
  final List<Song> songs;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onEdit;

  const _ContiCard({
    required this.conti,
    required this.songs,
    required this.onTap,
    required this.onLongPress,
    required this.onEdit,
  });

  String _formatDate(DateTime dt) {
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단: 제목 + 편집 버튼
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.menu_book,
                        size: 16, color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      conti.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: onEdit,
                    icon: Icon(Icons.edit_outlined,
                        size: 18, color: Colors.grey.shade400),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // 날짜 + 곡 수
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 12, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(conti.createdAt),
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.music_note,
                      size: 12, color: cs.primary.withValues(alpha: 0.6)),
                  const SizedBox(width: 3),
                  Text(
                    '${songs.length}곡',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.primary,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              if (songs.isNotEmpty) ...[
                const SizedBox(height: 10),
                Divider(height: 1, color: cs.outlineVariant),
                const SizedBox(height: 8),
                // 찬양 목록
                ...songs.take(4).toList().asMap().entries.map((entry) {
                  final idx = entry.key;
                  final song = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0EFFF),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Center(
                            child: Text(
                              '${idx + 1}',
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF5C56C9)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            song.isHymn
                                ? '${song.hymnNumber!}장  ${song.title}'
                                : song.title,
                            style: const TextStyle(fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                if (songs.length > 4) ...[
                  const SizedBox(height: 2),
                  Text(
                    '+ ${songs.length - 4}곡 더보기',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
                ],
              ],
              // 시작 버튼
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: songs.isEmpty ? null : onTap,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('악보 보기'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5C56C9),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 콘티 옵션 시트 ───────────────────────────
class _ContiOptionsSheet extends StatelessWidget {
  final Conti conti;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ContiOptionsSheet({
    required this.conti,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                conti.title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('편집'),
              onTap: onEdit,
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('삭제', style: TextStyle(color: Colors.red)),
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('콘티 삭제'),
                    content: Text('"${conti.title}"을(를) 삭제하시겠습니까?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('취소'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('삭제',
                            style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}
