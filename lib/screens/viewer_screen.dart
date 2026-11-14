import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/song.dart';
import '../services/favorites_service.dart';

// ── Drawing models ────────────────────────────────────────────

enum DrawTool { none, pen, highlighter, eraser }

class _Pt {
  final double x, y;
  const _Pt(this.x, this.y);
  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  static _Pt fromJson(Map<dynamic, dynamic> j) =>
      _Pt((j['x'] as num).toDouble(), (j['y'] as num).toDouble());
}

class _Stroke {
  final List<_Pt> pts;
  final int clr;
  final double w;
  final bool erase;
  final bool highlight;
  const _Stroke({required this.pts, required this.clr, required this.w, this.erase = false, this.highlight = false});
  Color get color => Color(clr);
  Map<String, dynamic> toJson() => {
    'pts': pts.map((p) => p.toJson()).toList(),
    'c': clr,
    'w': w,
    'e': erase,
    if (highlight) 'h': true,
  };
  static _Stroke fromJson(Map<dynamic, dynamic> j) => _Stroke(
    pts: (j['pts'] as List).map((p) => _Pt.fromJson(p as Map)).toList(),
    clr: j['c'] as int,
    w: (j['w'] as num).toDouble(),
    erase: j['e'] == true,
    highlight: j['h'] == true,
  );
}

// ── Annotation persistence ────────────────────────────────────

const _kAnnoPrefix = 'anno_v1_';

Future<List<_Stroke>> _loadAnno(String songId) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('$_kAnnoPrefix$songId');
  if (raw == null) return [];
  try {
    return (jsonDecode(raw) as List).map((s) => _Stroke.fromJson(s as Map)).toList();
  } catch (_) {
    return [];
  }
}

Future<void> _saveAnno(String songId, List<_Stroke> strokes) async {
  final prefs = await SharedPreferences.getInstance();
  if (strokes.isEmpty) {
    await prefs.remove('$_kAnnoPrefix$songId');
  } else {
    await prefs.setString(
      '$_kAnnoPrefix$songId',
      jsonEncode(strokes.map((s) => s.toJson()).toList()),
    );
  }
}

// ── Annotation painter ────────────────────────────────────────

class _AnnoPainter extends CustomPainter {
  final List<_Stroke> strokes;
  final _Stroke? current;
  const _AnnoPainter(this.strokes, this.current);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final s in [...strokes, ?current]) {
      _draw(canvas, s);
    }
    canvas.restore();
  }

  void _draw(Canvas canvas, _Stroke s) {
    if (s.pts.isEmpty) return;
    final paint = Paint()
      ..strokeWidth = s.w
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke;

    if (s.erase) {
      paint
        ..blendMode = BlendMode.clear
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
    } else if (s.highlight) {
      paint
        ..color = s.color   // alpha already baked in
        ..strokeCap = StrokeCap.square
        ..strokeJoin = StrokeJoin.bevel
        ..isAntiAlias = false;
    } else {
      paint
        ..color = s.color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
    }

    if (s.pts.length == 1) {
      canvas.drawCircle(
        Offset(s.pts.first.x, s.pts.first.y),
        s.w / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    final path = Path()..moveTo(s.pts.first.x, s.pts.first.y);
    for (final pt in s.pts.skip(1)) {
      path.lineTo(pt.x, pt.y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_AnnoPainter old) => true;
}

// ── ViewerScreen ──────────────────────────────────────────────

class ViewerScreen extends StatefulWidget {
  final Song initialSong;
  final List<Song> songList;

  const ViewerScreen({
    super.key,
    required this.initialSong,
    required this.songList,
  });

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  // Navigation
  late Song _song;
  late int _idx;

  // PDF
  List<Uint8List> _pages = [];
  double _pageW = 0;
  double _totalH = 0;
  bool _loading = true;
  String? _noFileMsg;

  // Drawing
  DrawTool _tool = DrawTool.none;
  final List<_Stroke> _strokes = [];
  final List<_Stroke> _redoStack = [];
  _Stroke? _current;
  Color _penColor = Colors.red;
  double _penWidth = 4.0;
  Color _hlColor = Colors.yellow;
  double _hlWidth = 20.0;
  double _eraserWidth = 28.0;
  bool _unsaved = false;

  // UI
  final _txCtrl = TransformationController();
  bool _showUI = true;
  bool _toolbarAtBottom = false;

  @override
  void initState() {
    super.initState();
    _song = widget.initialSong;
    _idx = widget.songList.indexOf(_song);
    _loadPdf();
    _loadToolbarPref();
  }

  Future<void> _loadToolbarPref() async {
    final prefs = await SharedPreferences.getInstance();
    final pos = prefs.getString('viewer_toolbar_position') ?? 'top';
    if (mounted) setState(() => _toolbarAtBottom = pos == 'bottom');
  }

  Future<void> _toggleToolbarPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final newVal = !_toolbarAtBottom;
    await prefs.setString('viewer_toolbar_position', newVal ? 'bottom' : 'top');
    setState(() => _toolbarAtBottom = newVal);
  }

  @override
  void dispose() {
    if (_unsaved) _saveAnno(_song.id, _strokes);
    _txCtrl.dispose();
    super.dispose();
  }

  // ── PDF / Image loading ───────────────────────────────────

  Future<void> _loadPdf() async {
    setState(() { _loading = true; _noFileMsg = null; _pages = []; });

    bool exists = true;
    if (_song.isLocalFile) {
      exists = await File(_song.assetPath).exists();
    } else {
      try {
        await rootBundle.load(_song.assetPath);
      } catch (_) {
        exists = false;
      }
    }

    if (!exists) {
      final saved = await _loadAnno(_song.id);
      setState(() {
        _strokes..clear()..addAll(saved);
        _loading = false;
        _noFileMsg = _song.isLocalFile ? '악보 파일을 찾을 수 없습니다' : '악보 파일 준비 중';
      });
      return;
    }

    try {
      final pages = <Uint8List>[];
      double pw = 0, th = 0;

      if (_song.isLocalFile && !_song.isPdf) {
        final bytes = await File(_song.assetPath).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        pw = frame.image.width.toDouble();
        th = frame.image.height.toDouble();
        frame.image.dispose();
        pages.add(bytes);
      } else {
        final doc = _song.isLocalFile
            ? await PdfDocument.openFile(_song.assetPath)
            : await PdfDocument.openAsset(_song.assetPath);

        for (int i = 1; i <= doc.pagesCount; i++) {
          final page = await doc.getPage(i);
          final render = await page.render(
            width: page.width * 3,
            height: page.height * 3,
            format: PdfPageImageFormat.png,
            backgroundColor: '#ffffff',
          );
          final r = render!;
          pages.add(r.bytes);
          pw = (r.width ?? 0).toDouble();
          th += (r.height ?? 0).toDouble();
          await page.close();
        }
        await doc.close();
      }

      final saved = await _loadAnno(_song.id);
      setState(() {
        _pages = pages;
        _pageW = pw;
        _totalH = th;
        _strokes..clear()..addAll(saved);
        _loading = false;
        _unsaved = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageW > 0) {
          final scale = MediaQuery.of(context).size.width / _pageW;
          _txCtrl.value = Matrix4.diagonal3Values(scale, scale, 1.0);
        }
      });
    } catch (e) {
      setState(() { _loading = false; _noFileMsg = '로드 오류'; });
    }
  }

  // ── Drawing ───────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent e) {
    if (_tool == DrawTool.none) return;
    final isHL = _tool == DrawTool.highlighter;
    final isErase = _tool == DrawTool.eraser;
    setState(() {
      _current = _Stroke(
        pts: [_Pt(e.localPosition.dx, e.localPosition.dy)],
        clr: isErase
            ? Colors.white.toARGB32()
            : isHL
                ? _hlColor.withValues(alpha: 0.45).toARGB32()
                : _penColor.toARGB32(),
        w: isErase ? _eraserWidth : isHL ? _hlWidth : _penWidth,
        erase: isErase,
        highlight: isHL,
      );
      _redoStack.clear();
    });
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_current == null) return;
    setState(() {
      _current = _Stroke(
        pts: [..._current!.pts, _Pt(e.localPosition.dx, e.localPosition.dy)],
        clr: _current!.clr,
        w: _current!.w,
        erase: _current!.erase,
      );
    });
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_current == null) return;
    setState(() {
      _strokes.add(_current!);
      _current = null;
      _unsaved = true;
    });
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() { _redoStack.add(_strokes.removeLast()); _unsaved = true; });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    setState(() { _strokes.add(_redoStack.removeLast()); _unsaved = true; });
  }

  void _clearAll() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('전체 지우기'),
        content: const Text('모든 필기를 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() { _strokes.clear(); _redoStack.clear(); _unsaved = true; });
            },
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    await _saveAnno(_song.id, _strokes);
    setState(() => _unsaved = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('저장됐습니다'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Navigation ─────────────────────────────────────────────

  void _navigate(int delta) async {
    final newIdx = _idx + delta;
    if (newIdx < 0 || newIdx >= widget.songList.length) return;
    if (_unsaved) await _saveAnno(_song.id, _strokes);
    setState(() {
      _idx = newIdx;
      _song = widget.songList[newIdx];
      _tool = DrawTool.none;
    });
    _loadPdf();
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    final toolbar = _showUI ? _buildTopBar() : const SizedBox.shrink();

    final viewer = Expanded(
      child: GestureDetector(
        onTap: _tool == DrawTool.none
            ? () => setState(() => _showUI = !_showUI)
            : null,
        child: _buildViewer(),
      ),
    );

    final drawBar = _tool != DrawTool.none ? _buildDrawToolbar() : const SizedBox.shrink();

    final List<Widget> columnChildren = _toolbarAtBottom
        ? [viewer, drawBar, toolbar]
        : [toolbar, viewer, drawBar];

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          if (_unsaved) _saveAnno(_song.id, _strokes);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(children: columnChildren),
      ),
    );
  }

  Widget _buildViewer() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_noFileMsg != null && _pages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_note, color: Color(0xFFCCCCCC), size: 80),
            const SizedBox(height: 16),
            Text(_noFileMsg!,
                style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 16)),
            if (_song.youtubeUrl != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.play_circle_outline, color: Colors.white),
                label: const Text('YouTube로 보기',
                    style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () async {
                  final uri = Uri.parse(_song.youtubeUrl!);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ],
          ],
        ),
      );
    }

    final screenH = MediaQuery.of(context).size.height;
    final scaledH = _totalH * (MediaQuery.of(context).size.width / _pageW);
    final verticalMargin = (scaledH > screenH) ? scaledH : screenH;

    return InteractiveViewer(
      panEnabled: _tool == DrawTool.none,
      scaleEnabled: _tool == DrawTool.none,
      constrained: false,
      boundaryMargin: EdgeInsets.symmetric(horizontal: 80, vertical: verticalMargin),
      minScale: 0.3,
      maxScale: 5.0,
      transformationController: _txCtrl,
      child: Stack(
        children: [
          Column(
            children: _pages
                .map((bytes) => Image.memory(bytes, fit: BoxFit.contain))
                .toList(),
          ),
          Positioned(
            top: 0, left: 0,
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              behavior: _tool != DrawTool.none
                  ? HitTestBehavior.opaque
                  : HitTestBehavior.translucent,
              child: CustomPaint(
                painter: _AnnoPainter(_strokes, _current),
                size: Size(_pageW, _totalH),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final cs = Theme.of(context).colorScheme;
    final iconColor = cs.onSurface;
    return Material(
      color: cs.surface,
      elevation: 2,
      child: SafeArea(
        bottom: _toolbarAtBottom,
        top: !_toolbarAtBottom,
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: iconColor),
              onPressed: () async {
                if (_unsaved) await _save();
                if (mounted) {
                  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                  Navigator.pop(context);
                }
              },
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _song.shortLabel,
                    style: TextStyle(
                      color: iconColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _song.title,
                    style: TextStyle(color: iconColor.withValues(alpha: 0.55), fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            ValueListenableBuilder(
              valueListenable: FavoritesService.instance.favorites,
              builder: (context, favs, _) {
                final isFav = favs.containsKey(_song.id);
                return IconButton(
                  icon: Icon(
                    isFav ? Icons.star : Icons.star_border,
                    color: isFav ? Colors.amber : iconColor,
                  ),
                  onPressed: () => FavoritesService.instance.toggle(_song.id),
                );
              },
            ),
            if (_song.youtubeUrl != null)
              IconButton(
                icon: const Icon(Icons.play_circle_outline, color: Colors.red),
                tooltip: 'YouTube',
                onPressed: () async {
                  final uri = Uri.parse(_song.youtubeUrl!);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            IconButton(
              icon: Icon(
                Icons.draw,
                color: _tool != DrawTool.none ? cs.primary : iconColor,
              ),
              tooltip: '필기 모드',
              onPressed: () => setState(() {
                _tool = _tool == DrawTool.none ? DrawTool.pen : DrawTool.none;
                if (_tool != DrawTool.none) _showUI = true;
              }),
            ),
            if (_unsaved)
              IconButton(
                icon: Icon(Icons.save, color: Colors.green.shade600),
                tooltip: '저장',
                onPressed: _save,
              ),
            IconButton(
              icon: Icon(Icons.chevron_left, color: _idx > 0 ? iconColor : iconColor.withValues(alpha: 0.3)),
              onPressed: _idx > 0 ? () => _navigate(-1) : null,
            ),
            Text(
              '${_idx + 1}/${widget.songList.length}',
              style: TextStyle(color: iconColor.withValues(alpha: 0.6), fontSize: 12),
            ),
            IconButton(
              icon: Icon(Icons.chevron_right,
                  color: _idx < widget.songList.length - 1 ? iconColor : iconColor.withValues(alpha: 0.3)),
              onPressed: _idx < widget.songList.length - 1 ? () => _navigate(1) : null,
            ),
            IconButton(
              icon: Icon(
                _toolbarAtBottom ? Icons.vertical_align_top : Icons.vertical_align_bottom,
                color: iconColor.withValues(alpha: 0.6),
                size: 20,
              ),
              tooltip: _toolbarAtBottom ? '툴바 위로' : '툴바 아래로',
              onPressed: _toggleToolbarPosition,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawToolbar() {
    final isPen = _tool == DrawTool.pen;
    final isHL = _tool == DrawTool.highlighter;
    final isErase = _tool == DrawTool.eraser;
    final double curW = isPen ? _penWidth : isHL ? _hlWidth : _eraserWidth;
    final double minW = isPen ? 1 : isHL ? 5 : 10;
    final double maxW = isPen ? 30 : isHL ? 50 : 80;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.88),
        border: const Border(top: BorderSide(color: Colors.white12)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ─ 툴 + 색상 + 액션 ─
            Row(
              children: [
                _toolBtn(Icons.draw, DrawTool.pen, '펜'),
                _toolBtn(Icons.highlight, DrawTool.highlighter, '형광펜'),
                _toolBtn(Icons.auto_fix_normal, DrawTool.eraser, '지우개'),
                const SizedBox(width: 4),
                const SizedBox(height: 32, child: VerticalDivider(color: Colors.white24, width: 1)),
                const SizedBox(width: 4),
                if (isPen)
                  for (final c in [Colors.red, Colors.blue, const Color(0xFF111111), Colors.deepOrange, Colors.purple])
                    _colorBtn(c),
                if (isHL)
                  for (final c in [Colors.yellow, Colors.cyanAccent, Colors.lightGreenAccent, Colors.pinkAccent, Colors.orangeAccent])
                    _hlColorBtn(c),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.undo, color: _strokes.isNotEmpty ? Colors.white : Colors.white24),
                  onPressed: _strokes.isNotEmpty ? _undo : null,
                  iconSize: 22,
                ),
                IconButton(
                  icon: Icon(Icons.redo, color: _redoStack.isNotEmpty ? Colors.white : Colors.white24),
                  onPressed: _redoStack.isNotEmpty ? _redo : null,
                  iconSize: 22,
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: _strokes.isNotEmpty ? Colors.redAccent : Colors.white24),
                  onPressed: _strokes.isNotEmpty ? _clearAll : null,
                  iconSize: 22,
                ),
                IconButton(
                  icon: Icon(Icons.save, color: _unsaved ? Colors.lightGreenAccent : Colors.white38),
                  onPressed: _unsaved ? _save : null,
                  iconSize: 22,
                ),
              ],
            ),
            // ─ 크기 슬라이더 ─
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 2),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Text(
                    isErase ? '지우개 ' : (isHL ? '형광펜 ' : '굵기 '),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  Text(
                    '${curW.round()}px',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.white70,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                        overlayColor: Colors.white24,
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      ),
                      child: Slider(
                        value: curW,
                        min: minW,
                        max: maxW,
                        onChanged: (v) => setState(() {
                          if (isPen) { _penWidth = v; }
                          else if (isHL) { _hlWidth = v; }
                          else { _eraserWidth = v; }
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolBtn(IconData icon, DrawTool t, String label) {
    final active = _tool == t;
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: () => setState(() => _tool = t),
        child: Container(
          width: 42, height: 42,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: active ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? Colors.white54 : Colors.white12,
            ),
          ),
          child: Icon(icon, color: active ? Colors.yellow : Colors.white70, size: 22),
        ),
      ),
    );
  }

  Widget _colorBtn(Color c) {
    final selected = _penColor.toARGB32() == c.toARGB32() && _tool == DrawTool.pen;
    return GestureDetector(
      onTap: () => setState(() { _penColor = c; _tool = DrawTool.pen; }),
      child: Container(
        width: 26, height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.white30,
            width: selected ? 2.5 : 1,
          ),
        ),
      ),
    );
  }

  Widget _hlColorBtn(Color c) {
    final selected = _hlColor.toARGB32() == c.toARGB32() && _tool == DrawTool.highlighter;
    return GestureDetector(
      onTap: () => setState(() { _hlColor = c; _tool = DrawTool.highlighter; }),
      child: Container(
        width: 26, height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.65),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.white30,
            width: selected ? 2.5 : 1,
          ),
        ),
      ),
    );
  }
}
