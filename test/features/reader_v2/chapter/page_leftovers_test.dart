import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content_transformer.dart';

/// 網站把別處分頁的章節整章轉貼過來，頁碼與換頁提示留在正文裡（ADR 0071）：
/// 讀的時候拿掉，替換規則與「本書套用替換規則」都不用管。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<String>> shown(
    String raw, {
    required String title,
    bool useReplaceRules = true,
  }) async {
    final result = await ReaderV2ContentTransformWorker.instance.process({
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
    return ReaderV2Content.fromRaw(
      chapterIndex: 0,
      title: '',
      rawText: result['content']! as String,
    ).paragraphs;
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

  test('the leftovers go even when the book skips replace rules', () async {
    expect(await shown('(第1/2页)\n正文。', title: '第一章', useReplaceRules: false), [
      '正文。',
    ]);
  });
}
