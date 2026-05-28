import 'package:reader/features/reader_v2/render/reader_v2_render_page.dart';
import 'package:reader/features/reader_v2/content/reader_v2_chapter_repository.dart';
import 'package:reader/features/reader_v2/layout/reader_v2_layout_engine.dart';
import 'package:reader/features/reader_v2/layout/reader_v2_layout_spec.dart';

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
  final Future<ReaderV2ChapterView> future;
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

  final Map<int, ReaderV2ChapterView> _layouts = <int, ReaderV2ChapterView>{};
  final Map<String, _InFlightLayout> _inFlight = <String, _InFlightLayout>{};
  final Set<int> _invalidatedInFlightTaskIds = <int>{};
  final Map<int, String> _layoutErrors = <int, String>{};
  int _cacheGeneration = 0;
  int _nextInFlightTaskId = 0;

  int get chapterCount => repository.chapterCount;

  void updateLayoutSpec(ReaderV2LayoutSpec spec) {
    if (layoutSpec.layoutSignature == spec.layoutSignature) return;
    layoutSpec = spec;
    _cacheGeneration += 1;
    _layouts.clear();
  }

  ReaderV2ChapterView? cachedLayout(int chapterIndex) => _layouts[chapterIndex];

  void clearCachedLayouts() {
    _cacheGeneration += 1;
    _layouts.clear();
    _inFlight.clear();
    _layoutErrors.clear();
  }

  Future<ReaderV2ChapterView> ensureLayout(
    int chapterIndex, {
    bool retryOnStale = true,
  }) async {
    while (true) {
      try {
        return await _ensureLayoutForCurrentGeneration(chapterIndex);
      } on _StaleLayoutGeneration {
        if (!retryOnStale) rethrow;
      }
    }
  }

  Future<ReaderV2ChapterView> _ensureLayoutForCurrentGeneration(
    int chapterIndex,
  ) async {
    await repository.ensureChapters();
    final safeIndex = _normalizeChapterIndex(chapterIndex);
    final cached = _layouts[safeIndex];
    if (cached != null &&
        cached.layoutSignature == layoutSpec.layoutSignature) {
      return cached;
    }
    final spec = layoutSpec;
    final cacheGeneration = _cacheGeneration;
    final taskKey = '$safeIndex|${spec.layoutSignature}|$cacheGeneration';
    final inFlight = _inFlight[taskKey];
    if (inFlight != null) return inFlight.future;
    final taskId = _nextInFlightTaskId++;
    late final Future<ReaderV2ChapterView> task;
    task = () async {
      try {
        final content = await repository.loadContent(safeIndex);
        _throwIfStale(spec, cacheGeneration, taskId);
        final layout = layoutEngine.layout(content, spec);
        _throwIfStale(spec, cacheGeneration, taskId);
        final view = ReaderV2ChapterView(
          layout,
          chapterSize: repository.chapterCount,
          title: repository.titleFor(safeIndex),
        );
        _layouts[safeIndex] = view;
        _layoutErrors.remove(safeIndex);
        return view;
      } catch (e) {
        if (e is! _StaleLayoutGeneration &&
            cacheGeneration == _cacheGeneration &&
            !_invalidatedInFlightTaskIds.contains(taskId)) {
          _layoutErrors[safeIndex] = e.toString();
        }
        rethrow;
      }
    }();
    _inFlight[taskKey] = _InFlightLayout(id: taskId, future: task);
    try {
      return await task;
    } finally {
      final current = _inFlight[taskKey];
      if (current != null && identical(current.future, task)) {
        _inFlight.remove(taskKey);
      }
      _invalidatedInFlightTaskIds.remove(taskId);
    }
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
    return prevLayout.pages.last;
  }

  ReaderV2RenderPage? nextPageSync(ReaderV2RenderPage page) {
    if (page.isPlaceholder) return null;
    final layout = cachedLayout(page.chapterIndex);
    final pages = layout?.pages ?? const <ReaderV2RenderPage>[];
    if (page.pageIndex + 1 < pages.length) {
      return pages[page.pageIndex + 1];
    }
    final nextLayout = cachedLayout(page.chapterIndex + 1);
    if (nextLayout == null || nextLayout.pages.isEmpty) return null;
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
