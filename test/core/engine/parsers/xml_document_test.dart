import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/parsers/analyze_by_css.dart';
import 'package:night_reader/core/engine/parsers/analyze_by_xpath.dart';

/// 網站回 XML 時，CSS 規則也照 Legado（Jsoup 的 XML 解析器）讀；轻文库小说
/// 的目錄是 `<volume>` 裡放 `<chapter>`，規則是 `volume,chapter`。
void main() {
  const toc = '''<?xml version="1.0" encoding="utf-8"?>
<package>
<volume vid="10">第一卷<chapter cid="11">第一章</chapter><chapter cid="12">第二章</chapter></volume>
<volume vid="20">第二卷<chapter cid="21"/></volume>
</package>''';

  test('CSS 規則照 XML 的結構找，自己結束的標籤不包住後面的', () {
    final css = AnalyzeByCss(toc);
    final nodes = css.getElements('volume,chapter');
    expect(nodes.map((e) => e.localName), [
      'volume',
      'chapter',
      'chapter',
      'volume',
      'chapter',
    ]);
    expect(css.getStringList('chapter@cid'), ['11', '12', '21']);
  });

  test('CSS 找到的節點交給 XPath 時照 XML 讀，不再轉成網頁', () {
    final chapter = AnalyzeByCss(toc).getElements('chapter').first;
    expect(AnalyzeByXPath(chapter).getStringList('/text()'), ['第一章']);
    final volume = AnalyzeByCss(toc).getElements('volume').first;
    expect(AnalyzeByXPath(volume).getString('/text()[1]'), '第一卷');
  });
}
