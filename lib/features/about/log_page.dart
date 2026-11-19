import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:night_reader/core/exception/user_error.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/chinese/ui_language.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:night_reader/shared/layout/readable_width.dart';
import 'package:night_reader/shared/navigation/transition_settled.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/ui_text.dart';
import 'package:share_plus/share_plus.dart';

/// 「關於夜讀」裡看一份日誌的頁面：讀出來顯示（[LogTextView]），可以複製、
/// 存成文字檔分享出去（系統的分享面板也能存進手機的檔案或雲端硬碟），
/// 也可以清除。
class LogPage extends StatefulWidget {
  const LogPage({
    super.key,
    required this.title,
    required this.emptyTitle,
    required this.fileName,
    required this.readLogs,
    required this.clearLogs,
    this.writeClipboard,
    this.shareFile,
  });

  /// 頁首的標題，也用在提示與確認視窗裡（「已清除崩潰日誌」）。
  final String title;

  /// 沒有內容時的說明（「目前沒有崩潰日誌」）。
  final String emptyTitle;

  /// 分享出去的檔名開頭；後面接上分享的時間與 `.txt`。
  final String fileName;

  /// 讀出整份日誌，切成一段段（接回整份用 `join()`）；沒有內容時是空清單。
  final Future<List<String>> Function() readLogs;
  final Future<void> Function() clearLogs;
  final Future<void> Function(String text)? writeClipboard;

  /// 測試換掉分享：拿到寫好的檔案路徑。
  final Future<void> Function(String path)? shareFile;

  @override
  State<LogPage> createState() => _LogPageState();
}

enum _LogStatus { loading, loaded, error }

enum _LogAction { copy, share, clear }

class _LogPageState extends State<LogPage> {
  _LogStatus _status = _LogStatus.loading;
  List<String> _chunks = const [];
  Object? _loadError;
  bool _hasLogs = false;
  bool _busy = false;

  /// 進場播完：讀好的日誌等到這時才放上來，不和換頁搶同一幀（ADR 0037
  /// 「等靜止再放」）。
  Future<void>? _entrance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 先有進場的等待才開始讀：讀取當下就完成時，也照樣等換頁播完。
    if (_entrance != null) return;
    _entrance = TransitionSettled.entered(context);
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    if (mounted) {
      setState(() {
        _status = _LogStatus.loading;
        _loadError = null;
      });
    }
    try {
      final chunks = await widget.readLogs();
      await _entrance;
      if (!mounted) return;
      setState(() {
        _chunks = chunks;
        _hasLogs = chunks.any((chunk) => chunk.trim().isNotEmpty);
        _status = _LogStatus.loaded;
      });
    } catch (error, stackTrace) {
      AppLog.e('讀取${widget.title}失敗', error: error, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _status = _LogStatus.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUseLogs = _status == _LogStatus.loaded && _hasLogs && !_busy;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassNavHeader(
        title: widget.title,
        actions: [
          // 和 AI 找書頁的「複製摘要」「分享完整紀錄」同一種做法：三顆圓鈕
          // 會把標題擠到一邊（使用者 2026-11-18 從候選圖選的）。
          GlassMenuButton<_LogAction>(
            enabled: canUseLogs,
            entriesBuilder: (_) => const [
              GlassMenuItem(
                value: _LogAction.copy,
                icon: Icons.copy_rounded,
                label: '複製日誌',
              ),
              GlassMenuItem(
                value: _LogAction.share,
                icon: Icons.ios_share_rounded,
                label: '分享日誌檔',
              ),
              GlassMenuItem(
                value: _LogAction.clear,
                icon: Icons.delete_outline_rounded,
                label: '清除日誌',
                destructive: true,
              ),
            ],
            onSelected: (action) => unawaited(switch (action) {
              _LogAction.copy => _copyLogs(),
              _LogAction.share => _shareLogs(),
              _LogAction.clear => _confirmClearLogs(),
            }),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_status) {
      case _LogStatus.loading:
        return Center(
          child: Semantics(
            liveRegion: true,
            label: context.ui('正在載入${widget.title}'),
            child: const ExcludeSemantics(child: CircularProgressIndicator()),
          ),
        );
      case _LogStatus.error:
        return AppStateView(
          icon: Icons.error_outline,
          title: '${widget.title}載入失敗',
          description: userErrorReason(_loadError!),
          tone: AppStateTone.error,
          primaryAction: AppStateAction(
            label: '重試',
            icon: Icons.refresh,
            onPressed: _loadLogs,
          ),
        );
      case _LogStatus.loaded:
        if (!_hasLogs) {
          return AppStateView(
            icon: Icons.article_outlined,
            title: widget.emptyTitle,
          );
        }
        return LogTextView(chunks: _chunks);
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: UiText(message)));
  }

  Future<void> _copyLogs() async {
    final text = _chunks.join();
    try {
      final writer = widget.writeClipboard;
      if (writer == null) {
        await Clipboard.setData(ClipboardData(text: text));
      } else {
        await writer(text);
      }
      _say('已複製至剪貼簿');
    } catch (error, stackTrace) {
      AppLog.e('複製${widget.title}失敗', error: error, stackTrace: stackTrace);
      // 太長時剪貼簿放不下；檔案沒有這個限制。
      _say('複製${widget.title}失敗，可以改用分享日誌檔');
    }
  }

  Future<void> _shareLogs() async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final stamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
      final file = await AppStoragePaths.shareExportFile(
        '${widget.fileName}-$stamp.txt',
      );
      await file.writeAsString(_chunks.join(), flush: true);
      // 寫檔時已經離開這頁：不再跳出系統分享。
      if (!mounted) return;
      final share = widget.shareFile;
      if (share != null) {
        await share(file.path);
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'text/plain')],
            subject: widget.title,
          ),
        );
      }
    } catch (error, stackTrace) {
      AppLog.e('分享${widget.title}失敗', error: error, stackTrace: stackTrace);
      _say('分享${widget.title}失敗：${userErrorReason(error)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmClearLogs() async {
    if (!mounted) return;
    final confirmed = await showAppConfirm(
      context: context,
      title: '清除${widget.title}？',
      confirmLabel: '清除',
      destructive: true,
      irreversible: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.clearLogs();
      await _loadLogs();
      _say('已清除${widget.title}');
    } catch (error, stackTrace) {
      AppLog.e('清除${widget.title}失敗', error: error, stackTrace: stackTrace);
      _say('清除${widget.title}失敗：${userErrorReason(error)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// 一份長日誌放在一張分組卡片裡：照 [chunks] 一段一列、捲到才排版，片與
/// 片之間不畫線，看起來是同一段字；可以跨段選取。整份放進同一段字的話，
/// 百萬字排一次要好幾秒。
class LogTextView extends StatelessWidget {
  const LogTextView({super.key, required this.chunks});

  final List<String> chunks;

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final mediaPadding = MediaQuery.paddingOf(context);
    final style = AppTextStyles.labelSm.copyWith(
      height: 1.45,
      fontFamily: 'monospace',
      color: Theme.of(context).colorScheme.onSurface,
    );
    final count = chunks.length;
    return ColoredBox(
      color: chrome.groupedBackground,
      child: SelectionArea(
        child: ListView.builder(
          padding:
              EdgeInsets.only(
                top: mediaPadding.top + AppSpacing.md,
                bottom: mediaPadding.bottom + AppSpacing.xxxl,
              ) +
              ReadableWidth.insetOf(context),
          itemCount: count,
          itemBuilder: (context, i) => GroupedSliceItem(
            index: i,
            count: count,
            separated: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppGrouped.rowPadding,
                i == 0 ? AppSpacing.md : 0,
                AppGrouped.rowPadding,
                i == count - 1 ? AppSpacing.md : 0,
              ),
              child: _LogChunk(chunk: chunks[i], style: style),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一個片段。片段多半切在換行之後：那個換行不畫（下一片本來就從新的一行
/// 開始，畫了會多一行空白），選取蓋到這片結尾時再補回複製的字裡，跨片
/// 選取複製出來的換行才和原文一樣。
class _LogChunk extends StatefulWidget {
  const _LogChunk({required this.chunk, required this.style});

  final String chunk;
  final TextStyle style;

  @override
  State<_LogChunk> createState() => _LogChunkState();
}

class _LogChunkState extends State<_LogChunk> {
  final _selection = _TrailingNewlineSelection();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chunk = widget.chunk;
    if (!chunk.endsWith('\n')) return Text(chunk, style: widget.style);
    return SelectionContainer(
      delegate: _selection,
      child: Text(chunk.substring(0, chunk.length - 1), style: widget.style),
    );
  }
}

/// 選取蓋到結尾時，複製的字後面補上這片沒畫出來的換行。
class _TrailingNewlineSelection extends StaticSelectionContainerDelegate {
  @override
  SelectedContent? getSelectedContent() {
    final content = super.getSelectedContent();
    final range = getSelection();
    if (content == null || range == null) return content;
    final end = math.max(range.startOffset, range.endOffset);
    return end >= contentLength
        ? SelectedContent(plainText: '${content.plainText}\n')
        : content;
  }
}
