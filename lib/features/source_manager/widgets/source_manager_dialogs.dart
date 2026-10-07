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
      builder:
          (context, _, _) => AnimatedBuilder(
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
                          : '已完成',
                      style: AppTextStyles.uiSm.copyWith(
                        color: scheme.onSurface,
                      ),
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
                      child:
                          logs.isEmpty
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
                                separatorBuilder:
                                    (_, _) => Padding(
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
                      label: '取消校驗',
                      value: 'cancel',
                      destructive: true,
                    ),
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

  static Future<void> showCheckConfigDialog(
    BuildContext context,
    SourceManagerProvider provider, {
    bool checkAll = false,
  }) async {
    final targetCount =
        checkAll ? provider.totalSourceCount : provider.selectedUrls.length;
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

      final config =
          SourceCheckConfig(
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
          ScaffoldMessenger.of(
            pageContext,
          ).showSnackBar(SnackBar(content: Text('校驗啟動失敗：$error')));
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
          title:
              checkAll
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
                hintText: '未設置書源校驗關鍵字時使用',
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
                subtitle: '檢查 searchUrl 與搜尋結果',
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
                subtitle: '依 exploreUrl 解析並檢查發現入口',
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
                subtitle: '拉取書籍詳情頁',
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
                subtitle: '拉取章節列表',
                onChanged:
                    checkInfo
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
                subtitle: '拉取首個可閱讀章節正文',
                onChanged:
                    checkInfo && checkCategory
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

  static Future<void> confirmClearInvalid(
    BuildContext context,
    SourceManagerProvider provider,
  ) async {
    final confirmed = await showAppConfirm(
      context: context,
      title: '清理建議刪除來源',
      message: '會刪除目前標記為非小說、需要登入或下載站的來源。這些來源不會再參與搜尋或閱讀。',
      confirmLabel: '確定刪除',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await provider.clearInvalidSources();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('清理完成')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('清理失敗：$error')));
      }
    }
  }

  static Future<void> confirmDeleteNonNovel(
    BuildContext context,
    SourceManagerProvider provider,
  ) async {
    final confirmed = await showAppConfirm(
      context: context,
      title: '刪除非小說源',
      message: '會直接刪除影音、漫畫、RSS 等非小說源，且無法復原。要繼續嗎？',
      confirmLabel: '確定刪除',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      final affected = await provider.deleteNonNovelSources();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已刪除 $affected 個非小說源')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('刪除非小說源失敗：$error')));
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
      builder:
          (dialogContext, setDialogState, fields) => AppAlert<bool>(
            title: '輸入調試關鍵字',
            onAction: (confirmed) {
              if (!confirmed) {
                Navigator.pop(dialogContext);
                return;
              }
              final debugKey = fields.single.text.trim();
              if (debugKey.isEmpty) {
                setDialogState(() => inputError = '請輸入調試關鍵字或 URL');
                return;
              }
              Navigator.pop(dialogContext);
              Navigator.push(
                pageContext,
                MaterialPageRoute(
                  builder:
                      (c) =>
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
              AppAlertAction(label: '開始調試', value: true, isDefault: true),
            ],
          ),
    );
  }
}
