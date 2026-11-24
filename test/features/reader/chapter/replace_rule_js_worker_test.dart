import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/features/reader/chapter/reader_content.dart';
import 'package:night_reader/features/reader/chapter/reader_content_transformer.dart';

import '../../../test_helper.dart';

/// 「替換為」寫 `@js:` 的規則在處理正文的背景 isolate 照 Legado 跑 JS，
/// 不把 JS 原文貼進正文（R3）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = quickJsUnavailableReason();

  test('正文裡對到的數字照 JS 算出的字替換', skip: skip, () async {
    final rule = ReplaceRule(
      id: 1,
      name: '數字加倍',
      pattern: r'\d+',
      replacement: '@js:String(Number(result) * 2)',
    );
    final result = await ReaderContentTransformWorker.instance.process({
      'chapterIndex': 0,
      'bookName': '書',
      'bookOrigin': 'https://a.example',
      'chapterTitle': '第一章',
      'rawContent': '　　他走了3步，又走了21步。',
      'rulesJson': [rule.toJson()],
      'useReplaceRules': true,
      'reSegmentEnabled': false,
      'chineseConvertType': 0,
    });
    expect((result['document']! as ReaderContent).paragraphs, [
      '他走了6步，又走了42步。',
    ]);
  });
}
