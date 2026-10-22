import 'dart:async';
import 'dart:convert';

import 'package:night_reader/core/exception/user_error.dart';
import 'package:flutter/foundation.dart';
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
    this.loadTestSample,
  });

  final Book book;
  final BookDao bookDao;
  final ReplaceRuleDao replaceDao;
  final Future<void> Function() onReload;

  /// 即時測試框的預設文字（畫面上那一段的原文），面板打開後才讀、讀到才
  /// 填；取不到時留空。測試框固定三行高，字什麼時候填進來都不影響面板
  /// 高度（ADR 0029）。
  final Future<String?> Function()? loadTestSample;

  /// 讀這本書啟用的規則；讀不到時記下錯誤、回傳 null。錯誤在這裡就接住，
  /// 不交給之後才建的列（面板的列在滑到位後才建，交給它時錯誤已經沒人接）。
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

  /// 「管理規則」右側的規則數。讀到時只有那一列聽它重建：常在面板滑入途中
  /// 讀到，通知整個面板會在那一格重建全部的列、重算骨架（ADR 0029 做法 3）。
  final ValueNotifier<_RulesState> _rules = ValueNotifier(
    const _RulesState.loading(),
  );
  final TextEditingController _testController = TextEditingController();

  /// 還沒按「執行測試」時為 null，結果區不顯示。
  String? _testResult;
  bool _updatingToggle = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _useReplaceRule = widget.book.getUseReplaceRule();
    unawaited(_reloadEnabledRules());
    unawaited(_fillTestSample());
  }

  Future<void> _fillTestSample() async {
    final String? sample;
    try {
      sample = await widget.loadTestSample?.call();
    } catch (error, stack) {
      AppLog.e('讀取替換規則測試文字失敗: $error', error: error, stackTrace: stack);
      return;
    }
    // 使用者已經開始打字就不覆蓋。
    if (!mounted || sample == null || _testController.text.isNotEmpty) return;
    _testController.text = sample;
  }

  @override
  void dispose() {
    _testController.dispose();
    _rules.dispose();
    super.dispose();
  }

  Future<void> _reloadEnabledRules() async {
    final rules = await ReaderV2ReplaceRuleSheet.loadEnabledRules(
      widget.replaceDao,
      widget.book,
    );
    if (!mounted) return;
    _rules.value = _RulesState.loaded(rules);
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
    // 讀不到快照時照樣進管理頁，回來後當作有改動重載。
    final before = await _rulesSnapshotOrNull();
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReaderV2ReplaceRulePage()),
    );
    if (!mounted) return;
    // 只是進去看看、沒有改動時不重載正文。
    if (before != null && await _rulesSnapshotOrNull() == before) return;
    await _applyRuleChange();
  }

  Future<String?> _rulesSnapshotOrNull() async {
    try {
      return await _rulesSnapshot();
    } catch (error, stack) {
      AppLog.e('讀取替換規則快照失敗: $error', error: error, stackTrace: stack);
      return null;
    }
  }

  /// 規則有改動：重讀規則數，正文照新規則重載。這兩條路徑由列的點擊觸發，
  /// 錯誤在這裡接住，不留給沒人等的 Future。
  Future<void> _applyRuleChange() async {
    unawaited(_reloadEnabledRules());
    try {
      await widget.onReload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage('套用替換規則', error))));
    }
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
                await _applyRuleChange();
              },
            ),
            // 右側是這本書目前啟用的規則數。
            _RuleManagementRow(
              rules: _rules,
              onRetry: _reloadEnabledRules,
              onManage: () => _manageRules(context),
            ),
          ],
        ),
        GroupedSection(
          margin: EdgeInsets.zero,
          header: '即時測試',
          children: [
            // 固定三行高，長的原文在框內捲動：原文是面板打開後才讀到、填進
            // 來的，框的高度不能跟著它變（骨架第一幀就照三行畫）。
            GroupedTextFieldRow(
              controller: _testController,
              minLines: 3,
              maxLines: 3,
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

/// 「管理規則」列，右側是啟用的規則數（讀到前空著）；讀不到時換成「規則
/// 讀取失敗」。規則數是面板打開後才讀到的，三種樣子都是一行標題（放不下
/// 時截斷，不換行）、同樣大小的列首圖示，讀到什麼只換字，不改列高；骨架
/// 照打開時這一列畫。
class _RuleManagementRow extends StatelessWidget
    implements GroupedRowLike, GroupedSkeletonItem {
  const _RuleManagementRow({
    required this.rules,
    required this.onRetry,
    required this.onManage,
  });

  final ValueListenable<_RulesState> rules;
  final VoidCallback onRetry;
  final VoidCallback onManage;

  @override
  bool get hasLeading => true;

  GroupedRow _row(_RulesState state) => switch (state) {
    _RulesState(loaded: true, rules: null) => GroupedRow(
      leading: const GroupedIconTile(
        Icons.error_outline_rounded,
        tint: AppTint.rust,
      ),
      title: '規則讀取失敗',
      maxTitleLines: 1,
      value: '重試',
      showChevron: false,
      onTap: onRetry,
    ),
    _RulesState(:final rules) => GroupedRow(
      leading: const GroupedIconTile(Icons.settings_rounded, tint: AppTint.ink),
      title: '管理規則',
      maxTitleLines: 1,
      value: rules == null ? null : '${rules.length}',
      onTap: onManage,
    ),
  };

  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) => _row(rules.value).skeletonShape(context, width: width);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<_RulesState>(
    valueListenable: rules,
    builder: (context, state, _) => _row(state),
  );
}

/// 啟用的規則讀到了沒有；讀到後 [rules] 為 null 是讀不到。
@immutable
class _RulesState {
  const _RulesState.loading() : loaded = false, rules = null;
  const _RulesState.loaded(this.rules) : loaded = true;

  final bool loaded;
  final List<ReplaceRule>? rules;
}
