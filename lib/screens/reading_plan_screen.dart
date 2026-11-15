import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../services/bible_service.dart';
import '../services/reading_plan_service.dart';

/// 2027년 성경읽기표 (창세기~요한계시록, 365일)
/// 날짜를 누르면 그날 첫 장으로 이동하고, 체크박스로 읽음을 표시합니다.
class ReadingPlanScreen extends StatefulWidget {
  const ReadingPlanScreen({super.key});

  @override
  State<ReadingPlanScreen> createState() => _ReadingPlanScreenState();
}

class _ReadingPlanScreenState extends State<ReadingPlanScreen> {
  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  final _plan = ReadingPlanService.instance;

  @override
  void initState() {
    super.initState();
    _plan.ensureLoaded();
  }

  String _dateLabel(DateTime d) =>
      '${d.month}월 ${d.day}일 (${_weekdays[d.weekday - 1]})';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = _plan.todayIndex();
    final shortNames = BibleService.shortNames;

    return Scaffold(
      appBar: AppBar(title: const Text('2027 성경읽기표')),
      body: ValueListenableBuilder<Set<int>>(
        valueListenable: _plan.done,
        builder: (context, done, _) {
          final percent = done.length / ReadingPlanService.totalDays;
          final focus = today ?? 0;
          final focusDay = _plan.days[focus];
          return Column(
            children: [
              // 진도 + 오늘(또는 첫날) 분량
              Container(
                width: double.infinity,
                color: cs.secondaryContainer.withValues(alpha: 0.5),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '진도 ${done.length} / ${ReadingPlanService.totalDays}일',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const Spacer(),
                        Text('${(percent * 100).toStringAsFixed(1)}%',
                            style: TextStyle(
                                color: cs.primary,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: percent,
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      today == null
                          ? '2027년 1월 1일에 시작합니다 · 첫날 분량'
                          : '오늘 (${_dateLabel(focusDay.date)})',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ReadingPlanService.rangeLabel(focusDay, shortNames),
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => Navigator.pop(
                                context, focusDay.chapters.first),
                            icon: const Icon(Icons.menu_book, size: 18),
                            label: const Text('읽으러 가기'),
                          ),
                        ),
                        if (today != null) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _plan.setDone(
                                  focus, !done.contains(focus)),
                              icon: Icon(
                                done.contains(focus)
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 18,
                              ),
                              label: Text(
                                  done.contains(focus) ? '읽음' : '읽음 표시'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ScrollablePositionedList.builder(
                  initialScrollIndex: (focus - 2).clamp(0, 364),
                  itemCount: ReadingPlanService.totalDays,
                  itemBuilder: (context, i) {
                    final day = _plan.days[i];
                    final isDone = done.contains(i);
                    final isToday = i == today;
                    final showMonth = i == 0 ||
                        _plan.days[i - 1].date.month != day.date.month;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showMonth)
                          Container(
                            color: cs.surfaceContainerHigh,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            child: Text(
                              '${day.date.month}월',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ListTile(
                          dense: true,
                          tileColor: isToday
                              ? cs.primaryContainer.withValues(alpha: 0.5)
                              : null,
                          leading: Checkbox(
                            value: isDone,
                            onChanged: (v) => _plan.setDone(i, v ?? false),
                          ),
                          title: Text(
                            ReadingPlanService.rangeLabel(day, shortNames),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              decoration:
                                  isDone ? TextDecoration.lineThrough : null,
                              color: isDone ? cs.onSurfaceVariant : null,
                            ),
                          ),
                          subtitle: Text(
                              '${i + 1}일차 · ${_dateLabel(day.date)}${isToday ? ' · 오늘' : ''}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              Navigator.pop(context, day.chapters.first),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
