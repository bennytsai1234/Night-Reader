import 'dart:async';
import 'dart:convert';

import 'package:night_reader/core/exception/user_error.dart';
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
import 'package:night_reader/shared/widgets/grouped_list_skeleton.dart';

class ReaderV2ReplaceRuleSheet extends StatefulWidget {
  const ReaderV2ReplaceRuleSheet({
    super.key,
    required this.book,
    required this.bookDao,
    required this.replaceDao,
    required this.onReload,
    this.testSample,
    required this.enabledRules,
  });

  final Book book;
  final BookDao bookDao;
  final ReplaceRuleDao replaceDao;
  final Future<void> Function() onReload;

  /// 即時測試框一打開就填好的文字（畫面上那一段的原文）；取不到時留空。
  /// 和 [enabledRules] 一樣在開面板前讀好：面板滑上來的第一幀，骨架就得
  /// 照輸入框裡的字與「管理規則」右側的數字算高度（ADR 0029）。
  final String? testSample;

  /// 這本書目前啟用的規則，開面板前用 [loadEnabledRules] 讀好；null 是讀不到，
  /// 那一列一開始就是「規則讀取失敗」，骨架也照它畫。
  final List<ReplaceRule>? enabledRules;

  /// 讀這本書啟用的規則；讀不到時記下錯誤、回傳 null。開面板前與面板裡的
  /// 重讀共用，錯誤在這裡就接住，不交給之後才建的列（面板的列在滑到位後
  /// 才建，交給它時錯誤已經沒人接）。
  static Future<List<ReplaceRule>?> loadEnabledRules(
    ReplaceRuleDao dao,
    Book book,
  ) async {
    try {
      return await dao.getEnabledForBook(book.name, book.origin);
    } catch (error, stack) {
      AppLog.e('讀取啟用的替換規則失敗: $error', error: error, stackTrace: stack);
      return null;
    }
  }

  @override
  State<ReaderV2ReplaceRuleSheet> createState() =>
      _ReaderV2ReplaceRuleSheetState();
}

class _ReaderV2ReplaceRuleSheetState extends State<ReaderV2ReplaceRuleSheet> {
  late bool _useReplaceRule;

  /// 「管理規則」右側的規則數；null 是讀不到。
  late List<ReplaceRule>? _enabledRules = widget.enabledRules;
  late final TextEditingController _testController = TextEditingController(
    text: widget.testSample,
  );

  /// 還沒按「執行測試」時為 null，結果區不顯示。
  String? _testResult;
  bool _updatingToggle = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _useReplaceRule = widget.book.getUseReplaceRule();
  }

  @override
  void dispose() {
    _testController.dispose();
    super.dispose();
  }

  Future<void> _reloadEnabledRules() async {
    final rules = await ReaderV2ReplaceRuleSheet.loadEnabledRules(
      widget.replaceDao,
      widget.book,
    );
    if (mounted) setState(() => _enabledRules = rules);
  }

  /// 全部規則的內容快照，用來判斷管理頁裡有沒有改動。
  Future<String> _rulesSnapshot() async => jsonEncode([
    for (final rule in await widget.replaceDao.getAll()) rule.toJson(),
  ]);

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failureMessage('更新替換規則設定', error))),
      );
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
          .showSnackBar(SnackBar(content: Text(failureMessage('執行測試', error))));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _manageRules(BuildContext context) async {
    final before = await _rulesSnapshot();
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReaderV2ReplaceRulePage()),
    );
    // 只是進去看看、沒有改動時不重載正文。
    if (!mounted || await _rulesSnapshot() == before) return;
    unawaited(_reloadEnabledRules());
    await widget.onReload();
  }

  @override
  Widget build(BuildContext context) {
    return AppBottomSheet(
      title: '替換規則',
      icon: Icons.rule_rounded,
      skeletonEntrance: true,
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
            GroupedRow(
              leading: const GroupedIconTile(
                Icons.add_rounded,
                tint: AppTint.azurite,
              ),
              title: '新增規則',
              onTap: () async {
                var saved = false;
                await ReaderV2ReplaceRuleEditorSheet.show(
                  context,
                  onSave: (rule) async {
                    final nextOrder = (await widget.replaceDao.getAll()).length;
                    rule.order = nextOrder;
                    await widget.replaceDao.upsert(rule);
                    saved = true;
                  },
                );
                // 取消時不重載：重載會重新排版並打斷朗讀。
                if (!mounted || !saved) return;
                unawaited(_reloadEnabledRules());
                await widget.onReload();
              },
            ),
            // 右側是這本書目前啟用的規則數。
            _RuleManagementRow(
              rules: _enabledRules,
              onRetry: _reloadEnabledRules,
              onManage: () => _manageRules(context),
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
                          SnackBar(
                            content: Text(failureMessage('重載內容', error)),
                          ),
                        );
                      }
                    },
            ),
          ],
        ),
        if (_testResult case final result?)
          GroupedSection(
            margin: EdgeInsets.zero,
            topGap: AppSpacing.lg,
            header: '測試結果',
            children: [
              GroupedContent(
                child: Text(
                  result.isEmpty ? '（空白）' : result,
                  style: AppTextStyles.bodySm.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// 「管理規則」列，右側是啟用的規則數；讀不到（[rules] 為 null）時換成
/// 「規則讀取失敗」。骨架與內容照同一個 [rules] 畫同一列，第一幀就一樣高。
class _RuleManagementRow extends StatelessWidget
    implements GroupedRowLike, GroupedSkeletonItem {
  const _RuleManagementRow({
    required this.rules,
    required this.onRetry,
    required this.onManage,
  });

  final List<ReplaceRule>? rules;
  final VoidCallback onRetry;
  final VoidCallback onManage;

  @override
  bool get hasLeading => true;

  GroupedRow get _row => switch (rules) {
    final rules? => GroupedRow(
      leading: const GroupedIconTile(Icons.settings_rounded, tint: AppTint.ink),
      title: '管理規則',
      value: '${rules.length}',
      onTap: onManage,
    ),
    null => GroupedRow(
      leading: const GroupedIconTile(
        Icons.error_outline_rounded,
        tint: AppTint.rust,
      ),
      title: '規則讀取失敗',
      value: '重試',
      showChevron: false,
      onTap: onRetry,
    ),
  };

  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) => _row.skeletonShape(context, width: width);

  @override
  Widget build(BuildContext context) => _row;
}
