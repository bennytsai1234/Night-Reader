import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/crash_handler.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';

class CrashLogPage extends StatefulWidget {
  const CrashLogPage({
    super.key,
    this.readLogs,
    this.clearLogs,
    this.writeClipboard,
  });

  final Future<String> Function()? readLogs;
  final Future<void> Function()? clearLogs;
  final Future<void> Function(String text)? writeClipboard;

  @override
  State<CrashLogPage> createState() => _CrashLogPageState();
}

enum _CrashLogStatus { loading, loaded, error }

class _CrashLogPageState extends State<CrashLogPage> {
  _CrashLogStatus _status = _CrashLogStatus.loading;
  String _logs = '';
  Object? _loadError;
  bool _isClearing = false;

  bool get _hasLogs => _logs.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    if (mounted) {
      setState(() {
        _status = _CrashLogStatus.loading;
        _loadError = null;
      });
    }
    try {
      final logs = await (widget.readLogs ?? CrashHandler.readLogs)();
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _status = _CrashLogStatus.loaded;
      });
    } catch (error, stackTrace) {
      AppLog.e('讀取崩潰日誌失敗', error: error, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _status = _CrashLogStatus.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUseLogs =
        _status == _CrashLogStatus.loaded && _hasLogs && !_isClearing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('崩潰日誌'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: '複製日誌',
            onPressed: canUseLogs ? _copyLogs : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever_outlined),
            tooltip: '清除日誌',
            onPressed: canUseLogs ? _confirmClearLogs : null,
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_status) {
      case _CrashLogStatus.loading:
        return Center(
          child: Semantics(
            liveRegion: true,
            label: '正在載入崩潰日誌',
            child: ExcludeSemantics(child: CircularProgressIndicator()),
          ),
        );
      case _CrashLogStatus.error:
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '崩潰日誌載入失敗',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SelectableText(
                  _loadError.toString(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: _loadLogs,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重試'),
                ),
              ],
            ),
          ),
        );
      case _CrashLogStatus.loaded:
        if (!_hasLogs) {
          return Center(
            child: Semantics(
              label: '目前沒有崩潰日誌',
              child: ExcludeSemantics(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.article_outlined,
                      size: 56,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Text('目前沒有崩潰日誌'),
                  ],
                ),
              ),
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: SelectableText(
            _logs,
            style: AppTextStyles.labelSm.copyWith(
              height: 1.45,
              fontFamily: 'monospace',
            ),
          ),
        );
    }
  }

  Future<void> _copyLogs() async {
    try {
      final writer = widget.writeClipboard;
      if (writer == null) {
        await Clipboard.setData(ClipboardData(text: _logs));
      } else {
        await writer(_logs);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('已複製至剪貼簿')));
    } catch (error, stackTrace) {
      AppLog.e('複製崩潰日誌失敗', error: error, stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('複製崩潰日誌失敗')));
    }
  }

  Future<void> _confirmClearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.cardXl,
            ),
            title: const Text('清除崩潰日誌？'),
            content: const Text('清除後無法復原。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('清除'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isClearing = true);
    try {
      await (widget.clearLogs ?? CrashHandler.clearLogs)();
      await _loadLogs();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('已清除崩潰日誌')));
    } catch (error, stackTrace) {
      AppLog.e('清除崩潰日誌失敗', error: error, stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('清除崩潰日誌失敗：$error')));
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }
}
