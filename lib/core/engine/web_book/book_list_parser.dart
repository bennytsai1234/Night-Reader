import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/js/async_js_rewriter.dart';
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
          isSearch ? source.ruleSearch : _resolveExploreRule(source);
      if (listRule == null) return [];

      String ruleList = listRule.bookList ?? '';
      final listRuleNeedsAsync = _ruleNeedsAsync(ruleList);
      var isReverse = false;
      if (ruleList.startsWith('-')) {
        isReverse = true;
        ruleList = ruleList.substring(1);
      }
      if (ruleList.startsWith('+')) {
        ruleList = ruleList.substring(1);
      }

      var elements =
          listRuleNeedsAsync
              ? await rule.getElementsAsync(ruleList)
              : rule.getElements(ruleList);

      if (!isSearch &&
          elements.isEmpty &&
          _shouldFallbackToSearchRule(source, listRule)) {
        final fallbackRule = source.ruleSearch;
        if (fallbackRule != null) {
          listRule = fallbackRule;
          ruleList = fallbackRule.bookList ?? '';
          final fallbackNeedsAsync = _ruleNeedsAsync(ruleList);
          isReverse = false;
          if (ruleList.startsWith('-')) {
            isReverse = true;
            ruleList = ruleList.substring(1);
          }
          if (ruleList.startsWith('+')) {
            ruleList = ruleList.substring(1);
          }
          elements =
              fallbackNeedsAsync
                  ? await rule.getElementsAsync(ruleList)
                  : rule.getElements(ruleList);
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
      final nameRuleNeedsAsync = _ruleNeedsAsync(nameRule);
      final bookUrlRuleNeedsAsync = _ruleNeedsAsync(bookUrlRule);
      final authorRuleNeedsAsync = _ruleNeedsAsync(authorRule);
      final kindRuleNeedsAsync = _ruleNeedsAsync(kindRule);
      final coverUrlRuleNeedsAsync = _ruleNeedsAsync(coverUrlRule);
      final introRuleNeedsAsync = _ruleNeedsAsync(introRule);
      final latestChapterRuleNeedsAsync = _ruleNeedsAsync(latestChapterRule);
      final wordCountRuleNeedsAsync = _ruleNeedsAsync(wordCountRule);
      // 以 (name|author|bookUrl) 作為去重鍵，對標 Android LinkedHashSet<SearchBook>
      final seen = <String>{};

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
        ).setContent(element, baseUrl: baseUrl);

        try {
          final name = BookHelp.formatBookName(
            await _readString(
              itemRule,
              nameRule,
              needsAsync: nameRuleNeedsAsync,
            ),
          );
          if (name.isEmpty) continue;

          searchBook.name = name;
          searchBook.author = BookHelp.formatBookAuthor(
            await _safeString(
              () => _readString(
                itemRule,
                authorRule,
                needsAsync: authorRuleNeedsAsync,
              ),
            ),
          );
          if (filter != null && !filter(name, searchBook.author ?? '')) {
            continue;
          }
          searchBook.kind = (await _safeStringList(
            () => _readStringList(
              itemRule,
              kindRule,
              needsAsync: kindRuleNeedsAsync,
            ),
          )).join(',');
          searchBook.coverUrl = await _safeString(() {
            return _readString(
              itemRule,
              coverUrlRule,
              needsAsync: coverUrlRuleNeedsAsync,
              isUrl: true,
            );
          });
          searchBook.intro = HtmlFormatter.format(
            await _safeString(() {
              return _readString(
                itemRule,
                introRule,
                needsAsync: introRuleNeedsAsync,
              );
            }),
          );
          searchBook.latestChapterTitle = await _safeString(
            () => _readString(
              itemRule,
              latestChapterRule,
              needsAsync: latestChapterRuleNeedsAsync,
            ),
          );
          searchBook.wordCount = StringUtils.wordCountFormat(
            await _safeString(
              () => _readString(
                itemRule,
                wordCountRule,
                needsAsync: wordCountRuleNeedsAsync,
              ),
            ),
          );

          var bookUrl = await _readString(
            itemRule,
            bookUrlRule,
            needsAsync: bookUrlRuleNeedsAsync,
            isUrl: true,
          );
          // 空 bookUrl fallback 為 baseUrl (對標 Android BookList 邏輯)
          if (bookUrl.isEmpty) bookUrl = baseUrl;
          searchBook.bookUrl = bookUrl;

          // 去重：同一個 (name, author, bookUrl) 只保留首次出現
          final dedupKey = '$name|${searchBook.author ?? ''}|$bookUrl';
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
        final originalExploreRule = source.ruleExplore;
        source.ruleExplore = _copySearchRuleAsExploreRule(source.ruleSearch!);
        try {
          return parse(
            source: source,
            body: body,
            baseUrl: baseUrl,
            isSearch: false,
            filter: filter,
            shouldBreak: shouldBreak,
          );
        } finally {
          source.ruleExplore = originalExploreRule;
        }
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

  static Future<String> _safeString(Future<String> Function() reader) async {
    try {
      return await reader();
    } catch (_) {
      return '';
    }
  }

  static Future<List<String>> _safeStringList(
    Future<List<String>> Function() reader,
  ) async {
    try {
      return await reader();
    } catch (_) {
      return const <String>[];
    }
  }

  static bool _ruleNeedsAsync(String rule) {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return false;
    return AsyncJsRewriter.needsAsync(trimmed);
  }

  static Future<String> _readString(
    AnalyzeRule rule,
    String ruleText, {
    required bool needsAsync,
    bool isUrl = false,
  }) async {
    if (ruleText.isEmpty) return '';
    if (needsAsync) {
      return rule.getStringAsync(ruleText, isUrl: isUrl);
    }
    return rule.getString(ruleText, isUrl: isUrl);
  }

  static Future<List<String>> _readStringList(
    AnalyzeRule rule,
    String ruleText, {
    required bool needsAsync,
    bool isUrl = false,
  }) async {
    if (ruleText.isEmpty) return const <String>[];
    if (needsAsync) {
      return rule.getStringListAsync(ruleText, isUrl: isUrl);
    }
    return rule.getStringList(ruleText, isUrl: isUrl);
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
