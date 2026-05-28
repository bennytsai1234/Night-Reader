import 'package:flutter/material.dart';
import 'package:reader/core/models/replace_rule.dart';
import 'package:reader/features/replace_rule/widgets/replace_edit_form.dart';
import 'package:reader/features/replace_rule/widgets/replace_edit_options.dart';
import 'package:reader/features/replace_rule/widgets/replace_edit_test_panel.dart';
import 'package:reader/shared/widgets/app_bottom_sheet.dart';

class ReaderV2ReplaceRuleEditorSheet extends StatefulWidget {
  const ReaderV2ReplaceRuleEditorSheet({
    super.key,
    this.rule,
    required this.onSave,
  });

  final ReplaceRule? rule;
  final Future<void> Function(ReplaceRule rule) onSave;

  static Future<void> show(
    BuildContext context, {
    ReplaceRule? rule,
    required Future<void> Function(ReplaceRule rule) onSave,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => ReaderV2ReplaceRuleEditorSheet(rule: rule, onSave: onSave),
    );
  }

  @override
  State<ReaderV2ReplaceRuleEditorSheet> createState() =>
      _ReaderV2ReplaceRuleEditorSheetState();
}

class _ReaderV2ReplaceRuleEditorSheetState
    extends State<ReaderV2ReplaceRuleEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _groupCtrl;
  late final TextEditingController _timeoutCtrl;
  late final TextEditingController _patternCtrl;
  late final TextEditingController _replacementCtrl;
  late final TextEditingController _scopeCtrl;
  late final TextEditingController _excludeScopeCtrl;
  final TextEditingController _testInputCtrl = TextEditingController(
    text: '這是一段測試文字，包含 junk123 內容。',
  );

  String _testResult = '';
  bool _isEnabled = true;
  bool _isRegex = true;
  bool _scopeTitle = false;
  bool _scopeContent = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _nameCtrl = TextEditingController(text: rule?.name ?? '');
    _groupCtrl = TextEditingController(text: rule?.group ?? '');
    _timeoutCtrl = TextEditingController(
      text: (rule?.timeoutMillisecond ?? 3000).toString(),
    );
    _patternCtrl = TextEditingController(text: rule?.pattern ?? '');
    _replacementCtrl = TextEditingController(text: rule?.replacement ?? '');
    _scopeCtrl = TextEditingController(text: rule?.scope ?? '');
    _excludeScopeCtrl = TextEditingController(text: rule?.excludeScope ?? '');
    _isEnabled = rule?.isEnabled ?? true;
    _isRegex = rule?.isRegex ?? true;
    _scopeTitle = rule?.scopeTitle ?? false;
    _scopeContent = rule?.scopeContent ?? true;
    for (final controller in [_patternCtrl, _replacementCtrl, _testInputCtrl]) {
      controller.addListener(_runTest);
    }
    _runTest();
  }

  @override
  void dispose() {
    for (final controller in [
      _nameCtrl,
      _groupCtrl,
      _timeoutCtrl,
      _patternCtrl,
      _replacementCtrl,
      _scopeCtrl,
      _excludeScopeCtrl,
      _testInputCtrl,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _runTest() {
    final rule = ReplaceRule(
      pattern: _patternCtrl.text,
      replacement: _replacementCtrl.text,
      isRegex: _isRegex,
    );
    setState(() {
      _testResult = rule.apply(_testInputCtrl.text);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    final rule = ReplaceRule(
      id: widget.rule?.id ?? 0,
      name: _nameCtrl.text.trim(),
      group: _groupCtrl.text.trim(),
      pattern: _patternCtrl.text.trim(),
      replacement: _replacementCtrl.text,
      scope: _scopeCtrl.text.trim(),
      excludeScope: _excludeScopeCtrl.text.trim(),
      timeoutMillisecond: int.tryParse(_timeoutCtrl.text) ?? 3000,
      isEnabled: _isEnabled,
      isRegex: _isRegex,
      scopeTitle: _scopeTitle,
      scopeContent: _scopeContent,
      order: widget.rule?.order ?? 0,
    );
    if (!rule.isValid()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('規則格式無效，請檢查正則內容')));
      return;
    }
    setState(() {
      _saving = true;
    });
    await widget.onSave(rule);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AppBottomSheet(
      title: widget.rule == null ? '新增規則' : '編輯規則',
      icon: Icons.rule_rounded,
      trailing: TextButton(
        onPressed: _saving ? null : _save,
        child: const Text('儲存'),
      ),
      children: [
        Form(
          key: _formKey,
          child: Column(
            children: [
              ReplaceEditForm(
                nameCtrl: _nameCtrl,
                groupCtrl: _groupCtrl,
                timeoutCtrl: _timeoutCtrl,
                patternCtrl: _patternCtrl,
                replacementCtrl: _replacementCtrl,
              ),
              const SizedBox(height: 16),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 12),
                title: const Text('進階範圍設定'),
                children: [
                  TextFormField(
                    controller: _scopeCtrl,
                    decoration: const InputDecoration(
                      labelText: '作用範圍 (書名/書源URL)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _excludeScopeCtrl,
                    decoration: const InputDecoration(
                      labelText: '排除範圍 (書名/書源URL)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              ReplaceEditOptions(
                isEnabled: _isEnabled,
                isRegex: _isRegex,
                scopeTitle: _scopeTitle,
                scopeContent: _scopeContent,
                onEnabledChanged: (value) => setState(() => _isEnabled = value),
                onRegexChanged: (value) {
                  setState(() => _isRegex = value);
                  _runTest();
                },
                onTitleChanged: (value) => setState(() => _scopeTitle = value),
                onContentChanged:
                    (value) => setState(() => _scopeContent = value),
              ),
              const SizedBox(height: 16),
              ReplaceEditTestPanel(
                testInputCtrl: _testInputCtrl,
                testResult: _testResult,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
