import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/features/search/search_model.dart';

/// 繁簡字典在 App 啟動後背景載入；搜尋或打字建議可能比它早。字典還沒好
/// 時的比對結果不能記下來，好了之後要照字典重算。
void main() {
  test('text normalized before the dictionary loads is redone after', () {
    expect(ChineseUtils.isInitialized, isFalse);
    expect(normalizeSearchText('鬥羅大陸'), '鬥羅大陸');

    ChineseUtils.initializeFromDictionaryData([
      for (final path in ChineseUtils.dictionaryAssetPaths)
        File(path).readAsStringSync(),
    ]);

    expect(normalizeSearchText('鬥羅大陸'), '斗罗大陆');
  });
}
