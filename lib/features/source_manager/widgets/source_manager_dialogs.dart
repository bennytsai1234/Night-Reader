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

/// 需要自己管理狀態（輸入框、勾選）的置中提示框；外觀與動畫同
/// [showAppAlert]，內容由 [builder] 在 [StatefulBuilder] 內建立。
Future<T?> showStatefulAppAlert<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, StateSetter setState) builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: '關閉',
    barrierColor: AppChrome.of(context).barrier,
    transitionDuration: AppMotion.menu,
    pageBuilder: (context, _, _) => StatefulBuilder(builder: builder),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.springCurve,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: AppMotion.fadeCurve),
        child: ScaleTransition(
          scale: Tween<double>(begin: 1.08, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// 提示框內的輸入框：分組底色的圓角欄位，沒有外框線。
class AlertTextField extends StatelessWidget {
  const AlertTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.labelText,
    this.errorText,
    this.onChanged,
    this.autofocus = false,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String? hintText;
  final String? labelText;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final scheme = Theme.of(context).colorScheme;
    const border = OutlineInputBorder(
      borderRadius: AppRadius.cardMd,
      borderSide: BorderSide.none,
    );
    return TextField(
      controller: controller,
      autofocus: autofocus,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      style: AppTextStyles.bodyBase.copyWith(
        height: 1.3,
        color: scheme.onSurface,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: chrome.groupedBackground,
        hintText: hintText,
        labelText: labelText,
        errorText: errorText,
        hintStyle: AppTextStyles.bodyBase.copyWith(
          height: 1.3,
          color: chrome.sectionText.withValues(alpha: 0.7),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border,
        errorBorder: border,
        focusedErrorBorder: border,
      ),
    );
  }
}

/// 提示框內的多選列：標題、說明與右側勾選圈。
class AlertCheckRow extends StatelessWidget {
  const AlertCheckRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
    final enabled = onChanged != null;
    return Semantics(
      checked: value,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? () => onChanged!(!value) : null,
        borderRadius: AppRadius.cardSm,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.bodyBase.copyWith(
                          height: 1.3,
                          color: scheme.onSurface,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: AppTextStyles.bodySm.copyWith(
                            height: 1.3,
                            color: chrome.sectionText,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Icon(
                  value
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: value ? scheme.primary : chrome.sectionText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SourceManagerDialogs {
  static void showCheckLog(
    BuildContext context,
    SourceManagerProvider provider,
  ) {
    showStatefulAppAlert<void>(
      context: context,
      builder:
          (context, _) => AnimatedBuilder(
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
    final keywordController = TextEditingController(text: initial.keyword);
    final timeoutController = TextEditingController(
      text: initial.timeoutSeconds.toString(),
    );

    var checkSearch = initial.checkSearch;
    var checkDiscovery = initial.checkDiscovery;
    var checkInfo = initial.checkInfo;
    var checkCategory = initial.checkCategory;
    var checkContent = initial.checkContent;
    String? timeoutError;
    final pageContext = context;

    Future<void> start(BuildContext dialogContext, StateSetter setState) async {
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

    try {
      await showStatefulAppAlert<void>(
        context: context,
        builder: (dialogContext, setState) {
          final chrome = AppChrome.of(dialogContext);
          return AppAlert<bool>(
            title:
                checkAll
                    ? '校驗所有書源（全部 $targetCount 項）'
                    : '校驗選中書源 ($targetCount)',
            onAction: (confirmed) {
              if (confirmed) {
                start(dialogContext, setState);
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
    } finally {
      keywordController.dispose();
      timeoutController.dispose();
    }
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
    final ctrl = TextEditingController(text: '我的世界');
    String? inputError;
    final pageContext = context;
    try {
      await showStatefulAppAlert<void>(
        context: context,
        builder:
            (dialogContext, setDialogState) => AppAlert<bool>(
              title: '輸入調試關鍵字',
              onAction: (confirmed) {
                if (!confirmed) {
                  Navigator.pop(dialogContext);
                  return;
                }
                final debugKey = ctrl.text.trim();
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
                controller: ctrl,
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
    } finally {
      ctrl.dispose();
    }
  }
}
