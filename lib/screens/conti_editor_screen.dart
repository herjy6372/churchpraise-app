import 'package:flutter/material.dart';
import '../data/hymn_data.dart';
import '../models/conti.dart';
import '../models/song.dart';
import '../services/conti_service.dart';
import '../services/score_service.dart';

// Resolves a stored songId (e.g. 'h_1', 's_...') to a Song object
Song? resolveSongId(String id) {
  if (id.startsWith('h_')) {
    final n = int.tryParse(id.substring(2));
    if (n == null) return null;
    return Song(
      id: id,
      title: HymnData.getTitle(n),
      assetPath: HymnData.getAssetPath(n),
      hymnNumber: n,
      youtubeUrl: HymnData.getYoutubeUrl(n),
    );
  } else if (id.startsWith('s_')) {
    return ScoreService.instance.findById(id)?.toSong();
  }
  return null;
}

class ContiEditorScreen extends StatefulWidget {
  final Conti? existing;
  const ContiEditorScreen({super.key, this.existing});

  @override
  State<ContiEditorScreen> createState() => _ContiEditorScreenState();
}

class _ContiEditorScreenState extends State<ContiEditorScreen> {
  late final TextEditingController _titleCtrl;
  late List<String> _songIds;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.existing?.title ?? '');
    _songIds = List.from(widget.existing?.songIds ?? []);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목을 입력해주세요')),
      );
      return;
    }
    if (widget.existing == null) {
      await ContiService.instance.create(title, _songIds);
    } else {
      await ContiService.instance.update(
        widget.existing!.id,
        title: title,
        songIds: _songIds,
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _pickSongs() async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SongPickerSheet(alreadySelected: _songIds),
    );
    if (result != null) {
      setState(() {
        for (final id in result) {
          if (!_songIds.contains(id)) _songIds.add(id);
        }
      });
    }
  }

  void _removeSong(int index) {
    setState(() => _songIds.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(
          widget.existing == null ? '새 콘티' : '콘티 편집',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text('저장',
                style: TextStyle(
                    color: cs.primary, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      body: Column(
        children: [
          const Divider(height: 1),
          // 제목 입력
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _titleCtrl,
              autofocus: widget.existing == null,
              decoration: InputDecoration(
                labelText: '콘티 제목',
                hintText: '예: 2024년 12월 주일 찬양',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
            ),
          ),
          // 찬양 추가 버튼
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _pickSongs,
                icon: const Icon(Icons.add),
                label: const Text('찬양 추가'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          // 곡 목록
          if (_songIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  Text('${_songIds.length}곡',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: cs.primary)),
                  const SizedBox(width: 6),
                  Text('(길게 눌러 순서 변경)',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500)),
                ],
              ),
            ),
          Expanded(
            child: _songIds.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.queue_music,
                            size: 60,
                            color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('위 버튼으로 찬양을 추가하세요',
                            style: TextStyle(color: Colors.grey.shade400)),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
                    itemCount: _songIds.length,
                    onReorderItem: (oldIdx, newIdx) {
                      setState(() {
                        final item = _songIds.removeAt(oldIdx);
                        _songIds.insert(newIdx, item);
                      });
                    },
                    itemBuilder: (ctx, i) {
                      final song = resolveSongId(_songIds[i]);
                      return Card(
                        key: ValueKey(_songIds[i] + i.toString()),
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        elevation: 0.5,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: Theme.of(ctx).colorScheme.outlineVariant)),
                        child: ListTile(
                          leading: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text('${i + 1}',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: cs.onPrimaryContainer)),
                            ),
                          ),
                          title: Text(
                            song != null
                                ? (song.isHymn
                                    ? '${song.hymnNumber!}장  ${song.title}'
                                    : song.title)
                                : _songIds[i],
                            style: const TextStyle(fontSize: 14),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.close,
                                    size: 18, color: Colors.grey.shade400),
                                onPressed: () => _removeSong(i),
                              ),
                              ReorderableDragStartListener(
                                index: i,
                                child: Icon(Icons.drag_handle,
                                    color: Colors.grey.shade400),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── 노래 선택 시트 ───────────────────────────
class _SongPickerSheet extends StatefulWidget {
  final List<String> alreadySelected;
  const _SongPickerSheet({required this.alreadySelected});

  @override
  State<_SongPickerSheet> createState() => _SongPickerSheetState();
}

class _SongPickerSheetState extends State<_SongPickerSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Set<String> _picked = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim()));
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _isSelected(String id) =>
      widget.alreadySelected.contains(id) || _picked.contains(id);

  void _toggle(String id) {
    if (widget.alreadySelected.contains(id)) return;
    setState(() {
      if (_picked.contains(id)) {
        _picked.remove(id);
      } else {
        _picked.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hymnNums = HymnData.search(_query);
    final customScores = ScoreService.instance.search(_query);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 핸들
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 12),
          // 헤더
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text('찬양 선택',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                if (_picked.isNotEmpty)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(_picked.toList()),
                    child: Text('추가 (${_picked.length})',
                        style: TextStyle(
                            color: cs.primary, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
          // 검색
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '제목 또는 번호로 검색...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: _searchCtrl.clear)
                    : null,
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                isDense: true,
              ),
            ),
          ),
          // 탭
          TabBar(
            controller: _tab,
            tabs: [
              Tab(text: '새찬송가 (${hymnNums.length})'),
              Tab(text: '악보 (${customScores.length})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                // 새찬송가 목록
                ListView.builder(
                  itemCount: hymnNums.length,
                  itemBuilder: (_, i) {
                    final n = hymnNums[i];
                    final id = 'h_$n';
                    final selected = _isSelected(id);
                    final alreadyIn = widget.alreadySelected.contains(id);
                    return ListTile(
                      dense: true,
                      leading: selected
                          ? Icon(Icons.check_circle,
                              color: alreadyIn
                                  ? Colors.grey.shade400
                                  : cs.primary)
                          : Icon(Icons.radio_button_unchecked,
                              color: Colors.grey.shade400),
                      title: Text('$n장  ${HymnData.getTitle(n)}',
                          style: const TextStyle(fontSize: 13)),
                      onTap: alreadyIn ? null : () => _toggle(id),
                    );
                  },
                ),
                // 악보 목록
                customScores.isEmpty
                    ? Center(
                        child: Text(
                          '등록된 악보가 없습니다.\n악보 탭에서 이미지나 PDF를 추가해보세요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade400, height: 1.5),
                        ),
                      )
                    : ListView.builder(
                        itemCount: customScores.length,
                        itemBuilder: (_, i) {
                          final song = customScores[i];
                          final selected = _isSelected(song.id);
                          final alreadyIn = widget.alreadySelected.contains(song.id);
                          return ListTile(
                            dense: true,
                            leading: selected
                                ? Icon(Icons.check_circle,
                                    color: alreadyIn
                                        ? Colors.grey.shade400
                                        : cs.primary)
                                : Icon(Icons.radio_button_unchecked,
                                    color: Colors.grey.shade400),
                            title: Text(song.title,
                                style: const TextStyle(fontSize: 13)),
                            onTap: alreadyIn ? null : () => _toggle(song.id),
                          );
                        },
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
