import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/update_preferences.dart';
import 'package:night_reader/core/services/update_service.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

/// 更新紀錄：列出 GitHub Releases 上各版的發布說明。
///
/// 有開「接收測試版更新」時包含測試版，沒開只列正式版。
class ReleaseNotesPage extends StatefulWidget {
  const ReleaseNotesPage({super.key, this.service, this.preferences});

  final AppUpdateService? service;
  final UpdatePreferences? preferences;

  @override
  State<ReleaseNotesPage> createState() => _ReleaseNotesPageState();
}

enum _ReleaseNotesStatus { loading, loaded, error }

class _ReleaseNotesPageState extends State<ReleaseNotesPage> {
  static final _dateFormat = DateFormat('yyyy-MM-dd');

  late final _service = widget.service ?? AppUpdateService();
  late final _preferences = widget.preferences ?? UpdatePreferences();
  _ReleaseNotesStatus _status = _ReleaseNotesStatus.loading;
  List<ReleaseNote> _notes = const [];

  /// 載入失敗後按了重試、還在等：錯誤畫面留著，按鈕寫「重新載入中…」。
  /// 這時不是推入頁面，沒有進場骨架可以接（[GroupedListView.ready]）。
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _retry() {
    setState(() => _retrying = true);
    _load();
  }

  Future<void> _load() async {
    try {
      final notes = await _service.fetchReleaseNotes(
        includeBeta: await _preferences.betaChannel(),
      );
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _status = _ReleaseNotesStatus.loaded;
        _retrying = false;
      });
    } catch (error, stackTrace) {
      AppLog.e('讀取更新紀錄失敗', error: error, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _status = _ReleaseNotesStatus.error;
          _retrying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassNavHeader(title: '更新紀錄'),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_status == _ReleaseNotesStatus.error) {
      return AppStateView(
        icon: Icons.cloud_off_outlined,
        title: '更新紀錄載入失敗',
        description: '請確認網路連線後再試一次。',
        tone: AppStateTone.error,
        primaryAction: AppStateAction(
          label: _retrying ? '重新載入中…' : '重試',
          icon: Icons.refresh,
          onPressed: _retrying ? null : _retry,
        ),
      );
    }
    final loading = _status == _ReleaseNotesStatus.loading;
    if (!loading && _notes.isEmpty) {
      return const AppStateView(icon: Icons.history_rounded, title: '目前沒有更新紀錄');
    }
    // 骨架照幾段固定樣子的版本畫（還不知道有幾版、各寫了多少），資料到了
    // 先照真正的版本變一次形狀再換場（[GroupedListView.ready]）。
    return GroupedListView(
      ready: !loading,
      loadingLabel: '正在載入更新紀錄',
      children: [
        if (loading)
          for (final (index, lines) in const [4, 2, 3, 2].indexed)
            _buildPlaceholder(context, lines: lines, first: index == 0)
        else
          for (final (index, note) in _notes.indexed)
            _buildRelease(context, note, first: index == 0),
      ],
    );
  }

  /// 載入中骨架照的一段版本：和 [_buildRelease] 同樣的標題、日期與 [lines]
  /// 行說明（最後一行短一些）。只給骨架量形狀，不會顯示出來。
  Widget _buildPlaceholder(
    BuildContext context, {
    required int lines,
    required bool first,
  }) {
    final chrome = AppChrome.of(context);
    return GroupedSection(
      topGap: first ? AppSpacing.md : AppGrouped.sectionGap,
      header: 'v0.0.0',
      headerTrailing: Text(
        '0000-00-00',
        style: AppTextStyles.uiSm.copyWith(color: chrome.sectionText),
      ),
      children: [
        GroupedContent(
          // 每行字數不同、最後一行短，像一段條列；都短於手機的一行寬，不會
          // 自己換行。
          child: Text(
            [
              for (var i = 0; i < lines; i++)
                '• ${'更新說明' * 6}'.substring(
                  0,
                  i == lines - 1 ? 9 : const [20, 17, 19][i % 3],
                ),
            ].join('\n'),
            style: AppTextStyles.bodySm.copyWith(height: 1.5),
          ),
        ),
      ],
    );
  }

  Widget _buildRelease(
    BuildContext context,
    ReleaseNote note, {
    required bool first,
  }) {
    final chrome = AppChrome.of(context);
    final notes = releaseNotesForDisplay(note.body);
    final publishedAt = note.publishedAt;
    return GroupedSection(
      topGap: first ? AppSpacing.md : AppGrouped.sectionGap,
      header: note.isCurrent
          ? 'v${note.versionName}（目前版本）'
          : 'v${note.versionName}',
      headerTrailing: publishedAt == null
          ? null
          : Text(
              _dateFormat.format(publishedAt),
              style: AppTextStyles.uiSm.copyWith(color: chrome.sectionText),
            ),
      children: [
        GroupedContent(
          child: Text(
            notes.isEmpty ? '這個版本沒有附更新說明。' : notes,
            style: AppTextStyles.bodySm.copyWith(
              height: 1.5,
              color: notes.isEmpty
                  ? chrome.sectionText
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
