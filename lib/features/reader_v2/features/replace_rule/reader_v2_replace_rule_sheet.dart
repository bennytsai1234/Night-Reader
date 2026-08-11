import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/features/reader_v2/features/replace_rule/reader_v2_replace_rule_page.dart';
import 'package:night_reader/features/reader_v2/features/replace_rule/reader_v2_replace_rule_editor_sheet.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';

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
  bool _updatingToggle = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _useReplaceRule = widget.book.getUseReplaceRule();
    _reloadEnabledRules();
  }

  @override
  void dispose() {
    _testController.dispose();
    super.dispose();
  }

  void _reloadEnabledRules() {
    _enabledRulesFuture = widget.replaceDao.getEnabledForBook(
      widget.book.name,
      widget.book.origin,
    );
  }

  Future<void> _setUseReplaceRule(bool value) async {
    if (_updatingToggle) return;
    final previous = _useReplaceRule;
    setState(() {
      _updatingToggle = true;
      _useReplaceRule = value;
      (widget.book.readConfig ??= ReadConfig()).useReplaceRule = value;
    });
    try {
      await widget.bookDao.upsert(widget.book);
      await widget.onReload();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _useReplaceRule = previous;
        (widget.book.readConfig ??= ReadConfig()).useReplaceRule = previous;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新替換規則設定失敗：$error')));
    } finally {
      if (mounted) setState(() => _updatingToggle = false);
    }
  }

  Future<void> _runTest() async {
    if (_testing) return;
    setState(() => _testing = true);
    try {
      var text = _testController.text;
      if (_useReplaceRule) {
        final enabledRules = await widget.replaceDao.getEnabledContentForBook(
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
      setState(() => _testResult = text);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('執行測試失敗：$error')));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
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
          subtitle: Text(_updatingToggle ? '正在套用設定…' : '切換後會重載目前閱讀位置內容'),
          value: _useReplaceRule,
          onChanged: _updatingToggle ? null : _setUseReplaceRule,
        ),
        FutureBuilder<List<ReplaceRule>>(
          future: _enabledRulesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.fact_check_rounded),
                title: Text('啟用狀態'),
                subtitle: Text('正在讀取本書可套用規則'),
                trailing: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            if (snapshot.hasError) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: const Text('規則讀取失敗'),
                subtitle: const Text('無法取得本書目前可套用的規則'),
                trailing: TextButton(
                  onPressed: () => setState(_reloadEnabledRules),
                  child: const Text('重試'),
                ),
              );
            }
            final rules = snapshot.data ?? const <ReplaceRule>[];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.fact_check_rounded),
              title: const Text('啟用狀態'),
              subtitle: Text('本書可套用 ${rules.length} 條規則'),
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
            setState(_reloadEnabledRules);
            await widget.onReload();
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.settings_rounded),
          title: const Text('管理規則'),
          subtitle: const Text('新增、編輯、啟用或刪除規則'),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ReaderV2ReplaceRulePage(),
              ),
            );
            if (!mounted) return;
            setState(_reloadEnabledRules);
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
              onPressed: _testing ? null : _runTest,
              child: Text(_testing ? '測試中…' : '執行測試'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed:
                  _updatingToggle
                      ? null
                      : () async {
                        try {
                          await widget.onReload();
                          if (!mounted) return;
                          Navigator.pop(context);
                        } catch (error) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('重載內容失敗：$error')),
                          );
                        }
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
