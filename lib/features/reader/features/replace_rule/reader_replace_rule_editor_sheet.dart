import 'dart:async';

import 'package:night_reader/core/exception/user_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/features/replace_rule/replace_rule_exchange.dart';
import 'package:night_reader/features/replace_rule/replace_rule_preview.dart';
import 'package:night_reader/features/replace_rule/widgets/replace_edit_form.dart';
import 'package:night_reader/features/replace_rule/widgets/replace_edit_options.dart';
import 'package:night_reader/features/replace_rule/widgets/replace_edit_test_panel.dart';
import 'package:night_reader/shared/widgets/popups/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/glass/glass.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:night_reader/core/chinese/ui_language.dart';

class ReaderReplaceRuleEditorSheet extends StatefulWidget {
  const ReaderReplaceRuleEditorSheet({
    super.key,
    this.rule,
    this.testSample,
    required this.onSave,
  });

  /// 要編輯的規則；編號是 0（還沒存過，例如選字「替換」先填好的）時是
  /// 新增。
  final ReplaceRule? rule;

  /// 即時測試先放的字；沒給用預設的範例。
  final String? testSample;
  final Future<void> Function(ReplaceRule rule) onSave;

  /// 打開編輯畫面，關掉之後才完成。按了「儲存」、還沒存好就被關掉（返回鍵、
  /// 點遮罩、往下拉）時，等存好（或存不進去）才完成：呼叫的一方關掉之後看
  /// 存了沒、要不要重載正文，看到的是真的結果。
  static Future<void> show(
    BuildContext context, {
    ReplaceRule? rule,
    String? testSample,
    required Future<void> Function(ReplaceRule rule) onSave,
    BoxConstraints? constraints,
  }) async {
    Future<void>? saving;
    await AppBottomSheet.showCustom<void>(
      context: context,
      // 從閱讀器打開時對齊正文（ReaderMenuSheet.constraintsFor）。
      constraints: constraints,
      isScrollControlled: true,
      builder: (_) => ReaderReplaceRuleEditorSheet(
        rule: rule,
        testSample: testSample,
        onSave: (rule) => saving = onSave(rule),
      ),
    );
    // 存不進去的錯誤由編輯畫面提示（還開著時）；這裡只等它結束。
    await saving?.catchError((Object _) {});
  }

  @override
  State<ReaderReplaceRuleEditorSheet> createState() =>
      _ReaderReplaceRuleEditorSheetState();
}

class _ReaderReplaceRuleEditorSheetState
    extends State<ReaderReplaceRuleEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _groupCtrl;
  late final TextEditingController _timeoutCtrl;
  late final TextEditingController _patternCtrl;
  late final TextEditingController _replacementCtrl;
  late final TextEditingController _scopeCtrl;
  late final TextEditingController _excludeScopeCtrl;
  late final TextEditingController _testInputCtrl = TextEditingController(
    text: widget.testSample ?? '這是一段測試文字，包含 junk123 內容。',
  );

  final ReplaceRulePreview _preview = ReplaceRulePreview();
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
    // 名稱與逾時也會進試跑（逾時的期限、停下時的說明）。
    for (final controller in [
      _nameCtrl,
      _timeoutCtrl,
      _patternCtrl,
      _replacementCtrl,
      _testInputCtrl,
    ]) {
      controller.addListener(_runTest);
    }
    _runTest();
  }

  @override
  void dispose() {
    _preview.cancel();
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

  /// 每改一個字就重跑一次；還沒跑完的上一次直接作廢（[ReplaceRulePreview]）。
  void _runTest() {
    final rule = ReplaceRule(
      name: _nameCtrl.text.trim(),
      pattern: _patternCtrl.text,
      replacement: _replacementCtrl.text,
      isRegex: _isRegex,
      timeoutMillisecond: int.tryParse(_timeoutCtrl.text) ?? 3000,
    );
    unawaited(
      _preview
          .run([rule], _testInputCtrl.text)
          .then(
            (result) {
              if (!mounted || result == null) return;
              // 規則跑出來的字照原文，逾時這類 App 的說明照介面語言
              // （ADR 0066）；結果區整段不再轉。
              setState(
                () => _testResult = result is ReplaceRulePreviewDone
                    ? result.text
                    : context.ui(result.display),
              );
            },
            onError: (Object error) {
              if (!mounted) return;
              setState(
                () => _testResult = context.ui(failureMessage('執行測試', error)),
              );
            },
          ),
    );
  }

  /// 畫面上的這條規則：儲存與「複製規則」都用它。編號與順序是打開的那一條
  /// 的，畫面上不能改。
  ReplaceRule _ruleFromForm() {
    return ReplaceRule(
      id: widget.rule?.id ?? 0,
      name: _nameCtrl.text.trim(),
      group: _groupCtrl.text.trim(),
      // 與規則除錯用同一個字串；前後空白是替換內容的一部分。
      pattern: _patternCtrl.text,
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
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    final rule = _ruleFromForm();
    if (!rule.isValid()) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: UiText('規則格式無效，請檢查正則內容')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(rule);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: UiText(failureMessage('儲存規則', error))));
      setState(() => _saving = false);
    }
  }

  /// 把畫面上的這條規則複製成 JSON（Legado 讀得懂，同 Legado 編輯頁的
  /// 「複製規則」）。
  Future<void> _copyRule() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Clipboard.setData(
        ClipboardData(text: encodeReplaceRule(_ruleFromForm())),
      );
      messenger.showSnackBar(const SnackBar(content: UiText('已複製至剪貼簿')));
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: UiText(failureMessage('複製規則', error))),
      );
    }
  }

  /// 從剪貼簿貼一條規則進來：欄位換成那一條的，編號與順序留著這一條的
  /// （同 Legado）；按「儲存」才存。剪貼簿裡不是規則時欄位不動。
  Future<void> _pasteRule() async {
    final messenger = ScaffoldMessenger.of(context);
    final ClipboardData? data;
    try {
      data = await Clipboard.getData(Clipboard.kTextPlain);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: UiText(failureMessage('貼上規則', error))),
      );
      return;
    }
    if (!mounted) return;
    final rule = decodeOneReplaceRule(data?.text);
    if (rule == null) {
      messenger.showSnackBar(const SnackBar(content: UiText('剪貼簿裡不是替換規則')));
      return;
    }
    setState(() {
      _nameCtrl.text = rule.name;
      _groupCtrl.text = rule.group ?? '';
      _timeoutCtrl.text = rule.timeoutMillisecond.toString();
      _patternCtrl.text = rule.pattern;
      _replacementCtrl.text = rule.replacement;
      _scopeCtrl.text = rule.scope ?? '';
      _excludeScopeCtrl.text = rule.excludeScope ?? '';
      _isEnabled = rule.isEnabled;
      _isRegex = rule.isRegex;
      _scopeTitle = rule.scopeTitle;
      _scopeContent = rule.scopeContent;
    });
    _runTest();
  }

  @override
  Widget build(BuildContext context) {
    return AppBottomSheet(
      title: (widget.rule?.id ?? 0) == 0 ? '新增規則' : '編輯規則',
      icon: Icons.rule_rounded,
      trailing: GlassTextButton(
        label: _saving ? '儲存中…' : '儲存',
        emphasized: true,
        onPressed: _saving ? null : _save,
      ),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReplaceEditForm(
                margin: EdgeInsets.zero,
                nameCtrl: _nameCtrl,
                groupCtrl: _groupCtrl,
                timeoutCtrl: _timeoutCtrl,
                patternCtrl: _patternCtrl,
                replacementCtrl: _replacementCtrl,
              ),
              GroupedSection(
                margin: EdgeInsets.zero,
                children: [
                  GroupedTextFieldRow(
                    controller: _scopeCtrl,
                    label: '作用範圍',
                    hintText: '書名/書源URL',
                  ),
                  GroupedTextFieldRow(
                    controller: _excludeScopeCtrl,
                    label: '排除範圍',
                    hintText: '書名/書源URL',
                  ),
                ],
              ),
              ReplaceEditOptions(
                margin: EdgeInsets.zero,
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
                onContentChanged: (value) =>
                    setState(() => _scopeContent = value),
              ),
              ReplaceEditTestPanel(
                margin: EdgeInsets.zero,
                testInputCtrl: _testInputCtrl,
                testResult: _testResult,
              ),
              // 頁首右邊只放「儲存」，複製、貼上放最下面（同書源編輯頁的
              // 「除錯書源」）。
              GroupedSection(
                margin: EdgeInsets.zero,
                children: [
                  GroupedRow(
                    title: '複製規則',
                    accent: true,
                    showChevron: false,
                    onTap: _copyRule,
                  ),
                  GroupedRow(
                    title: '貼上規則',
                    accent: true,
                    showChevron: false,
                    onTap: _pasteRule,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
