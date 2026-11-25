import 'dart:math' as math;

import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/chinese/chinese_utils.dart';
import 'package:night_reader/core/utils/string_utils.dart';

/// 舊目錄第 [oldIndex] 章（章名 [oldTitle]）在 [newChapters] 裡是第幾章：
/// 照 [ChapterMatcher.sameChapter] 找同一章，都沒有就照比例估。
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

/// 記下的章（章名與序號）在 [chapters] 裡是第幾章：先找同名的章（繁簡
/// 不同也算，好幾章同名時取離序號最近的），再照章號；目錄還沒讀出來時照
/// 記下的序號。書籤與標註共用。
///
/// 序號是照記下時的目錄方向數的（[countedReversed]，null 是沒記，當成和
/// 這本書現在一樣）：和現在的方向（[reversed]）不同時從目錄的另一頭數，
/// 同名的章（好幾個「番外」）才對得到同一章（反轉目錄，ADR 0085）。
int chapterIndexByTitle({
  required int chapterIndex,
  required String chapterTitle,
  required bool? countedReversed,
  required bool reversed,
  required List<BookChapter> chapters,
}) {
  final flipped =
      countedReversed != null &&
      countedReversed != reversed &&
      chapterIndex >= 0 &&
      chapterIndex < chapters.length;
  return alignChapterIndex(
    oldIndex: flipped ? chapters.length - 1 - chapterIndex : chapterIndex,
    oldTitle: chapterTitle,
    oldTotalCount: 0,
    newChapters: chapters,
  );
}

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
  final matcher = ChapterMatcher(newChapters);
  final found = matcher.sameChapter(
    oldIndex: oldIndex,
    oldTitle: oldTitle,
    oldTotalCount: oldTotalCount,
  );
  if (found != null) return (index: found, matched: true);
  return (
    index: matcher.estimate(oldIndex: oldIndex, oldTotalCount: oldTotalCount),
    matched: false,
  );
}

/// 在一份目錄 [chapters] 裡找舊目錄的某一章。一份目錄要找很多章時（檢查
/// 更新對每個書源換掉網址的章節）共用一個，章名的比對用字只算一次。
///
/// [among] 限定哪些章可以被認成同一章（檢查更新只比網址不在舊目錄的新章）；
/// 估位置照整份 [chapters] 的序號與章數，和舊目錄同一個方向數，反轉目錄時
/// 也估得準。
class ChapterMatcher {
  ChapterMatcher(this.chapters, {bool Function(BookChapter chapter)? among})
    : _candidates = [
        for (final (i, chapter) in chapters.indexed)
          if (among == null || among(chapter)) i,
      ];

  final List<BookChapter> chapters;

  /// 可以被認成同一章的序號，由小到大。
  final List<int> _candidates;

  late final Set<int> _candidateSet = _candidates.toSet();
  late final Map<String, List<int>> _byTitle = _group((i) => chapters[i].title);
  late final Map<String, List<int>> _byKey = _group(
    (i) => _titleKey(chapters[i].title),
  );
  late final Map<String, List<int>> _byFullKey = _group(
    (i) => _fullChapterKey(chapters[i].title),
  );
  late final Map<int, List<int>> _byNumber = _group(_numberAt);
  final Map<int, int?> _numbers = {};
  final Map<int, String> _pureNames = {};

  Map<K, List<int>> _group<K>(K? Function(int index) keyOf) {
    final groups = <K, List<int>>{};
    for (final i in _candidates) {
      final key = keyOf(i);
      if (key != null) groups.putIfAbsent(key, () => []).add(i);
    }
    return groups;
  }

  int? _numberAt(int index) => _numbers.containsKey(index)
      ? _numbers[index]
      : _numbers[index] = _extractChapterNumber(chapters[index].title);

  String _pureAt(int index) =>
      _pureNames[index] ??= _pureChapterName(chapters[index].title);

  /// 照章數比例估的位置。
  int estimate({required int oldIndex, required int oldTotalCount}) {
    if (chapters.isEmpty) return oldIndex;
    var estimated = oldIndex;
    if (oldTotalCount > 0) {
      estimated = (oldIndex * chapters.length / oldTotalCount).round();
    }
    return estimated.clamp(0, chapters.length - 1);
  }

  /// 舊目錄第 [oldIndex] 章（章名 [oldTitle]）在這份目錄裡的同一章，沒有
  /// 是 null：先找同名的章（[sameChapterTitle]：繁簡、空白不同也算）。
  ///
  /// [approximate]（預設）只影響位置，同 Legado `BookHelp.getDurChapter`：
  /// 再在估計位置前後 10 章裡比去掉章號的章名（相似度超過 0.96），再找同
  /// 一個章號（認中文數字與「100、」）。false 時（檢查更新要拿掉舊章，見
  /// `mergeFetchedToc`）只認正規化後完整章名相同（[_fullChapterKey]）：章號
  /// 寫法（「第3章」「第三章」）、全形半形、繁簡、空白與「（求月票）」這類
  /// 附加的字不算不同；「（上）」與「（下）」是不同章。
  ///
  /// 目錄裡有好幾章同名或同章號時（例如好幾個「番外」），取離估計位置最近
  /// 的那一章，不是第一個。
  int? sameChapter({
    required int oldIndex,
    required String? oldTitle,
    required int oldTotalCount,
    bool approximate = true,
  }) {
    if (_candidates.isEmpty) return null;
    final newSize = chapters.length;
    var estimatedIndex = oldIndex;
    if (oldTotalCount > 0) {
      estimatedIndex = (oldIndex * newSize / oldTotalCount).round();
    }

    int? nearest(List<int>? indexes) {
      if (indexes == null) return null;
      int? best;
      for (final i in indexes) {
        if (best == null ||
            (i - estimatedIndex).abs() < (best - estimatedIndex).abs()) {
          best = i;
        }
      }
      return best;
    }

    if (oldTitle != null && oldTitle.isNotEmpty) {
      final exact = nearest(_byTitle[oldTitle]);
      if (exact != null) return exact;
      final converted = nearest(_byKey[_titleKey(oldTitle)]);
      if (converted != null) return converted;
    }

    if (!approximate) {
      return nearest(_byFullKey[_fullChapterKey(oldTitle)]);
    }

    // 同 Legado：估計位置與原本的位置前後 10 章裡，比去掉章號與非分段標記
    // 括號的章名。好幾章一樣像時（每章都叫「正文」、短的「上」「下」），
    // 章號相同的優先，再取離估計位置最近的（Legado 取第一個）。
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
        if (!_candidateSet.contains(i)) continue;
        final similarity = _jaccard(oldPure, _pureAt(i));
        if (similarity <= _similarEnough) continue;
        final sameNumber =
            oldChapterNumber != null && _numberAt(i) == oldChapterNumber;
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
      if (best != null) return best;
    }

    if (oldChapterNumber != null) {
      return nearest(_byNumber[oldChapterNumber]);
    }
    return null;
  }
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

/// 章名結尾括號裡附加的字（「（求月票）」）；整段是括號時只算最後的結尾
/// 括號。分段標記（[_segmentMarker]）留著，兩半才分得開。
final RegExp _trailingBracketed = RegExp(
  r'(?!^)(?:[〖【《〔\[{(]([^〖【《〔\[{()〕》】〗\]}]+))?[)〕》】〗\]}]$',
);

/// 章名開頭括號裡附加的字（「（求月票）大戰」）；分段標記留著。
final RegExp _leadingBracketed = RegExp(
  r'^[〖【《〔\[{(](?:([^〖【《〔\[{()〕》】〗\]}]+)[〕》】〗\]})])?(?!$)',
);

/// 括號裡是分段標記（「（上）」「（下）」「（一）」「（2）」「（前篇）」）：
/// 兩半是不同章，比對時不拿掉。其他附加的字（「（求月票）」）照舊拿掉。
final RegExp _segmentMarker = RegExp(
  '^(?:[上中下前后後](?:篇|部|卷|半)?|'
  '[$_numberChars]+(?:篇|部|卷|章|节|節)?)\$',
);

/// 字母、數字與漢字以外的字（Legado `regexOther`）。
final RegExp _notWordOrHan = RegExp(
  r'[^\w一-鿯〇㐀-䶿\u{20000}-\u{2A6DF}\u{2A700}-\u{2EBEF}]',
  unicode: true,
);

/// 拿掉 [pattern] 對到的括號附加字；括號裡是分段標記時留著。
String _stripBracketedAdditions(String text, RegExp pattern) =>
    text.replaceAllMapped(
      pattern,
      (match) => _segmentMarker.hasMatch(match.group(1) ?? '') ? match[0]! : '',
    );

/// 比對用的章名本身：去掉空白、章號、前後括號與標點，繁體轉簡體（Legado
/// `getPureChapterName`；夜讀多轉繁簡，繁體站換簡體站也比得上）。分段標記
/// 留著。
String _pureChapterName(String? title) {
  if (title == null || title.isEmpty) return '';
  var pure = ChineseUtils.t2s(StringUtils.fullToHalf(title))
      .replaceAll(_whitespace, '')
      .replaceAll(_numberPrefix, '');
  pure = _stripBracketedAdditions(pure, _trailingBracketed);
  pure = _stripBracketedAdditions(pure, _leadingBracketed);
  return pure.replaceAll(_notWordOrHan, '');
}

/// 完整章名的正規化：章號寫法不同（「第3章」「第三章」「100、」）算同一個
/// 章號，後面的字照 [_pureChapterName]（附加的括號拿掉、分段標記留著）；
/// 章名只有章號時只比章號。
String? _fullChapterKey(String? title) {
  if (title == null || title.isEmpty) return null;
  final number = _extractChapterNumber(title);
  if (number != null && _onlyNumber(title)) return '#$number';
  final pure = _pureChapterName(title);
  if (number == null && pure.isEmpty) return null;
  return '${number ?? ''}|$pure';
}

/// 章名只有章號、沒有別的字（「第3章」「100、」）。
bool _onlyNumber(String? title) {
  if (title == null) return false;
  final compact = StringUtils.fullToHalf(title).replaceAll(_whitespace, '');
  final match =
      _numberedTitle.firstMatch(compact) ?? _leadingNumber.firstMatch(compact);
  return match != null &&
      compact.substring(match.end).replaceAll(_notWordOrHan, '').isEmpty;
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
