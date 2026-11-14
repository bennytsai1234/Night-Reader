import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/ai_find/ai_find_prompt.dart';
import 'package:night_reader/core/ai_find/ai_find_session.dart';
import 'package:night_reader/core/ai_repair/ai_repair_settings.dart';
import 'package:night_reader/core/models/ai_find_record.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/background_work/background_work.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';
import 'package:night_reader/features/book_detail/book_detail_page.dart';
import 'package:night_reader/features/explore/widgets/explore_book_item.dart';
import 'package:night_reader/features/search/models/search_scope.dart';
import 'package:night_reader/features/search/widgets/search_result_item.dart';
import 'package:night_reader/features/source_manager/ai_repair/ai_repair_settings_page.dart';
import 'package:night_reader/features/source_manager/ai_repair/repair_runs.dart';
import 'package:night_reader/features/source_manager/ai_repair/source_repair_page.dart'
    show aiRepairStepIcon;
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/book_kind_mark.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/glass_segmented.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_find_run.dart';
import 'app_ai_find_library.dart';

/// 上次選的深度：只存這台手機、不同步（ADR 0060）。
const String aiFindDepthKey = 'ai_find.depth';

/// 搜尋頁的 ✦：有一次找書在跑、或做完還沒看過結果時推回那一頁；不然推
/// 開始前的頁面（docs/design/screens.md「AI 找書」）。
Future<void> openAiFind(BuildContext context) async {
  final navigator = Navigator.of(context);
  if (aiFindRuns.current case final AiFindRun current when !current.isDone) {
    await navigator.push(
      MaterialPageRoute<void>(builder: (_) => current.page()),
    );
    return;
  }
  await navigator.push(MaterialPageRoute<void>(builder: (_) => AiFindPage()));
}

/// 「過去的找書」一列右邊的日期：今年的寫「11/13」，不是今年的寫
/// 「2025/11/13」（docs/design/screens.md「搜尋」）。
String aiFindDateLabel(int millis, DateTime now) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  final day = '${date.month}/${date.day}';
  return date.year == now.year ? day : '${date.year}/$day';
}

/// 「8.4 萬 token」：頁面上的用量。
String aiFindTokens(int tokens) => tokens < 10000
    ? '$tokens token'
    : '${(tokens / 10000).toStringAsFixed(1)} 萬 token';

/// AI 找書頁：開始前填描述與深度；開始後一輪一列，做完列推薦與 AI 的說明
/// （docs/design/screens.md「AI 找書」）。給了 [record] 是「過去的找書」的
/// 一次報告。
class AiFindPage extends StatefulWidget {
  AiFindPage({
    super.key,
    this.run,
    this.record,
    AiRepairSettings? settings,
    SharedPreferences? prefs,
    this.startRun,
  }) : settings = settings ?? AiRepairSettings(prefs),
       _prefs = prefs;

  /// 在跑或跑完的那一次；開始前是 null。
  final AiFindRun? run;

  /// 過去的一次找書。
  final AiFindRecord? record;

  final AiRepairSettings settings;
  final SharedPreferences? _prefs;

  /// 開始找書時建立那一次；測試換掉它，不連真的書源與 AI 服務。
  final AiFindRun Function({
    required String description,
    required AiFindDepth depth,
    required AiService service,
    required SearchScope scope,
  })?
  startRun;

  @override
  State<AiFindPage> createState() => _AiFindPageState();
}

class _AiFindPageState extends State<AiFindPage> {
  final TextEditingController _description = TextEditingController();
  AiFindRun? _run;
  AiFindDepth _depth = AiFindDepth.normal;
  AiService? _service;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _run = widget.run;
    _description.addListener(_redraw);
    BackgroundWork.instance.addListener(_redraw);
    final run = _run;
    if (run != null) {
      _attach(run);
    } else if (widget.record == null) {
      unawaited(_loadDraft());
    }
  }

  Future<SharedPreferences> _prefs() async =>
      widget._prefs ?? await SharedPreferences.getInstance();

  Future<void> _loadDraft() async {
    final prefs = await _prefs();
    final service = await widget.settings.findService();
    if (!mounted) return;
    setState(() {
      _depth = AiFindDepth.fromName(prefs.getString(aiFindDepthKey));
      _service = service;
    });
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  /// 頁面看著這一次：通知點了不再推一頁；推入動畫播完才開始（ADR 0018）。
  void _attach(AiFindRun run) {
    run
      ..attach()
      ..addListener(_redraw);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      run.route = route;
      final animation = route?.animation;
      if (animation == null || animation.isCompleted) {
        run.start();
        return;
      }
      void begin(AnimationStatus status) {
        if (status != AnimationStatus.completed) return;
        animation.removeStatusListener(begin);
        if (mounted) run.start();
      }

      animation.addStatusListener(begin);
    });
  }

  @override
  void dispose() {
    _description.dispose();
    BackgroundWork.instance.removeListener(_redraw);
    final run = _run;
    if (run != null) {
      run
        ..removeListener(_redraw)
        ..detach();
    }
    super.dispose();
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 背景工作的位置空著、也沒有還沒看過結果的那一次（ADR 0058）。
  bool get _slotFree => backgroundWorkIdle() && aiFindRuns.canStartNew;

  bool get _canStart =>
      !_starting && _description.text.trim().isNotEmpty && _slotFree;

  Future<void> _start() async {
    if (!_canStart) return;
    FocusScope.of(context).unfocus();
    setState(() => _starting = true);
    try {
      final service = await widget.settings.findService();
      if (!mounted) return;
      if (service == null) {
        final choice = await showAppAlert<String>(
          context: context,
          title: 'AI 找書',
          message: '還沒設定 AI 服務。',
          actions: const [
            AppAlertAction(
              label: '設定 AI 服務',
              value: 'settings',
              isDefault: true,
            ),
            AppAlertAction(label: '取消', value: 'cancel'),
          ],
        );
        if (choice == 'settings' && mounted) await _openSettings();
        return;
      }
      // 讀設定的時候別的工作可能開始了。
      if (!_slotFree) return;
      final prefs = await _prefs();
      await prefs.setString(aiFindDepthKey, _depth.name);
      final scope = SearchScope.fromPrefs(prefs);
      final description = _description.text.trim();
      final run = (widget.startRun ?? _defaultRun)(
        description: description,
        depth: _depth,
        service: service,
        scope: scope,
      );
      if (!mounted || !aiFindRuns.adopt(run)) {
        run
          ..disposeWork()
          ..dispose();
        return;
      }
      setState(() => _run = run);
      _attach(run);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  static AiFindRun _defaultRun({
    required String description,
    required AiFindDepth depth,
    required AiService service,
    required SearchScope scope,
  }) => AiFindRun(
    AiFindSession(
      description: description,
      depth: depth,
      library: AppAiFindLibrary(scope: scope),
      ask: AiFindSession.askService(service),
      serviceLabel: _serviceLabel(service),
    ),
  );

  static String _serviceLabel(AiService service) =>
      '${Uri.tryParse(service.baseUrl)?.host ?? service.baseUrl} · '
      '${service.model}';

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AiRepairSettingsPage()),
    );
    if (!mounted || _run != null) return;
    final service = await widget.settings.findService();
    if (mounted) setState(() => _service = service);
  }

  Future<void> _copySummary(AiFindSession session) async {
    await Clipboard.setData(ClipboardData(text: session.log.summary));
    if (mounted) _say('已複製摘要');
  }

  Future<void> _shareFullLog(AiFindSession session) async {
    final file = await session.log.file();
    if (file == null) {
      if (mounted) _say('完整紀錄沒有存成檔案');
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')],
        subject: 'AI 找書紀錄：${session.description}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _run?.session;
    final record = widget.record ?? session?.record;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassNavHeader(
        title: 'AI 找書',
        actions: [
          if (widget.record == null)
            GlassMenuButton<String>(
              entriesBuilder: (_) => [
                const GlassMenuItem(
                  value: 'settings',
                  icon: Icons.tune_rounded,
                  label: 'AI 服務設定',
                ),
                GlassMenuItem(
                  value: 'copy',
                  icon: Icons.copy_rounded,
                  label: '複製摘要',
                  enabled: session != null,
                ),
                GlassMenuItem(
                  value: 'share',
                  icon: Icons.ios_share_rounded,
                  label: '分享完整紀錄',
                  enabled: session != null,
                ),
              ],
              onSelected: (value) {
                switch (value) {
                  case 'settings':
                    unawaited(_openSettings());
                  case 'copy' when session != null:
                    unawaited(_copySummary(session));
                  case 'share' when session != null:
                    unawaited(_shareFullLog(session));
                }
              },
            ),
        ],
      ),
      body: GroupedListView(
        children: [
          if (record != null)
            ..._report(context, record, finished: widget.record == null)
          else if (session != null)
            ..._running(context, session)
          else
            ..._draft(context),
        ],
      ),
    );
  }

  String? get _sentTo {
    final label = _run?.session.serviceLabel;
    if (label != null && label.isNotEmpty) return '送到 $label';
    final service = _service;
    return service == null ? null : '送到 ${_serviceLabel(service)}';
  }

  List<Widget> _draft(BuildContext context) => [
    GroupedSection(
      children: [
        GroupedTextFieldRow(
          controller: _description,
          hintText: '想看什麼樣的書',
          keyboardType: TextInputType.multiline,
          minLines: 4,
          maxLines: 8,
        ),
      ],
    ),
    GroupedSection(
      header: '深度',
      children: [
        GroupedContent(
          child: GlassSegmented<AiFindDepth>(
            segments: [
              for (final depth in AiFindDepth.values)
                GlassSegment(depth, depth.label),
            ],
            selected: _depth,
            onChanged: (depth) => setState(() => _depth = depth),
          ),
        ),
      ],
    ),
    GroupedSection(
      footer: _sentTo,
      children: [
        GroupedRow(
          title: '開始找書',
          accent: true,
          showChevron: false,
          enabled: _canStart,
          onTap: _canStart ? () => unawaited(_start()) : null,
        ),
      ],
    ),
  ];

  List<Widget> _running(BuildContext context, AiFindSession session) => [
    GroupedSection(
      footer: _sentTo,
      children: [
        GroupedRow(
          title: context.zh(session.description),
          subtitle: '深度：${session.depth.label}',
          showChevron: false,
          maxTitleLines: 3,
        ),
        for (final round in session.rounds)
          GroupedRow(
            leading: aiRepairStepIcon(context, round.state),
            title: round.title,
            subtitle: round.detail,
            showChevron: false,
          ),
        GroupedRow(
          title: 'AI 用量',
          value: aiFindTokens(session.tokens),
          showChevron: false,
        ),
      ],
    ),
    GroupedSection(
      children: [
        GroupedRow(
          title: session.isStopped ? '正在停下…' : '停止',
          destructive: true,
          showChevron: false,
          onTap: session.isStopped ? null : session.stop,
        ),
      ],
    ),
  ];

  /// 做完的那一次（[finished]，最後一張是「完成」）或過去的一次。
  List<Widget> _report(
    BuildContext context,
    AiFindRecord record, {
    required bool finished,
  }) {
    final depth = AiFindDepth.fromName(record.depth);
    final bodyStyle = AppTextStyles.bodySm.copyWith(
      color: Theme.of(context).colorScheme.onSurface,
    );
    return [
      GroupedSection(
        children: [
          GroupedRow(
            title: context.zh(record.description),
            subtitle:
                '深度：${depth.label} · ${record.rounds} 輪 · '
                '${aiFindTokens(record.tokens)}',
            showChevron: false,
            maxTitleLines: 3,
          ),
        ],
      ),
      if (record.outcome != AiFindOutcome.found)
        GroupedSection(
          header: '沒有找完',
          children: [
            GroupedRow(
              title: record.outcome == AiFindOutcome.stopped
                  ? '已停止'
                  : record.failure.isEmpty
                  ? '沒有找完'
                  : record.failure,
              showChevron: false,
              maxTitleLines: 6,
            ),
          ],
        )
      else ...[
        if (record.picks.isNotEmpty)
          GroupedSection(
            header: '推薦 · ${record.picks.length}',
            children: [
              for (final pick in record.picks) _AiFindPickRow(pick: pick),
            ],
          ),
        if (record.summary.trim().isNotEmpty)
          GroupedSection(
            header: 'AI 的說明',
            children: [
              GroupedContent(
                child: Text(context.zh(record.summary), style: bodyStyle),
              ),
            ],
          ),
      ],
      if (finished)
        GroupedSection(
          children: [
            GroupedRow(
              title: '完成',
              accent: true,
              showChevron: false,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
    ];
  }
}

/// 推薦的一本：封面、書名、「作者 · 字數 · 分類」與推薦理由（不截斷）；點了
/// 照找到它的書源進書籍詳情。
class _AiFindPickRow extends StatelessWidget {
  const _AiFindPickRow({required this.pick});

  final AiFindPick pick;

  @override
  Widget build(BuildContext context) {
    final book = pick.book;
    final scheme = Theme.of(context).colorScheme;
    final secondary = AppTextStyles.bodySm.copyWith(
      height: 1.35,
      color: scheme.onSurfaceVariant,
    );
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BookDetailPage(
            searchBook: AggregatedSearchBook(
              book: book,
              sources: book.sourceLabels.isNotEmpty
                  ? book.sourceLabels
                  : [book.originName ?? book.origin],
            ),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppGrouped.margin,
          AppSpacing.md,
          AppGrouped.margin,
          AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookKindMark.onCover(
              book.bookKind,
              BookCoverWidget(
                coverUrl: book.coverUrl,
                bookName: context.zh(book.name),
                kind: book.bookKind,
                author: context.zh(book.author ?? ''),
                width: ExploreBookItem.coverWidth,
                height: ExploreBookItem.coverHeight,
                borderRadius: AppRadius.cardXs,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.zh(book.name),
                    style: AppTextStyles.bodyBase.copyWith(
                      height: 1.3,
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatSearchResultMetadata(
                      author: context.zh(book.author ?? ''),
                      kind: context.zh(book.kind ?? ''),
                      wordCount: book.wordCount,
                    ),
                    style: secondary,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    context.zh(pick.reason),
                    style: AppTextStyles.bodySm.copyWith(
                      height: 1.45,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
