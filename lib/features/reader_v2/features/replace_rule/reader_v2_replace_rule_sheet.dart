import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/features/reader_v2/features/replace_rule/reader_v2_replace_rule_page.dart';
import 'package:night_reader/features/reader_v2/features/replace_rule/reader_v2_replace_rule_editor_sheet.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

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
      try {
        await widget.bookDao.upsert(widget.book);
      } catch (rollbackError, rollbackStack) {
        AppLog.e(
          '替換規則設定 rollback 持久化失敗: $rollbackError',
          error: rollbackError,
          stackTrace: rollbackStack,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('更新替換規則設定失敗：$error')));
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
          text = rule.apply(text);
        }
      }
      if (!mounted) return;
      setState(() => _testResult = text);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('執行測試失敗：$error')));
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
        GroupedSection(
          margin: EdgeInsets.zero,
          topGap: 0,
          children: [
            GroupedSwitchRow(
              leading: const GroupedIconTile(Icons.auto_fix_high_rounded),
              title: '本書套用替換規則',
              value: _useReplaceRule,
              onChanged: _updatingToggle ? null : _setUseReplaceRule,
            ),
            FutureBuilder<List<ReplaceRule>>(
              future: _enabledRulesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const GroupedRow(
                    leading: GroupedIconTile(
                      Icons.fact_check_rounded,
                      tint: AppTint.moss,
                    ),
                    title: '啟用狀態',
                    trailing: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return GroupedRow(
                    leading: const GroupedIconTile(
                      Icons.error_outline_rounded,
                      tint: AppTint.rust,
                    ),
                    title: '規則讀取失敗',
                    value: '重試',
                    showChevron: false,
                    onTap: () => setState(_reloadEnabledRules),
                  );
                }
                final rules = snapshot.data ?? const <ReplaceRule>[];
                return GroupedRow(
                  leading: const GroupedIconTile(
                    Icons.fact_check_rounded,
                    tint: AppTint.moss,
                  ),
                  title: '啟用狀態',
                  value: rules.isEmpty ? null : '${rules.length}',
                );
              },
            ),
            GroupedRow(
              leading: const GroupedIconTile(
                Icons.add_rounded,
                tint: AppTint.azurite,
              ),
              title: '新增規則',
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
            GroupedRow(
              leading: const GroupedIconTile(
                Icons.settings_rounded,
                tint: AppTint.ink,
              ),
              title: '管理規則',
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
          ],
        ),
        GroupedSection(
          margin: EdgeInsets.zero,
          header: '即時測試',
          children: [
            GroupedTextFieldRow(
              controller: _testController,
              minLines: 3,
              maxLines: 5,
            ),
            GroupedRow(
              title: _testing ? '測試中…' : '執行測試',
              accent: true,
              showChevron: false,
              enabled: !_testing,
              onTap: _testing ? null : _runTest,
            ),
            GroupedRow(
              title: '重載目前內容',
              accent: true,
              showChevron: false,
              enabled: !_updatingToggle,
              onTap: _updatingToggle
                  ? null
                  : () async {
                      try {
                        await widget.onReload();
                        if (!context.mounted) return;
                        Navigator.pop(context);
                      } catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('重載內容失敗：$error')),
                        );
                      }
                    },
            ),
          ],
        ),
        GroupedSection(
          margin: EdgeInsets.zero,
          topGap: AppSpacing.lg,
          header: '測試結果',
          children: [
            GroupedContent(
              child: Text(
                _testResult.isEmpty ? '測試結果會顯示在這裡' : _testResult,
                style: AppTextStyles.bodySm.copyWith(
                  color: _testResult.isEmpty
                      ? AppChrome.of(context).sectionText
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
