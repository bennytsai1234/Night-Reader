import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/reader/chinese_text_converter.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content_transformer.dart';
import 'package:night_reader/features/reader_v2/features/replace_rule/selection_source_text.dart';

/// 選字「隱藏」的契約：用真的內容轉換流程排出畫面上的段落，選其中一段的
/// 字，找回原文建成規則接在既有規則之後，再排一次，那一段只少了選到的字，
/// 其他段落不受影響。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    ChineseUtils.initializeFromDictionaryData([
      for (final path in ChineseUtils.dictionaryAssetPaths)
        File(path).readAsStringSync(),
    ]);
  });

  final book = Book(
    bookUrl: 'http://hide.test',
    name: '隱藏測試書',
    origin: 'http://source.test',
  )..readConfig = ReadConfig(useReplaceRule: true);

  Future<List<String>> shown(
    String raw, {
    required String title,
    List<ReplaceRule> rules = const <ReplaceRule>[],
    int convert = 0,
  }) async {
    final result = await ReaderV2ContentTransformWorker.instance.process({
      'chapterIndex': 0,
      'bookName': book.name,
      'bookOrigin': book.origin,
      'chapterTitle': title,
      'rawContent': raw,
      'rulesJson': rules.map((rule) => rule.toJson()).toList(),
      'useReplaceRules': true,
      'reSegmentEnabled': false,
      'chineseConvertType': 0,
    });
    // worker 拿不到 rootBundle 的字典，轉換照它的做法在這裡做。
    final content = const ChineseTextConverter().convert(
      result['content']! as String,
      convertType: convert,
    );
    return ReaderV2Content.fromRaw(
      chapterIndex: 0,
      title: '',
      rawText: content,
    ).paragraphs;
  }

  /// 選第 [paragraph] 段裡的 [text]（段內第 [occurrence] 個），隱藏後重排。
  Future<List<String>> hide(
    String raw, {
    required int paragraph,
    required String text,
    int occurrence = 0,
    String title = '第一章',
    List<ReplaceRule> rules = const <ReplaceRule>[],
    int convert = 0,
  }) async {
    final before = await shown(
      raw,
      title: title,
      rules: rules,
      convert: convert,
    );
    final line = before[paragraph];
    var start = -1;
    for (var i = 0; i <= occurrence; i += 1) {
      start = line.indexOf(text, start + 1);
    }
    expect(start, isNonNegative, reason: '第 $paragraph 段沒有「$text」');
    final sources = await ReaderV2ContentTransformer.ruleStageParagraphs(
      book: book,
      chapter: BookChapter(url: 'c', title: title),
      rawContent: raw,
      enabledRules: rules,
    );
    expect(sources, hasLength(before.length));
    final source = sources[paragraph];
    final range = sourceRangeOf(
      source: source,
      shown: line,
      start: start,
      end: start + text.length,
    );
    expect(range, isNotNull, reason: '「$text」對不回原文「$source」');
    final rule = ReplaceRule(
      pattern: source.substring(range!.start, range.end),
      replacement: '',
      isRegex: false,
      order: 99,
    );
    return shown(raw, title: title, rules: [...rules, rule], convert: convert);
  }

  test('半形標點與中文之間的空白排版後不同，仍刪得掉', () async {
    expect(
      await hide(
        '他走了。請記住本站網址: www.Example.com ,最快更新!下一句',
        paragraph: 0,
        text: '請記住本站網址：www.Example.com，最快更新！',
      ),
      ['他走了。下一句'],
    );
  });

  test('刪節號與破折號排版後長度不同，仍刪得掉', () async {
    expect(await hide('她說...本章未完--請翻頁。', paragraph: 0, text: '……本章未完——請翻頁。'), [
      '她說',
    ]);
  });

  test('開了簡轉繁，詞組轉換過的字也對得回簡體原文', () async {
    expect(await hide('一目了然。广告词。', paragraph: 0, text: '一目瞭然。', convert: 1), [
      '廣告詞。',
    ]);
  });

  test('只刪選到的那一段，大小寫不同的字不受影響', () async {
    expect(await hide('正文ad仍有用。\n正文AD應隱藏。', paragraph: 1, text: 'AD'), [
      '正文ad仍有用。',
      '正文應隱藏。',
    ]);
  });

  test('不同的符號不會被當成同一個', () async {
    expect(await hide('正文😀仍有用。\n正文🚫應隱藏。', paragraph: 1, text: '🚫'), [
      '正文😀仍有用。',
      '正文應隱藏。',
    ]);
  });

  test('排版成一樣的括號，刪的是選到那段的原文', () async {
    expect(await hide('正文「廣告」仍有用。\n正文【廣告】應隱藏。', paragraph: 1, text: '「廣告」'), [
      '正文「廣告」仍有用。',
      '正文應隱藏。',
    ]);
  });

  test('只選連續標點的一部分，不多刪沒選到的', () async {
    expect(await hide('甲——乙', paragraph: 0, text: '—乙'), ['甲—']);
    // 刪完剩下的「甲…」排版時又補成「……」，所以直接看規則取到的範圍。
    expect(sourceRangeOf(source: '甲……乙', shown: '甲……乙', start: 2, end: 4), (
      start: 2,
      end: 4,
    ));
  });

  test('排版刪掉標點之間的空白，仍刪得掉', () async {
    expect(await hide('甲。 。乙丙', paragraph: 0, text: '。。乙'), ['甲丙']);
  });

  test('既有規則改過的字，用改過之後的樣子建規則', () async {
    final colon = ReplaceRule(
      pattern: ':',
      replacement: '：',
      isRegex: false,
      order: 1,
    );
    expect(
      await hide('正文。廣告:內容。正文', paragraph: 0, text: '廣告：內容。', rules: [colon]),
      ['正文。正文'],
    );
  });

  test('開頭重複的章名不算，選到正文裡同樣的字照樣刪', () async {
    expect(
      await hide(
        '第一章  廣告\n正文\n第一章廣告',
        paragraph: 1,
        text: '第一章廣告',
        title: '第一章 廣告',
      ),
      ['正文'],
    );
  });

  test('原文行首的空白不影響對到哪一段', () async {
    expect(await hide('正文廣\n  告。\n正文廣告。', paragraph: 2, text: '廣告'), [
      '正文廣',
      '告。',
      '正文。',
    ]);
  });

  test('只選到空白，或排版改了字數對不齊時回傳 null', () {
    expect(
      sourceRangeOf(source: '甲 乙', shown: '甲　乙', start: 1, end: 2),
      isNull,
    );
    expect(sourceRangeOf(source: '甲乙', shown: '甲乙丙', start: 0, end: 1), isNull);
  });
}
