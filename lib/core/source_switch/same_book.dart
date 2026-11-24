import 'package:night_reader/core/chinese/chinese_utils.dart';
import 'package:night_reader/core/utils/string_utils.dart';

/// 比對用的書名、作者與關鍵字：全形轉半形、去空白、轉小寫，繁體轉成簡體，
/// 繁體站與簡體站回傳的同一本書才會併成一張、照同樣的相關度排。
String normalizeSearchText(String? value) {
  if (value == null || value.isEmpty) return '';
  String normalize() => ChineseUtils.t2s(
    StringUtils.fullToHalf(value).replaceAll(_whitespace, '').toLowerCase(),
  );
  // 繁簡字典還沒載入時 t2s 原樣返回，這時的結果不記下來，載入後重算。
  if (!ChineseUtils.isInitialized) return normalize();
  return _normalizedText.putIfAbsent(value, normalize);
}

final RegExp _whitespace = RegExp(r'\s+');

/// 繁簡轉換一個書名要十幾微秒，合併每次重算都會對整份結果再做一次，所以把
/// 結果記下來。搜尋頁每次新搜尋開始時清空（[clearNormalizedSearchText]），
/// 大小不超過一次搜尋碰到的文字數。
final Map<String, String> _normalizedText = {};

/// 清掉 [normalizeSearchText] 記下的結果。
void clearNormalizedSearchText() => _normalizedText.clear();

/// 書源多半是簡體站，也有繁體站：關鍵字照原文搜，轉成另一種寫法後不同時
/// 也一起搜，輸入哪一種都找得到兩邊的書。
List<String> searchKeyVariants(String key) =>
    {key, ChineseUtils.t2s(key), ChineseUtils.s2t(key)}.toList();

/// 書名 [name]、作者 [author] 的結果是不是《[bookName]》這本書：書名正規化後
/// 相同；[checkAuthor] 時作者正規化後也要相同。正規化和搜尋合併卡同一套；
/// 自動換源（同 Legado 的精準搜尋，ADR 0069）與換封面照這一條認同一本書，
/// 手動換源與單章借源照 [isChangeSourceMatch]。
bool isSameBook(
  String name,
  String? author,
  String bookName,
  String? bookAuthor, {
  required bool checkAuthor,
}) {
  if (normalizeSearchText(name) != normalizeSearchText(bookName)) {
    return false;
  }
  return !checkAuthor ||
      normalizeSearchText(author) == normalizeSearchText(bookAuthor);
}

/// 換源搜尋的過濾條件（[isSameBook]），跟著搜尋送進書源 isolate，所以在只
/// 捕捉書名與作者的頂層函式裡建立。
bool Function(String name, String author) sameBookFilter(
  String bookName,
  String bookAuthor, {
  required bool checkAuthor,
}) =>
    (name, author) => isSameBook(
      name,
      author,
      bookName,
      bookAuthor,
      checkAuthor: checkAuthor,
    );

/// 手動換源與單章借源的清單列不列 [name]、[author] 這個結果（同 Legado
/// `ChangeBookSourceViewModel`）：書名正規化後相同；[checkAuthor] 時搜到的
/// 作者「含」這本書的作者 [bookAuthor]（「張三（著）」「張三／李四」也算）。
bool isChangeSourceMatch(
  String name,
  String? author,
  String bookName,
  String? bookAuthor, {
  required bool checkAuthor,
}) {
  if (normalizeSearchText(name) != normalizeSearchText(bookName)) {
    return false;
  }
  return !checkAuthor ||
      normalizeSearchText(author).contains(normalizeSearchText(bookAuthor));
}

/// 手動換源搜尋的過濾條件（[isChangeSourceMatch]），跟著搜尋送進書源
/// isolate。
bool Function(String name, String author) changeSourceFilter(
  String bookName,
  String bookAuthor, {
  required bool checkAuthor,
}) =>
    (name, author) => isChangeSourceMatch(
      name,
      author,
      bookName,
      bookAuthor,
      checkAuthor: checkAuthor,
    );
