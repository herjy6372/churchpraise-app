import 'package:flutter/material.dart';
import '../models/song.dart';
import '../data/tag_definitions.dart';
import '../services/tag_service.dart';

class TagEditorSheet extends StatefulWidget {
  final Song song;

  const TagEditorSheet({super.key, required this.song});

  @override
  State<TagEditorSheet> createState() => _TagEditorSheetState();
}

class _TagEditorSheetState extends State<TagEditorSheet> {
  late Map<String, String> _draft;

  @override
  void initState() {
    super.initState();
    _draft = Map.from(TagService.instance.getTagsFor(widget.song.id));
  }

  void _toggle(String category, String value) {
    setState(() {
      if (_draft[category] == value) {
        _draft.remove(category);
      } else {
        _draft[category] = value;
      }
    });
  }

  Future<void> _save() async {
    // Write each category
    for (final category in TagCategory.all) {
      await TagService.instance.setTag(
        widget.song.id,
        category,
        _draft[category],
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('태그 편집',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: cs.onSurface)),
                        Text(widget.song.title,
                            style: TextStyle(
                                fontSize: 13,
                                color: cs.onSurface.withValues(alpha: 0.6)),
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _draft.clear()),
                    child: const Text('전체 삭제'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Tag categories
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  for (final category in TagCategory.all) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 14, bottom: 8),
                      child: Row(
                        children: [
                          Text(
                            category,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (_draft.containsKey(category)) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _draft[category]!,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onPrimaryContainer,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: TagDefinitions.optionsFor(category).map((opt) {
                        final selected = _draft[category] == opt;
                        return ChoiceChip(
                          label: Text(opt),
                          selected: selected,
                          showCheckmark: false,
                          onSelected: (_) => _toggle(category, opt),
                          selectedColor: cs.primaryContainer,
                          labelStyle: TextStyle(
                            color: selected ? cs.onPrimaryContainer : null,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          side: BorderSide(
                            color: selected
                                ? cs.primary
                                : cs.onSurface.withValues(alpha: 0.2),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
            // Save button
            SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check),
                    label: const Text('저장'),
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
