import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已複製完整日誌至剪貼簿')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('複製日誌失敗：$error')));
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
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _scrollToBottom(),
          );

          return Scaffold(
            appBar: AppBar(
              title: Text('除錯：${widget.source.bookSourceName}'),
              actions: [
                if (provider.isRunning || !provider.isFinished)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed:
                      provider.logs.isEmpty
                          ? null
                          : () => _copyFullLog(provider.logs),
                  tooltip: '複製完整日誌',
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed:
                      provider.isFinished && !provider.isRunning
                          ? () => provider.startDebug()
                          : null,
                  tooltip: '重新除錯',
                ),
              ],
            ),
            body: Container(
              color: Colors.black87,
              width: double.infinity,
              child:
                  provider.logs.isEmpty
                      ? Center(
                        child: Text(
                          provider.isFinished ? '沒有除錯日誌' : '準備除錯…',
                          style: AppTextStyles.bodySm.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      )
                      : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        itemCount: provider.logs.length,
                        itemBuilder: (context, index) {
                          final log = provider.logs[index];
                          var textColor = Colors.white;

                          if (log.state == -1) {
                            textColor = Colors.redAccent;
                          } else if (log.state == 1000) {
                            textColor = Colors.greenAccent;
                          } else if (log.state >= 10 && log.state <= 40) {
                            textColor = Colors.lightBlueAccent;
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: SelectableText.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${log.formattedTime} ',
                                    style: AppTextStyles.labelXs.copyWith(
                                      color: Colors.white70,
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
