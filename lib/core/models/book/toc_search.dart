import 'package:night_reader/core/chinese/chinese_display.dart';

/// 目錄搜尋（書籍詳情與閱讀器的目錄共用）：章名含 [query] 就算，不分大小
/// 寫；照原文的章名與畫面上轉過繁簡的章名都比，讀者照畫面打字也找得到。
bool tocTitleMatches(String title, String query) {
  final wanted = query.toLowerCase();
  if (wanted.isEmpty) return true;
  return title.toLowerCase().contains(wanted) ||
      ChineseDisplay.convert(title).toLowerCase().contains(wanted);
}
