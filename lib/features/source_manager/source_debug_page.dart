import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/core/services/source_debug_service.dart';

import 'source_debug_provider.dart';

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
          .showSnackBar(const SnackBar(content: Text('已複製完整日誌至剪貼簿')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('複製日誌失敗：$error')));
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
              title: '除錯：${widget.source.bookSourceName}',
              actions: [
                GlassIconButton(
                  icon: Icons.copy_rounded,
                  iconSize: 20,
                  onPressed: provider.logs.isEmpty
                      ? null
                      : () => _copyFullLog(provider.logs),
                  tooltip: '複製完整日誌',
                ),
                busy
                    ? Semantics(
                        label: '除錯中',
                        liveRegion: true,
                        child: const SizedBox.square(
                          dimension: AppGlass.buttonSize,
                          child: GlassSurface(
                            shape: BoxShape.circle,
                            shadow: false,
                            child: Center(
                              child: SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    : GlassIconButton(
                        icon: Icons.refresh_rounded,
                        onPressed: () => provider.startDebug(),
                        tooltip: '重新除錯',
                      ),
              ],
            ),
            body: SafeArea(
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
                  child: Text(
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
