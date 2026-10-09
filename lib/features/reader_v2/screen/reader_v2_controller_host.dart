import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_storage_service.dart';
import 'package:night_reader/features/reader_v2/screen/dependencies/reader_v2_dependencies.dart';
import 'package:night_reader/features/reader_v2/features/auto_page/reader_v2_auto_page_controller.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_controller.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_controller.dart';
import 'package:night_reader/features/reader_v2/hybrid/layout/reader_paragraph_layout.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_open_target.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';

class ReaderV2ControllerHost {
  ReaderV2ControllerHost({
    required this.book,
    required this.initialChapters,
    required this.openTarget,
    required this._onChanged,
    required this._onProgressPersisted,
    required this._isMounted,
  }) {
    settings.addListener(_onSettingsChanged);
    menu.addListener(_onMenuChanged);
    dependencies = ReaderV2Dependencies(
      book: book,
      initialChapters: initialChapters,
      currentChineseConvert: () => settings.chineseConvert,
    );
    bookStorageService = BookStorageService(
      bookDao: dependencies.bookDao,
      chapterDao: dependencies.chapterDao,
      contentDao: dependencies.readerChapterContentDao,
    );
    _appliedContentSettingsGeneration = settings.contentSettingsGeneration;
    unawaited(settings.loadSettings());
    // Reader session visibility belongs to the host, not the viewport.
    // Leaving the visible app stops viewport motion and persists the latest
    // captured location through the Runtime owner.
    _lifecycleListener = AppLifecycleListener(onHide: _handleAppHidden);
  }

  late final AppLifecycleListener _lifecycleListener;

  final Book book;
  final List<BookChapter> initialChapters;
  final ReaderV2OpenTarget? openTarget;
  final VoidCallback _onChanged;
  final VoidCallback _onProgressPersisted;
  final bool Function() _isMounted;

  final ReaderV2SettingsController settings = ReaderV2SettingsController();
  final ReaderV2MenuController menu = ReaderV2MenuController();
  final ReaderV2ViewportController viewportController =
      ReaderV2ViewportController();

  late final ReaderV2Dependencies dependencies;
  late final BookStorageService bookStorageService;

  ReaderV2Runtime? runtime;
  ReaderV2TtsController? tts;
  ReaderV2AutoPageController? autoPage;

  Size? _lastViewportSize;
  int _appliedContentSettingsGeneration = 0;
  int? _contentSettingsInFlightGeneration;
  ({int settingsGeneration, int chapterIndex, int contentGeneration})?
  _lastFailedContentSettingsAttempt;
  bool _contentSettingsCallbackQueued = false;
  ReaderV2LayoutSpec? _pendingPresentationSpec;
  ReaderV2LayoutSpec? _presentationInFlightSpec;
  ({int presentationSignature, int chapterIndex, int contentGeneration})?
  _lastFailedPresentationAttempt;
  bool _presentationCallbackQueued = false;
  int _presentationRevision = 0;
  bool _opening = false;
  bool _ttsWasPlaying = false;

  void _onControllerChanged() {
    _onChanged();
  }

  void _onMenuChanged() {
    autoPage?.setPaused(menu.controlsVisible);
    _onChanged();
  }

  /// 朗讀跟隨與自動捲動都會移動正文，同一時間只留一個：朗讀一開始播放
  /// 就停掉自動捲動；開始自動捲動時停掉朗讀，見
  /// `ReaderV2PageCoordinator.toggleAutoPage`。
  void _onTtsChanged() {
    final playing = tts?.isPlaying ?? false;
    if (playing && !_ttsWasPlaying) autoPage?.stop();
    _ttsWasPlaying = playing;
    _onChanged();
  }

  void _onSettingsChanged() {
    autoPage?.refreshConfiguration();
    _onChanged();
  }

  void _handleAppHidden() {
    autoPage?.stop();
    final activeRuntime = runtime;
    if (activeRuntime != null) {
      unawaited(activeRuntime.flushProgress());
    }
  }

  ReaderV2Runtime ensureRuntime(Size size, ReaderV2Style style) {
    _lastViewportSize = size;
    final existing = runtime;
    if (existing != null) return existing;

    final spec = specFromStyle(size, style);
    final repository = dependencies.createChapterRepository();
    final progressController = ReaderV2ProgressController(
      book: book,
      repository: repository,
      bookDao: dependencies.bookDao,
      onProgressPersisted: _onProgressPersisted,
    );
    final initialLocation = _initialLocationFor(spec);
    final nextRuntime = ReaderV2Runtime(
      book: book,
      repository: repository,
      progressController: progressController,
      initialLayoutSpec: spec,
      initialLocation: initialLocation,
    )..addListener(_onControllerChanged);
    final nextTts = ReaderV2TtsController(runtime: nextRuntime)
      ..addListener(_onTtsChanged);
    final nextAutoPage = ReaderV2AutoPageController(
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
    _openRuntimeAfterFirstFrame(nextRuntime);
    return nextRuntime;
  }

  void syncRuntimeConfiguration(
    ReaderV2Runtime runtime,
    Size size,
    ReaderV2Style style,
  ) {
    _lastViewportSize = size;
    final spec = specFromStyle(size, style);
    final committedSignature = runtime.state.layoutSpec.presentationSignature;
    if (committedSignature == spec.presentationSignature) {
      if (_pendingPresentationSpec?.presentationSignature ==
          spec.presentationSignature) {
        _pendingPresentationSpec = null;
      }
      if (_lastFailedPresentationAttempt?.presentationSignature ==
          spec.presentationSignature) {
        _lastFailedPresentationAttempt = null;
      }
    } else {
      final attempt = _presentationAttempt(runtime, spec);
      final alreadyPending =
          _pendingPresentationSpec?.presentationSignature ==
          spec.presentationSignature;
      final alreadyInFlight =
          _presentationInFlightSpec?.presentationSignature ==
          spec.presentationSignature;
      final failedForSameWorld = _lastFailedPresentationAttempt == attempt;
      if (!alreadyPending && !alreadyInFlight && !failedForSameWorld) {
        _pendingPresentationSpec = spec;
        _presentationRevision += 1;
        _queuePresentationDispatch(runtime);
      }
    }
    _reconcileContentSettings(runtime);
  }

  void _reconcileContentSettings(ReaderV2Runtime runtime) {
    final desiredGeneration = settings.contentSettingsGeneration;
    if (_appliedContentSettingsGeneration == desiredGeneration) {
      if (_lastFailedContentSettingsAttempt?.settingsGeneration ==
          desiredGeneration) {
        _lastFailedContentSettingsAttempt = null;
      }
      return;
    }
    if (_contentSettingsInFlightGeneration != null) return;

    final attempt = _contentSettingsAttempt(runtime, desiredGeneration);
    if (_lastFailedContentSettingsAttempt == attempt) return;
    _queueContentSettingsDispatch(runtime);
  }

  void _queueContentSettingsDispatch(ReaderV2Runtime runtime) {
    if (_contentSettingsCallbackQueued ||
        _contentSettingsInFlightGeneration != null) {
      return;
    }
    _contentSettingsCallbackQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _contentSettingsCallbackQueued = false;
      if (!_isMounted()) return;

      final desiredGeneration = settings.contentSettingsGeneration;
      if (_appliedContentSettingsGeneration == desiredGeneration) return;
      final attempt = _contentSettingsAttempt(runtime, desiredGeneration);
      if (_lastFailedContentSettingsAttempt == attempt) return;

      _contentSettingsInFlightGeneration = desiredGeneration;
      unawaited(
        _applyContentSettings(
          runtime,
          desiredGeneration: desiredGeneration,
          attempt: attempt,
        ),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _applyContentSettings(
    ReaderV2Runtime runtime, {
    required int desiredGeneration,
    required ({int settingsGeneration, int chapterIndex, int contentGeneration})
    attempt,
  }) async {
    try {
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
    } finally {
      if (_contentSettingsInFlightGeneration == desiredGeneration) {
        _contentSettingsInFlightGeneration = null;
      }
    }

    if (!_isMounted()) return;
    _reconcileContentSettings(runtime);
  }

  ({int settingsGeneration, int chapterIndex, int contentGeneration})
  _contentSettingsAttempt(ReaderV2Runtime runtime, int settingsGeneration) {
    final target = runtime.pendingLocation ?? runtime.state.visibleLocation;
    return (
      settingsGeneration: settingsGeneration,
      chapterIndex: target.chapterIndex,
      contentGeneration: runtime.state.contentGeneration,
    );
  }

  /// Wait for one quiet frame before dispatching the latest presentation.
  ///
  /// Rotation and inset animations can produce a new presentation signature
  /// every frame. Keeping the request pending until a frame arrives without a
  /// new signature coalesces that stream while still guaranteeing that the
  /// final size is dispatched. The extra frame is scheduler-based rather than a
  /// fixed wall-clock debounce, so it does not depend on device speed.
  void _queuePresentationDispatch(ReaderV2Runtime runtime) {
    if (_presentationCallbackQueued || _presentationInFlightSpec != null) {
      return;
    }
    _presentationCallbackQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isMounted()) {
        _presentationCallbackQueued = false;
        _pendingPresentationSpec = null;
        return;
      }
      _waitForQuietPresentationFrame(runtime, _presentationRevision);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _waitForQuietPresentationFrame(
    ReaderV2Runtime runtime,
    int observedRevision,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isMounted()) {
        _presentationCallbackQueued = false;
        _pendingPresentationSpec = null;
        return;
      }
      if (_presentationRevision != observedRevision) {
        _waitForQuietPresentationFrame(runtime, _presentationRevision);
        return;
      }

      _presentationCallbackQueued = false;
      final pendingSpec = _pendingPresentationSpec;
      _pendingPresentationSpec = null;
      if (pendingSpec == null) return;

      final attempt = _presentationAttempt(runtime, pendingSpec);
      _presentationInFlightSpec = pendingSpec;
      unawaited(
        runtime.applyPresentation(spec: pendingSpec).whenComplete(() {
          _presentationInFlightSpec = null;
          final committed =
              runtime.state.layoutSpec.presentationSignature ==
              pendingSpec.presentationSignature;
          if (committed) {
            if (_lastFailedPresentationAttempt?.presentationSignature ==
                pendingSpec.presentationSignature) {
              _lastFailedPresentationAttempt = null;
            }
          } else {
            _lastFailedPresentationAttempt = attempt;
          }
          if (!_isMounted()) {
            _pendingPresentationSpec = null;
            return;
          }
          if (_pendingPresentationSpec != null) {
            _queuePresentationDispatch(runtime);
          }
        }),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  ({int presentationSignature, int chapterIndex, int contentGeneration})
  _presentationAttempt(ReaderV2Runtime runtime, ReaderV2LayoutSpec spec) {
    final target = runtime.pendingLocation ?? runtime.state.visibleLocation;
    return (
      presentationSignature: spec.presentationSignature,
      chapterIndex: target.chapterIndex,
      contentGeneration: runtime.state.contentGeneration,
    );
  }

  ReaderV2Location _initialLocationFor(ReaderV2LayoutSpec spec) {
    final target = openTarget;
    if (target != null) {
      if (target.intent == ReaderV2OpenIntent.chapterStart) {
        return target.location.copyWith(
          visualOffsetPx: spec.anchorOffsetInViewport,
        );
      }
      return target.location;
    }
    return ReaderV2Location(
      chapterIndex: book.chapterIndex,
      charOffset: book.charOffset,
      visualOffsetPx: book.visualOffsetPx,
    );
  }

  ReaderV2LayoutSpec specFromStyle(Size size, ReaderV2Style style) {
    // cellWidth 只描述全形字 advance 的 typography metric。
    // ReaderV2LayoutSpec 可用它推導置中的內部 text frame，但不得用它
    // 裁切或重定義 viewport 擁有的實體 contentWidth。
    final cellWidth = const ReaderParagraphLayout().measureCellWidth(
      fontSize: style.fontSize,
      letterSpacing: style.letterSpacing,
      bold: style.bold,
    );
    return ReaderV2LayoutSpec.fromViewport(
      viewportSize: size,
      cellWidth: cellWidth,
      style: ReaderV2LayoutStyle(
        fontSize: style.fontSize,
        lineHeight: style.lineHeight,
        letterSpacing: style.letterSpacing,
        paragraphSpacing: style.paragraphSpacing,
        chapterSpacing: style.chapterSpacing,
        paddingTop: style.paddingTop,
        paddingBottom: style.paddingBottom,
        paddingLeft: style.paddingLeft,
        paddingRight: style.paddingRight,
        bold: style.bold,
        textIndent: style.textIndent,
        titleFontSize: style.titleFontSize,
      ),
    );
  }

  Future<ReaderV2Location?> flushProgress() async {
    return runtime?.flushProgress();
  }

  void _openRuntimeAfterFirstFrame(ReaderV2Runtime runtime) {
    if (_opening) return;
    _opening = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isMounted()) return;
      unawaited(runtime.openBook().whenComplete(() => _opening = false));
    });
  }

  void dispose() {
    _lifecycleListener.dispose();
    settings.removeListener(_onSettingsChanged);
    menu.removeListener(_onMenuChanged);
    autoPage?.removeListener(_onControllerChanged);
    tts?.removeListener(_onTtsChanged);
    runtime?.removeListener(_onControllerChanged);
    autoPage?.dispose();
    tts?.dispose();
    runtime?.dispose();
    menu.dispose();
    settings.dispose();
  }
}
