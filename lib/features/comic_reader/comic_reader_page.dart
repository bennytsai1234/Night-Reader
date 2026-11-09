import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/comic/comic_chapter_download.dart';
import 'package:night_reader/core/comic/comic_chapter_numbers.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/features/book_detail/book_detail_page.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_bottom_menu.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_controller.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_sheet.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_top_menu.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_chapters_drawer.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_side_panel.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_window_settings.dart';
import 'package:night_reader/features/settings/settings_page.dart';
import 'package:night_reader/features/settings/settings_provider.dart';
import 'package:night_reader/shared/navigation/status_bar.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/number_stepper_row.dart';
import 'package:night_reader/shared/widgets/theme_reveal_scope.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'comic_page_source.dart';
import 'comic_reader_menu.dart';
import 'comic_strip_model.dart';
import 'comic_strip_view.dart';
import 'network_comic_page_source.dart';

/// 漫畫閱讀器（ADR 0052、`docs/design/comics.md`）：條漫加上閱讀選單。
/// 平常只有圖，點中間叫出選單；進度記「第幾話第幾張」（`Book.charOffset`
/// 是第幾張，`visualOffsetPx` 是在那張讀到幾成，只用在這台回到原處）。
class ComicReaderPage extends StatefulWidget {
  const ComicReaderPage({
    super.key,
    required this.book,
    this.startChapter,
    this.initialChapters = const <BookChapter>[],
    this.pageSource,
  });

  final Book book;

  /// 從第幾話開頭讀；null 是接著上次讀到的地方。
  final int? startChapter;
  final List<BookChapter> initialChapters;

  /// 圖從哪裡來；null 時照書源（網路書）。測試與本地漫畫傳自己的。
  final ComicPageSource? pageSource;

  @override
  State<ComicReaderPage> createState() => _ComicReaderPageState();
}

enum _MoreAction { refetchChapter, bookDetail, globalSettings }

class _ComicReaderPageState extends State<ComicReaderPage> {
  static const Duration _saveDelay = Duration(milliseconds: 400);

  final ReaderV2SettingsController _settings = ReaderV2SettingsController();
  final ValueNotifier<bool> _menuVisible = ValueNotifier(false);
  final ValueNotifier<bool> _autoScrolling = ValueNotifier(false);
  final ValueNotifier<int> _currentChapter = ValueNotifier(0);
  final ValueNotifier<ComicMenuProgress> _progress = ValueNotifier(
    const ComicMenuProgress(chapterIndex: 0, pageIndex: 0, pageCount: 0),
  );
  final ValueNotifier<ReaderV2ScrubState> _scrub = ValueNotifier((
    isScrubbing: false,
    percent: 0,
  ));
  final ReaderV2SidePanelController _chapterPanel =
      ReaderV2SidePanelController();
  final ComicStripController _strip = ComicStripController();

  List<BookChapter> _chapters = const [];
  BookSource? _source;
  ComicStripModel? _model;
  double _initialFraction = 0;
  Object? _loadError;

  ComicLocation? _pendingSave;
  Timer? _saveTimer;

  Book get _book => widget.book;

  @override
  void initState() {
    super.initState();
    _strip.onAutoScrollStopped = () => _autoScrolling.value = false;
    unawaited(_settings.loadSettings());
    unawaited(_open());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    final pending = _pendingSave;
    if (pending != null) unawaited(_save(pending));
    _model?.dispose();
    _settings.dispose();
    _menuVisible.dispose();
    _autoScrolling.dispose();
    _currentChapter.dispose();
    _progress.dispose();
    _scrub.dispose();
    _chapterPanel.dispose();
    super.dispose();
  }

  // ─── 開書與進度 ─────────────────────────────────────────────────────

  Future<void> _open() async {
    try {
      var chapters = widget.initialChapters;
      if (chapters.isEmpty) {
        chapters = await getIt<ChapterDao>().getByBook(_book.bookUrl);
      }
      BookSource? source;
      if (!_book.isLocal) {
        source = await getIt<BookSourceDao>().getByUrl(_book.origin);
        if (source == null) throw StateError('找不到這本書的書源');
        if (chapters.isEmpty) {
          chapters = await BookSourceService().getChapterList(source, _book);
          if (_book.isInBookshelf) {
            await getIt<ChapterDao>().insertChapters(chapters);
          }
        }
      }
      if (chapters.isEmpty) throw StateError('目錄是空的');
      if (!mounted) return;
      final start = widget.startChapter;
      final chapterIndex = (start ?? _book.chapterIndex).clamp(
        0,
        chapters.length - 1,
      );
      final pageSource =
          widget.pageSource ??
          NetworkComicPageSource(
            book: _book,
            source: source!,
            chapters: chapters,
          );
      final model = ComicStripModel(
        source: pageSource,
        chapterCount: chapters.length,
        chapterIndex: chapterIndex,
        pageIndex: start == null ? _book.charOffset : 0,
      )..addListener(_onModel);
      setState(() {
        _chapters = chapters;
        _source = source;
        _model = model;
        _initialFraction = start == null
            ? _book.visualOffsetPx.clamp(0.0, 1.0).toDouble()
            : 0;
      });
      _currentChapter.value = chapterIndex;
      model.start();
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  void _onModel() =>
      _refreshProgress(_progress.value.chapterIndex, _progress.value.pageIndex);

  void _refreshProgress(int chapterIndex, int pageIndex) {
    _progress.value = ComicMenuProgress(
      chapterIndex: chapterIndex,
      pageIndex: pageIndex,
      pageCount: _model?.pageCountOf(chapterIndex) ?? 0,
    );
  }

  void _onLocation(ComicLocation location) {
    _currentChapter.value = location.chapterIndex;
    _refreshProgress(location.chapterIndex, location.pageIndex);
    _pendingSave = location;
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, () {
      final pending = _pendingSave;
      _pendingSave = null;
      if (pending != null) unawaited(_save(pending));
    });
  }

  Future<void> _save(ComicLocation location) async {
    final title = _titleOf(location.chapterIndex);
    final movedAt = await getIt<BookDao>().updateProgress(
      _book.bookUrl,
      location.chapterIndex,
      title,
      location.pageIndex,
      visualOffsetPx: location.fraction,
    );
    _book
      ..chapterIndex = location.chapterIndex
      ..charOffset = location.pageIndex
      ..visualOffsetPx = location.fraction
      ..durChapterTitle = title
      ..durChapterTime = DateTime.now().millisecondsSinceEpoch;
    if (movedAt != null) _book.progressTime = movedAt;
  }

  Future<void> _flush() async {
    _saveTimer?.cancel();
    final pending = _pendingSave;
    _pendingSave = null;
    if (pending != null) await _save(pending);
  }

  String _titleOf(int index) =>
      index >= 0 && index < _chapters.length ? _chapters[index].title : '';

  int _gapBetween(int from, int to) =>
      ComicChapterNumbers.gapBetween(_titleOf(from), _titleOf(to));

  // ─── 操作 ───────────────────────────────────────────────────────────

  void _onTap(ComicTapRegion region) {
    if (_menuVisible.value) {
      _menuVisible.value = false;
      return;
    }
    switch (region) {
      case ComicTapRegion.menu:
        _menuVisible.value = true;
      case ComicTapRegion.previous:
        _strip.scrollByScreen(forward: false);
      case ComicTapRegion.next:
        _strip.scrollByScreen(forward: true);
    }
  }

  void _jumpTo(int chapterIndex, {int pageIndex = 0}) {
    final model = _model;
    if (model == null) return;
    _stopAutoScroll();
    model.jumpTo(chapterIndex, pageIndex: pageIndex);
    _currentChapter.value = chapterIndex;
    _refreshProgress(chapterIndex, pageIndex);
    _onLocation(ComicLocation(chapterIndex, pageIndex));
  }

  void _toggleAutoScroll() {
    if (_autoScrolling.value) {
      _stopAutoScroll();
      return;
    }
    _autoScrolling.value = true;
    _menuVisible.value = false;
    _strip.setAutoScroll(_settings.autoPageSpeed);
  }

  void _stopAutoScroll() {
    if (!_autoScrolling.value) return;
    _autoScrolling.value = false;
    _strip.setAutoScroll(0);
  }

  /// 深淺是整個 App 共用的設定，閱讀器切換後其他畫面一併跟著換。
  void _toggleDayNight() {
    final dark = StylePalette.of(context).brightness == Brightness.dark;
    final settings = context.read<SettingsProvider>();
    ThemeRevealScope.of(context).run(
      change: () =>
          settings.setThemeMode(dark ? ThemeMode.light : ThemeMode.dark),
    );
  }

  Future<void> _openPreferences() => ReaderV2MenuSheet.show<void>(
    context,
    settings: _settings,
    builder: (context) => ReaderV2SheetScaffold(
      title: '漫畫偏好',
      children: [
        NumberStepperRow(
          label: '自動捲動速度',
          value: _settings.autoPageSpeed,
          min: ReaderV2SettingsController.minAutoPageSpeed,
          max: ReaderV2SettingsController.maxAutoPageSpeed,
          step: 0.01,
          displayScale: 100,
          unit: '%',
          onChanged: (speed) {
            _settings.setAutoPageSpeed(speed);
            if (_autoScrolling.value) _strip.setAutoScroll(speed);
          },
        ),
      ],
    ),
  );

  Future<void> _showMore() async {
    final action = await showAppActionSheet<_MoreAction>(
      context: context,
      actions: [
        if (!_book.isLocal)
          const AppSheetAction(
            label: '重新取得本章',
            icon: Icons.refresh_rounded,
            value: _MoreAction.refetchChapter,
          ),
        const AppSheetAction(
          label: '書籍詳情',
          icon: Icons.info_outline_rounded,
          value: _MoreAction.bookDetail,
        ),
        const AppSheetAction(
          label: '全域系統設定',
          icon: Icons.settings_suggest_rounded,
          value: _MoreAction.globalSettings,
        ),
      ],
    );
    if (!mounted || action == null) return;
    _menuVisible.value = false;
    switch (action) {
      case _MoreAction.refetchChapter:
        await _refetchChapter();
      case _MoreAction.bookDetail:
        await _showBookDetail();
      case _MoreAction.globalSettings:
        await Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
        if (mounted) unawaited(_settings.loadSettings());
    }
  }

  /// 刪掉這一話下載好的與抓到一半的圖，照書源重抓。
  Future<void> _refetchChapter() async {
    final index = _currentChapter.value;
    final chapter = _chapters[index];
    final cbz = await ComicChapterDownload.cbzFor(_book, chapter);
    if (cbz != null) await cbz.delete();
    final partial = await ComicChapterDownload.partialDirFor(_book, chapter);
    if (await partial.exists()) await partial.delete(recursive: true);
    imageCache.clear();
    if (!mounted) return;
    final model = _model;
    if (model == null) return;
    final source =
        widget.pageSource ??
        NetworkComicPageSource(
          book: _book,
          source: _source!,
          chapters: _chapters,
        );
    final fresh = ComicStripModel(
      source: source,
      chapterCount: _chapters.length,
      chapterIndex: index,
    )..addListener(_onModel);
    model
      ..removeListener(_onModel)
      ..dispose();
    setState(() {
      _model = fresh;
      _initialFraction = 0;
    });
    fresh.start();
  }

  Future<void> _showBookDetail() async {
    await _flush();
    if (!mounted) return;
    final targetUrl = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => BookDetailPage(book: _book, fromReader: true),
      ),
    );
    if (!mounted || targetUrl == null) return;
    final index = _chapters.indexWhere((chapter) => chapter.url == targetUrl);
    if (index >= 0) _jumpTo(index);
  }

  Future<void> _openWeb(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _exit() async {
    await _flush();
    if (mounted) Navigator.of(context).pop();
  }

  // ─── 畫面 ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = StylePalette.of(context);
    final dark = palette.brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) => StatusBarHidden(
        hidden: _settings.hideStatusBar,
        hideNavigationBar: _settings.hideNavigationBar,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: dark
                ? Brightness.light
                : Brightness.dark,
          ),
          child: ReaderV2WindowSettings(
            keepScreenOn: _settings.keepScreenOn,
            backlight: null,
            orientation: _settings.orientation,
            child: PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                if (_chapterPanel.isOnScreen) {
                  _chapterPanel.close();
                } else if (_menuVisible.value) {
                  _menuVisible.value = false;
                } else {
                  unawaited(_exit());
                }
              },
              child: Scaffold(
                backgroundColor: palette.readerBackground,
                body: _buildBody(context, palette, dark),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, StylePalette palette, bool dark) {
    final model = _model;
    if (model == null) {
      return _loadError == null
          ? const SizedBox.expand()
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  '打不開這本漫畫：$_loadError',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.readerText),
                ),
              ),
            );
    }
    final navigation = ReaderV2ChapterNavigationState(
      chapterCount: _chapters.length,
      current: _currentChapter,
      scrub: _scrub,
      titleFor: _titleOf,
    );
    return ReaderV2SidePanel(
      controller: _chapterPanel,
      panel: ReaderV2ChaptersDrawer(
        shown: _chapterPanel.shown,
        chapters: _chapters,
        currentChapter: _currentChapter,
        titleFor: _titleOf,
        onChapterTap: (index) {
          _chapterPanel.close();
          _jumpTo(index);
        },
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ComicStripView(
              key: ObjectKey(model),
              model: model,
              controller: _strip,
              foreground: palette.readerText,
              accent: palette.primary,
              initialFraction: _initialFraction,
              onLocation: _onLocation,
              onTap: _onTap,
              titleOf: _titleOf,
              gapBetween: _gapBetween,
              webUrlOpener: (url) => unawaited(_openWeb(url)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: ReaderV2TopMenu(
              controlsVisible: _menuVisible,
              bookName: _book.name,
              navigation: navigation,
              originName: _book.isLocal ? '' : _book.originName,
              showReadTitleAddition: true,
              onBack: () => unawaited(_exit()),
              onMore: () => unawaited(_showMore()),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ComicReaderBottomMenu(
              controlsVisible: _menuVisible,
              progress: _progress,
              chapterCount: _chapters.length,
              autoScrolling: _autoScrolling,
              dayNightIcon: dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              dayNightTooltip: dark ? '淺色' : '深色',
              onToggleAutoScroll: _toggleAutoScroll,
              onToggleDayNight: _toggleDayNight,
              onPrevChapter: () => _jumpTo(_currentChapter.value - 1),
              onNextChapter: () => _jumpTo(_currentChapter.value + 1),
              onSeekPage: (page) =>
                  _jumpTo(_currentChapter.value, pageIndex: page),
              onOpenChapters: () {
                _menuVisible.value = false;
                _chapterPanel.open();
              },
              onPreferences: () => unawaited(_openPreferences()),
            ),
          ),
        ],
      ),
    );
  }
}
