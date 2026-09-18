import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/core/services/check_source_service.dart';
import '../source_manager_provider.dart';
import 'package:night_reader/core/models/book_source.dart';
import '../source_debug_page.dart';

class SourceManagerDialogs {
  static void showCheckLog(
    BuildContext context,
    SourceManagerProvider provider,
  ) {
    showDialog(
      context: context,
      builder:
          (context) => AnimatedBuilder(
            animation: provider.checkService,
            builder: (context, _) {
              final logs = provider.checkService.logs;
              return AlertDialog(
                title: const Text('校驗詳情'),
                content: SizedBox(
                  width: double.maxFinite,
                  height: 420,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.checkService.config.summary,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        provider.checkService.isChecking
                            ? '進度 ${provider.checkService.currentCount}/${provider.checkService.totalCount}'
                            : '已完成',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        provider.checkService.statusMsg,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child:
                            logs.isEmpty
                                ? const Center(child: Text('目前還沒有校驗日誌'))
                                : ListView.separated(
                                  itemCount: logs.length,
                                  separatorBuilder:
                                      (_, __) => const Divider(height: 12),
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
                ),
                actions: [
                  if (provider.checkService.isChecking)
                    TextButton(
                      onPressed: provider.cancelSourceCheck,
                      child: const Text('取消校驗'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('關閉'),
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
    final pageContext = context;

    try {
      await showDialog(
        context: context,
        builder:
            (dialogContext) => StatefulBuilder(
              builder:
                  (context, setState) => AlertDialog(
                    title: Text(
                      checkAll
                          ? '校驗所有書源（全部 $targetCount 項）'
                          : '校驗選中書源 ($targetCount)',
                    ),
                    content: SizedBox(
                      width: double.maxFinite,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: keywordController,
                              decoration: const InputDecoration(
                                labelText: '預設關鍵字',
                                hintText: '未設置書源校驗關鍵字時使用',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: timeoutController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: '單步超時（秒）',
                                hintText: '至少 1 秒',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 12),
                            CheckboxListTile(
                              value: checkSearch,
                              contentPadding: EdgeInsets.zero,
                              title: const Text('校驗搜尋'),
                              subtitle: const Text('檢查 searchUrl 與搜尋結果'),
                              onChanged: (value) {
                                setState(() {
                                  checkSearch = value ?? false;
                                  if (!checkSearch && !checkDiscovery) {
                                    checkDiscovery = true;
                                  }
                                });
                              },
                            ),
                            CheckboxListTile(
                              value: checkDiscovery,
                              contentPadding: EdgeInsets.zero,
                              title: const Text('校驗發現'),
                              subtitle: const Text('依 exploreUrl 解析並檢查發現入口'),
                              onChanged: (value) {
                                setState(() {
                                  checkDiscovery = value ?? false;
                                  if (!checkSearch && !checkDiscovery) {
                                    checkSearch = true;
                                  }
                                });
                              },
                            ),
                            CheckboxListTile(
                              value: checkInfo,
                              contentPadding: EdgeInsets.zero,
                              title: const Text('校驗詳情'),
                              subtitle: const Text('拉取書籍詳情頁'),
                              onChanged: (value) {
                                setState(() {
                                  checkInfo = value ?? false;
                                  if (!checkInfo) {
                                    checkCategory = false;
                                    checkContent = false;
                                  }
                                });
                              },
                            ),
                            CheckboxListTile(
                              value: checkCategory,
                              contentPadding: EdgeInsets.zero,
                              title: const Text('校驗目錄'),
                              subtitle: const Text('拉取章節列表'),
                              onChanged:
                                  checkInfo
                                      ? (value) {
                                        setState(() {
                                          checkCategory = value ?? false;
                                          if (!checkCategory) {
                                            checkContent = false;
                                          }
                                        });
                                      }
                                      : null,
                            ),
                            CheckboxListTile(
                              value: checkContent,
                              contentPadding: EdgeInsets.zero,
                              title: const Text('校驗正文'),
                              subtitle: const Text('拉取首個可閱讀章節正文'),
                              onChanged:
                                  checkInfo && checkCategory
                                      ? (value) {
                                        setState(() {
                                          checkContent = value ?? false;
                                        });
                                      }
                                      : null,
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.06),
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
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('取消'),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          final timeoutSeconds = int.tryParse(
                            timeoutController.text,
                          );
                          if (timeoutSeconds == null || timeoutSeconds < 1) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('超時秒數至少要 1 秒')),
                            );
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
                              await provider.checkSelectedSources(
                                config: config,
                              );
                            }
                          } catch (error) {
                            if (pageContext.mounted) {
                              ScaffoldMessenger.of(pageContext).showSnackBar(
                                SnackBar(content: Text('校驗啟動失敗：$error')),
                              );
                            }
                          }
                        },
                        child: const Text('開始校驗'),
                      ),
                    ],
                  ),
            ),
      );
    } finally {
      keywordController.dispose();
      timeoutController.dispose();
    }
  }

  static Future<void> showBatchGroup(
    BuildContext context,
    SourceManagerProvider provider,
  ) async {
    final ctrl = TextEditingController();
    final pageContext = context;
    try {
      await showDialog<void>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('批量管理分組'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: ctrl,
                    decoration: const InputDecoration(hintText: '輸入或選擇分組名'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 150,
                    width: double.maxFinite,
                    child: ListView.builder(
                      itemCount: provider.groups.length,
                      itemBuilder: (ctx, i) {
                        final g = provider.groups[i];
                        if (g == '全部' || g == '未分組') {
                          return const SizedBox.shrink();
                        }
                        return ListTile(
                          title: Text(g),
                          dense: true,
                          onTap: () {
                            ctrl.value = TextEditingValue(
                              text: g,
                              selection: TextSelection.collapsed(
                                offset: g.length,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    final group = ctrl.text.trim();
                    if (group.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('請輸入或選擇分組名稱')),
                      );
                      return;
                    }
                    final selected = provider.selectedUrls;
                    Navigator.pop(dialogContext);
                    try {
                      await provider.selectionRemoveFromGroups(selected, group);
                    } catch (error) {
                      if (pageContext.mounted) {
                        ScaffoldMessenger.of(pageContext).showSnackBar(
                          SnackBar(content: Text('移除分組失敗：$error')),
                        );
                      }
                    }
                  },
                  child: const Text('移除分組'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final group = ctrl.text.trim();
                    if (group.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('請輸入或選擇分組名稱')),
                      );
                      return;
                    }
                    final selected = provider.selectedUrls;
                    Navigator.pop(dialogContext);
                    try {
                      await provider.selectionAddToGroups(selected, group);
                    } catch (error) {
                      if (pageContext.mounted) {
                        ScaffoldMessenger.of(pageContext).showSnackBar(
                          SnackBar(content: Text('加入分組失敗：$error')),
                        );
                      }
                    }
                  },
                  child: const Text('加入分組'),
                ),
              ],
            ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  static void confirmClearInvalid(
    BuildContext context,
    SourceManagerProvider provider,
  ) {
    final pageContext = context;
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('清理建議刪除來源'),
            content: const Text('會刪除目前標記為非小說、需要登入或下載站的來源。這些來源不會再參與搜尋或閱讀。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await provider.clearInvalidSources();
                    if (pageContext.mounted) {
                      ScaffoldMessenger.of(
                        pageContext,
                      ).showSnackBar(const SnackBar(content: Text('清理完成')));
                    }
                  } catch (error) {
                    if (pageContext.mounted) {
                      ScaffoldMessenger.of(
                        pageContext,
                      ).showSnackBar(SnackBar(content: Text('清理失敗：$error')));
                    }
                  }
                },
                child: Text(
                  '確定刪除',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
    );
  }

  static void confirmDeleteNonNovel(
    BuildContext context,
    SourceManagerProvider provider,
  ) {
    final pageContext = context;
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('刪除非小說源'),
            content: const Text('會直接刪除影音、漫畫、RSS 等非小說源，且無法復原。要繼續嗎？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    final affected = await provider.deleteNonNovelSources();
                    if (pageContext.mounted) {
                      ScaffoldMessenger.of(pageContext).showSnackBar(
                        SnackBar(content: Text('已刪除 $affected 個非小說源')),
                      );
                    }
                  } catch (error) {
                    if (pageContext.mounted) {
                      ScaffoldMessenger.of(pageContext).showSnackBar(
                        SnackBar(content: Text('刪除非小說源失敗：$error')),
                      );
                    }
                  }
                },
                child: Text(
                  '確定刪除',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
    );
  }

  static Future<void> showDebugInput(
    BuildContext context,
    BookSource source,
  ) async {
    final ctrl = TextEditingController(text: '我的世界');
    String? inputError;
    final pageContext = context;
    try {
      await showDialog<void>(
        context: context,
        builder:
            (ctx) => StatefulBuilder(
              builder:
                  (context, setDialogState) => AlertDialog(
                    title: const Text('輸入調試關鍵字'),
                    content: TextField(
                      controller: ctrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: '搜尋詞或 URL',
                        errorText: inputError,
                      ),
                      onChanged: (_) {
                        if (inputError != null) {
                          setDialogState(() => inputError = null);
                        }
                      },
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          final debugKey = ctrl.text.trim();
                          if (debugKey.isEmpty) {
                            setDialogState(() => inputError = '請輸入調試關鍵字或 URL');
                            return;
                          }
                          Navigator.pop(ctx);
                          Navigator.push(
                            pageContext,
                            MaterialPageRoute(
                              builder:
                                  (c) => SourceDebugPage(
                                    source: source,
                                    debugKey: debugKey,
                                  ),
                            ),
                          );
                        },
                        child: const Text('開始調試'),
                      ),
                    ],
                  ),
            ),
      );
    } finally {
      ctrl.dispose();
    }
  }
}
