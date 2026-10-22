import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/reader/chinese_text_converter.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content_transformer.dart';
import 'package:night_reader/features/reader_v2/features/replace_rule/selection_source_text.dart';

/// 選字「隱藏」要用原文建規則：畫面上的字是原文經過排版整理（與繁簡轉換）
/// 的結果，這裡用真的整理程式產生畫面上的字，再確認找回來的原文當成規則
/// 能把原文那一段刪掉。
void main() {
  setUpAll(() {
    ChineseUtils.initializeFromDictionaryData([
      for (final path in ChineseUtils.dictionaryAssetPaths)
        File(path).readAsStringSync(),
    ]);
  });

  String hide(String raw, String shown) {
    final pattern = findSourceText(
      source: raw,
      shown: shown,
      toSimplified: ChineseUtils.t2s,
    );
    expect(pattern, isNotNull, reason: '找不到「$shown」的原文');
    return ReplaceRule(
      pattern: pattern!,
      replacement: '',
      isRegex: false,
    ).apply(raw);
  }

  test('半形標點與中文之間的空白排版後不同，仍找得到原文', () {
    const raw = '他走了。請記住本站網址: www.Example.com ,最快更新!下一句';
    final display = normalizeTypography(raw);
    expect(display, isNot(contains(': www')));
    final start = display.indexOf('請記住');
    final end = display.indexOf('下一句');
    expect(hide(raw, display.substring(start, end)), '他走了。下一句');
  });

  test('刪節號與破折號排版後長度不同，仍找得到原文', () {
    const raw = '她說...本章未完--請翻頁。';
    final display = normalizeTypography(raw);
    expect(display, contains('……'));
    expect(display, contains('——'));
    expect(hide(raw, display.substring(2)), '她說');
  });

  test('開了簡轉繁時，畫面上的繁體字找得到簡體原文', () {
    const raw = '正文。本章未完，请点击下一页继续阅读。正文';
    final display = const ChineseTextConverter().convert(
      normalizeTypography(raw),
      convertType: 1,
    );
    expect(display, contains('請點擊下一頁'));
    final start = display.indexOf('本章');
    final end = display.lastIndexOf('正文');
    expect(hide(raw, display.substring(start, end)), '正文。正文');
  });

  test('只選括號裡外的字，不多吃前面的句號', () {
    const raw = '正文。【广告】正文';
    final display = normalizeTypography(raw);
    final start = display.indexOf('广告') - 1;
    expect(hide(raw, display.substring(start, start + 4)), '正文。正文');
  });

  test('原文裡沒有、或只選到空白時找不到', () {
    expect(findSourceText(source: '甲乙丙', shown: '丁'), isNull);
    expect(findSourceText(source: '甲乙丙', shown: '　 '), isNull);
  });
}
