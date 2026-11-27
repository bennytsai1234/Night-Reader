import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/storage/book_storage_service.dart';
import 'package:night_reader/features/reader/screen/dependencies/reader_dependencies.dart';
import 'package:night_reader/features/reader/screen/latest_only_scheduler.dart';
import 'package:night_reader/features/reader/features/auto_page/reader_auto_page_controller.dart';
import 'package:night_reader/features/reader/features/bookmark/reader_bookmarks.dart';
import 'package:night_reader/features/reader/features/highlight/reader_highlights.dart';
import 'package:night_reader/features/reader/features/menu/reader_menu_controller.dart';
import 'package:night_reader/features/reader/features/settings/reader_settings_controller.dart';
import 'package:night_reader/features/reader/features/tts/reader_tts_controller.dart';
import 'package:night_reader/features/reader/text_view/layout/reader_paragraph_layout.dart';
import 'package:night_reader/features/reader/layout/reader_layout_spec.dart';
import 'package:night_reader/features/reader/layout/reader_style_preferences.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';
import 'package:night_reader/features/reader/session/reader_open_target.dart';
import 'package:night_reader/features/reader/session/reader_progress_controller.dart';
import 'package:night_reader/features/reader/session/reader_runtime.dart';
import 'package:night_reader/features/reader/viewport/reader_viewport_controller.dart';
import 'package:night_reader/features/replace_rule/replace_rule_deadline.dart';

/// 排版設定送出的一筆：送出時用的 Runtime 與版面。
typedef _PresentationJob = ({ReaderRuntime runtime, ReaderLayoutSpec spec});

class ReaderControllerHost {
  ReaderControllerHost({
    required this.book,
    required this.initialChapters,
    required this.openTarget,
    required this._entrance,
    required this._onChanged,
    required this._isMounted,
    this._openLocation,
  }) {
    settings.addListener(_onSettingsChanged);
    menu.controlsVisible.addListener(_onMenuChanged);
    dependencies = ReaderDependencies(
      book: book,
      initialChapters: initialChapters,
      currentChineseConvert: () => settings.chineseConvert,
      currentShowIllustrations: () => settings.showIllustrations,
    );
    bookmarks = ReaderBookmarks(
      book: book,
      dao: dependencies.bookmarkDao,
      chapters: () => runtime?.chapters ?? initialChapters,
    );
    highlights = ReaderHighlights(
      book: book,
      dao: dependencies.highlightDao,
      chapters: () => runtime?.chapters ?? initialChapters,
    );
    bookStorageService = BookStorageService(
      bookDao: dependencies.bookDao,
      chapterDao: dependencies.chapterDao,
      contentDao: dependencies.readerChapterContentDao,
    );
    _appliedContentSettingsGeneration = settings.contentSettingsGeneration;
    // Reader session visibility belongs to the host, not the viewport.
    // Leaving the visible app stops viewport motion and persists the latest
    // captured location through the Runtime owner.
    _lifecycleListener = AppLifecycleListener(onHide: _handleAppHidden);
  }

  late final AppLifecycleListener _lifecycleListener;

  final Book book;
  final List<BookChapter> initialChapters;
  final ReaderOpenTarget? openTarget;

  /// 開書的換頁動畫與骨架淡入都播完時完成；開書載入等它（ADR 0018）。
  final Future<void> _entrance;

  /// 進場播完、開書之前問一次要不要改停在別的位置（剛同步來、比 [book]
  /// 新的閱讀紀錄，見 `ReaderProgressSync.openLocation`）；null 就停在
  /// [openTarget]。
  final Future<ReaderLocation?> Function(ReaderRuntime runtime)? _openLocation;
  final VoidCallback _onChanged;
  final bool Function() _isMounted;

  final ReaderSettingsController settings = ReaderSettingsController();
  final ReaderMenuController menu = ReaderMenuController();
  final ReaderViewportController viewportController =
      ReaderViewportController();

  late final ReaderDependencies dependencies;

  /// 讀書途中要給讀者的提示，例如替換規則跑太久被停用；閱讀器顯示成浮動
  /// 提示。
  Stream<String> get notices => _notices.stream;
  final StreamController<String> _notices =
      StreamController<String>.broadcast();
  late final BookStorageService bookStorageService;

  /// 這本書的書籤（正文旁的記號、目錄的書籤分頁）。
  late final ReaderBookmarks bookmarks;

  /// 這本書的標註（正文上的底色與底線、目錄的標註分頁）。
  late final ReaderHighlights highlights;

  /// 上次算書籤記號與標註落在哪一章時的目錄（章數、頭尾章節網址）；目錄
  /// 讀出來或換過才重算。
  (int, String, String)? _markedChapters;

  ReaderRuntime? runtime;
  ReaderTtsController? tts;
  ReaderAutoPageController? autoPage;

  Size? _lastViewportSize;
  int _appliedContentSettingsGeneration = 0;
  ({int settingsGeneration, int chapterIndex, int contentGeneration})?
  _lastFailedContentSettingsAttempt;
  ({int presentationSignature, int chapterIndex, int contentGeneration})?
  _lastFailedPresentationAttempt;

  /// 內容設定（繁簡、替換規則）送出時，用的 Runtime。
  late final LatestOnlyScheduler<ReaderRuntime> _contentSettings =
      LatestOnlyScheduler<ReaderRuntime>(
        isMounted: _isMounted,
        gate: _contentSettingsWanted,
        send: _applyContentSettings,
        onSettled: (runtime, {required completed}) {
          if (completed) _reconcileContentSettings(runtime);
        },
      );

  /// 排版設定等一幀沒再變才送（旋轉與 inset 動畫每幀都會變，見
  /// [LatestOnlyScheduler.quietFrames]）。
  late final LatestOnlyScheduler<_PresentationJob> _presentation =
      LatestOnlyScheduler<_PresentationJob>(
        isMounted: _isMounted,
        quietFrames: true,
        send: _applyPresentation,
      );

  bool _opening = false;
  bool _ttsWasPlaying = false;

  void _onControllerChanged() {
    final chapters = runtime?.chapters;
    if (chapters != null && chapters.isNotEmpty) {
      final signature = (
        chapters.length,
        chapters.first.url,
        chapters.last.url,
      );
      if (signature != _markedChapters) {
        _markedChapters = signature;
        bookmarks.refreshMarks();
        highlights.refreshMarks();
      }
    }
    _onChanged();
  }

  /// 從選單推一整頁的期間（選單開始滑出起，到選單再打開為止）自動捲動
  /// 保持暫停：整頁蓋著閱讀器時正文不在後面往前捲。
  bool _awayOverMenu = false;

  /// 從選單推一整頁之前呼叫，收起選單時不恢復自動捲動。
  void holdAutoPageWhileAway() {
    _awayOverMenu = true;
    _syncAutoPagePause();
  }

  /// 沒推出去，或回來後不滑回選單時呼叫，自動捲動照選單狀態恢復。
  void releaseAutoPage() {
    _awayOverMenu = false;
    _syncAutoPagePause();
  }

  void _syncAutoPagePause() =>
      autoPage?.setPaused(menu.controlsVisible.value || _awayOverMenu);

  /// 選單開關只改自動捲動的暫停，不通知閱讀頁：選單、收起手勢與正文的
  /// 點擊層各自聽 [ReaderMenuController.controlsVisible]。
  void _onMenuChanged() {
    if (menu.controlsVisible.value) _awayOverMenu = false;
    _syncAutoPagePause();
  }

  /// 朗讀跟隨與自動捲動都會移動正文，同一時間只留一個：朗讀一開始播放
  /// 就停掉自動捲動；開始自動捲動時停掉朗讀，見
  /// `ReaderPageCoordinator.toggleAutoPage`。
  void _onTtsChanged() {
    final playing = tts?.isPlaying ?? false;
    if (playing && !_ttsWasPlaying) autoPage?.stop();
    _ttsWasPlaying = playing;
    _onChanged();
  }

  void _onSettingsChanged() => _onChanged();

  void _handleAppHidden() {
    autoPage?.stop();
    if (_retired) return;
    final activeRuntime = runtime;
    if (activeRuntime != null) {
      unawaited(activeRuntime.flushProgress());
    }
  }

  ReaderRuntime ensureRuntime(Size size, ReaderStylePreferences style) {
    _lastViewportSize = size;
    final existing = runtime;
    if (existing != null) return existing;

    final spec = specFromStyle(size, style);
    // 開書時已經套用目前的繁簡轉換，不必再為設定重載一次正文。
    _appliedContentSettingsGeneration = settings.contentSettingsGeneration;
    final repository = dependencies.createChapterRepository(
      // 閱讀器關掉時先關 repository 才關提示，關掉之後 repository 不再停用
      // 規則；runtime 還沒接上就關掉時 repository 沒被關，這裡也不送。
      onReplaceRuleDisabled: (rule) {
        if (!_notices.isClosed) _notices.add(replaceRuleDisabledNotice(rule));
      },
    );
    final progressController = ReaderProgressController(
      book: book,
      repository: repository,
      bookDao: dependencies.bookDao,
    );
    final initialLocation = _initialLocationFor(spec);
    final nextRuntime = ReaderRuntime(
      book: book,
      repository: repository,
      progressController: progressController,
      initialLayoutSpec: spec,
      initialLocation: initialLocation,
    )..addListener(_onControllerChanged);
    // 書源搬家時，開著「顯示插圖」的正文裡插圖是照舊網址的書本資料夾排的：
    // 照新網址重排畫面上的這一章。
    repository.onOriginMoved = () {
      if (identical(runtime, nextRuntime) &&
          repository.currentShowIllustrations()) {
        unawaited(nextRuntime.reloadContentPreservingLocation());
      }
    };
    final nextTts = ReaderTtsController(runtime: nextRuntime)
      ..addListener(_onTtsChanged);
    final nextAutoPage = ReaderAutoPageController(
      runtime: nextRuntime,
      viewportController: viewportController,
      viewportExtent: () =>
          _lastViewportSize?.height ??
          nextRuntime.state.layoutSpec.viewportSize.height,
      autoPageSpeed: () => settings.autoPageSpeed,
    )..addListener(_onControllerChanged);

    runtime = nextRuntime;
    tts = nextTts;
    autoPage = nextAutoPage;
    unawaited(nextTts.loadSettings());
    _openRuntimeAfterEntrance(nextRuntime);
    return nextRuntime;
  }

  void syncRuntimeConfiguration(
    ReaderRuntime runtime,
    Size size,
    ReaderStylePreferences style,
  ) {
    _lastViewportSize = size;
    final spec = specFromStyle(size, style);
    final committedSignature = runtime.state.layoutSpec.presentationSignature;
    if (committedSignature == spec.presentationSignature) {
      if (_presentation.requested?.spec.presentationSignature ==
          spec.presentationSignature) {
        _presentation.cancelRequest();
      }
      if (_lastFailedPresentationAttempt?.presentationSignature ==
          spec.presentationSignature) {
        _lastFailedPresentationAttempt = null;
      }
    } else {
      final attempt = _presentationAttempt(runtime, spec);
      final alreadyPending =
          _presentation.requested?.spec.presentationSignature ==
          spec.presentationSignature;
      final alreadyInFlight =
          _presentation.inFlight?.spec.presentationSignature ==
          spec.presentationSignature;
      final failedForSameWorld = _lastFailedPresentationAttempt == attempt;
      if (!alreadyPending && !alreadyInFlight && !failedForSameWorld) {
        _presentation.request((runtime: runtime, spec: spec));
      }
    }
    _reconcileContentSettings(runtime);
  }

  void _reconcileContentSettings(ReaderRuntime runtime) {
    final desiredGeneration = settings.contentSettingsGeneration;
    if (_appliedContentSettingsGeneration == desiredGeneration) {
      if (_lastFailedContentSettingsAttempt?.settingsGeneration ==
          desiredGeneration) {
        _lastFailedContentSettingsAttempt = null;
      }
      return;
    }
    if (_contentSettings.inFlight != null) return;

    final attempt = _contentSettingsAttempt(runtime, desiredGeneration);
    if (_lastFailedContentSettingsAttempt == attempt) return;
    _contentSettings.request(runtime);
  }

  /// 送出當下還要不要送內容設定：還沒生效，且這個 Reader 世界沒有失敗過。
  bool _contentSettingsWanted(ReaderRuntime runtime) {
    final desiredGeneration = settings.contentSettingsGeneration;
    if (_appliedContentSettingsGeneration == desiredGeneration) return false;
    final attempt = _contentSettingsAttempt(runtime, desiredGeneration);
    return _lastFailedContentSettingsAttempt != attempt;
  }

  Future<void> _applyContentSettings(ReaderRuntime runtime) async {
    final desiredGeneration = settings.contentSettingsGeneration;
    final attempt = _contentSettingsAttempt(runtime, desiredGeneration);
    final applied = await runtime.reloadContentPreservingLocation();
    if (applied && settings.contentSettingsGeneration == desiredGeneration) {
      _appliedContentSettingsGeneration = desiredGeneration;
      if (_lastFailedContentSettingsAttempt?.settingsGeneration ==
          desiredGeneration) {
        _lastFailedContentSettingsAttempt = null;
      }
    } else if (!applied) {
      _lastFailedContentSettingsAttempt = attempt;
    }
  }

  ({int settingsGeneration, int chapterIndex, int contentGeneration})
  _contentSettingsAttempt(ReaderRuntime runtime, int settingsGeneration) {
    final target = runtime.pendingLocation ?? runtime.state.visibleLocation;
    return (
      settingsGeneration: settingsGeneration,
      chapterIndex: target.chapterIndex,
      contentGeneration: runtime.state.contentGeneration,
    );
  }

  /// 送出排版設定；送完（含丟例外）都記下成敗，失敗的世界之後不再重送。
  ///
  /// 排程在送出前會等一幀沒有新的版面才呼叫這裡（見 [_presentation]），
  /// 所以旋轉途中的中間版面不會各送一次。
  Future<void> _applyPresentation(_PresentationJob job) async {
    final attempt = _presentationAttempt(job.runtime, job.spec);
    try {
      await job.runtime.applyPresentation(spec: job.spec);
    } finally {
      final committed =
          job.runtime.state.layoutSpec.presentationSignature ==
          job.spec.presentationSignature;
      if (committed) {
        if (_lastFailedPresentationAttempt?.presentationSignature ==
            job.spec.presentationSignature) {
          _lastFailedPresentationAttempt = null;
        }
      } else {
        _lastFailedPresentationAttempt = attempt;
      }
    }
  }

  ({int presentationSignature, int chapterIndex, int contentGeneration})
  _presentationAttempt(ReaderRuntime runtime, ReaderLayoutSpec spec) {
    final target = runtime.pendingLocation ?? runtime.state.visibleLocation;
    return (
      presentationSignature: spec.presentationSignature,
      chapterIndex: target.chapterIndex,
      contentGeneration: runtime.state.contentGeneration,
    );
  }

  ReaderLocation _initialLocationFor(ReaderLayoutSpec spec) {
    final target = openTarget;
    if (target != null) {
      if (target.intent == ReaderOpenIntent.chapterStart) {
        return target.location.copyWith(
          visualOffsetPx: spec.anchorOffsetInViewport,
        );
      }
      return target.location;
    }
    return ReaderLocation(
      chapterIndex: book.chapterIndex,
      charOffset: book.charOffset,
      visualOffsetPx: book.visualOffsetPx,
    );
  }

  ReaderLayoutSpec specFromStyle(Size size, ReaderStylePreferences style) {
    // cellWidth 只描述全形字 advance 的 typography metric。
    // ReaderLayoutSpec 可用它推導置中的內部 text frame，但不得用它
    // 裁切或重定義 viewport 擁有的實體 contentWidth。
    double? measureCell(double letterSpacing) =>
        const ReaderParagraphLayout().measureCellWidth(
          fontSize: style.fontSize,
          letterSpacing: letterSpacing,
          bold: style.bold,
          fontFamily: style.fontFamily,
        );
    var letterSpacing = style.letterSpacing;
    var cellWidth = measureCell(letterSpacing);
    if (style.justify && cellWidth != null) {
      // 左右對齊：剩下的空隙攤進字距後重量字格，文字框就撐滿內容寬。
      letterSpacing = ReaderTextLayoutFrame.justifiedLetterSpacing(
        contentWidth: size.width - style.paddingLeft - style.paddingRight,
        cellWidth: cellWidth,
        letterSpacing: letterSpacing,
      );
      cellWidth = measureCell(letterSpacing);
    }
    return ReaderLayoutSpec.fromViewport(
      viewportSize: size,
      cellWidth: cellWidth,
      style: ReaderLayoutStyle(
        fontSize: style.fontSize,
        lineHeight: style.lineHeight,
        letterSpacing: letterSpacing,
        paragraphSpacing: style.paragraphSpacing,
        chapterSpacing: style.chapterSpacing,
        paddingTop: style.paddingTop,
        paddingBottom: style.paddingBottom,
        paddingLeft: style.paddingLeft,
        paddingRight: style.paddingRight,
        bold: style.bold,
        titleBold: style.titleBold,
        titleCenter: style.titleCenter,
        fontFamily: style.fontFamily,
        textIndent: style.textIndent,
        titleFontSize: style.titleFontSize,
        titleSpacing: style.titleSpacing,
      ),
    );
  }

  Future<ReaderLocation?> flushProgress() async {
    if (_retired) return null;
    return runtime?.flushProgress();
  }

  /// 這本書要換目錄了（改編碼）：舊閱讀器停止存正文與寫進度，關掉時也不再
  /// 寫回。呼叫前先 [flushProgress] 存好最後一次。
  void retire() {
    if (_retired) return;
    _retired = true;
    runtime?.retire();
  }

  /// 換目錄失敗、閱讀器照舊時恢復。
  void resume() {
    if (!_retired) return;
    _retired = false;
    runtime?.resume();
  }

  bool _retired = false;

  final Completer<void> _opened = Completer<void>();

  /// 開書定位完成（含取不到正文而停在錯誤畫面）時完成。
  Future<void> get opened => _opened.future;

  void _openRuntimeAfterEntrance(ReaderRuntime runtime) {
    if (_opening) return;
    _opening = true;
    unawaited(
      _entrance.then((_) async {
        if (!_isMounted() || runtime.disposed) return;
        if (book.isLocal) {
          // 本地書先對好目錄：TXT 重新分章時開書的位置換成新目錄的，之後
          // 比對的雲端進度也照新目錄。對不了的錯誤由開書處理。
          try {
            await runtime.alignChaptersBeforeOpen();
          } catch (error, stackTrace) {
            AppLog.e('開書前對目錄失敗', error: error, stackTrace: stackTrace);
          }
          if (!_isMounted() || runtime.disposed) return;
        }
        final at = await _openLocation?.call(runtime);
        if (!_isMounted() || runtime.disposed) return;
        unawaited(
          runtime
              .openBook(
                at: at,
                // 換成別處讀到的位置時，不再照書籤的章名對。
                chapterTitle: at == null ? openTarget?.chapterTitle : null,
              )
              .whenComplete(() {
                _opening = false;
                if (!_opened.isCompleted) _opened.complete();
              }),
        );
      }),
    );
  }

  void dispose() {
    _lifecycleListener.dispose();
    settings.removeListener(_onSettingsChanged);
    menu.controlsVisible.removeListener(_onMenuChanged);
    autoPage?.removeListener(_onControllerChanged);
    tts?.removeListener(_onTtsChanged);
    runtime?.removeListener(_onControllerChanged);
    autoPage?.dispose();
    tts?.dispose();
    runtime?.dispose();
    bookmarks.dispose();
    highlights.dispose();
    menu.dispose();
    settings.dispose();
    unawaited(_notices.close());
  }
}
