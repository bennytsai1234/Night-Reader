import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/utils/network_utils.dart';

/// 目錄解析結果
class ChapterListResult {
  final List<BookChapter> chapters;

  /// 下一頁 URL 清單 (對標 Android BookChapterList.analyzeChapterList 返回的 nextUrlList)
  /// - 長度 0：沒有下一頁
  /// - 長度 1：daisy-chain (每頁解析後再跟下一頁)
  /// - 長度 > 1：首頁列出所有分頁，可並發抓取
  final List<String> nextUrls;

  /// 是否使用反向排序 (對標 Android `-` 前綴)
  /// 只在首頁 (list rule 解析時) 計算；後續翻頁沿用首頁的值
  final bool isReverse;

  const ChapterListResult({
    required this.chapters,
    this.nextUrls = const [],
    this.isReverse = false,
  });
}

class ChapterListParser {
  /// 解析目錄頁，返回章節列表與下一頁 URL
  /// (對標 Android BookChapterList.analyzeChapterList)
  ///
  /// [baseUrl] 是請求這一頁的網址，[redirectUrl] 是網站轉址後回應的網址
  /// （同 Legado）；沒給時是同一個。相對網址用 [redirectUrl] 補，章節沒有
  /// 網址時用 [baseUrl]。
  static Future<ChapterListResult> parse({
    required BookSource source,
    required Book book,
    required String body,
    required String baseUrl,
    String? redirectUrl,
    int? maxChapters,
  }) async {
    if (maxChapters != null && maxChapters <= 0) {
      return const ChapterListResult(chapters: []);
    }
    final tocRule = source.ruleToc;
    if (tocRule == null) return const ChapterListResult(chapters: []);

    // 處理 -/+ 前綴 (對標 Android BookChapterList.analyzeChapterList 開頭邏輯)
    var listRule = tocRule.chapterList ?? '';
    var isReverse = false;
    if (listRule.startsWith('-')) {
      isReverse = true;
      listRule = listRule.substring(1);
    }
    if (listRule.startsWith('+')) {
      listRule = listRule.substring(1);
    }

    final pageUrl = redirectUrl ?? baseUrl;
    final rule = AnalyzeRule(
      source: source,
      ruleData: book,
    ).setContent(body, baseUrl: baseUrl, redirectUrl: pageUrl);
    try {
      final chapterNameRule = tocRule.chapterName ?? '';
      final chapterUrlRule = tocRule.chapterUrl ?? '';
      final updateTimeRule = tocRule.updateTime ?? '';
      final isVolumeRule = tocRule.isVolume ?? '';
      final isVipRule = tocRule.isVip ?? '';
      final isPayRule = tocRule.isPay ?? '';
      final nextTocUrlRule = tocRule.nextTocUrl ?? '';
      final elements = rule.getElements(listRule);

      final chapters = <BookChapter>[];
      for (var i = 0; i < elements.length; i++) {
        final itemRule = AnalyzeRule(source: source, ruleData: book).setContent(
          elements[i],
          baseUrl: baseUrl,
          redirectUrl: pageUrl,
        )..jsEngineOwner = rule;
        final chapter = BookChapter(
          baseUrl: pageUrl,
          bookUrl: book.bookUrl,
          index: i,
        );
        itemRule.setChapter(chapter);

        try {
          chapter.title = _readString(itemRule, chapterNameRule);
          if (chapter.title.isEmpty) continue;

          // 同 Legado `bookChapter.url = getString(urlRule)`：先讀原文、不加
          // isUrl。isUrl 在讀不到時會傳回目錄網址，卷那一列（沒有章節網址）
          // 就分不出「規則沒抓到」，拿不到下面的「標題＋序號」，之後依網址去重
          // 還會把所有卷收成一個。
          final rawUrl = _readString(itemRule, chapterUrlRule);
          chapter.url = rawUrl.isEmpty
              ? ''
              : NetworkUtils.getAbsoluteURL(
                  itemRule.redirectUrl ?? baseUrl,
                  rawUrl,
                );
          chapter.tag = _readString(itemRule, updateTimeRule);
          chapter.isVolume = _isTrue(_readString(itemRule, isVolumeRule));

          if (chapter.url.isEmpty) {
            if (chapter.isVolume) {
              chapter.url = '${chapter.title}$i';
            } else {
              chapter.url = baseUrl;
            }
          }

          chapter.isVip = _isTrue(_readString(itemRule, isVipRule));
          chapter.isPay = _isTrue(_readString(itemRule, isPayRule));

          chapters.add(chapter);
          if (maxChapters != null && chapters.length >= maxChapters) {
            return ChapterListResult(
              chapters: chapters,
              nextUrls: const <String>[],
              isReverse: isReverse,
            );
          }
        } finally {
          itemRule.dispose();
        }
      }

      final nextUrls = <String>[];
      if (nextTocUrlRule.isNotEmpty) {
        final list = rule.getStringList(nextTocUrlRule, isUrl: true);
        for (final u in list) {
          if (u.isNotEmpty && u != pageUrl) nextUrls.add(u);
        }
      }

      return ChapterListResult(
        chapters: chapters,
        nextUrls: nextUrls,
        isReverse: isReverse,
      );
    } finally {
      rule.dispose();
    }
  }

  /// 解析布林字串 (對標 Android String.isTrue)
  /// 認可: true / yes / 1 / 是
  static bool _isTrue(String s) {
    if (s.isEmpty) return false;
    final lower = s.trim().toLowerCase();
    return lower == 'true' || lower == 'yes' || lower == '1' || lower == '是';
  }

  static String _readString(
    AnalyzeRule rule,
    String ruleText, {
    bool isUrl = false,
  }) {
    if (ruleText.isEmpty) return '';
    return rule.getString(ruleText, isUrl: isUrl);
  }
}
