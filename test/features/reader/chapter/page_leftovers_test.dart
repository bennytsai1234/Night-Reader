import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/features/reader/chapter/reader_content.dart';
import 'package:night_reader/features/reader/chapter/reader_content_transformer.dart';

/// 網站把別處分頁的章節整章轉貼過來，頁碼與換頁提示留在正文裡（ADR 0071）：
/// 讀的時候拿掉，替換規則與「本書套用替換規則」都不用管。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<String>> shown(
    String raw, {
    required String title,
    bool useReplaceRules = true,
  }) async {
    final result = await ReaderContentTransformWorker.instance.process({
      'chapterIndex': 0,
      'bookName': '咒回：特级的我去死灭打宿傩了！',
      'bookOrigin': 'https://www.biquge345.com',
      'chapterTitle': title,
      'rawContent': raw,
      'rulesJson': const <Map<String, dynamic>>[],
      'useReplaceRules': useReplaceRules,
      'reSegmentEnabled': false,
      'chineseConvertType': 0,
    });
    return (result['document']! as ReaderContent).paragraphs;
  }

  // 2026-11-18 笔趣阁 biquge345《咒回》第 7 章：網站一頁就給整章，原本兩頁的
  // 頁碼與「本章未完」那行照樣夾在正文裡（書源的正文規則 `#txt@html`）。
  const chapter7 =
      '　　第7章添加规则(第1/2页)\n'
      '　　听着芥剑的解释，鹿紫云一的脸色并没有过多的缓和。\n'
      '　　整个死灭回游存在四个结界，而鹿紫云一所在的「东京第二结界」似乎没有什么特别出名的选手？\n'
      '　　（本章未完，请点击下一页继续阅读）第7章添加规则(第2/2页)\n'
      '　　这里剧情中有名字的咒术师好像只有两个？';

  test(
    'page numbers and the page-turn line of a merged chapter are gone',
    () async {
      expect(await shown(chapter7, title: '第7章 添加规则'), [
        '听着芥剑的解释，鹿紫云一的脸色并没有过多的缓和。',
        '整个死灭回游存在四个结界，而鹿紫云一所在的「东京第二结界」似乎没有什么特别出名的选手？',
        '这里剧情中有名字的咒术师好像只有两个？',
      ]);
    },
  );

  // 換頁提示接在一段正文後面、沒有括號、頁碼寫成「第(1/3)页」的網站。
  test('a page-turn note after a story line leaves the story', () async {
    expect(
      await shown(
        '他推开门走了进去。本章未完，点击下一页继续阅读。\n'
        '第十二章 夜雨 第(2/3)页\n'
        '屋里一片漆黑。',
        title: '第十二章 夜雨',
      ),
      ['他推开门走了进去。', '屋里一片漆黑。'],
    );
  });

  test('page counts the story talks about stay', () async {
    const story = '地图在第3/5页的角落，他翻了好几页才找到。\n这一页没有记下本章的内容。';

    expect(await shown(story, title: '第一章'), [
      '地图在第3/5页的角落，他翻了好几页才找到。',
      '这一页没有记下本章的内容。',
    ]);
  });

  // Codex 審查找到的：「本章未完」後面沒接翻頁的字，是正文。
  test('story text that says the chapter is unfinished stays', () async {
    const story =
        '她說：「本章未完待續!」說完就關燈。\n'
        '（本章未完稿，作者已手寫保留這段後記）';

    expect(await shown(story, title: '第一章'), [
      '她說：「本章未完待續！」說完就關燈。',
      '（本章未完稿，作者已手寫保留這段後記）',
    ]);
  });

  // 換頁那行同時有插圖：插圖留著，「隱藏」找原文的段落和畫面上的一樣多。
  test(
    'an illustration on the page-turn line stays and hiding still lines up',
    () async {
      const raw =
          '前文。\n'
          '第一章夜雨(第2/2页)<img src="image.png">\n'
          '想隱藏的廣告。';
      final book = Book(
        bookUrl: 'https://www.biquge345.com/book/1/',
        origin: 'https://www.biquge345.com',
        name: '書',
      );

      expect(await shown(raw, title: '第一章 夜雨'), ['前文。', '想隱藏的廣告。']);
      expect(
        (await ReaderContentTransformer.ruleStageParagraphs(
          book: book,
          chapter: BookChapter(
            url: 'u',
            title: '第一章 夜雨',
            bookUrl: book.bookUrl,
          ),
          rawContent: raw,
          enabledRules: const [],
        )).paragraphs,
        ['前文。', '想隱藏的廣告。'],
      );
    },
  );

  test('a long line of unclosed notes is cleaned quickly', () async {
    final line = '（本章未完。' * 4000;
    final watch = Stopwatch()..start();
    await shown(line, title: '第一章');
    expect(watch.elapsedMilliseconds, lessThan(500));
  });

  test('the leftovers go even when the book skips replace rules', () async {
    expect(await shown('(第1/2页)\n正文。', title: '第一章', useReplaceRules: false), [
      '正文。',
    ]);
  });
}
