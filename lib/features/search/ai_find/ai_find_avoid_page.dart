import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/ai_find/ai_find_avoid.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/widgets/popups/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass/glass.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:night_reader/shared/widgets/lists/swipe_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AI 找書「不想看的」清單（docs/design/screens.md「AI 找書」）：一項一列，
/// 點了修改、往左滑刪除，最後一列「新增」。改了就存，跟著設定同步。
class AiFindAvoidPage extends StatefulWidget {
  const AiFindAvoidPage({super.key, required this.prefs});

  final SharedPreferences prefs;

  @override
  State<AiFindAvoidPage> createState() => _AiFindAvoidPageState();
}

class _AiFindAvoidPageState extends State<AiFindAvoidPage> {
  late List<String> _items = AiFindAvoid.read(widget.prefs);

  Future<void> _save(List<String> items) async {
    setState(() => _items = items);
    await AiFindAvoid.write(widget.prefs, items);
  }

  /// 新增時 [index] 是 null；一次打「女頻、後宮」是兩項。修改成好幾項時
  /// 第一項換掉原本那項，其餘接在它後面。
  Future<void> _edit({int? index}) async {
    final typed = await showStatefulAppAlert<String>(
      context: context,
      fieldTexts: [if (index != null) _items[index] else ''],
      builder: (dialogContext, _, fields) => AppAlert<bool>(
        title: index == null ? '新增不想看的' : '修改',
        content: AlertTextField(
          controller: fields.single,
          autofocus: true,
          hintText: '例如：女頻、後宮',
        ),
        actions: const [
          AppAlertAction(label: '取消', value: false),
          AppAlertAction(label: '確定', value: true, isDefault: true),
        ],
        onAction: (confirmed) => confirmed
            ? Navigator.of(dialogContext).pop(fields.single.text)
            : Navigator.of(dialogContext).pop(),
      ),
    );
    if (typed == null || !mounted) return;
    final others = [
      for (var i = 0; i < _items.length; i++)
        if (i != index) _items[i],
    ];
    final added = AiFindAvoid.split(typed, existing: others);
    if (index == null) {
      if (added.isNotEmpty) await _save([..._items, ...added]);
      return;
    }
    // 修改成空的就是刪掉那一項。
    await _save([...others.take(index), ...added, ...others.skip(index)]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    appBar: const GlassNavHeader(title: '不想看的'),
    body: SwipeActionsGroup(
      child: GroupedListView(
        children: [
          GroupedSection(
            children: [
              for (final (index, item) in _items.indexed)
                SwipeActions(
                  key: ValueKey(item),
                  trailing: [
                    SwipeAction(
                      label: '刪除',
                      icon: Icons.delete_outline_rounded,
                      color: AppTint.rust.color,
                      destructive: true,
                      onPressed: () =>
                          unawaited(_save([..._items]..removeAt(index))),
                    ),
                  ],
                  child: _ItemRow(
                    title: item,
                    onTap: () => unawaited(_edit(index: index)),
                  ),
                ),
              GroupedRow(
                title: '新增',
                accent: true,
                showChevron: false,
                onTap: () => unawaited(_edit()),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// 一項：不透明底讓滑動動作藏在列下方（同書源分組管理）。
class _ItemRow extends StatelessWidget implements GroupedRowLike {
  const _ItemRow({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  bool get hasLeading => false;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppChrome.of(context).groupedSurface,
    // 使用者自己寫的字照原文，不跟著介面語言轉繁簡（ADR 0066）。
    child: GroupedRow(
      title: title,
      translateTitle: false,
      showChevron: false,
      onTap: onTap,
    ),
  );
}
