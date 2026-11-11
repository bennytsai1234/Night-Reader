import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/exception/user_error.dart';
import 'package:night_reader/core/services/book_cover_storage_service.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/core/services/source_switch_service.dart';
import 'package:night_reader/features/book_detail/widgets/change_source_sheet.dart';
import 'package:night_reader/shared/navigation/book_open_route.dart';
import 'package:night_reader/shared/navigation/transition_settled.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_chapter_files.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';
import 'package:night_reader/core/widgets/default_book_cover.dart';
import 'package:night_reader/features/about/crash_log_page.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_orientation.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_window_settings.dart';
import 'package:night_reader/features/source_login/source_failure_remedy.dart';
import 'package:night_reader/features/source_login/source_login_page.dart';
import 'package:night_reader/features/source_manager/source_editor_page.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/number_stepper_row.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:night_reader/shared/widgets/sleep_timer_section.dart';
import 'package:night_reader/shared/widgets/toc_volume_row.dart';

import 'audiobook_player.dart';

/// 有聲書播放器（`docs/design/audiobook.md`「播放器」）：集數清單是主體，
/// 控制在底部的浮動玻璃膠囊，膠囊上方是倍速、定時、播放模式三顆圓鈕。
/// 畫面只看 [AudiobookPlayer]，離開這頁照樣在播。
class AudiobookPage extends StatefulWidget {
  const AudiobookPage({
    super.key,
    required this.book,
    this.chapterIndex,
    this.player,
  });

  final Book book;

  /// 從目錄點了某一集時是那一集、從頭播；null 時接著上次聽的地方。
  final int? chapterIndex;

  /// 測試換成自己的播放器；平常是 [AudiobookPlayer.instance]。
  final AudiobookPlayer? player;

  @override
  State<AudiobookPage> createState() => _AudiobookPageState();
}

enum _MoreAction { changeSource, login, keepAwake, copyUrl, editSource, log }

class _AudiobookPageState extends State<AudiobookPage> {
  late final AudiobookPlayer _player =
      widget.player ?? AudiobookPlayer.instance;

  /// 已下載的集（[BookChapterFiles.baseNameFor]）；清單畫小勾。
  Set<String> _downloaded = const {};

  /// 這本書的下載做完時重讀已下載的集（清單畫小勾）。
  StreamSubscription<AppEvent>? _downloads;

  /// 集數清單的捲動；第一次畫清單時照正在播的那集決定起點。
  ScrollController? _listScroll;
  ScrollController? _skeletonScroll;

  /// 換頁動畫播完了：這之後才開書、才把骨架換成清單（ADR 0037 等靜止
  /// 再放）。換頁途中建整份清單、播換場，每一幀都超過上限。
  bool _entered = false;

  /// 已經提示過的播放錯誤：同一次失敗只跳一次提示（重試又失敗會再跳）。
  String? _noticedError;

  /// 這一頁跳出、還在畫面上的失敗提示；提示掛在整個 App 共用的那一層，
  /// 離開這一頁時要自己收掉。
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _notice;

  @override
  void initState() {
    super.initState();
    // 進來之前就留著的失敗不再跳一次；按播放重試又失敗才跳。
    _noticedError = _playbackError;
    _player.addListener(_onPlayerChanged);
    unawaited(_start());
  }

  /// 播放失敗：跳一則提示寫原因；能解決時（登入、前往驗證）旁邊給那一顆。
  void _onPlayerChanged() {
    final error = _playbackError;
    if (error == _noticedError) return;
    _noticedError = error;
    if (error == null || !mounted) return;
    final remedy = SourceFailureRemedy.of(error, _player.source);
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final notice = messenger.showSnackBar(
      SnackBar(
        content: Text(error),
        persist: false,
        duration: const Duration(seconds: 4),
        action: remedy == null
            ? null
            : SnackBarAction(
                label: remedy.label,
                onPressed: () {
                  if (mounted) unawaited(_runRemedy(context, remedy));
                },
              ),
      ),
    );
    _notice = notice;
    unawaited(
      notice.closed.then<void>((_) {
        if (identical(_notice, notice)) _notice = null;
      }),
    );
  }

  /// 這本書某一集播不出來的原因；整本打不開（還沒有目錄）由狀態畫面顯示，
  /// 不算在這裡。
  String? get _playbackError =>
      _player.isCurrent(widget.book) && _player.chapters.isNotEmpty
      ? _player.error
      : null;

  /// 登入或驗證回來：有錯就重試（[_retry]）。
  Future<void> _runRemedy(
    BuildContext context,
    SourceFailureRemedy remedy,
  ) async {
    if (await remedy.run(context) && mounted) _retry();
  }

  /// 重試：還沒有目錄就重開這本書；有了就重播，[AudiobookPlayer.play] 會重載
  /// 失敗的那一集。播放器已經換成別本書時不動它。
  void _retry() {
    if (!_player.isCurrent(widget.book)) return;
    if (_player.chapters.isEmpty) {
      unawaited(_player.open(widget.book, chapterIndex: widget.chapterIndex));
    } else {
      unawaited(_player.play());
    }
  }

  Future<void> _start() async {
    // initState 裡還不能查上層的路由：先讓出一次。
    await Future<void>.value();
    if (!mounted) return;
    await TransitionSettled.entered(context);
    if (!mounted) return;
    setState(() => _entered = true);
    unawaited(_player.open(widget.book, chapterIndex: widget.chapterIndex));
    unawaited(_loadDownloaded());
    _downloads = AppEventBus().onName(AppEventBus.upBookshelf).listen((event) {
      if (event.data == widget.book.bookUrl) unawaited(_loadDownloaded());
    });
  }

  Future<void> _loadDownloaded() async {
    try {
      final files = await BookChapterFiles.downloaded(widget.book);
      if (mounted) setState(() => _downloaded = files.keys.toSet());
    } catch (_) {
      // 讀不到資料夾就當作都沒下載；播放時照樣從網路抓。
    }
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayerChanged);
    _notice?.close();
    unawaited(_downloads?.cancel());
    _listScroll?.dispose();
    _skeletonScroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    return ListenableBuilder(
      listenable: _player,
      builder: (context, _) {
        final book = _player.isCurrent(widget.book)
            ? _player.book!
            : widget.book;
        return ReaderV2WindowSettings(
          keepScreenOn: _player.keepAwake,
          backlight: null,
          orientation: ReaderV2Orientation.system,
          child: Scaffold(
            extendBodyBehindAppBar: true,
            backgroundColor: chrome.groupedBackground,
            appBar: GlassNavHeader(
              title: book.name,
              actions: [_buildMoreButton(context)],
            ),
            body: Stack(
              children: [
                Positioned.fill(child: _buildBody(context, book)),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _ControlDock(player: _player),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMoreButton(BuildContext context) {
    final source = _player.source;
    return GlassMenuButton<_MoreAction>(
      onSelected: (action) => _onMore(context, action),
      entriesBuilder: (_) => [
        const GlassMenuItem(
          value: _MoreAction.changeSource,
          label: '換源',
          icon: Icons.swap_horiz_rounded,
        ),
        // 書源沒有登入、或還沒載入時灰著（ADR 0059）。
        GlassMenuItem(
          value: _MoreAction.login,
          label: '登入',
          icon: Icons.login_rounded,
          enabled: source != null && source.hasLogin,
        ),
        GlassMenuItem(
          value: _MoreAction.keepAwake,
          label: '保持喚醒',
          icon: Icons.light_mode_outlined,
          checked: _player.keepAwake,
        ),
        GlassMenuItem(
          value: _MoreAction.copyUrl,
          label: '複製音訊網址',
          icon: Icons.link_rounded,
          enabled: _player.request != null,
        ),
        const GlassMenuDivider(),
        GlassMenuItem(
          value: _MoreAction.editSource,
          label: '編輯書源',
          icon: Icons.edit_outlined,
          enabled: source != null,
        ),
        const GlassMenuItem(
          value: _MoreAction.log,
          label: '日誌',
          icon: Icons.article_outlined,
        ),
      ],
    );
  }

  Future<void> _onMore(BuildContext context, _MoreAction action) async {
    final source = _player.source;
    switch (action) {
      case _MoreAction.changeSource:
        await _changeSource(context);
      case _MoreAction.login:
        if (source == null) return;
        final changed = await openSourceLogin(context, source);
        if (changed &&
            mounted &&
            _player.isCurrent(widget.book) &&
            _player.error != null) {
          _retry();
        }
      case _MoreAction.keepAwake:
        _player.toggleKeepAwake();
      case _MoreAction.copyUrl:
        final url = _player.request?.url;
        if (url == null) return;
        await Clipboard.setData(ClipboardData(text: url));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('已複製音訊網址')));
      case _MoreAction.editSource:
        if (source == null) return;
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => SourceEditorPage(source: source)),
        );
      case _MoreAction.log:
        await Navigator.of(
          context,
        ).push<void>(MaterialPageRoute(builder: (_) => const CrashLogPage()));
    }
  }

  /// 換源：只列有聲書源（ADR 0053），選了就存好這一集聽到哪，照閱讀器的
  /// 換源搬到新書源，再換成新書源的播放器，從同一集接著聽。
  Future<void> _changeSource(BuildContext context) async {
    final book = _player.isCurrent(widget.book) ? _player.book! : widget.book;
    final service = SourceSwitchService(
      operationQuiescer: (oldBook) =>
          DownloadService().quiesceForSourceSwitch(oldBook),
      assetRetirer: BookCoverStorageService().handoffSourceSwitchAssets,
    );
    PreparedSourceSwitch? done;
    await AppBottomSheet.showCustom<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeSourceSheet(
        book: book,
        onSelectSource: (candidate) async {
          try {
            await _player.saveProgress();
            final prepared = await service.prepareSwitch(
              book,
              candidate,
              targetChapterIndex: book.chapterIndex,
              targetChapterTitle: book.durChapterTitle,
            );
            await service.commitSwitch(book, prepared);
            AppEventBus().fire(AppEventBus.upBookshelf);
            done = prepared;
            return (
              success: true,
              message: '已切換到 ${prepared.source.bookSourceName}',
            );
          } catch (error) {
            if (!isSourceSwitchUnavailable(error)) rethrow;
            return (success: false, message: failureMessage('換源', error));
          }
        },
      ),
    );
    final prepared = done;
    if (prepared == null || !context.mounted) return;
    await _player.stop();
    if (!context.mounted) return;
    await Navigator.of(context)
        .pushReplacement(BookOpenRoute(book: prepared.migratedBook));
  }

  /// 目錄還沒到時畫骨架，到了照骨架換場換成清單（ADR 0024）；頁首下的書
  /// 資訊開頁就有，兩層一樣，換場時看不出來。
  Widget _buildBody(BuildContext context, Book book) {
    final current = _player.isCurrent(widget.book);
    final chapters = current ? _player.chapters : const <BookChapter>[];
    final error = current ? _player.error : null;
    if (chapters.isEmpty && error != null) {
      final padding = MediaQuery.paddingOf(context);
      final remedy = SourceFailureRemedy.of(error, _player.source);
      final retry = AppStateAction(
        label: '重試',
        icon: Icons.refresh,
        onPressed: _retry,
      );
      return Padding(
        padding: EdgeInsets.only(
          top: padding.top + AppGlass.headerToolbarHeight,
          bottom: _ControlDock.height + padding.bottom,
        ),
        child: AppStateView(
          icon: Icons.error_outline,
          title: '有聲書打不開',
          description: error,
          tone: AppStateTone.error,
          // 有解法（登入、前往驗證）時排第一，重試退成次要。
          primaryAction: remedy == null
              ? retry
              : AppStateAction(
                  label: remedy.label,
                  icon: remedy.icon,
                  onPressed: () => unawaited(_runRemedy(context, remedy)),
                ),
          secondaryAction: remedy == null ? null : retry,
        ),
      );
    }
    return SkeletonSwitcher(
      loading: chapters.isEmpty || !_entered,
      backdrop: AppChrome.of(context).groupedBackground,
      skeleton: _buildSkeleton(context, book),
      builder: (context) => _buildList(context, book, chapters),
    );
  }

  /// 清單的骨架：書資訊照真的畫，每集一列一條；捲到和清單一樣的位置。
  Widget _buildSkeleton(BuildContext context, Book book) {
    final count = math.max(book.totalChapterNum, 1);
    final index = (widget.chapterIndex ?? book.chapterIndex).clamp(
      0,
      count - 1,
    );
    return ExcludeSemantics(
      child: _scrollView(
        context,
        book: book,
        episodes: book.totalChapterNum,
        controller: _skeletonScroll ??= ScrollController(
          initialScrollOffset: _offsetFor(context, book, index, count),
        ),
        physics: const NeverScrollableScrollPhysics(),
        rows: SliverFixedExtentList(
          itemExtent: _rowExtent,
          delegate: SliverChildBuilderDelegate(
            (context, i) => _SkeletonSlice(
              index: i,
              count: count,
              child: _EpisodeSkeletonRow(widthFactor: _skeletonWidths[i % 4]),
            ),
            childCount: count,
            addRepaintBoundaries: false,
          ),
        ),
      ),
    );
  }

  /// 還不知道集名多長：輪流用幾種長度（同書架沒記下書名時）。
  static const _skeletonWidths = [0.42, 0.3, 0.36, 0.26];

  Widget _buildList(
    BuildContext context,
    Book book,
    List<BookChapter> chapters,
  ) {
    final scroll = _listScroll ??= ScrollController(
      initialScrollOffset: _offsetFor(
        context,
        book,
        _player.chapterIndex,
        chapters.length,
      ),
    );
    return _scrollView(
      context,
      book: book,
      episodes: chapters.where((c) => !c.isVolume).length,
      controller: scroll,
      rows: SliverFixedExtentList(
        itemExtent: _rowExtent,
        delegate: SliverChildBuilderDelegate((context, i) {
          final chapter = chapters[i];
          return _sliceOf(
            i,
            chapters.length,
            chapter.isVolume
                ? TocVolumeRow(
                    title: chapter.title,
                    count: _volumeSize(chapters, i),
                    unit: '集',
                  )
                : _EpisodeRow(
                    chapter: chapter,
                    state: _stateOf(i),
                    position: _player.position,
                    downloaded: _downloaded.contains(
                      BookChapterFiles.baseNameFor(chapter),
                    ),
                    // 付費章節不放，只提示（ADR 0057）。
                    onTap: chapter.isLocked
                        ? () => ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              const SnackBar(
                                content: Text(lockedChapterNotice),
                              ),
                            )
                        : () => unawaited(_player.playChapter(i)),
                  ),
          );
        }, childCount: chapters.length),
      ),
    );
  }

  /// 每列一樣高（含上方的分隔線），清單排好前就算得出正在播的那集在哪裡。
  static const double _rowExtent = _EpisodeRow.height + AppGlass.hairline;

  /// 分組卡片裡的第 [i] 列；第一列沒有分隔線，那一點高度補在列裡。
  static Widget _sliceOf(int i, int count, Widget row) => GroupedSliceItem(
    index: i,
    count: count,
    child: SizedBox(
      height: i == 0 ? _rowExtent : _EpisodeRow.height,
      child: row,
    ),
  );

  Widget _scrollView(
    BuildContext context, {
    required Book book,
    required int episodes,
    required ScrollController controller,
    required Widget rows,
    ScrollPhysics? physics,
  }) {
    return CustomScrollView(
      controller: controller,
      physics: physics,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(top: _headerTop(context)),
          sliver: SliverToBoxAdapter(
            child: _BookHeader(
              book: book,
              sourceName: _sourceNameOf(book),
              episodes: episodes,
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: SizedBox(height: AppGrouped.sectionGap),
        ),
        rows,
        SliverToBoxAdapter(
          child: SizedBox(
            height: _ControlDock.height + MediaQuery.paddingOf(context).bottom,
          ),
        ),
      ],
    );
  }

  /// 書源名稱：書記著加入書架時的，書源讀到後用書源現在的。
  String _sourceNameOf(Book book) =>
      (_player.isCurrent(book) ? _player.source?.bookSourceName : null) ??
      book.originName;

  static double _headerTop(BuildContext context) =>
      MediaQuery.paddingOf(context).top +
      AppGlass.headerToolbarHeight +
      AppSpacing.sm;

  /// 打開時清單捲到哪裡：正在播的第 [index] 列（共 [count] 列）在第一個
  /// 畫面就看得到時不捲，否則捲到它在頁首與圓鈕之間約三分之一高的地方。
  static double _offsetFor(
    BuildContext context,
    Book book,
    int index,
    int count,
  ) {
    final media = MediaQuery.of(context);
    final listTop =
        _headerTop(context) +
        _BookHeader.heightOf(context, book) +
        AppGrouped.sectionGap;
    final rowTop = listTop + index * _rowExtent;
    final visibleTop = media.padding.top + AppGlass.headerToolbarHeight;
    final visibleBottom =
        media.size.height - _ControlDock.height - media.padding.bottom;
    if (rowTop + _rowExtent <= visibleBottom) return 0;
    final end =
        listTop +
        count * _rowExtent +
        _ControlDock.height +
        media.padding.bottom;
    final target = rowTop - visibleTop - (visibleBottom - visibleTop) / 3;
    return target.clamp(0.0, math.max(0.0, end - media.size.height));
  }

  /// 第 [index] 個分卷底下有幾集（到下一個分卷為止）。
  static int _volumeSize(List<BookChapter> chapters, int index) {
    var count = 0;
    for (var i = index + 1; i < chapters.length; i++) {
      if (chapters[i].isVolume) break;
      count++;
    }
    return count;
  }

  _EpisodeState _stateOf(int index) {
    final current = _player.chapterIndex;
    if (index < current) return _EpisodeState.finished;
    if (index > current) return _EpisodeState.ahead;
    return _player.playing ? _EpisodeState.playing : _EpisodeState.paused;
  }
}

/// 頁首下的小封面、書名、「作者 · 書源」與「共 N 集」。
class _BookHeader extends StatelessWidget {
  const _BookHeader({
    required this.book,
    required this.sourceName,
    required this.episodes,
  });

  static const double coverWidth = 72;
  static const double coverHeight = coverWidth * 7 / 5;

  final Book book;
  final String sourceName;
  final int episodes;

  static TextStyle get _titleStyle => AppTextStyles.titleMd;
  static TextStyle get _metaStyle => AppTextStyles.bodySm;

  /// 這一塊多高：封面與右側文字取高的那個。清單排好前就要知道正在播的
  /// 那集在哪裡（[_AudiobookPageState._offsetFor]）。
  static double heightOf(BuildContext context, Book book) {
    final scaler = MediaQuery.textScalerOf(context);
    final width =
        MediaQuery.sizeOf(context).width -
        AppGrouped.margin * 2 -
        coverWidth -
        AppSpacing.lg;
    final title = TextPainter(
      text: TextSpan(text: book.name, style: _titleStyle),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 2,
    )..layout(maxWidth: math.max(0, width));
    final metaLine = scaler.scale(_metaStyle.fontSize!) * _metaStyle.height!;
    final text = title.height + AppSpacing.xs + metaLine + 2 + metaLine;
    title.dispose();
    return math.max(coverHeight, text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final byline = [
      book.getRealAuthor(),
      sourceName,
    ].where((text) => text.trim().isNotEmpty).join(' · ');
    return Container(
      height: heightOf(context, book),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: AppGrouped.margin),
      child: Row(
        children: [
          SizedBox(
            width: coverWidth,
            child: AspectRatio(
              aspectRatio: 5 / 7,
              // 沒有封面時直接畫有聲書的預設封面；BookCoverWidget 載不到時
              // 畫的夜空要等書的類別定下來才分類別（見交接）。
              child: switch (UnifiedCovers.coverOf(book)) {
                final cover? when cover.trim().isNotEmpty => BookCoverWidget(
                  coverUrl: cover,
                  bookName: book.name,
                  width: coverWidth,
                  height: coverHeight,
                ),
                _ => ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: DefaultBookCover(
                    bookName: book.name,
                    kind: BookSourceKind.audio,
                  ),
                ),
              },
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleMd.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                if (byline.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    byline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySm.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (episodes > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '共 $episodes 集',
                    style: AppTextStyles.bodySm.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 骨架那份清單的一列：和分組卡片同樣的底色、圓角與分隔線，但不包
/// `Material` 與圓角裁切——骨架在換頁途中呼吸，每一列各一層會讓每一幀
/// 都超過上限。
class _SkeletonSlice extends StatelessWidget {
  const _SkeletonSlice({
    required this.index,
    required this.count,
    required this.child,
  });

  final int index;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    const corner = Radius.circular(AppGrouped.radius);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppGrouped.margin),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: chrome.groupedSurface,
          borderRadius: BorderRadius.vertical(
            top: index == 0 ? corner : Radius.zero,
            bottom: index == count - 1 ? corner : Radius.zero,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (index == 0)
              const SizedBox(height: AppGlass.hairline)
            else
              const InsetSeparator(indent: AppGrouped.rowPadding),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// 集數清單骨架的一列：和 [_EpisodeRow] 同樣的內距與字樣，集名一條。
class _EpisodeSkeletonRow extends StatelessWidget {
  const _EpisodeSkeletonRow({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppGrouped.rowPadding),
    child: Align(
      alignment: Alignment.centerLeft,
      child: SkeletonLine(
        style: AppTextStyles.bodyBase,
        widthFactor: widthFactor,
      ),
    ),
  );
}

enum _EpisodeState { finished, playing, paused, ahead }

/// 集數清單的一列（列高 48）：右側只寫收聽狀態——聽完、聽到幾分幾秒、
/// 正在播的音波圖示、已下載的小勾。
class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.chapter,
    required this.state,
    required this.position,
    required this.downloaded,
    required this.onTap,
  });

  static const double height = 48;

  final BookChapter chapter;
  final _EpisodeState state;
  final ValueNotifier<Duration> position;
  final bool downloaded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current =
        state == _EpisodeState.playing || state == _EpisodeState.paused;
    final titleColor = switch (state) {
      _EpisodeState.finished => scheme.onSurfaceVariant,
      _EpisodeState.playing => scheme.primary,
      _ => scheme.onSurface,
    };
    final status = switch (state) {
      _EpisodeState.finished => Text(
        '聽完',
        style: AppTextStyles.bodySm.copyWith(color: scheme.onSurfaceVariant),
      ),
      _EpisodeState.playing => Icon(
        Icons.graphic_eq_rounded,
        size: 20,
        color: scheme.primary,
      ),
      _EpisodeState.paused => ValueListenableBuilder<Duration>(
        valueListenable: position,
        builder: (context, at, _) => Text(
          '聽到 ${formatPlayTime(at)}',
          style: AppTextStyles.bodySm.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
      _EpisodeState.ahead => null,
    };
    return Semantics(
      button: true,
      selected: current,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppGrouped.rowPadding,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    chapter.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyBase.copyWith(
                      color: titleColor,
                      fontWeight: current ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(width: AppSpacing.md),
                  status,
                ],
                if (downloaded) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    Icons.download_done_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 播放時間：一小時內「mm:ss」，以上「h:mm:ss」。
String formatPlayTime(Duration value) {
  String two(int n) => n.toString().padLeft(2, '0');
  final seconds = value.inSeconds % 60;
  final minutes = value.inMinutes % 60;
  final hours = value.inHours;
  return hours > 0
      ? '$hours:${two(minutes)}:${two(seconds)}'
      : '${two(minutes)}:${two(seconds)}';
}

/// 底部：膠囊上方的三顆圓鈕（倍速、定時、播放模式）與浮動玻璃膠囊（集名、
/// 進度條、五顆控制鍵）。
class _ControlDock extends StatelessWidget {
  const _ControlDock({required this.player});

  /// 圓鈕、間距與膠囊的高度，清單底部讓出這麼多。
  static const double height =
      AppGlass.buttonSize + AppSpacing.md + _capsuleHeight + AppSpacing.sm;
  static const double _capsuleHeight = 148;

  final AudiobookPlayer player;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final tint = chrome.glassTint;
    final accentMuted = scheme.primary.withValues(alpha: 0.16);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppGrouped.margin,
        0,
        AppGrouped.margin,
        bottomInset + AppSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GlassIconButton(
                icon: Icons.speed_rounded,
                label: '${_speedText(player.speed)}×',
                tooltip: '倍速',
                tint: tint,
                color: scheme.onSurface,
                onPressed: () => _showSpeed(context),
              ),
              SleepTimerButton(
                timer: player.sleepTimer,
                tooltip: '定時',
                tint: tint,
                color: scheme.onSurface,
                accent: scheme.primary,
                accentMuted: accentMuted,
                onPressed: () => _showTimer(context),
              ),
              GlassIconButton(
                icon: _modeIcon(player.mode),
                tooltip: player.mode.label,
                tint: tint,
                color: scheme.onSurface,
                onPressed: player.cycleMode,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: _capsuleHeight,
            child: GlassSurface(
              borderRadius: AppRadius.cardXl,
              grouped: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Column(
                  children: [
                    Text(
                      player.chapter?.title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.uiMd.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    _ProgressBar(player: player),
                    const Spacer(),
                    _Controls(player: player),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _speedText(double speed) {
    final text = speed.toStringAsFixed(2);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static IconData _modeIcon(AudiobookPlayMode mode) => switch (mode) {
    AudiobookPlayMode.inOrder => Icons.playlist_play_rounded,
    AudiobookPlayMode.singleLoop => Icons.repeat_one_rounded,
    AudiobookPlayMode.shuffle => Icons.shuffle_rounded,
    AudiobookPlayMode.listLoop => Icons.repeat_rounded,
  };

  void _showSpeed(BuildContext context) {
    unawaited(
      AppBottomSheet.showCustom<void>(
        context: context,
        builder: (sheetContext) => ListenableBuilder(
          listenable: player,
          builder: (context, _) => AppBottomSheet(
            title: '倍速',
            children: [
              NumberStepperRow(
                label: '倍速',
                value: player.speed,
                min: 0.5,
                max: 3,
                step: 0.25,
                fractionDigits: 2,
                trimZeroFraction: true,
                unit: '倍',
                onChanged: (value) => unawaited(player.setSpeed(value)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTimer(BuildContext context) {
    unawaited(
      AppBottomSheet.showCustom<void>(
        context: context,
        builder: (_) => AppBottomSheet(
          title: '定時',
          children: [SleepTimerSection(timer: player.sleepTimer)],
        ),
      ),
    );
  }
}

/// 進度條與已播／總長；播著時只有這一塊跟著位置重建。
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.player});

  final AudiobookPlayer player;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = player.duration;
    final timeStyle = AppTextStyles.labelSm.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return ValueListenableBuilder<Duration>(
      valueListenable: player.position,
      builder: (context, at, _) {
        final max = total?.inMilliseconds ?? 0;
        final value = max <= 0
            ? 0.0
            : at.inMilliseconds.clamp(0, max).toDouble();
        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 8,
                  disabledThumbRadius: 8,
                ),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: scheme.primary,
                inactiveTrackColor: scheme.onSurfaceVariant.withValues(
                  alpha: 0.24,
                ),
                thumbColor: scheme.primary,
              ),
              child: SizedBox(
                height: 28,
                child: Slider(
                  value: value,
                  max: max <= 0 ? 1 : max.toDouble(),
                  onChanged: max <= 0
                      ? null
                      : (ms) => player.position.value = Duration(
                          milliseconds: ms.round(),
                        ),
                  onChangeEnd: max <= 0
                      ? null
                      : (ms) => unawaited(
                          player.seek(Duration(milliseconds: ms.round())),
                        ),
                ),
              ),
            ),
            Row(
              children: [
                Text(formatPlayTime(at), style: timeStyle),
                const Spacer(),
                Text(
                  total == null ? '--:--' : formatPlayTime(total),
                  style: timeStyle,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// 上一集、倒退 10 秒、播放鍵（主色實心圓）、快轉 10 秒、下一集。
class _Controls extends StatelessWidget {
  const _Controls({required this.player});

  static const double _playSize = 52;

  final AudiobookPlayer player;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget button(IconData icon, String tooltip, VoidCallback? onPressed) =>
        IconButton(
          icon: Icon(icon, size: 28),
          tooltip: tooltip,
          color: scheme.onSurface,
          onPressed: onPressed,
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 頭尾沒有上一集、下一集時灰掉（ADR 0059）。
        button(
          Icons.skip_previous_rounded,
          '上一集',
          player.hasPrevious ? () => unawaited(player.previous()) : null,
        ),
        button(
          Icons.replay_10_rounded,
          '倒退 10 秒',
          () => unawaited(player.skipBy(-AudiobookPlayer.skipStep)),
        ),
        Semantics(
          button: true,
          // 接著聽一律叫「繼續」，同朗讀與下載。
          label: player.playing ? '暫停' : '繼續',
          excludeSemantics: true,
          child: PressScale(
            onTap: () => unawaited(player.toggle()),
            child: Container(
              width: _playSize,
              height: _playSize,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
              child: player.loading
                  ? Padding(
                      padding: const EdgeInsets.all(15),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: scheme.onPrimary,
                      ),
                    )
                  : Icon(
                      player.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 32,
                      color: scheme.onPrimary,
                    ),
            ),
          ),
        ),
        button(
          Icons.forward_10_rounded,
          '快轉 10 秒',
          () => unawaited(player.skipBy(AudiobookPlayer.skipStep)),
        ),
        button(
          Icons.skip_next_rounded,
          '下一集',
          player.hasNext ? () => unawaited(player.next()) : null,
        ),
      ],
    );
  }
}
