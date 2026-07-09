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
  final int windowRadius;
  final StreamController<ChapterEvent> _events =
      StreamController<ChapterEvent>.broadcast();
  final LinkedHashMap<int, ChapterText> _window =
      LinkedHashMap<int, ChapterText>();
  final Map<int, Future<ChapterText>> _inFlight = <int, Future<ChapterText>>{};
  int? _prefetchCenter;

  @override
  Stream<ChapterEvent> get events => _events.stream;

  @override
  Future<ChapterText> load(ChapterId id) {
    final cached = _window.remove(id);
    if (cached != null) {
      _window[id] = cached;
      return Future<ChapterText>.value(cached);
    }
    final inFlight = _inFlight[id];
    if (inFlight != null) return inFlight;
    late final Future<ChapterText> task;
    task = () async {
      final content = await _loadContent(id);
      final text = _adapt(content);
      _window[id] = text;
      _events.add(
        ChapterEvent.loaded(chapterId: id, contentHash: text.contentHash),
      );
      _evictOutsideWindow();
      return text;
    }();
    _inFlight[id] = task;
    task.whenComplete(() {
      if (identical(_inFlight[id], task)) _inFlight.remove(id);
    });
    return task;
  }

  @override
  void setPrefetchCenter(ChapterId id) {
    _prefetchCenter = id;
    _evictOutsideWindow();
    for (
      var index = id - windowRadius;
      index <= id + windowRadius;
      index += 1
    ) {
      if (index < 0) continue;
      if (_repository != null && index >= _repository.chapterCount) continue;
      unawaited(load(index));
    }
  }

  void invalidateLoaded() {
    final ids = _window.keys.toList(growable: false);
    _window.clear();
    for (final id in ids) {
      _events.add(ChapterEvent.invalidated(chapterId: id));
    }
  }

  Future<void> dispose() async {
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
    final center = _prefetchCenter;
    if (center == null) return;
    final min = center - windowRadius;
    final max = center + windowRadius;
    final evicted = <int>[];
    _window.removeWhere((id, _) {
      final shouldEvict = id < min || id > max;
      if (shouldEvict) evicted.add(id);
      return shouldEvict;
    });
    for (final id in evicted) {
      _events.add(ChapterEvent.evicted(chapterId: id));
    }
  }
}
