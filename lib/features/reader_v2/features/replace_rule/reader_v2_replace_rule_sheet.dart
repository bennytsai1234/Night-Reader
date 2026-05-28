import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader/core/database/dao/book_dao.dart';
import 'package:reader/core/database/dao/replace_rule_dao.dart';
import 'package:reader/core/models/book.dart';
import 'package:reader/core/models/replace_rule.dart';
import 'package:reader/features/reader_v2/features/replace_rule/reader_v2_replace_rule_page.dart';
import 'package:reader/features/reader_v2/features/replace_rule/reader_v2_replace_rule_editor_sheet.dart';
import 'package:reader/shared/widgets/app_bottom_sheet.dart';

class ReaderV2ReplaceRuleSheet extends StatefulWidget {
  const ReaderV2ReplaceRuleSheet({
    super.key,
    required this.book,
    required this.bookDao,
    required this.replaceDao,
    required this.onReload,
  });

  final Book book;
  final BookDao bookDao;
  final ReplaceRuleDao replaceDao;
  final Future<void> Function() onReload;

  @override
  State<ReaderV2ReplaceRuleSheet> createState() =>
      _ReaderV2ReplaceRuleSheetState();
}

class _ReaderV2ReplaceRuleSheetState extends State<ReaderV2ReplaceRuleSheet> {
  late bool _useReplaceRule;
  Future<List<ReplaceRule>>? _enabledRulesFuture;
  final TextEditingController _testController = TextEditingController();
  String _testResult = '';

  @override
  void initState() {
    super.initState();
    _useReplaceRule = widget.book.getUseReplaceRule();
    _enabledRulesFuture = widget.replaceDao.getEnabledForBook(
      widget.book.name,
      widget.book.origin,
    );
  }

  @override
  void dispose() {
    _testController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppBottomSheet(
      title: '替換規則',
      icon: Icons.rule_rounded,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.auto_fix_high_rounded),
          title: const Text('本書套用替換規則'),
          subtitle: const Text('切換後會重載目前閱讀位置內容'),
          value: _useReplaceRule,
          onChanged: (value) async {
            setState(() {
              _useReplaceRule = value;
              (widget.book.readConfig ??= ReadConfig()).useReplaceRule = value;
            });
            await widget.bookDao.upsert(widget.book);
            await widget.onReload();
          },
        ),
        FutureBuilder<List<ReplaceRule>>(
          future: _enabledRulesFuture,
          builder: (context, snapshot) {
            final rules = snapshot.data ?? const <ReplaceRule>[];
            final subtitle =
                snapshot.connectionState == ConnectionState.waiting
                    ? '讀取本書可套用規則中'
                    : '本書可套用 ${rules.length} 條規則';
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.fact_check_rounded),
              title: const Text('啟用狀態'),
              subtitle: Text(subtitle),
              trailing:
                  rules.isEmpty
                      ? null
                      : Text(
                        '${rules.length}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
            );
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.add_circle_outline_rounded),
          title: const Text('新增規則'),
          subtitle: const Text('直接建立一條新的替換規則'),
          onTap: () async {
            await ReaderV2ReplaceRuleEditorSheet.show(
              context,
              onSave: (rule) async {
                final nextOrder = (await widget.replaceDao.getAll()).length;
                rule.order = nextOrder;
                await widget.replaceDao.upsert(rule);
              },
            );
            if (!mounted) return;
            setState(() {
              _enabledRulesFuture = widget.replaceDao.getEnabledForBook(
                widget.book.name,
                widget.book.origin,
              );
            });
            await widget.onReload();
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.settings_rounded),
          title: const Text('管理規則'),
          subtitle: const Text('新增、編輯、排序與批量匯入'),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ReaderV2ReplaceRulePage(),
              ),
            );
            if (!mounted) return;
            setState(() {
              _enabledRulesFuture = widget.replaceDao.getEnabledForBook(
                widget.book.name,
                widget.book.origin,
              );
            });
            await widget.onReload();
          },
        ),
        const SizedBox(height: 8),
        const Text(
          '即時測試',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _testController,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: '輸入一段文本，測試本書正文實際套用規則',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton(
              onPressed: () async {
                var text = _testController.text;
                if (_useReplaceRule) {
                  final enabledRules = await widget.replaceDao
                      .getEnabledContentForBook(
                        widget.book.name,
                        widget.book.origin,
                      );
                  for (final rule in enabledRules) {
                    try {
                      text = rule.apply(text);
                    } catch (_) {
                      // 單條規則失敗時保持測試流程不中斷，和文章處理一致。
                    }
                  }
                }
                if (!mounted) return;
                setState(() {
                  _testResult = text;
                });
              },
              child: const Text('執行測試'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () async {
                await widget.onReload();
                if (!mounted) return;
                Navigator.pop(context);
              },
              child: const Text('重載目前內容'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(_testResult.isEmpty ? '測試結果會顯示在這裡' : _testResult),
        ),
      ],
    );
  }
}
