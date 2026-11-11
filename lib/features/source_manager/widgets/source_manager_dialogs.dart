import 'package:night_reader/core/exception/user_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/check_source_service.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';

import '../source_debug_page.dart';
import '../source_manager_provider.dart';

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
              if (value == 'cancel') {
                provider.cancelSourceCheck();
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
                Text(
                  provider.checkService.isChecking
                      ? '進度 ${provider.checkService.currentCount}/${provider.checkService.totalCount}'
                      : provider.checkService.lastReport.stopped
                      ? '已停止'
                      : '已完成',
                  style: AppTextStyles.uiSm.copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
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
                          child: Text(
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
              if (provider.checkService.isChecking)
                const AppAlertAction(
                  label: '停止校驗',
                  value: 'cancel',
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
        messenger.showSnackBar(const SnackBar(content: Text('這次校驗沒有診斷')));
        return;
      }
      await Clipboard.setData(ClipboardData(text: text));
      messenger.showSnackBar(const SnackBar(content: Text('已複製校驗診斷')));
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('複製校驗診斷失敗：${userErrorReason(error)}')),
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
            SnackBar(content: Text(failureMessage('校驗啟動', error))),
          );
        }
      }
    }

    await showStatefulAppAlert<void>(
      context: context,
      fieldTexts: [initial.keyword, initial.timeoutSeconds.toString()],
      builder: (dialogContext, setState, fields) {
        final [keywordController, timeoutController] = fields;
        final chrome = AppChrome.of(dialogContext);
        return AppAlert<bool>(
          title: checkAll
              ? '校驗所有書源（全部 $targetCount 項）'
              : '校驗選中書源 ($targetCount)',
          onAction: (confirmed) {
            if (confirmed) {
              start(
                dialogContext,
                setState,
                keywordController,
                timeoutController,
              );
            } else {
              Navigator.pop(dialogContext);
            }
          },
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AlertTextField(
                controller: keywordController,
                labelText: '預設關鍵字',
                // 底部的設定摘要含關鍵字，輸入時跟著更新。
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
              AlertTextField(
                controller: timeoutController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                labelText: '單步超時（秒）',
                hintText: '至少 1 秒',
                errorText: timeoutError,
                onChanged: (_) => setState(() => timeoutError = null),
              ),
              const SizedBox(height: AppSpacing.sm),
              AlertCheckRow(
                value: checkSearch,
                title: '校驗搜尋',
                onChanged: (value) {
                  setState(() {
                    checkSearch = value;
                    if (!checkSearch && !checkDiscovery) {
                      checkDiscovery = true;
                    }
                  });
                },
              ),
              AlertCheckRow(
                value: checkDiscovery,
                title: '校驗發現',
                onChanged: (value) {
                  setState(() {
                    checkDiscovery = value;
                    if (!checkSearch && !checkDiscovery) {
                      checkSearch = true;
                    }
                  });
                },
              ),
              AlertCheckRow(
                value: checkInfo,
                title: '校驗詳情',
                onChanged: (value) {
                  setState(() {
                    checkInfo = value;
                    if (!checkInfo) {
                      checkCategory = false;
                      checkContent = false;
                    }
                  });
                },
              ),
              AlertCheckRow(
                value: checkCategory,
                title: '校驗目錄',
                onChanged: checkInfo
                    ? (value) {
                        setState(() {
                          checkCategory = value;
                          if (!checkCategory) {
                            checkContent = false;
                          }
                        });
                      }
                    : null,
              ),
              AlertCheckRow(
                value: checkContent,
                title: '校驗正文',
                onChanged: checkInfo && checkCategory
                    ? (value) => setState(() => checkContent = value)
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: chrome.groupedBackground,
                  borderRadius: AppRadius.cardMd,
                ),
                child: Text(
                  SourceCheckConfig(
                    keyword: keywordController.text,
                    timeoutSeconds:
                        int.tryParse(timeoutController.text) ??
                        initial.timeoutSeconds,
                    checkSearch: checkSearch,
                    checkDiscovery: checkDiscovery,
                    checkInfo: checkInfo,
                    checkCategory: checkCategory,
                    checkContent: checkContent,
                  ).normalized().summary,
                  style: AppTextStyles.bodySm.copyWith(
                    color: chrome.sectionText,
                  ),
                ),
              ),
            ],
          ),
          actions: const [
            AppAlertAction(label: '取消', value: false),
            AppAlertAction(label: '開始校驗', value: true, isDefault: true),
          ],
        );
      },
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
        title: '清除校驗標記',
        message: '所有書源的校驗分組與錯誤註解都會移除，全部回到可用。',
        confirmLabel: '清除',
        destructive: true,
      );
      if (!confirmed) return;
    }
    try {
      final affected = await provider.clearCheckMarks(urls);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已清除 $affected 個書源的校驗標記')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failureMessage('清除校驗標記', error))),
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
            .showSnackBar(SnackBar(content: Text('已刪除 $affected 個書源')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failureMessage('刪除', error))));
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

/// 問要刪帶哪些標籤的書源：類別、校驗標記、自己的分組各一段，每個標籤
/// 寫有幾個書源，預設都不勾；回傳勾選的標籤，取消時是 null。
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
  return showStatefulAppAlert<Set<SourceTag>>(
    context: context,
    builder: (dialogContext, setState, _) {
      final count = provider.countSourcesWithTags(selected);
      final sectionStyle = AppTextStyles.bodySm.copyWith(
        color: AppChrome.of(dialogContext).sectionText,
      );
      return AppAlert<bool>(
        title: '按標籤刪除',
        message: '勾選標籤，帶任一個標籤的書源都會刪除，無法復原。',
        onAction: (confirmed) => Navigator.pop(
          dialogContext,
          confirmed ? Set<SourceTag>.of(selected) : null,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (title, rows) in sections)
              if (rows.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(title, style: sectionStyle),
                ),
                for (final row in rows)
                  AlertCheckRow(
                    title:
                        '${row.tag.kind?.sourceLabel ?? row.tag.group}：'
                        '${row.count} 個',
                    value: selected.contains(row.tag),
                    onChanged: (value) => setState(
                      () => value
                          ? selected.add(row.tag)
                          : selected.remove(row.tag),
                    ),
                  ),
              ],
          ],
        ),
        actions: [
          const AppAlertAction(label: '取消', value: false),
          AppAlertAction(
            label: count == 0 ? '刪除' : '刪除 $count 個',
            value: true,
            destructive: true,
            enabled: count > 0,
          ),
        ],
      );
    },
  );
}
