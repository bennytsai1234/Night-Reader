import 'package:flutter/material.dart';
import 'package:reader/shared/theme/app_text_styles.dart';

class ReplaceEditOptions extends StatelessWidget {
  final bool isEnabled;
  final bool isRegex;
  final bool scopeTitle;
  final bool scopeContent;
  final Function(bool) onEnabledChanged;
  final Function(bool) onRegexChanged;
  final Function(bool) onTitleChanged;
  final Function(bool) onContentChanged;

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
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 0,
      children: [
        _buildChip('已啟用', isEnabled, onEnabledChanged),
        _buildChip('正則', isRegex, onRegexChanged),
        _buildChip('標題', scopeTitle, onTitleChanged),
        _buildChip('正文', scopeContent, onContentChanged),
      ],
    );
  }

  Widget _buildChip(String label, bool value, Function(bool) onChanged) {
    return FilterChip(
      label: Text(label, style: AppTextStyles.labelSm),
      selected: value,
      onSelected: onChanged,
      visualDensity: VisualDensity.compact,
    );
  }
}
