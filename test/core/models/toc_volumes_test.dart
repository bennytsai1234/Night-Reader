import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/toc_volumes.dart';

void main() {
  // 0 序章、1 第一卷（2–3）、4 第二卷（5–7）、8 第三卷（沒有章）
  final chapters = [
    BookChapter(url: '/0', title: '序章'),
    BookChapter(url: '/1', title: '第一卷', isVolume: true),
    BookChapter(url: '/2', title: '第1章'),
    BookChapter(url: '/3', title: '第2章'),
    BookChapter(url: '/4', title: '第二卷', isVolume: true),
    BookChapter(url: '/5', title: '第3章'),
    BookChapter(url: '/6', title: '第4章'),
    BookChapter(url: '/7', title: '第5章'),
    BookChapter(url: '/8', title: '第三卷', isVolume: true),
  ];

  test('chapters belong to the volume above them; chapters before the first '
      'volume belong to none, and volumes are not counted as chapters', () {
    final volumes = TocVolumes(chapters);
    expect(volumes.hasVolumes, isTrue);
    expect(volumes.chapterCount, 6);
    expect(
      [for (var i = 0; i < 9; i++) volumes.volumeOf(i)],
      [
        -1, -1, 1, 1, -1, 4, 4, 4, -1, //
      ],
    );
    expect(volumes.countOf(1), 2);
    expect(volumes.countOf(4), 3);
    expect(volumes.countOf(8), 0);
  });

  test('volumes before the current chapter start collapsed; the current one '
      'and later ones stay open', () {
    final volumes = TocVolumes(chapters);
    expect(volumes.initiallyCollapsed(6), {1});
    expect(volumes.initiallyCollapsed(4), {1});
    expect(volumes.initiallyCollapsed(2), isEmpty);
    expect(volumes.initiallyCollapsed(0), isEmpty);
    expect(volumes.initiallyCollapsed(-1), isEmpty);
  });

  test('a collapsed volume keeps its own row and hides its chapters', () {
    final volumes = TocVolumes(chapters);
    expect(volumes.rows({1}), [0, 1, 4, 5, 6, 7, 8]);
    expect(volumes.rows({1, 4}), [0, 1, 4, 8]);
    expect(volumes.rows({}), List.generate(9, (i) => i));
  });

  test(
    'a volume row is its own volume when revealing the current position',
    () {
      final volumes = TocVolumes(chapters);
      expect(volumes.volumeAt(4), 4);
      expect(volumes.volumeAt(6), 4);
      expect(volumes.volumeAt(0), -1);
      expect(volumes.volumeAt(99), -1);
      expect(volumes.initiallyCollapsed(8), {1, 4});
    },
  );

  test('a new table of contents keeps the collapsed volumes while the volumes '
      'stay put, even with new chapters at the end; moved volumes do not', () {
    final volumes = TocVolumes(chapters);
    expect(volumes.sameVolumes(TocVolumes(List.of(chapters))), isTrue);
    expect(
      volumes.sameVolumes(
        TocVolumes([...chapters, BookChapter(url: '/9', title: '第6章')]),
      ),
      isTrue,
    );
    expect(
      volumes.sameVolumes(
        TocVolumes([BookChapter(url: '/p', title: '楔子'), ...chapters]),
      ),
      isFalse,
    );
    expect(TocVolumes(const []).hasVolumes, isFalse);
  });
}
