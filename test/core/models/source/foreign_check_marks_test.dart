import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/source/book_source.dart';

/// 別的 App（Legado）校驗留下的分組與錯誤註解：書源進來時拿掉，當成夜讀
/// 還沒校驗過；夜讀的校驗與清除校驗標記也一起清。
void main() {
  final checkedAt = DateTime(2026, 11, 1).millisecondsSinceEpoch;

  BookSource legadoChecked({String? group, String? comment}) => BookSource(
    bookSourceUrl: 'https://legado.example',
    bookSourceName: 'Legado 校驗過',
    bookSourceGroup: group ?? '精品,搜索失效,正文失效',
    bookSourceComment: comment ?? '// Error: 未获取到正文\n\n作者说明',
    lastCheckTime: checkedAt,
  );

  test('an incoming source Legado marked broken comes in as unchecked', () {
    final source = legadoChecked()..prepareIncoming();

    expect(source.groupTags, {'精品'});
    expect(source.bookSourceComment, '作者说明');
    expect(source.lastCheckTime, 0);
    // 舊版 Legado 的「正文失效」和夜讀的同字：拿掉後才參加搜尋、打得開。
    expect(source.runtimeHealth.category, SourceHealthCategory.healthy);
  });

  test('every Legado check group goes, user groups stay', () {
    final source = legadoChecked(
      group:
          '精品,搜索失效,搜索正文失效,搜索目录失效,发现失效,网站失效,js失效,'
          '校验超时,網站失效,校驗超時,🔥 推薦',
      comment: '',
    )..prepareIncoming();

    expect(source.groupTags, {'精品', '🔥 推薦'});
  });

  test('a source Night Reader checked keeps its marks and drops only the '
      'groups Night Reader does not write', () {
    final source = legadoChecked(
      group: '精品,$abnormalSourceGroupTag,$contentBrokenSourceGroupTag,搜索失效',
      comment: '// Error: 正文為空',
    )..prepareIncoming();

    expect(source.groupTags, {
      '精品',
      abnormalSourceGroupTag,
      contentBrokenSourceGroupTag,
    });
    expect(source.bookSourceComment, '// Error: 正文為空');
    expect(source.lastCheckTime, checkedAt);
  });

  test('a source without check marks is left exactly as it was', () {
    final source = legadoChecked(group: '精品;男頻', comment: '作者说明');

    expect(source.dropForeignCheckMarks(), isFalse);
    expect(source.bookSourceGroup, '精品;男頻');
    expect(source.lastCheckTime, checkedAt);
  });

  test('the non-novel mark added on import stays', () {
    final source = legadoChecked(group: nonNovelSourceGroupTag, comment: '');

    expect(source.dropForeignCheckMarks(), isFalse);
    expect(source.groupTags, {nonNovelSourceGroupTag});
  });

  test('clearing check marks also clears the ones Legado left', () {
    final source = legadoChecked(
      group: '精品,$abnormalSourceGroupTag,$searchBrokenSourceGroupTag,搜索失效',
    )..removeInvalidGroups();

    expect(source.groupTags, {'精品'});
  });
}
