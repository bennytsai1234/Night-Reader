import 'package:night_reader/core/exception/user_error.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/ui_text.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/check_source_service.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

import '../source_debug_page.dart';
import 'source_check_status_bar.dart' show sourceCheckPausedText;
import '../source_manager_provider.dart';

import 'package:night_reader/core/services/ui_language.dart';

class SourceManagerDialogs {
  static void showCheckLog(
    BuildContext context,
    SourceManagerProvider provider,
  ) {
    showStatefulAppAlert<void>(
      context: context,
      builder: (context, _, _) => AnimatedBuilder(
        animation: provider.checkService,
        builder: (context, _) {
          final logs = provider.checkService.logs;
          final chrome = AppChrome.of(context);
          final scheme = Theme.of(context).colorScheme;
          return AppAlert<String>(
            title: '校驗詳情',
            message: provider.checkService.config.summary,
            onAction: (value) {
              if (value == 'end') {
                provider.endSourceCheck();
              } else if (value == 'copy') {
                _copyCheckDiagnostics(context, provider.checkService);
              } else {
                Navigator.pop(context);
              }
            },
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                UiText(
                  provider.checkService.isChecking
                      ? '進度 ${provider.checkService.currentCount}/${provider.checkService.totalCount}'
                      : provider.pausedCheck.plan != null
                      ? sourceCheckPausedText(provider.pausedCheck.plan!)
                      : provider.checkService.lastReport.stopped
                      ? '已結束'
                      : '已完成',
                  style: AppTextStyles.uiSm.copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: AppSpacing.xs),
                UiText(
                  provider.checkService.statusMsg,
                  style: AppTextStyles.bodySm.copyWith(
                    color: chrome.sectionText,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  height: 320,
                  decoration: BoxDecoration(
                    color: chrome.groupedBackground,
                    borderRadius: AppRadius.cardMd,
                  ),
                  child: logs.isEmpty
                      ? Center(
                          child: UiText(
                            '目前還沒有校驗日誌',
                            style: AppTextStyles.bodySm.copyWith(
                              color: chrome.sectionText,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          itemCount: logs.length,
                          separatorBuilder: (_, _) => Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.sm,
                            ),
                            child: Container(
                              height: AppGlass.hairline,
                              color: chrome.separator,
                            ),
                          ),
                          itemBuilder: (context, index) {
                            final entry = logs[index];
                            return SelectableText(
                              '${entry.formattedTime} ${entry.message}',
                              style: AppTextStyles.labelSm.copyWith(
                                fontFamily: 'monospace',
                                height: 1.45,
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
            actions: [
              if (provider.checkService.isChecking ||
                  provider.pausedCheck.isPaused)
                const AppAlertAction(
                  label: '結束校驗',
                  value: 'end',
                  destructive: true,
                )
              else if (provider.checkService.lastReport.affectedCount > 0)
                const AppAlertAction(label: '複製診斷', value: 'copy'),
              const AppAlertAction(
                label: '關閉',
                value: 'close',
                isDefault: true,
              ),
            ],
          );
        },
      ),
    );
  }

  /// 複製最近一次校驗的診斷（`SourceCheckDiagnostics`）：每個出問題的
  /// 書源沒截斷的錯誤、實際執行的 JS、請求與網站的回應。
  static Future<void> _copyCheckDiagnostics(
    BuildContext context,
    CheckSourceService checkService,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final text = await checkService.diagnostics.read();
      if (text.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: UiText('這次校驗沒有診斷')));
        return;
      }
      await Clipboard.setData(ClipboardData(text: text));
      messenger.showSnackBar(const SnackBar(content: UiText('已複製校驗診斷')));
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: UiText('複製校驗診斷失敗：${userErrorReason(error)}')),
      );
    }
  }

  static Future<void> showCheckConfigDialog(
    BuildContext context,
    SourceManagerProvider provider, {
    bool checkAll = false,
  }) async {
    final targetCount = checkAll
        ? provider.totalSourceCount
        : provider.selectedUrls.length;
    if (targetCount == 0) {
      return;
    }

    final initial = provider.checkConfig.normalized();

    var checkSearch = initial.checkSearch;
    var checkDiscovery = initial.checkDiscovery;
    var checkInfo = initial.checkInfo;
    var checkCategory = initial.checkCategory;
    var checkContent = initial.checkContent;
    String? timeoutError;
    final pageContext = context;

    Future<void> start(
      BuildContext dialogContext,
      StateSetter setState,
      TextEditingController keywordController,
      TextEditingController timeoutController,
    ) async {
      final timeoutSeconds = int.tryParse(timeoutController.text);
      if (timeoutSeconds == null || timeoutSeconds < 1) {
        setState(() => timeoutError = '超時秒數至少要 1 秒');
        return;
      }

      final config = SourceCheckConfig(
        keyword: keywordController.text,
        timeoutSeconds: timeoutSeconds,
        checkSearch: checkSearch,
        checkDiscovery: checkDiscovery,
        checkInfo: checkInfo,
        checkCategory: checkCategory,
        checkContent: checkContent,
      ).normalized();

      Navigator.pop(dialogContext);
      try {
        if (checkAll) {
          await provider.checkAllSources(config: config);
        } else {
          await provider.checkSelectedSources(config: config);
        }
      } catch (error) {
        if (pageContext.mounted) {
          ScaffoldMessenger.of(pageContext).showSnackBar(
            SnackBar(content: UiText(failureMessage('校驗啟動', error))),
          );
        }
      }
    }

    await AppBottomSheet.showCustom<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => TextControllersScope(
        initialTexts: [initial.keyword, initial.timeoutSeconds.toString()],
        builder: (sheetContext, fields) => StatefulBuilder(
          builder: (sheetContext, setState) {
            final [keywordController, timeoutController] = fields;
            final summary = SourceCheckConfig(
              keyword: keywordController.text,
              timeoutSeconds:
                  int.tryParse(timeoutController.text) ??
                  initial.timeoutSeconds,
              checkSearch: checkSearch,
              checkDiscovery: checkDiscovery,
              checkInfo: checkInfo,
              checkCategory: checkCategory,
              checkContent: checkContent,
            ).normalized().summary;
            return AppBottomSheet(
              title: checkAll
                  ? '校驗全部 $targetCount 個書源'
                  : '校驗選中的 $targetCount 個書源',
              trailing: GlassTextButton(
                label: '開始',
                emphasized: true,
                onPressed: () => start(
                  sheetContext,
                  setState,
                  keywordController,
                  timeoutController,
                ),
              ),
              children: [
                GroupedSection(
                  margin: EdgeInsets.zero,
                  topGap: AppSpacing.md,
                  children: [
                    GroupedTextFieldRow(
                      label: '關鍵字',
                      controller: keywordController,
                      // 底下的設定摘要含關鍵字，輸入時跟著更新。
                      onChanged: (_) => setState(() {}),
                    ),
                    GroupedTextFieldRow(
                      label: '單步超時',
                      controller: timeoutController,
                      keyboardType: TextInputType.number,
                      hintText: '秒，至少 1',
                      errorText: timeoutError,
                      onChanged: (_) => setState(() => timeoutError = null),
                    ),
                  ],
                ),
                GroupedSection(
                  margin: EdgeInsets.zero,
                  header: '校驗項目',
                  footer: summary,
                  children: [
                    // 搜尋與發現至少留一個。
                    GroupedSwitchRow(
                      title: '搜尋',
                      value: checkSearch,
                      onChanged: (value) => setState(() {
                        checkSearch = value;
                        if (!checkSearch && !checkDiscovery) {
                          checkDiscovery = true;
                        }
                      }),
                    ),
                    GroupedSwitchRow(
                      title: '發現',
                      value: checkDiscovery,
                      onChanged: (value) => setState(() {
                        checkDiscovery = value;
                        if (!checkSearch && !checkDiscovery) {
                          checkSearch = true;
                        }
                      }),
                    ),
                    GroupedSwitchRow(
                      title: '詳情',
                      value: checkInfo,
                      onChanged: (value) => setState(() {
                        checkInfo = value;
                        if (!checkInfo) {
                          checkCategory = false;
                          checkContent = false;
                        }
                      }),
                    ),
                    // 依賴上一層的開關，上一層關掉時藏起來（ADR 0009）。
                    if (checkInfo)
                      GroupedSwitchRow(
                        title: '目錄',
                        value: checkCategory,
                        onChanged: (value) => setState(() {
                          checkCategory = value;
                          if (!checkCategory) checkContent = false;
                        }),
                      ),
                    if (checkInfo && checkCategory)
                      GroupedSwitchRow(
                        title: '正文',
                        value: checkContent,
                        onChanged: (value) =>
                            setState(() => checkContent = value),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 清除校驗標記：不給網址是清全部書源，先確認；選中的書源直接清。
  static Future<void> clearCheckMarks(
    BuildContext context,
    SourceManagerProvider provider, {
    Set<String>? urls,
  }) async {
    if (urls == null) {
      final confirmed = await showAppConfirm(
        context: context,
        title: '清除所有校驗標記？',
        message: '校驗分組與錯誤註解都會移除，所有書源回到可用。',
        confirmLabel: '清除',
        destructive: true,
      );
      if (!confirmed) return;
    }
    try {
      final affected = await provider.clearCheckMarks(urls);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: UiText('已清除 $affected 個書源的校驗標記')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: UiText(failureMessage('清除校驗標記', error))),
        );
      }
    }
  }

  /// 「按標籤刪除」：列出書源身上的標籤，勾了哪幾個，帶任一個的書源都刪掉。
  static Future<void> confirmDeleteByTags(
    BuildContext context,
    SourceManagerProvider provider,
  ) async {
    final chosen = await pickSourceTagsToDelete(context, provider);
    if (chosen == null || chosen.isEmpty) return;
    try {
      final affected = await provider.deleteSourcesWithTags(chosen);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: UiText('已刪除 $affected 個書源')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: UiText(failureMessage('刪除', error))));
      }
    }
  }

  static Future<void> showDebugInput(
    BuildContext context,
    BookSource source,
  ) async {
    String? inputError;
    final pageContext = context;
    await showStatefulAppAlert<void>(
      context: context,
      fieldTexts: const ['我的世界'],
      builder: (dialogContext, setDialogState, fields) => AppAlert<bool>(
        title: '輸入除錯關鍵字',
        onAction: (confirmed) {
          if (!confirmed) {
            Navigator.pop(dialogContext);
            return;
          }
          final debugKey = fields.single.text.trim();
          if (debugKey.isEmpty) {
            setDialogState(() => inputError = '請輸入除錯關鍵字或 URL');
            return;
          }
          Navigator.pop(dialogContext);
          Navigator.push(
            pageContext,
            MaterialPageRoute(
              builder: (c) =>
                  SourceDebugPage(source: source, debugKey: debugKey),
            ),
          );
        },
        content: AlertTextField(
          controller: fields.single,
          autofocus: true,
          hintText: '搜尋詞或 URL',
          errorText: inputError,
          onChanged: (_) {
            if (inputError != null) {
              setDialogState(() => inputError = null);
            }
          },
        ),
        actions: const [
          AppAlertAction(label: '取消', value: false),
          AppAlertAction(label: '開始除錯', value: true, isDefault: true),
        ],
      ),
    );
  }
}

/// 問要刪帶哪些標籤的書源：底部面板裡類別、校驗標記、自己的分組各一組，
/// 每個標籤寫有幾個書源，預設都不勾；按頁首的「刪除 N 個」再確認一次。
/// 回傳勾選的標籤，取消時是 null。
Future<Set<SourceTag>?> pickSourceTagsToDelete(
  BuildContext context,
  SourceManagerProvider provider,
) {
  final tags = provider.sourceTagCounts;
  final checkTags = provider.checkResultTags.toSet();
  final sections = <(String, List<({SourceTag tag, int count})>)>[
    (
      '類別',
      [
        for (final t in tags)
          if (t.tag.kind != null) t,
      ],
    ),
    (
      '校驗標記',
      [
        for (final t in tags)
          if (checkTags.contains(t.tag.group)) t,
      ],
    ),
    (
      '分組',
      [
        for (final t in tags)
          if (t.tag.group != null && !checkTags.contains(t.tag.group)) t,
      ],
    ),
  ];
  final selected = <SourceTag>{};
  return AppBottomSheet.showCustom<Set<SourceTag>>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setState) {
        final count = provider.countSourcesWithTags(selected);
        Future<void> confirm() async {
          final ok = await showAppConfirm(
            context: sheetContext,
            title: '刪除 $count 個書源？',
            message: '帶任一個勾選標籤的書源都會刪除。',
            confirmLabel: '刪除',
            destructive: true,
            irreversible: true,
          );
          if (ok && sheetContext.mounted) {
            Navigator.pop(sheetContext, Set<SourceTag>.of(selected));
          }
        }

        return AppBottomSheet(
          title: '按標籤刪除',
          trailing: GlassTextButton(
            label: count == 0 ? '刪除' : '刪除 $count 個',
            destructive: true,
            onPressed: count == 0 ? null : confirm,
          ),
          children: [
            for (final (title, rows) in sections)
              if (rows.isNotEmpty)
                GroupedSection(
                  margin: EdgeInsets.zero,
                  header: title,
                  children: [
                    for (final row in rows)
                      GroupedCheckRow(
                        // 書源類型與數量是介面字，分組名稱照原文（ADR 0066）。
                        title: switch (row.tag.kind) {
                          final kind? => sheetContext.ui(
                            '${kind.sourceLabel}：${row.count} 個',
                          ),
                          null =>
                            '${row.tag.group}${sheetContext.ui('：${row.count} 個')}',
                        },
                        translate: false,
                        exclusive: false,
                        selected: selected.contains(row.tag),
                        onTap: () => setState(
                          () => selected.contains(row.tag)
                              ? selected.remove(row.tag)
                              : selected.add(row.tag),
                        ),
                      ),
                  ],
                ),
          ],
        );
      },
    ),
  );
}
