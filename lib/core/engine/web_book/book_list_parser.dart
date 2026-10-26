import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/book/book_help.dart';
import 'package:night_reader/core/engine/web_book/book_info_parser.dart';
import 'package:night_reader/core/utils/string_utils.dart';
import 'package:night_reader/core/utils/html_formatter.dart';

class BookListParser {
  static Future<List<SearchBook>> parse({
    required BookSource source,
    required String body,
    required String baseUrl,
    required bool isSearch,
    bool Function(String name, String author)? filter,
    bool Function(int size)? shouldBreak,
  }) => _parse(
    source: source,
    body: body,
    baseUrl: baseUrl,
    isSearch: isSearch,
    filter: filter,
    shouldBreak: shouldBreak,
  );

  static Future<List<SearchBook>> _parse({
    required BookSource source,
    required String body,
    required String baseUrl,
    required bool isSearch,
    bool Function(String name, String author)? filter,
    bool Function(int size)? shouldBreak,
    dynamic listRuleOverride,
  }) async {
    // 1. 偵測 bookUrlPattern (對標 Android BookList.analyzeBookList)
    if (isSearch && source.bookUrlPattern?.isNotEmpty == true) {
      try {
        if (RegExp(source.bookUrlPattern!).hasMatch(baseUrl)) {
          final searchBook = await _getInfoItem(
            source: source,
            body: body,
            baseUrl: baseUrl,
          );
          if (searchBook != null) {
            return [searchBook];
          }
        }
      } catch (_) {}
    }

    final rule = AnalyzeRule(source: source).setContent(body, baseUrl: baseUrl);
    try {
      dynamic listRule =
          listRuleOverride ??
          (isSearch ? source.ruleSearch : _resolveExploreRule(source));
      if (listRule == null) return [];

      String ruleList = listRule.bookList ?? '';
      var isReverse = false;
      if (ruleList.startsWith('-')) {
        isReverse = true;
        ruleList = ruleList.substring(1);
      }
      if (ruleList.startsWith('+')) {
        ruleList = ruleList.substring(1);
      }

      var elements = rule.getElements(ruleList);

      if (!isSearch &&
          elements.isEmpty &&
          _shouldFallbackToSearchRule(source, listRule)) {
        final fallbackRule = source.ruleSearch;
        if (fallbackRule != null) {
          listRule = fallbackRule;
          ruleList = fallbackRule.bookList ?? '';
          isReverse = false;
          if (ruleList.startsWith('-')) {
            isReverse = true;
            ruleList = ruleList.substring(1);
          }
          if (ruleList.startsWith('+')) {
            ruleList = ruleList.substring(1);
          }
          elements = rule.getElements(ruleList);
        }
      }

      // 2. 如果列表為空且未配置 bookUrlPattern，嘗試按詳情頁解析 (對標 Android 邏輯)
      if (elements.isEmpty &&
          (source.bookUrlPattern == null || source.bookUrlPattern!.isEmpty)) {
        final searchBook = await _getInfoItem(
          source: source,
          body: body,
          baseUrl: baseUrl,
        );
        if (searchBook != null) {
          return [searchBook];
        }
        return [];
      }

      final books = <SearchBook>[];
      final nameRule = listRule.name ?? '';
      final bookUrlRule = listRule.bookUrl ?? '';
      final authorRule = listRule.author ?? '';
      final kindRule = listRule.kind ?? '';
      final coverUrlRule = listRule.coverUrl ?? '';
      final introRule = listRule.intro ?? '';
      final latestChapterRule = listRule.lastChapter ?? '';
      final wordCountRule = listRule.wordCount ?? '';
      // 以 (name, author, bookUrl) 作為去重鍵，對標 Android LinkedHashSet<SearchBook>
      final seen = <(String, String, String)>{};

      for (final element in elements) {
        // 建立空的 SearchBook 作為 ruleData，以便儲存解析過程中產生的變數 (@put)
        final searchBook = SearchBook(
          bookUrl: '',
          name: '',
          origin: source.bookSourceUrl,
          originName: source.bookSourceName,
          originOrder: source.customOrder,
          type: source.bookSourceType,
        );

        final itemRule = AnalyzeRule(
          ruleData: searchBook,
          source: source,
        ).setContent(element, baseUrl: baseUrl)..jsEngineOwner = rule;

        try {
          final name = BookHelp.formatBookName(_readString(itemRule, nameRule));
          if (name.isEmpty) continue;

          searchBook.name = name;
          searchBook.author = BookHelp.formatBookAuthor(
            _safeString(() => _readString(itemRule, authorRule)),
          );
          if (filter != null && !filter(name, searchBook.author ?? '')) {
            continue;
          }
          searchBook.kind = _safeStringList(
            () => _readStringList(itemRule, kindRule),
          ).join(',');
          searchBook.coverUrl = BookInfoParser.coverUrlFrom(
            _safeString(() => _readString(itemRule, coverUrlRule)),
            baseUrl,
          );
          searchBook.intro = HtmlFormatter.format(
            _safeString(() => _readString(itemRule, introRule)),
          );
          searchBook.latestChapterTitle = _safeString(
            () => _readString(itemRule, latestChapterRule),
          );
          searchBook.wordCount = StringUtils.wordCountFormat(
            _safeString(() => _readString(itemRule, wordCountRule)),
          );

          var bookUrl = _readString(itemRule, bookUrlRule, isUrl: true);
          // 空 bookUrl fallback 為 baseUrl (對標 Android BookList 邏輯)
          if (bookUrl.isEmpty) bookUrl = baseUrl;
          searchBook.bookUrl = bookUrl;

          // 去重：同一個 (name, author, bookUrl) 只保留首次出現
          final dedupKey = (name, searchBook.author ?? '', bookUrl);
          if (!seen.add(dedupKey)) continue;

          books.add(searchBook);
          if (shouldBreak?.call(books.length) == true) {
            break;
          }
        } finally {
          itemRule.dispose();
        }
      }

      if (!isSearch &&
          books.isEmpty &&
          _shouldFallbackToSearchRule(source, listRule)) {
        return await _parse(
          source: source,
          body: body,
          baseUrl: baseUrl,
          isSearch: false,
          filter: filter,
          shouldBreak: shouldBreak,
          listRuleOverride: _copySearchRuleAsExploreRule(source.ruleSearch!),
        );
      }

      return isReverse ? books.reversed.toList() : books;
    } finally {
      rule.dispose();
    }
  }

  static Future<SearchBook?> _getInfoItem({
    required BookSource source,
    required String body,
    required String baseUrl,
  }) async {
    var book = Book(
      bookUrl: baseUrl,
      origin: source.bookSourceUrl,
      originName: source.bookSourceName,
      originOrder: source.customOrder,
      type: source.bookSourceType,
    );

    book = await BookInfoParser.parse(
      source: source,
      book: book,
      body: body,
      baseUrl: baseUrl,
    );

    if (book.name.isNotEmpty) {
      return book.toSearchBook();
    }
    return null;
  }

  static String _safeString(String Function() reader) {
    try {
      return reader();
    } catch (_) {
      return '';
    }
  }

  static List<String> _safeStringList(List<String> Function() reader) {
    try {
      return reader();
    } catch (_) {
      return const <String>[];
    }
  }

  static String _readString(
    AnalyzeRule rule,
    String ruleText, {
    bool isUrl = false,
  }) {
    if (ruleText.isEmpty) return '';
    return rule.getString(ruleText, isUrl: isUrl);
  }

  static List<String> _readStringList(AnalyzeRule rule, String ruleText) {
    if (ruleText.isEmpty) return const <String>[];
    return rule.getStringList(ruleText);
  }

  static dynamic _resolveExploreRule(BookSource source) {
    final exploreRule = source.ruleExplore;
    final exploreBookList = exploreRule?.bookList?.trim() ?? '';
    if (exploreBookList.isNotEmpty) {
      return exploreRule;
    }
    return source.ruleSearch ?? exploreRule;
  }

  static bool _shouldFallbackToSearchRule(
    BookSource source,
    dynamic activeRule,
  ) {
    final searchRule = source.ruleSearch;
    if (searchRule == null) return false;
    final searchBookList = searchRule.bookList?.trim() ?? '';
    if (searchBookList.isEmpty) return false;
    if (identical(activeRule, searchRule)) return false;
    final activeBookList = (activeRule?.bookList as String?)?.trim() ?? '';
    return activeBookList != searchBookList;
  }

  static ExploreRule _copySearchRuleAsExploreRule(SearchRule rule) {
    return ExploreRule(
      bookList: rule.bookList,
      name: rule.name,
      author: rule.author,
      intro: rule.intro,
      kind: rule.kind,
      lastChapter: rule.lastChapter,
      updateTime: rule.updateTime,
      bookUrl: rule.bookUrl,
      coverUrl: rule.coverUrl,
      wordCount: rule.wordCount,
    );
  }
}
