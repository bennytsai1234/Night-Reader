import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/models/highlight.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_sheet.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/highlight_marks.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/grouped_list_skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

/// 點正文上已畫的標註打開的面板：畫到的字、換顏色、換底色或底線、備忘、
/// 複製、刪除。換了就存，不另按儲存；備忘在面板收起時存。
class ReaderV2HighlightSheet extends StatefulWidget {
  const ReaderV2HighlightSheet({
    super.key,
    required this.highlight,
    required this.onChanged,
    required this.onDelete,
  });

  final Highlight highlight;

  /// 換了顏色或樣子：照原本的編號存回去。
  final ValueChanged<Highlight> onChanged;

  /// 按了「刪除」：面板已經收起，提示與復原由呼叫端負責。
  final ValueChanged<Highlight> onDelete;

  @override
  State<ReaderV2HighlightSheet> createState() => _ReaderV2HighlightSheetState();
}

class _ReaderV2HighlightSheetState extends State<ReaderV2HighlightSheet> {
  late Highlight _highlight = widget.highlight;
  late final TextEditingController _note = TextEditingController(
    text: widget.highlight.note,
  );
  bool _deleted = false;

  /// 目前的樣子，備忘照輸入框裡的字。
  Highlight get _current => _highlight.copyWith(note: _note.text.trim());

  void _update(Highlight next) {
    setState(() => _highlight = next);
    widget.onChanged(next);
  }

  @override
  void dispose() {
    // 備忘改了就在收起時存一次，不是每打一個字存一次。
    final current = _current;
    if (!_deleted && current.note != _highlight.note) {
      widget.onChanged(current);
    }
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 面板不會自己避開鍵盤：寫備忘時整個面板墊高鍵盤的高度。
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ReaderV2SheetScaffold(
        title: '標註',
        // 看得到面板上方那一段正文，換顏色時就看得到效果。
        maxHeightFactor: 0.7,
        children: [
          GroupedSection(
            children: [
              GroupedRow(
                title: _highlight.quote,
                maxTitleLines: 4,
                subtitle: _highlight.chapterTitle,
                maxSubtitleLines: 1,
              ),
            ],
          ),
          GroupedSection(
            header: '顏色',
            children: [
              HighlightColorRow(
                selected: _highlight.color,
                onSelected: (color) => _update(_current.copyWith(color: color)),
              ),
            ],
          ),
          GroupedSection(
            header: '樣子',
            children: [
              for (final style in HighlightStyle.values)
                GroupedRow(
                  title: style.label,
                  showChevron: false,
                  trailing: style == _highlight.style
                      ? Icon(
                          Icons.check_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () => _update(_current.copyWith(style: style)),
                ),
            ],
          ),
          GroupedSection(
            header: '備忘',
            children: [
              GroupedTextFieldRow(
                controller: _note,
                hintText: '寫下自己的話',
                minLines: 2,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
              ),
            ],
          ),
          GroupedSection(
            children: [
              GroupedRow(
                title: '複製',
                showChevron: false,
                onTap: () {
                  unawaited(
                    Clipboard.setData(ClipboardData(text: _highlight.quote)),
                  );
                  Navigator.of(context).pop();
                },
              ),
              GroupedRow(
                title: '刪除',
                destructive: true,
                showChevron: false,
                onTap: () {
                  _deleted = true;
                  Navigator.of(context).pop();
                  widget.onDelete(_current);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 標註的色票：一排圓點，選中的打勾。
class HighlightColorRow extends StatelessWidget implements GroupedSkeletonItem {
  const HighlightColorRow({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final HighlightColor selected;
  final ValueChanged<HighlightColor> onSelected;

  static const double _swatchSize = 30;
  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: AppGrouped.rowPadding,
    vertical: AppSpacing.md,
  );

  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) {
    final inner = width - _padding.horizontal;
    final count = HighlightColor.values.length;
    final gap = (inner - _swatchSize * count) / (count - 1);
    return GroupedItemShape(
      _swatchSize,
      marks: [
        for (var i = 0; i < count; i++)
          SkeletonShape(
            Rect.fromLTWH(i * (_swatchSize + gap), 0, _swatchSize, _swatchSize),
            radius: AppRadius.pillShape,
          ),
      ],
    ).padded(_padding);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: _padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final color in HighlightColor.values)
            Semantics(
              button: true,
              selected: color == selected,
              label: color.label,
              excludeSemantics: true,
              onTap: () => onSelected(color),
              child: InkResponse(
                onTap: () => onSelected(color),
                radius: _swatchSize,
                child: Container(
                  width: _swatchSize,
                  height: _swatchSize,
                  decoration: BoxDecoration(
                    color: color.value,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color == selected
                          ? scheme.primary
                          : scheme.outlineVariant,
                      width: color == selected ? 2.5 : 1,
                    ),
                  ),
                  child: color == selected
                      ? Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: Colors.black.withValues(alpha: 0.7),
                        )
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
