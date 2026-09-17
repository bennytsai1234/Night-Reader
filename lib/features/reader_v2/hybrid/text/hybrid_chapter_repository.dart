import 'dart:async';
import 'dart:collection';

import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

typedef ReaderV2ContentLoader = Future<ReaderV2Content> Function(int index);

final class HybridChapterRepository implements HybridChapterTextRepository {
  HybridChapterRepository({
    ReaderV2ChapterRepository? repository,
    ReaderV2ContentLoader? loadContent,
    this.windowRadius = 2,
  }) : assert(repository != null || loadContent != null),
       _repository = repository,
       _loadContent = loadContent ?? repository!.loadContent;

  final ReaderV2ChapterRepository? _repository;
  final ReaderV2ContentLoader _loadContent;

  /// Minimum prefetch radius. The screen may widen the resident range from
  /// admitted viewport and lead geometry.
  final int windowRadius;
  final StreamController<ChapterEvent> _events =
      StreamController<ChapterEvent>.broadcast();
  final LinkedHashMap<int, ChapterText> _window =
      LinkedHashMap<int, ChapterText>();
  final Map<int, Future<ChapterText>> _inFlight = <int, Future<ChapterText>>{};
  int? _residentFirst;
  int? _residentLast;
  int _generation = 0;
  bool _disposed = false;

  @override
  Stream<ChapterEvent> get events => _events.stream;

  int? get residentFirst => _residentFirst;
  int? get residentLast => _residentLast;

  bool isResident(ChapterId id) {
    final first = _residentFirst;
    final last = _residentLast;
    return first != null && last != null && id >= first && id <= last;
  }

  @override
  Future<ChapterText> load(ChapterId id) {
    if (_disposed) {
      return Future<ChapterText>.error(
        StateError('HybridChapterRepository has been disposed.'),
      );
    }
    final cached = _window.remove(id);
    if (cached != null) {
      _window[id] = cached;
      return Future<ChapterText>.value(cached);
    }
    final inFlight = _inFlight[id];
    if (inFlight != null) return inFlight;
    final generation = _generation;
    late final Future<ChapterText> task;
    task = () async {
      final content = await _loadContent(id);
      final text = _adapt(content);
      if (_disposed || generation != _generation) return text;
      _window[id] = text;
      _events.add(
        ChapterEvent.loaded(chapterId: id, contentHash: text.contentHash),
      );
      // A semantic load is not a residency transfer. In particular a far jump
      // must be able to acquire its target while the old viewport still owns
      // the prefetch range. Eviction happens only in setResidentRange.
      return text;
    }();
    _inFlight[id] = task;
    void cleanUp() {
      if (identical(_inFlight[id], task)) _inFlight.remove(id);
    }

    unawaited(task.then<void>((_) => cleanUp(), onError: (_, _) => cleanUp()));
    return task;
  }

  /// Transfers raw-chapter residency ownership to an explicit contiguous
  /// range. The caller chooses the range from viewport/lead geometry; this
  /// repository only caches exactly that ownership set.
  @override
  void setResidentRange(int first, int last) {
    if (_disposed) return;
    var safeFirst = first < 0 ? 0 : first;
    var safeLast = last < safeFirst ? safeFirst : last;
    final count = _repository?.chapterCount;
    if (count != null && count > 0) {
      safeFirst = safeFirst.clamp(0, count - 1).toInt();
      safeLast = safeLast.clamp(safeFirst, count - 1).toInt();
    }
    _residentFirst = safeFirst;
    _residentLast = safeLast;
    _evictOutsideWindow();
    for (var index = safeFirst; index <= safeLast; index += 1) {
      unawaited(load(index).then<void>((_) {}, onError: (_, _) {}));
    }
  }

  void invalidateLoaded({bool emitEvents = true}) {
    _generation += 1;
    final ids = _window.keys.toList(growable: false);
    _window.clear();
    _inFlight.clear();
    if (!emitEvents || _disposed) return;
    for (final id in ids) {
      _events.add(ChapterEvent.invalidated(chapterId: id));
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    _window.clear();
    _inFlight.clear();
    await _events.close();
  }

  ChapterText _adapt(ReaderV2Content content) {
    return ChapterText(
      id: content.chapterIndex,
      title: content.title,
      paragraphs: content.paragraphs,
      displayText: content.displayText,
      contentHash: content.contentHash,
    );
  }

  void _evictOutsideWindow() {
    final first = _residentFirst;
    final last = _residentLast;
    if (first == null || last == null) return;
    final evicted = <int>[];
    _window.removeWhere((id, _) {
      final shouldEvict = id < first || id > last;
      if (shouldEvict) evicted.add(id);
      return shouldEvict;
    });
    for (final id in evicted) {
      _events.add(ChapterEvent.evicted(chapterId: id));
    }
  }
}
