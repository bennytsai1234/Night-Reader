import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader/chapter/content_re_segmenter.dart';

String reSegment(String content) =>
    ContentReSegmenter.reSegment(content, chapterTitle: '第一章');

void main() {
  group('重新分段', () {
    test('不以句末標點收尾的行接到下一行', () {
      expect(reSegment('他推開門走了\n進去，屋裡一片漆黑。'), '他推開門走了進去，屋裡一片漆黑。');
    });

    test('跨過空白行接', () {
      expect(reSegment('他推開門走了\n\n進去，屋裡一片漆黑。'), '他推開門走了進去，屋裡一片漆黑。');
    });

    test('句末標點收尾的行照樣分段', () {
      expect(reSegment('第一段。\n\n第二段。'), '第一段。\n第二段。');
    });

    test('只有插圖的行是邊界，圖不被併進字裡', () {
      expect(
        reSegment('他推開門走了\n\n進去。'),
        '他推開門走了\n\n進去。',
      );
    });

    test('段內的中文空白刪掉，英文單字之間留一個空格', () {
      expect(reSegment('他 說　好。'), '他說好。');
      expect(reSegment('He  said   hi.'), 'He said hi.');
    });

    test('接起來的兩行兩邊都是英文時補一個空格', () {
      expect(
        reSegment('He opened the door and\nwalked in.'),
        'He opened the door and walked in.',
      );
    });

    test('上一行以連字號結尾時，連字號留著直接接', () {
      expect(reSegment('a well-\nknown name.'), 'a well-known name.');
    });

    test('原文用「」時，重排完仍是「」', () {
      expect(reSegment('他說：\n「走吧。」'), '他說：「走吧。」');
    });

    test('行首落單的收引號接回上一句，不當成新的對白', () {
      expect(
        reSegment('　　「請進。\n　　」一個悅耳的女性聲音在門後傳來。'),
        '「請進。」一個悅耳的女性聲音在門後傳來。',
      );
    });

    test('繁體的說話字後面切段', () {
      expect(reSegment('他說道。她笑了。'), '他說道。\n她笑了。');
    });

    test('整章一行時切成好幾段，同一章每次切的都一樣', () {
      final chapter = '他走了很久，終於到了。' * 40;
      final first = reSegment(chapter);
      expect(first.split('\n').length, greaterThan(1));
      expect(first.replaceAll('\n', ''), chapter);
      expect(reSegment(chapter), first);
    });
  });
}
