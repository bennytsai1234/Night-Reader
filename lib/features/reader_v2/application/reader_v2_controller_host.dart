import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_storage_service.dart';
import 'package:night_reader/features/reader_v2/application/dependencies/reader_v2_dependencies.dart';
import 'package:night_reader/features/reader_v2/features/auto_page/reader_v2_auto_page_controller.dart';
import 'package:night_reader/features/reader_v2/features/bookmark/reader_v2_bookmark_controller.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_controller.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_controller.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_engine.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_open_target.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';

class ReaderV2ControllerHost {
  ReaderV2ControllerHost({
    required this.book,
    required this.initialChapters,
    required this.openTarget,
    required VoidCallback onChanged,
    required bool Function() isMounted,
  }) : _onChanged = onChanged,
       _isMounted = isMounted {
    settings.addListener(_onSettingsChanged);
    menu.addListener(_onControllerChanged);
    dependencies = ReaderV2Dependencies(
      book: book,
      initialChapters: initialChapters,
      currentChineseConvert: () => settings.chineseConvert,
    );
    bookStorageService = BookStorageService(
      bookDao: dependencies.bookDao,
      chapterDao: dependencies.chapterDao,
      contentDao: dependencies.readerChapterContentDao,
      bookmarkDao: dependencies.bookmarkDao,
    );
    _lastContentSettingsGeneration = settings.contentSettingsGeneration;
    unawaited(settings.loadSettings());
  }

  final Book book;
  final List<BookChapter> initialChapters;
  final ReaderV2OpenTarget? openTarget;
  final VoidCallback _onChanged;
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
  ReaderV2BookmarkController? bookmark;

  Size? _lastViewportSize;
  int? _lastLayoutSignature;
  int _lastContentSettingsGeneration = 0;
  bool _opening = false;

  void _onControllerChanged() {
    _onChanged();
  }

  void _onSettingsChanged() {
    autoPage?.refreshConfiguration();
    _onChanged();
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
    );
    final initialLocation = _initialLocationFor(spec);
    final nextRuntime = ReaderV2Runtime(
      book: book,
      repository: repository,
      layoutEngine: ReaderV2LayoutEngine(),
      progressController: progressController,
      initialLayoutSpec: spec,
      initialLocation: initialLocation,
    )..addListener(_onControllerChanged);
    final nextTts = ReaderV2TtsController(runtime: nextRuntime)
      ..addListener(_onControllerChanged);
    final nextAutoPage = ReaderV2AutoPageController(
      runtime: nextRuntime,
      viewportController: viewportController,
      viewportExtent:
          () =>
              _lastViewportSize?.height ??
              nextRuntime.state.layoutSpec.viewportSize.height,
      autoPageSpeed: () => settings.autoPageSpeed,
    )..addListener(_onControllerChanged);

    runtime = nextRuntime;
    tts = nextTts;
    autoPage = nextAutoPage;
    final bookmarkDao = dependencies.bookmarkDao;
    if (bookmarkDao != null) {
      bookmark = ReaderV2BookmarkController(
        book: book,
        runtime: nextRuntime,
        bookmarkDao: bookmarkDao,
      );
    }
    _lastLayoutSignature = spec.layoutSignature;
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
    final needsLayout = _lastLayoutSignature != spec.layoutSignature;
    if (needsLayout) {
      _lastLayoutSignature = spec.layoutSignature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isMounted()) return;
        unawaited(runtime.applyPresentation(spec: spec));
      });
    }
    if (_lastContentSettingsGeneration != settings.contentSettingsGeneration) {
      _lastContentSettingsGeneration = settings.contentSettingsGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isMounted()) return;
        unawaited(runtime.reloadContentPreservingLocation());
      });
    }
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
    return ReaderV2LayoutSpec.fromViewport(
      viewportSize: size,
      style: ReaderV2LayoutStyle(
        fontSize: style.fontSize,
        lineHeight: style.lineHeight,
        letterSpacing: style.letterSpacing,
        paragraphSpacing: style.paragraphSpacing,
        paddingTop: style.paddingTop,
        paddingBottom: style.paddingBottom,
        paddingLeft: style.paddingLeft,
        paddingRight: style.paddingRight,
        bold: style.bold,
        textIndent: style.textIndent,
      ),
    );
  }


  Future<void> flushProgress() async {
    await runtime?.flushProgress();
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
    settings.removeListener(_onSettingsChanged);
    menu.removeListener(_onControllerChanged);
    autoPage?.removeListener(_onControllerChanged);
    tts?.removeListener(_onControllerChanged);
    runtime?.removeListener(_onControllerChanged);
    autoPage?.dispose();
    tts?.dispose();
    runtime?.dispose();
    menu.dispose();
    settings.dispose();
  }
}
