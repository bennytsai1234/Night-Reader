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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _status = _ReleaseNotesStatus.loading);
    try {
      final notes = await _service.fetchReleaseNotes(
        includeBeta: await _preferences.betaChannel(),
      );
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _status = _ReleaseNotesStatus.loaded;
      });
    } catch (error, stackTrace) {
      AppLog.e('讀取更新紀錄失敗', error: error, stackTrace: stackTrace);
      if (mounted) setState(() => _status = _ReleaseNotesStatus.error);
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
    switch (_status) {
      case _ReleaseNotesStatus.loading:
        return Center(
          child: Semantics(
            liveRegion: true,
            label: '正在載入更新紀錄',
            child: const ExcludeSemantics(child: CircularProgressIndicator()),
          ),
        );
      case _ReleaseNotesStatus.error:
        return AppStateView(
          icon: Icons.cloud_off_outlined,
          title: '更新紀錄載入失敗',
          description: '請確認網路連線後再試一次。',
          tone: AppStateTone.error,
          primaryAction: AppStateAction(
            label: '重試',
            icon: Icons.refresh,
            onPressed: _load,
          ),
        );
      case _ReleaseNotesStatus.loaded:
        if (_notes.isEmpty) {
          return const AppStateView(
            icon: Icons.history_rounded,
            title: '目前沒有更新紀錄',
            description: '發布新版後，各版的更新內容會列在這裡。',
          );
        }
        return GroupedListView(
          children: [
            for (final (index, note) in _notes.indexed)
              _buildRelease(context, note, first: index == 0),
          ],
        );
    }
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
