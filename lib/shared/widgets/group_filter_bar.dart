import 'package:flutter/material.dart';

import '../theme/app_chrome.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_tokens.dart';
import 'app_bottom_sheet.dart';
import 'glass.dart';
import 'search_field.dart';

/// [GroupFilterBar] 的單一選項：分組值、顯示名稱與其中的書源數。
@immutable
class GroupFilterOption<T> {
  const GroupFilterOption(this.value, this.label, {this.count});

  final T value;
  final String label;
  final int? count;
}

/// 書源分組篩選列：「全部」固定在最左，其餘分組為可橫向捲動的獨立膠囊，
/// 最右的格狀鈕打開面板一次列出所有分組。
///
/// 為受控元件：點擊已選取的分組不會回報。
class GroupFilterBar<T> extends StatefulWidget {
  const GroupFilterBar({
    super.key,
    required this.all,
    required this.groups,
    required this.selected,
    required this.onChanged,
  });

  static const double height = GlassCapsule.height;

  /// 「全部」選項，固定不隨捲動移走。
  final GroupFilterOption<T> all;
  final List<GroupFilterOption<T>> groups;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  State<GroupFilterBar<T>> createState() => _GroupFilterBarState<T>();
}

class _GroupFilterBarState<T> extends State<GroupFilterBar<T>> {
  final Map<T, GlobalKey> _chipKeys = <T, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _revealSelected(animate: false);
  }

  @override
  void didUpdateWidget(GroupFilterBar<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) _revealSelected(animate: true);
  }

  /// 選到捲動區裡的分組時（包括從面板選的），把它捲進可視範圍。
  void _revealSelected({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chipContext = _chipKeys[widget.selected]?.currentContext;
      if (!mounted || chipContext == null) return;
      Scrollable.ensureVisible(
        chipContext,
        alignment: 0.5,
        duration: animate ? AppMotion.spring : Duration.zero,
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _select(T value) {
    if (value == widget.selected) return;
    widget.onChanged(value);
  }

  Future<void> _openPicker() async {
    final picked = await AppBottomSheet.showCustom<_Picked<T>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GroupPickerSheet<T>(
        all: widget.all,
        groups: widget.groups,
        selected: widget.selected,
      ),
    );
    if (!mounted || picked == null) return;
    _select(picked.value);
  }

  Widget _chip(GroupFilterOption<T> option, {Key? key}) {
    return GlassCapsule(
      key: key,
      label: option.label,
      count: option.count,
      selected: option.value == widget.selected,
      onTap: () => _select(option.value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final values = widget.groups.map((group) => group.value).toSet();
    _chipKeys.removeWhere((value, _) => !values.contains(value));

    return SizedBox(
      height: GroupFilterBar.height,
      child: Row(
        children: [
          _chip(widget.all),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: widget.groups.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (_, index) {
                final group = widget.groups[index];
                return _chip(
                  group,
                  key: _chipKeys.putIfAbsent(group.value, GlobalKey.new),
                );
              },
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          GlassIconButton(
            icon: Icons.grid_view_rounded,
            tooltip: '全部分組',
            size: GroupFilterBar.height,
            iconSize: 17,
            onPressed: _openPicker,
          ),
        ],
      ),
    );
  }
}

/// 面板的選取結果；包一層才分得出「選了值為 null 的全部」與「直接關閉」。
class _Picked<T> {
  const _Picked(this.value);

  final T value;
}

/// 一次列出所有分組的面板，可用名稱篩選；點選即關閉並套用。
class _GroupPickerSheet<T> extends StatefulWidget {
  const _GroupPickerSheet({
    required this.all,
    required this.groups,
    required this.selected,
  });

  final GroupFilterOption<T> all;
  final List<GroupFilterOption<T>> groups;
  final T selected;

  @override
  State<_GroupPickerSheet<T>> createState() => _GroupPickerSheetState<T>();
}

class _GroupPickerSheetState<T> extends State<_GroupPickerSheet<T>> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _chip(GroupFilterOption<T> option) {
    return GlassCapsule(
      label: option.label,
      count: option.count,
      selected: option.value == widget.selected,
      blur: false,
      tint: AppChrome.of(context).groupedSurface,
      onTap: () => Navigator.pop(context, _Picked<T>(option.value)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final matches = query.isEmpty
        ? widget.groups
        : widget.groups
              .where((group) => group.label.toLowerCase().contains(query))
              .toList();

    return AppBottomSheet(
      title: '選擇分組',
      children: [
        SearchField(
          controller: _searchController,
          hintText: '搜尋分組',
          textInputAction: TextInputAction.done,
          onChanged: (value) => setState(() => _query = value.trim()),
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (query.isEmpty) _chip(widget.all),
            for (final group in matches) _chip(group),
          ],
        ),
        if (matches.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(
              child: Text(
                '找不到符合的分組',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppChrome.of(context).sectionText,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
