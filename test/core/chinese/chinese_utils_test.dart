import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/chinese/chinese_utils.dart';

void main() {
  setUpAll(() {
    ChineseUtils.initializeFromDictionaryData([
      for (final path in ChineseUtils.dictionaryAssetPaths)
        File(path).readAsStringSync(),
    ]);
  });

  test('字典收的少見漢字（一個字佔兩個 UTF-16 單位）照字典轉', () {
    expect(ChineseUtils.s2t('𠮶'), '嗰');
    expect(ChineseUtils.t2s('𠁞'), '𠀾');
    expect(ChineseUtils.s2t('说𠮶话'), '說嗰話');
  });

  test('不在字典裡的 emoji 與一般字照舊，詞組仍優先', () {
    expect(ChineseUtils.s2t('头发😀'), '頭髮😀');
    expect(ChineseUtils.s2t('👩‍💻写代码'), '👩‍💻寫代碼');
  });
}
