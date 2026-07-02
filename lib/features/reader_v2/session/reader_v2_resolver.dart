import 'dart:math' as math;

import 'package:night_reader/features/reader_v2/render/reader_v2_render_page.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_engine.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';

import 'reader_v2_chapter_view.dart';
import 'reader_v2_location.dart';

class ReaderV2PageAddress {
  const ReaderV2PageAddress({
    required this.chapterIndex,
    required this.pageIndex,
  });

  final int chapterIndex;
  final int pageIndex;
}

class _StaleLayoutGeneration implements Exception {
  const _StaleLayoutGeneration();
}

class _InFlightLayout {
  const _InFlightLayout({required this.id, required this.future});

  final int id;
  final Future<void> future;
}

class ReaderV2Resolver {
  ReaderV2Resolver({
    required this.repository,
    required this.layoutEngine,
    required this.layoutSpec,
  });

  final ReaderV2ChapterRepository repository;
  final ReaderV2LayoutEngine layoutEngine;
  ReaderV2LayoutSpec layoutSpec;

  /// 每個 layoutStep 呼叫最多產生這麼多新內容才回傳，讓任何單一步進的延遲
  /// 都有上界，不會因為呼叫端要求的量（例如 ensureLayout 的 double.infinity）
  /// 而讓單一步進退化成整章排版。
  static const double _maxStepExtentPx = 3000.0;

  static const int _maxLayoutCacheSize = 50;
  final Map<int, ReaderV2ChapterView> _layouts = <int, ReaderV2ChapterView>{};
  final Map<int, ReaderV2LayoutCursor> _cursors = <int, ReaderV2LayoutCursor>{};
  final Map<String, _InFlightLayout> _inFlight = <String, _InFlightLayout>{};
  final Set<int> _invalidatedInFlightTaskIds = <int>{};
  final Map<int, String> _layoutErrors = <int, String>{};
  int _cacheGeneration = 0;
  int _nextInFlightTaskId = 0;

  /// 每次快取寫入（不論部分或完整就緒）都會呼叫一次，通知訂閱者「這一章
  /// 排版有進度了」。目前給 [ReaderV2ChapterPageCacheManager] 訂閱，讓已經
  /// 放進視窗的部分就緒章節在背景排版繼續推進時，不必等使用者再滑動就能
  /// 補上新長出來的內容。
  void Function(int chapterIndex)? onChapterProgressed;

  void _writeToLayoutCache(
    int chapterIndex,
    ReaderV2ChapterView view,
    ReaderV2LayoutCursor cursor,
  ) {
    _layouts.remove(chapterIndex);
    _cursors.remove(chapterIndex);
    if (_layouts.length >= _maxLayoutCacheSize) {
      final evicted = _layouts.keys.first;
      _layouts.remove(evicted);
      _cursors.remove(evicted);
    }
    _layouts[chapterIndex] = view;
    if (!cursor.isComplete) {
      _cursors[chapterIndex] = cursor;
    }
    onChapterProgressed?.call(chapterIndex);
  }

  void _touchLayoutCache(int chapterIndex) {
    final view = _layouts.remove(chapterIndex);
    if (view == null) return;
    _layouts[chapterIndex] = view;
  }

  int get chapterCount => repository.chapterCount;

  void updateLayoutSpec(ReaderV2LayoutSpec spec) {
    if (layoutSpec.layoutSignature == spec.layoutSignature) return;
    layoutSpec = spec;
    _cacheGeneration += 1;
    for (final inFlight in _inFlight.values) {
      _invalidatedInFlightTaskIds.add(inFlight.id);
    }
    _layouts.clear();
    _cursors.clear();
    // 舊 spec 底下的排版錯誤對新 spec 不成立，留著會讓 placeholderPageFor
    // 誤顯示「章節載入失敗」。
    _layoutErrors.clear();
  }

  /// 可能回傳「部分就緒」的結果——排版還沒排完整章時，`isComplete` 為
  /// false，且 `pages` 只包含目前已經排出來的頁面。呼叫端若需要保證整章
  /// 排完，改用 [ensureLayout]。
  ReaderV2ChapterView? cachedLayout(int chapterIndex) => _layouts[chapterIndex];

  void clearCachedLayouts() {
    _cacheGeneration += 1;
    for (final inFlight in _inFlight.values) {
      _invalidatedInFlightTaskIds.add(inFlight.id);
    }
    _layouts.clear();
    _cursors.clear();
    _inFlight.clear();
    _layoutErrors.clear();
  }

  /// 排完整章才回傳，行為與改動前的 `ensureLayout` 完全相同，內部改用
  /// [ensureLayoutAtLeast] 實作。
  Future<ReaderV2ChapterView> ensureLayout(
    int chapterIndex, {
    bool retryOnStale = true,
  }) {
    return ensureLayoutAtLeast(
      chapterIndex,
      minExtentPx: double.infinity,
      retryOnStale: retryOnStale,
    );
  }

  /// 排到「已完成」或「累積高度 ≥ minExtentPx」其中之一先滿足就回傳，不必
  /// 排完整章。等待時間的上界只跟 `minExtentPx` 成正比，不跟章節總長度
  /// 成正比——這是本次視窗擴張撞上未排版長章節時不再卡住主執行緒的關鍵。
  Future<ReaderV2ChapterView> ensureLayoutAtLeast(
    int chapterIndex, {
    required double minExtentPx,
    bool retryOnStale = true,
  }) async {
    while (true) {
      try {
        return await _ensureLayoutAtLeastForCurrentGeneration(
          chapterIndex,
          minExtentPx: minExtentPx,
        );
      } on _StaleLayoutGeneration {
        if (!retryOnStale) rethrow;
      }
    }
  }

  Future<ReaderV2ChapterView> _ensureLayoutAtLeastForCurrentGeneration(
    int chapterIndex, {
    required double minExtentPx,
  }) async {
    await repository.ensureChapters();
    final safeIndex = _normalizeChapterIndex(chapterIndex);
    while (true) {
      final cached = _layouts[safeIndex];
      if (cached != null &&
          cached.layoutSignature == layoutSpec.layoutSignature) {
        if (cached.isComplete || cached.contentHeight >= minExtentPx) {
          _touchLayoutCache(safeIndex);
          return _layouts[safeIndex]!;
        }
      }
      final cachedHeight =
          (cached != null &&
                  cached.layoutSignature == layoutSpec.layoutSignature)
              ? cached.contentHeight
              : 0.0;
      await _stepOnce(safeIndex, remainingNeeded: minExtentPx - cachedHeight);
    }
  }

  Future<void> _stepOnce(
    int chapterIndex, {
    required double remainingNeeded,
  }) async {
    final spec = layoutSpec;
    final cacheGeneration = _cacheGeneration;
    final taskKey = '$chapterIndex|${spec.layoutSignature}|$cacheGeneration';
    final inFlight = _inFlight[taskKey];
    if (inFlight != null) {
      await inFlight.future;
      return;
    }
    final taskId = _nextInFlightTaskId++;
    final stepTarget =
        remainingNeeded.isFinite
            ? math
                .min(remainingNeeded, _maxStepExtentPx)
                .clamp(1.0, _maxStepExtentPx)
            : _maxStepExtentPx;
    late final Future<void> task;
    task = () async {
      try {
        final content = await repository.loadContent(chapterIndex);
        _throwIfStale(spec, cacheGeneration, taskId);
        final existingView = _layouts[chapterIndex];
        final reuseExisting =
            existingView != null &&
            existingView.layoutSignature == spec.layoutSignature;
        final linesSoFar =
            reuseExisting
                ? existingView.layout.lines
                : const <ReaderV2TextLine>[];
        final existingCursor = _cursors[chapterIndex];
        final cursor =
            (reuseExisting &&
                    existingCursor != null &&
                    existingCursor.layoutSignature == spec.layoutSignature)
                ? existingCursor
                : null;
        final step = await layoutEngine.layoutStep(
          content: content,
          spec: spec,
          linesSoFar: linesSoFar,
          cursor: cursor,
          minNewExtentPx: stepTarget,
        );
        _throwIfStale(spec, cacheGeneration, taskId);
        final view = ReaderV2ChapterView(
          step.layout,
          chapterSize: repository.chapterCount,
          title: repository.titleFor(chapterIndex),
        );
        _writeToLayoutCache(chapterIndex, view, step.cursor);
        _layoutErrors.remove(chapterIndex);
      } catch (e) {
        if (e is! _StaleLayoutGeneration &&
            cacheGeneration == _cacheGeneration &&
            !_invalidatedInFlightTaskIds.contains(taskId)) {
          _layoutErrors[chapterIndex] = e.toString();
        }
        rethrow;
      }
    }();
    _inFlight[taskKey] = _InFlightLayout(id: taskId, future: task);
    try {
      await task;
    } finally {
      final current = _inFlight[taskKey];
      if (current != null && identical(current.future, task)) {
        _inFlight.remove(taskKey);
      }
      _invalidatedInFlightTaskIds.remove(taskId);
    }
  }

  /// 只做「一個 layoutStep 份量」的背景排版工作就回傳，不保證排完整章。
  /// 給背景排程器（[ReaderV2PreloadScheduler]）呼叫，讓多個排隊中的章節可
  /// 以輪流推進，不會被單一超長章節卡住、独占整個背景排版佇列。
  Future<ReaderV2ChapterView> continueLayoutStep(int chapterIndex) async {
    await repository.ensureChapters();
    final safeIndex = _normalizeChapterIndex(chapterIndex);
    final cached = _layouts[safeIndex];
    final upToDate =
        cached != null && cached.layoutSignature == layoutSpec.layoutSignature;
    if (upToDate && cached.isComplete) return cached;
    await _stepOnce(safeIndex, remainingNeeded: double.infinity);
    return _layouts[safeIndex]!;
  }

  void retainLayoutsFor(Iterable<int> chapterIndexes) {
    final retained = chapterIndexes.toSet();
    final staleInFlightKeys =
        _inFlight.keys.where((key) {
          final chapterIndex = _chapterIndexFromTaskKey(key);
          return chapterIndex != null && !retained.contains(chapterIndex);
        }).toList();
    for (final key in staleInFlightKeys) {
      final evicted = _inFlight.remove(key);
      if (evicted != null) {
        _invalidatedInFlightTaskIds.add(evicted.id);
      }
    }
    _layouts.removeWhere((chapterIndex, _) => !retained.contains(chapterIndex));
    _cursors.removeWhere((chapterIndex, _) => !retained.contains(chapterIndex));
    _layoutErrors.removeWhere(
      (chapterIndex, _) => !retained.contains(chapterIndex),
    );
  }

  Future<ReaderV2RenderPage> pageForLocation(ReaderV2Location location) async {
    final layout = await ensureLayout(location.chapterIndex);
    return layout.pageForCharOffset(location.charOffset);
  }

  Future<ReaderV2RenderPage?> nextPage(
    ReaderV2RenderPage page, {
    bool allowAsyncLoad = false,
  }) async {
    final layout =
        allowAsyncLoad
            ? await ensureLayout(page.chapterIndex)
            : cachedLayout(page.chapterIndex);
    final pages = layout?.pages ?? const <ReaderV2RenderPage>[];
    if (page.pageIndex + 1 < pages.length) {
      return pages[page.pageIndex + 1];
    }
    if (layout != null && !layout.isComplete) {
      return placeholderPageFor(page.chapterIndex);
    }
    final nextChapterIndex = page.chapterIndex + 1;
    if (nextChapterIndex >= repository.chapterCount) return null;
    final nextLayout =
        allowAsyncLoad
            ? await ensureLayout(nextChapterIndex)
            : cachedLayout(nextChapterIndex);
    if (nextLayout == null || nextLayout.pages.isEmpty) return null;
    return nextLayout.pages.first;
  }

  Future<ReaderV2RenderPage?> prevPage(
    ReaderV2RenderPage page, {
    bool allowAsyncLoad = false,
  }) async {
    final layout =
        allowAsyncLoad
            ? await ensureLayout(page.chapterIndex)
            : cachedLayout(page.chapterIndex);
    final pages = layout?.pages ?? const <ReaderV2RenderPage>[];
    if (page.pageIndex > 0 && page.pageIndex <= pages.length - 1) {
      return pages[page.pageIndex - 1];
    }
    final prevChapterIndex = page.chapterIndex - 1;
    if (prevChapterIndex < 0) return null;
    final prevLayout =
        allowAsyncLoad
            ? await ensureLayout(prevChapterIndex)
            : cachedLayout(prevChapterIndex);
    if (prevLayout == null || prevLayout.pages.isEmpty) return null;
    if (!prevLayout.isComplete) {
      return placeholderPageFor(prevChapterIndex);
    }
    return prevLayout.pages.last;
  }

  ReaderV2RenderPage? nextPageSync(ReaderV2RenderPage page) {
    if (page.isPlaceholder) return null;
    final layout = cachedLayout(page.chapterIndex);
    final pages = layout?.pages ?? const <ReaderV2RenderPage>[];
    if (page.pageIndex + 1 < pages.length) {
      return pages[page.pageIndex + 1];
    }
    if (layout != null && !layout.isComplete) {
      // 這一章排版還沒完成，目前只是排到這裡而已，不是真的章節結尾——
      // 不能誤判成「到底了」去接下一章，回傳本章自己的 loading 佔位頁。
      return placeholderPageFor(page.chapterIndex);
    }
    final nextLayout = cachedLayout(page.chapterIndex + 1);
    if (nextLayout == null || nextLayout.pages.isEmpty) return null;
    // 章節排版一律從頭開始排，第一頁一旦存在就不會再變，跟該章是否已經
    // 排完整章無關，可以安全使用。
    return nextLayout.pages.first;
  }

  ReaderV2RenderPage? prevPageSync(ReaderV2RenderPage page) {
    if (page.isPlaceholder) return null;
    final layout = cachedLayout(page.chapterIndex);
    final pages = layout?.pages ?? const <ReaderV2RenderPage>[];
    if (page.pageIndex > 0 && page.pageIndex <= pages.length - 1) {
      return pages[page.pageIndex - 1];
    }
    final prevLayout = cachedLayout(page.chapterIndex - 1);
    if (prevLayout == null || prevLayout.pages.isEmpty) return null;
    if (!prevLayout.isComplete) {
      // 前一章排版還沒完成：目前的 pages.last 只是「排到這裡」，不是那一
      // 章真正的最後一頁（排版一律從章節開頭往後排）。直接回傳它會讓使用
      // 者跳到錯誤的頁面，改回傳 loading 佔位頁——呼叫端（見
      // ReaderV2NavigationController.moveToPrevPage）本來就會處理
      // isPlaceholder && isLoading 的情況並重試。
      return placeholderPageFor(page.chapterIndex - 1);
    }
    return prevLayout.pages.last;
  }

  ReaderV2RenderPage? nextPageOrPlaceholder(ReaderV2RenderPage page) {
    final next = nextPageSync(page);
    if (next != null) return next;
    final nextChapterIndex = page.chapterIndex + 1;
    if (nextChapterIndex >= repository.chapterCount) return null;
    return placeholderPageFor(nextChapterIndex);
  }

  ReaderV2RenderPage? prevPageOrPlaceholder(ReaderV2RenderPage page) {
    final prev = prevPageSync(page);
    if (prev != null) return prev;
    final prevChapterIndex = page.chapterIndex - 1;
    if (prevChapterIndex < 0) return null;
    return placeholderPageFor(prevChapterIndex);
  }

  ReaderV2RenderPage placeholderPageFor(int chapterIndex) {
    final error = _layoutErrors[chapterIndex];
    final message = error == null ? '載入中...' : '章節載入失敗，翻頁重試';
    final contentHeight =
        layoutSpec.contentHeight <= 0 ? 1.0 : layoutSpec.contentHeight;
    final viewportHeight =
        layoutSpec.viewportSize.height <= 0
            ? contentHeight
            : layoutSpec.viewportSize.height;
    final top = (contentHeight / 2 - layoutSpec.style.fontSize).clamp(
      0.0,
      contentHeight,
    );
    final lineHeight =
        layoutSpec.style.fontSize * layoutSpec.style.effectiveLineHeight;
    return ReaderV2RenderPage(
      pageIndex: 0,
      chapterIndex: chapterIndex,
      chapterSize: repository.chapterCount,
      title: repository.titleFor(chapterIndex),
      contentHeight: contentHeight,
      viewportHeight: viewportHeight,
      startCharOffset: 0,
      endCharOffset: 0,
      isChapterStart: true,
      isChapterEnd: true,
      isLoading: error == null,
      errorMessage: error,
      lines: <ReaderV2RenderLine>[
        ReaderV2RenderLine(
          text: message,
          width: layoutSpec.contentWidth,
          height: lineHeight,
          isTitle: true,
          chapterPosition: 0,
          startCharOffset: 0,
          endCharOffset: 0,
          lineTop: top,
          lineBottom: top + lineHeight,
        ),
      ],
    );
  }

  ReaderV2PageAddress addressOf(ReaderV2RenderPage page) {
    return ReaderV2PageAddress(
      chapterIndex: page.chapterIndex,
      pageIndex: page.pageIndex,
    );
  }

  int _normalizeChapterIndex(int chapterIndex) {
    final count = repository.chapterCount;
    if (count <= 0) return chapterIndex < 0 ? 0 : chapterIndex;
    return chapterIndex.clamp(0, count - 1).toInt();
  }

  void _throwIfStale(ReaderV2LayoutSpec spec, int cacheGeneration, int taskId) {
    if (layoutSpec.layoutSignature != spec.layoutSignature ||
        cacheGeneration != _cacheGeneration ||
        _invalidatedInFlightTaskIds.contains(taskId)) {
      throw const _StaleLayoutGeneration();
    }
  }

  int? _chapterIndexFromTaskKey(String key) {
    final separator = key.indexOf('|');
    if (separator <= 0) return null;
    return int.tryParse(key.substring(0, separator));
  }
}
