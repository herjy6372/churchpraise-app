import 'package:flutter/material.dart';
import '../data/responsive_reading_data.dart';

class ResponsiveReadingDetailScreen extends StatefulWidget {
  final int initialIndex;
  final List<ResponsiveReading> readings;

  const ResponsiveReadingDetailScreen({
    super.key,
    required this.initialIndex,
    required this.readings,
  });

  @override
  State<ResponsiveReadingDetailScreen> createState() =>
      _ResponsiveReadingDetailScreenState();
}

class _ResponsiveReadingDetailScreenState
    extends State<ResponsiveReadingDetailScreen> {
  late int _idx;
  double _fontSize = 18.0;

  @override
  void initState() {
    super.initState();
    _idx = widget.initialIndex;
  }

  ResponsiveReading get _reading => widget.readings[_idx];

  void _navigate(int delta) {
    final next = _idx + delta;
    if (next < 0 || next >= widget.readings.length) return;
    setState(() => _idx = next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reading = _reading;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '교독문 ${reading.number}번',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            Text(
              reading.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.text_decrease),
            tooltip: '글자 작게',
            onPressed: _fontSize > 13
                ? () => setState(() => _fontSize -= 2)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.text_increase),
            tooltip: '글자 크게',
            onPressed: _fontSize < 30
                ? () => setState(() => _fontSize += 2)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: '이전 교독문',
            onPressed: _idx > 0 ? () => _navigate(-1) : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: '다음 교독문',
            onPressed:
                _idx < widget.readings.length - 1 ? () => _navigate(1) : null,
          ),
        ],
      ),
      body: Column(
        children: [
          const Divider(height: 1),
          // 범례 바
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: cs.surfaceContainerLow,
            child: Row(
              children: [
                _RoleBadge(role: ReadingRole.leader),
                const SizedBox(width: 6),
                Text('인도자',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                const SizedBox(width: 16),
                _RoleBadge(role: ReadingRole.congregation),
                const SizedBox(width: 6),
                Text('회중 (굵은 글씨)',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
                const SizedBox(width: 16),
                _RoleBadge(role: ReadingRole.together),
                const SizedBox(width: 6),
                Text('다같이',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.primary)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              itemCount: reading.verses.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final v = reading.verses[i];
                final isLeader = v.role == ReadingRole.leader;
                final isTogether = v.role == ReadingRole.together;

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isTogether
                        ? cs.primaryContainer.withValues(alpha: 0.45)
                        : isLeader
                            ? cs.surface
                            : cs.surfaceContainerHigh.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isTogether
                          ? cs.primary.withValues(alpha: 0.4)
                          : isLeader
                              ? cs.outlineVariant.withValues(alpha: 0.6)
                              : cs.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: _RoleBadge(role: v.role),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          v.text,
                          style: TextStyle(
                            fontSize: _fontSize,
                            height: 1.55,
                            fontWeight:
                                isLeader ? FontWeight.normal : FontWeight.w700,
                            color: isTogether
                                ? cs.primary
                                : cs.onSurface,
                          ),
                        ),
                      ),
                    ],
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

class _RoleBadge extends StatelessWidget {
  final ReadingRole role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final String label;
    final Color bg;
    final Color fg;

    switch (role) {
      case ReadingRole.leader:
        label = '인도자';
        bg = cs.surfaceContainerHighest;
        fg = cs.onSurfaceVariant;
        break;
      case ReadingRole.congregation:
        label = '회중';
        bg = cs.primaryContainer;
        fg = cs.onPrimaryContainer;
        break;
      case ReadingRole.together:
        label = '다같이';
        bg = cs.primary;
        fg = cs.onPrimary;
        break;
    }

    return Container(
      constraints: const BoxConstraints(minWidth: 46),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }
}
