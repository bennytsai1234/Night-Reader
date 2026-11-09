import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_chapter_files.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';
import 'package:night_reader/core/widgets/default_book_cover.dart';
import 'package:night_reader/features/about/crash_log_page.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_orientation.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_window_settings.dart';
import 'package:night_reader/features/source_login/source_login_page.dart';
import 'package:night_reader/features/source_manager/source_editor_page.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/number_stepper_row.dart';
import 'package:night_reader/shared/widgets/sleep_timer_section.dart';
import 'package:night_reader/shared/widgets/toc_volume_row.dart';

import 'audiobook_player.dart';

/// 有聲書播放器（`docs/design/audiobook.md`「播放器」）：集數清單是主體，
/// 控制在底部的浮動玻璃膠囊，膠囊上方是倍速、定時、播放模式三顆圓鈕。
/// 畫面只看 [AudiobookPlayer]，離開這頁照樣在播。
class AudiobookPage extends StatefulWidget {
  const AudiobookPage({super.key, required this.book, this.player});

  final Book book;

  /// 測試換成自己的播放器；平常是 [AudiobookPlayer.instance]。
  final AudiobookPlayer? player;

  @override
  State<AudiobookPage> createState() => _AudiobookPageState();
}

enum _MoreAction { login, keepAwake, copyUrl, editSource, log }

class _AudiobookPageState extends State<AudiobookPage> {
  late final AudiobookPlayer _player =
      widget.player ?? AudiobookPlayer.instance;

  /// 已下載的集（[BookChapterFiles.baseNameFor]）；清單畫小勾。
  Set<String> _downloaded = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_player.open(widget.book));
    unawaited(_loadDownloaded());
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
                Positioned.fill(child: _buildList(context, book)),
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
        if (source != null && source.hasLoginUrl)
          const GlassMenuItem(
            value: _MoreAction.login,
            label: '登入',
            icon: Icons.login_rounded,
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
      case _MoreAction.login:
        if (source != null) await openSourceLogin(context, source);
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

  Widget _buildList(BuildContext context, Book book) {
    final padding = MediaQuery.paddingOf(context);
    final chapters = _player.isCurrent(widget.book)
        ? _player.chapters
        : const <BookChapter>[];
    final episodes = chapters.where((c) => !c.isVolume).length;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(
            top: padding.top + AppGlass.headerToolbarHeight + AppSpacing.sm,
          ),
          sliver: SliverToBoxAdapter(
            child: _BookHeader(
              book: book,
              source: _player.source,
              episodes: episodes,
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: SizedBox(height: AppGrouped.sectionGap),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate((context, i) {
            final chapter = chapters[i];
            return GroupedSliceItem(
              index: i,
              count: chapters.length,
              child: chapter.isVolume
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
                      onTap: () => unawaited(_player.playChapter(i)),
                    ),
            );
          }, childCount: chapters.length),
        ),
        SliverToBoxAdapter(
          child: SizedBox(height: _ControlDock.height + padding.bottom),
        ),
      ],
    );
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
    required this.source,
    required this.episodes,
  });

  static const double coverWidth = 72;

  final Book book;
  final BookSource? source;
  final int episodes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final byline = [
      book.getRealAuthor(),
      ?source?.bookSourceName,
    ].where((text) => text.trim().isNotEmpty).join(' · ');
    return Padding(
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
                  height: coverWidth * 7 / 5,
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
    Widget button(IconData icon, String tooltip, VoidCallback onPressed) =>
        IconButton(
          icon: Icon(icon, size: 28),
          tooltip: tooltip,
          color: scheme.onSurface,
          onPressed: onPressed,
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        button(
          Icons.skip_previous_rounded,
          '上一集',
          () => unawaited(player.previous()),
        ),
        button(
          Icons.replay_10_rounded,
          '倒退 10 秒',
          () => unawaited(player.skipBy(-AudiobookPlayer.skipStep)),
        ),
        Semantics(
          button: true,
          label: player.playing ? '暫停' : '播放',
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
        button(Icons.skip_next_rounded, '下一集', () => unawaited(player.next())),
      ],
    );
  }
}
