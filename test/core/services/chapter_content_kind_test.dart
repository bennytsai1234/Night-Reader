import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/chapter_content_kind.dart';

String _prose(int runes) => '　　${'夜' * runes}';

void main() {
  test('a page of images with almost no words is a comic chapter', () {
    const content =
        '　　<img src="https://img.test/1.jpg">\n'
        '　　<img src="https://img.test/2.jpg">\n'
        '　　第一話';
    expect(ChapterContentKind.of(content), ChapterContentKind.images);
  });

  test('bare image links count as images', () {
    const content =
        'https://img.test/1.webp?x=1\n'
        'https://img.test/2.png\n'
        'https://img.test/3.jpg,{"headers":{"Referer":"https://a.test"}}';
    expect(ChapterContentKind.of(content), ChapterContentKind.images);
  });

  test('an illustrated novel chapter is still text', () {
    final content =
        '${_prose(150)}\n　　<img src="https://img.test/1.jpg">\n'
        '　　<img src="https://img.test/2.jpg">\n${_prose(100)}';
    expect(ChapterContentKind.of(content), ChapterContentKind.text);
  });

  test('a lone audio link is an audio chapter', () {
    expect(
      ChapterContentKind.of('https://cdn.test/ep1.m4a?token=abc'),
      ChapterContentKind.audio,
    );
  });

  test('short or mixed content is unclear', () {
    expect(ChapterContentKind.of(_prose(80)), ChapterContentKind.unclear);
    expect(
      ChapterContentKind.of('<img src="https://img.test/1.jpg">'),
      ChapterContentKind.unclear,
    );
    expect(
      ChapterContentKind.of('https://cdn.test/play?id=1'),
      ChapterContentKind.unclear,
    );
    expect(ChapterContentKind.of(''), ChapterContentKind.unclear);
    // 音訊和影片連結混在一起：不是只有音訊，不改成有聲。
    expect(
      ChapterContentKind.of(
        'https://cdn.test/one.mp3\nhttps://cdn.test/two.mp4',
      ),
      ChapterContentKind.unclear,
    );
  });
}
