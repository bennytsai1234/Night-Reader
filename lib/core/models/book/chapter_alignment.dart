import 'dart:math' as math;

import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/chinese/chinese_utils.dart';
import 'package:night_reader/core/utils/string_utils.dart';

/// 舊目錄第 [oldIndex] 章（章名 [oldTitle]）在 [newChapters] 裡是第幾章：
/// 先找同名的章（[sameChapterTitle]：繁簡、空白不同也算）；再照 Legado
/// `BookHelp.getDurChapter`，在估計位置前後 10 章裡比去掉章號的章名
/// （相似度超過 0.96），再找同一個章號（認中文數字與「100、」）；都沒有就
/// 照比例估。目錄裡有好幾章同名或同章號時（例如好幾個「番外」），取離估計
/// 位置最近的那一章，不是第一個。
int alignChapterIndex({
  required int oldIndex,
  required String? oldTitle,
  required int oldTotalCount,
  required List<BookChapter> newChapters,
}) => alignChapter(
  oldIndex: oldIndex,
  oldTitle: oldTitle,
  oldTotalCount: oldTotalCount,
  newChapters: newChapters,
).index;

/// 同 [alignChapterIndex]，另說這一章是不是真的找到（同名、去掉章號的章名
/// 或章號）；都不是、只照比例估時 `matched` 是 false。書籤與標註換目錄時
/// 拿它判斷「對不到舊目錄就跳過」。
({int index, bool matched}) alignChapter({
  required int oldIndex,
  required String? oldTitle,
  required int oldTotalCount,
  required List<BookChapter> newChapters,
}) {
  if (newChapters.isEmpty) return (index: oldIndex, matched: false);

  final newSize = newChapters.length;
  var estimatedIndex = oldIndex;
  if (oldTotalCount > 0) {
    estimatedIndex = (oldIndex * newSize / oldTotalCount).round();
  }

  int? nearest(bool Function(BookChapter chapter) matches) {
    int? best;
    for (var i = 0; i < newSize; i++) {
      if (!matches(newChapters[i])) continue;
      if (best == null ||
          (i - estimatedIndex).abs() < (best - estimatedIndex).abs()) {
        best = i;
      }
    }
    return best;
  }

  if (oldTitle != null && oldTitle.isNotEmpty) {
    final exact = nearest((chapter) => chapter.title == oldTitle);
    if (exact != null) return (index: exact, matched: true);
    final oldKey = _titleKey(oldTitle);
    final converted = nearest((chapter) => _titleKey(chapter.title) == oldKey);
    if (converted != null) return (index: converted, matched: true);
  }

  // 同 Legado：估計位置與原本的位置前後 10 章裡，比去掉章號與括號的章名。
  // 好幾章一樣像時（每章都叫「正文」、短的「上」「下」），章號相同的優先，
  // 再取離估計位置最近的（Legado 取第一個）。
  final oldChapterNumber = _extractChapterNumber(oldTitle);
  final windowStart = math.max(0, math.min(oldIndex, estimatedIndex) - 10);
  final windowEnd = math.min(
    newSize - 1,
    math.max(oldIndex, estimatedIndex) + 10,
  );
  final oldPure = _pureChapterName(oldTitle);
  if (oldPure.isNotEmpty) {
    int? best;
    var bestSimilarity = _similarEnough;
    var bestSameNumber = false;
    for (var i = windowStart; i <= windowEnd; i++) {
      final title = newChapters[i].title;
      final similarity = _jaccard(oldPure, _pureChapterName(title));
      if (similarity <= _similarEnough) continue;
      final sameNumber =
          oldChapterNumber != null &&
          _extractChapterNumber(title) == oldChapterNumber;
      final better =
          best == null ||
          similarity > bestSimilarity ||
          (similarity == bestSimilarity &&
              (sameNumber && !bestSameNumber ||
                  sameNumber == bestSameNumber &&
                      (i - estimatedIndex).abs() <
                          (best - estimatedIndex).abs()));
      if (better) {
        best = i;
        bestSimilarity = similarity;
        bestSameNumber = sameNumber;
      }
    }
    if (best != null) return (index: best, matched: true);
  }

  if (oldChapterNumber != null) {
    final numbered = nearest(
      (chapter) => _extractChapterNumber(chapter.title) == oldChapterNumber,
    );
    if (numbered != null) return (index: numbered, matched: true);
  }

  return (index: estimatedIndex.clamp(0, newSize - 1), matched: false);
}

/// 兩個章名算不算同一章：繁簡不同（繁體站換簡體站）、空白不同也算。
bool sameChapterTitle(String a, String b) => _titleKey(a) == _titleKey(b);

String _titleKey(String title) =>
    ChineseUtils.t2s(title.replaceAll(_whitespace, ''));

final RegExp _whitespace = RegExp(r'\s+');

/// 章名本身的相似度要超過這個才算同一章（Legado `getDurChapter` 的 0.96）。
const double _similarEnough = 0.96;

/// 兩個字串用到的字有多少重疊（Apache Commons Text `JaccardSimilarity`，
/// Legado 比章名用的）：共同的字數除以全部的字數。
double _jaccard(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1;
  final left = a.runes.toSet();
  final right = b.runes.toSet();
  final common = left.intersection(right).length;
  return common / (left.length + right.length - common);
}

final String _numberChars = '\\d${StringUtils.chineseNumberChars}';
const String _chapterUnits = '章节節篇回集话話';

/// 「第一百章」「第 100 節」（Legado `chapterNamePattern1`，多認繁體的節、話）。
final RegExp _numberedTitle = RegExp('^.*?第([$_numberChars]+)[$_chapterUnits]');

/// 「100、」「3.2.」這種開頭的序號（Legado `chapterNamePattern2`）。
final RegExp _leadingNumber = RegExp(
  '^(?:[$_numberChars]+[,:、])*([$_numberChars]+)(?:[,:、]|\\.[^\\d])',
);

/// 章名開頭的章號（不在結尾，免得整個章名被拿掉，Legado `regexB`）。
final RegExp _numberPrefix = RegExp(
  '^.*?第(?:[$_numberChars]+)[$_chapterUnits](?!\$)|'
  '^(?:[$_numberChars]+[,:、])*(?:[$_numberChars]+)(?:[,:、](?!\$)|\\.(?=[^\\d]))',
);

/// 章名前後括號裡附加的字（「（求月票）」）；整個章名都在括號裡時只拿掉
/// 頭尾的括號（Legado `regexC`）。
final RegExp _bracketed = RegExp(
  r'(?!^)(?:[〖【《〔\[{(][^〖【《〔\[{()〕》】〗\]}]+)?[)〕》】〗\]}]$|'
  r'^[〖【《〔\[{(](?:[^〖【《〔\[{()〕》】〗\]}]+[〕》】〗\]})])?(?!$)',
);

/// 字母、數字與漢字以外的字（Legado `regexOther`）。
final RegExp _notWordOrHan = RegExp(
  r'[^\w一-鿯〇㐀-䶿\u{20000}-\u{2A6DF}\u{2A700}-\u{2EBEF}]',
  unicode: true,
);

/// 比對用的章名本身：去掉空白、章號、前後括號與標點，繁體轉簡體（Legado
/// `getPureChapterName`；夜讀多轉繁簡，繁體站換簡體站也比得上）。
String _pureChapterName(String? title) {
  if (title == null || title.isEmpty) return '';
  return ChineseUtils.t2s(StringUtils.fullToHalf(title))
      .replaceAll(_whitespace, '')
      .replaceAll(_numberPrefix, '')
      .replaceAll(_bracketed, '')
      .replaceAll(_notWordOrHan, '');
}

/// 章名裡的章號（Legado `getChapterNum`）：「第一百章」「第100章」「100、」
/// 都是 100；讀不出來是 null。
int? _extractChapterNumber(String? title) {
  if (title == null) return null;
  final compact = StringUtils.fullToHalf(title).replaceAll(_whitespace, '');
  final match =
      _numberedTitle.firstMatch(compact) ?? _leadingNumber.firstMatch(compact);
  if (match == null) return null;
  final number = StringUtils.stringToInt(match.group(1));
  return number > 0 ? number : null;
}
