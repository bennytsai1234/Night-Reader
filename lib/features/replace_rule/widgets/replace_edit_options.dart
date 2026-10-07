import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

/// 替換規則的開關選項：啟用、正則、作用於標題、作用於正文。
class ReplaceEditOptions extends StatelessWidget {
  final bool isEnabled;
  final bool isRegex;
  final bool scopeTitle;
  final bool scopeContent;
  final Function(bool) onEnabledChanged;
  final Function(bool) onRegexChanged;
  final Function(bool) onTitleChanged;
  final Function(bool) onContentChanged;

  /// 分組卡片外距；放在已有左右內距的面板內時傳 [EdgeInsets.zero]。
  final EdgeInsetsGeometry? margin;

  const ReplaceEditOptions({
    super.key,
    required this.isEnabled,
    required this.isRegex,
    required this.scopeTitle,
    required this.scopeContent,
    required this.onEnabledChanged,
    required this.onRegexChanged,
    required this.onTitleChanged,
    required this.onContentChanged,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return GroupedSection(
      margin: margin,
      header: '選項',
      children: [
        GroupedSwitchRow(
          title: '啟用規則',
          value: isEnabled,
          onChanged: onEnabledChanged,
        ),
        GroupedSwitchRow(
          title: '使用正則',
          value: isRegex,
          onChanged: onRegexChanged,
        ),
        GroupedSwitchRow(
          title: '作用於標題',
          value: scopeTitle,
          onChanged: onTitleChanged,
        ),
        GroupedSwitchRow(
          title: '作用於正文',
          value: scopeContent,
          onChanged: onContentChanged,
        ),
      ],
    );
  }
}
