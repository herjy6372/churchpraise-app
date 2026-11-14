import 'package:flutter/material.dart';
import '../data/tag_definitions.dart';

class FilterSheet extends StatefulWidget {
  final Map<String, String> activeFilters;
  final bool favoritesOnly;
  final void Function(Map<String, String> filters, bool favoritesOnly) onApply;

  const FilterSheet({
    super.key,
    required this.activeFilters,
    required this.favoritesOnly,
    required this.onApply,
  });

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late Map<String, String> _filters;
  late bool _favoritesOnly;

  @override
  void initState() {
    super.initState();
    _filters = Map.from(widget.activeFilters);
    _favoritesOnly = widget.favoritesOnly;
  }

  void _toggleValue(String category, String value) {
    setState(() {
      if (_filters[category] == value) {
        _filters.remove(category);
      } else {
        _filters[category] = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = _filters.length + (_favoritesOnly ? 1 : 0);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Text('필터',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface)),
                  if (total > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('$total',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        setState(() => _filters = {}),
                    child: const Text('초기화'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  // 즐겨찾기
                  SwitchListTile(
                    title: const Text('⭐ 즐겨찾기만 보기',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    value: _favoritesOnly,
                    onChanged: (v) => setState(() => _favoritesOnly = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const Divider(),
                  // Tag categories
                  for (final category in TagCategory.all) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 14, bottom: 8),
                      child: Row(
                        children: [
                          Text(category,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurface)),
                          if (_filters.containsKey(category)) ...[
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _filters.remove(category)),
                              child: Icon(Icons.cancel,
                                  size: 16,
                                  color: cs.primary.withValues(alpha: 0.7)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: TagDefinitions.optionsFor(category).map((opt) {
                        final selected = _filters[category] == opt;
                        return FilterChip(
                          label: Text(opt),
                          selected: selected,
                          showCheckmark: false,
                          onSelected: (_) => _toggleValue(category, opt),
                          side: BorderSide(
                            color: selected
                                ? cs.primary
                                : cs.onSurface.withValues(alpha: 0.2),
                          ),
                          labelStyle: TextStyle(
                            color: selected ? cs.primary : cs.onSurface,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
            // Apply button
            SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onApply(_filters, _favoritesOnly);
                    },
                    child: Text(total == 0 ? '필터 없이 보기' : '필터 적용 ($total개)'),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
