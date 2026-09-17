import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/text/hybrid_chapter_repository.dart';

void main() {
  test('semantic load does not transfer or evict viewport residency', () async {
    Future<ReaderV2Content> load(int index) async {
      return ReaderV2Content.fromRaw(
        chapterIndex: index,
        title: '第 $index 章',
        rawText: 'chapter-$index',
      );
    }

    final repository = HybridChapterRepository(loadContent: load);
    final events = <ChapterEvent>[];
    final subscription = repository.events.listen(events.add);

    repository.setResidentRange(0, 2);
    await Future.wait([repository.load(0), repository.load(1), repository.load(2)]);
    await Future<void>.delayed(Duration.zero);
    events.clear();

    final farTarget = await repository.load(10);
    await Future<void>.delayed(Duration.zero);
    expect(farTarget.id, 10);
    expect(repository.residentFirst, 0);
    expect(repository.residentLast, 2);
    expect(
      events.where(
        (event) =>
            event.chapterId == 10 && event.kind == ChapterEventKind.evicted,
      ),
      isEmpty,
    );

    repository.setResidentRange(10, 12);
    await Future<void>.delayed(Duration.zero);
    expect(repository.residentFirst, 10);
    expect(repository.residentLast, 12);
    expect(
      events.where(
        (event) =>
            event.chapterId == 0 && event.kind == ChapterEventKind.evicted,
      ),
      isNotEmpty,
    );

    await subscription.cancel();
    await repository.dispose();
  });
}
