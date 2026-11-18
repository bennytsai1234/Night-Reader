import 'package:night_reader/core/exception/user_error.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/ui_text.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/core/services/source_debug_service.dart';

import 'source_debug_provider.dart';

import 'package:night_reader/core/services/ui_language.dart';

enum _DebugAction { copy, restart }

class SourceDebugPage extends StatefulWidget {
  final BookSource source;
  final String debugKey;
  final SourceDebugService? debugService;
  final Future<void> Function(ClipboardData data)? writeClipboard;

  const SourceDebugPage({
    super.key,
    required this.source,
    required this.debugKey,
    this.debugService,
    this.writeClipboard,
  });

  @override
  State<SourceDebugPage> createState() => _SourceDebugPageState();
}

class _SourceDebugPageState extends State<SourceDebugPage> {
  final ScrollController _scrollController = ScrollController();
  int _followedLogCount = 0;

  void _scrollToBottom() {
    if (!mounted) return;
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _copyFullLog(List<dynamic> logs) async {
    final fullLog = logs.map((l) => l.toString()).join('\n');
    try {
      final writeClipboard = widget.writeClipboard ?? Clipboard.setData;
      await writeClipboard(ClipboardData(text: fullLog));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: UiText('已複製完整日誌至剪貼簿')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: UiText(failureMessage('複製日誌', error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final provider = SourceDebugProvider(
          widget.source,
          widget.debugKey,
          debugService: widget.debugService,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!provider.isDisposed) provider.startDebug();
        });
        return provider;
      },
      child: Consumer<SourceDebugProvider>(
        builder: (context, provider, child) {
          // 只在有新日誌、而且使用者原本就停在底部附近（不到約兩行）時才跟到
          // 最底；往上捲著看前面的日誌時不打斷。
          final grew = provider.logs.length > _followedLogCount;
          _followedLogCount = provider.logs.length;
          final atBottom =
              !_scrollController.hasClients ||
              _scrollController.position.extentAfter < 48;
          if (grew && atBottom) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _scrollToBottom(),
            );
          }

          final busy = provider.isRunning || !provider.isFinished;
          return Scaffold(
            appBar: GlassNavHeader(
              // 除錯日誌照整個畫面寬，長網址少換行。
              readable: false,
              title: '${context.ui('除錯：')}${widget.source.bookSourceName}',
              translateTitle: false,
              // 頁首右邊只有一顆，動作都收進「更多」（docs/design/components.md
              // 「左右各一顆」）；除錯中由頁首下緣的進度線表示。
              actions: [
                GlassMenuButton<_DebugAction>(
                  // 兩項都不能按時整顆停用（ADR 0059）。
                  enabled: provider.logs.isNotEmpty || !busy,
                  entriesBuilder: (_) => [
                    GlassMenuItem(
                      value: _DebugAction.copy,
                      label: '複製完整日誌',
                      icon: Icons.copy_rounded,
                      enabled: provider.logs.isNotEmpty,
                    ),
                    GlassMenuItem(
                      value: _DebugAction.restart,
                      label: '重新除錯',
                      icon: Icons.refresh_rounded,
                      enabled: !busy,
                    ),
                  ],
                  onSelected: (action) => switch (action) {
                    _DebugAction.copy => _copyFullLog(provider.logs),
                    _DebugAction.restart => provider.startDebug(),
                  },
                ),
              ],
            ),
            body: Stack(
              children: [
                Positioned.fill(
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppGrouped.margin,
                        AppSpacing.xs,
                        AppGrouped.margin,
                        AppGrouped.margin,
                      ),
                      child: _DebugConsole(
                        logs: provider.logs,
                        isFinished: provider.isFinished,
                        controller: _scrollController,
                      ),
                    ),
                  ),
                ),
                // 除錯中頁首下緣一條載入進度線，同登入用的瀏覽器頁。
                if (busy)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: Semantics(
                      label: context.ui('除錯中'),
                      liveRegion: true,
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        color: Theme.of(context).colorScheme.primary,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

/// 除錯日誌主控台：固定夜墨底的圓角卡片，等寬字，依步驟上色。
class _DebugConsole extends StatelessWidget {
  const _DebugConsole({
    required this.logs,
    required this.isFinished,
    required this.controller,
  });

  final List<DebugLog> logs;
  final bool isFinished;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppGrouped.cardRadius,
      child: ColoredBox(
        color: AppPalette.ink700,
        child: SizedBox.expand(
          child: logs.isEmpty
              ? Center(
                  child: UiText(
                    isFinished ? '沒有除錯日誌' : '準備除錯…',
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppPalette.ink100,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: controller,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    var textColor = AppPalette.ink50;
                    if (log.state == -1) {
                      textColor = AppPalette.rustDark;
                    } else if (log.state == 1000) {
                      textColor = AppPalette.mossDark;
                    } else if (log.state >= 10 && log.state <= 40) {
                      textColor = AppPalette.azuriteDark;
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: SelectableText.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${log.formattedTime} ',
                              style: AppTextStyles.labelXs.copyWith(
                                color: AppPalette.ink200,
                                fontFamily: 'monospace',
                              ),
                            ),
                            TextSpan(
                              text: log.message,
                              style: AppTextStyles.labelSm.copyWith(
                                color: textColor,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
