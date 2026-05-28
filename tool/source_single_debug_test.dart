import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:reader/core/engine/analyze_rule.dart' as rule_engine;
import 'package:reader/core/engine/analyze_rule.dart';
import 'package:reader/core/engine/analyze_url.dart';
import 'package:reader/core/engine/explore_url_parser.dart';
import 'package:reader/core/engine/web_book/book_list_parser.dart';
import 'package:reader/core/models/book.dart';
import 'package:reader/core/models/chapter.dart';
import 'package:reader/core/engine/web_book/content_parser.dart';
import 'package:reader/core/services/book_source_service.dart';

import 'source_validation_support.dart';

void main() {
  final service = BookSourceService();
  final sourceIndex =
      int.tryParse(Platform.environment['SOURCE_INDEX'] ?? '') ?? 1;
  final probeCount =
      int.tryParse(Platform.environment['PROBE_COUNT'] ?? '') ?? 5;
  final keywordOverride = Platform.environment['KEYWORD']?.trim();
  final bookUrlOverride = Platform.environment['BOOK_URL']?.trim();
  final bookNameOverride = Platform.environment['BOOK_NAME']?.trim();
  final searchOnly = Platform.environment['SEARCH_ONLY'] == '1';
  final exploreOnly = Platform.environment['EXPLORE_ONLY'] == '1';
  final debugSearchParse = Platform.environment['DEBUG_SEARCH_PARSE'] == '1';
  final debugExploreParse = Platform.environment['DEBUG_EXPLORE_PARSE'] == '1';
  final debugExploreKindIndex =
      int.tryParse(Platform.environment['DEBUG_EXPLORE_KIND_INDEX'] ?? '') ?? 1;
  final debugRawCss = Platform.environment['DEBUG_RAW_CSS']?.trim();
  final debugPattern = Platform.environment['DEBUG_PATTERN']?.trim();
  final debugJsIntermediate =
      Platform.environment['DEBUG_JS_INTERMEDIATE'] == '1';
  final debugTocParse = Platform.environment['DEBUG_TOC_PARSE'] == '1';
  final debugTocJsResult = Platform.environment['DEBUG_TOC_JS_RESULT'] == '1';
  final debugBookInfoParse =
      Platform.environment['DEBUG_BOOK_INFO_PARSE'] == '1';
  final debugContentParse = Platform.environment['DEBUG_CONTENT_PARSE'] == '1';
  final debugChapterIndex =
      int.tryParse(Platform.environment['DEBUG_CHAPTER_INDEX'] ?? '') ?? 1;
  final debugTimings = Platform.environment['DEBUG_TIMINGS'] == '1';
  final stopAfterDebugSearchParse =
      Platform.environment['STOP_AFTER_DEBUG_SEARCH_PARSE'] == '1';

  test('debug single source flow', () async {
    await initSourceValidationEnvironment();
    final sources = await fetchSources(limit: sourceIndex);
    final source = sources[sourceIndex - 1];

    // ignore: avoid_print
    print('[debug] source #$sourceIndex ${source.bookSourceName}');

    if (exploreOnly) {
      final exploreUrl = source.exploreUrl?.trim() ?? '';
      if (exploreUrl.isNotEmpty) {
        final kinds = await ExploreUrlParser.parseAsync(
          exploreUrl,
          source: source,
        );
        // ignore: avoid_print
        print('[debug] explore kinds=${kinds.length}');
        for (final kind in kinds.take(3)) {
          // ignore: avoid_print
          print('[debug] explore kind=${kind.title} | url=${kind.url}');
          final books = await service.exploreBooks(
            source,
            kind.url ?? '',
            page: 1,
          );
          // ignore: avoid_print
          print('[debug] explore books=${books.length}');
          for (final book in books.take(8)) {
            // ignore: avoid_print
            print(
              '[debug] explore result=${book.name} | '
              'author=${book.author ?? ''} | url=${book.bookUrl}',
            );
          }
        }
      }
      return;
    }

    if (debugExploreParse) {
      final exploreUrl = source.exploreUrl?.trim() ?? '';
      final kinds = await ExploreUrlParser.parseAsync(
        exploreUrl,
        source: source,
      );
      // ignore: avoid_print
      print('[debug] explore kinds=${kinds.length}');
      for (final kind in kinds.take(5)) {
        // ignore: avoid_print
        print('[debug] explore kind=${kind.title} | url=${kind.url}');
      }
      if (kinds.isEmpty) {
        return;
      }

      final selectedIndex = (debugExploreKindIndex - 1).clamp(
        0,
        kinds.length - 1,
      );
      final selectedKind = kinds[selectedIndex];
      final analyzeUrl = await AnalyzeUrl.create(
        selectedKind.url ?? '',
        source: source,
        page: 1,
      );
      final response = await analyzeUrl.getStrResponse();
      // ignore: avoid_print
      print(
        '[debug] explore response url=${response.url} '
        'len=${response.body.length}',
      );
      // ignore: avoid_print
      print('[debug] explore body=${_previewBody(response.body)}');

      final listRule =
          source.ruleExplore?.bookList?.trim().isNotEmpty == true
              ? source.ruleExplore?.bookList ?? ''
              : source.ruleSearch?.bookList ?? '';
      final parser = rule_engine.AnalyzeRule(
        source: source,
      ).setContent(response.body, baseUrl: response.url);
      final elements = parser.getElements(listRule);
      // ignore: avoid_print
      print('[debug] explore rule=$listRule elements=${elements.length}');
      for (final element in elements.take(3)) {
        // ignore: avoid_print
        print('[debug] explore element=${_previewBody(element.toString())}');
      }

      final books = await BookListParser.parse(
        source: source,
        body: response.body,
        baseUrl: response.url,
        isSearch: false,
      );
      // ignore: avoid_print
      print('[debug] explore books=${books.length}');
      for (final book in books.take(5)) {
        // ignore: avoid_print
        print(
          '[debug] explore result=${book.name} | '
          'author=${book.author ?? ''} | url=${book.bookUrl}',
        );
      }
      return;
    }

    String? keyword;
    if (bookUrlOverride != null && bookUrlOverride.isNotEmpty) {
      // ignore: avoid_print
      print('[debug] direct book url=$bookUrlOverride');
    } else {
      keyword =
          keywordOverride != null && keywordOverride.isNotEmpty
              ? keywordOverride
              : await pickKeyword(service, source);
      // ignore: avoid_print
      print('[debug] keyword=$keyword');
    }

    if (debugSearchParse) {
      final analyzeStopwatch = Stopwatch()..start();
      final analyzeUrl = await AnalyzeUrl.create(
        source.searchUrl!,
        source: source,
        key: keyword,
        page: 1,
      );
      if (debugTimings) {
        // ignore: avoid_print
        print(
          '[timing] analyzeUrl.create=${analyzeStopwatch.elapsedMilliseconds}ms',
        );
      }
      final responseStopwatch = Stopwatch()..start();
      final response = await analyzeUrl.getStrResponse();
      if (debugTimings) {
        // ignore: avoid_print
        print(
          '[timing] analyzeUrl.getStrResponse=${responseStopwatch.elapsedMilliseconds}ms',
        );
      }
      final parserStopwatch = Stopwatch()..start();
      final searchRule = source.ruleSearch;
      final parser = rule_engine.AnalyzeRule(
        source: source,
      ).setContent(response.body, baseUrl: response.url);
      if (debugTimings) {
        // ignore: avoid_print
        print(
          '[timing] AnalyzeRule.setContent=${parserStopwatch.elapsedMilliseconds}ms',
        );
      }
      final elementStopwatch = Stopwatch()..start();
      final listRule = searchRule?.bookList ?? '';
      final elements = parser.getElements(listRule);
      if (debugTimings) {
        // ignore: avoid_print
        print(
          '[timing] parser.getElements=${elementStopwatch.elapsedMilliseconds}ms',
        );
      }
      // ignore: avoid_print
      print(
        '[debug] search response url=${response.url} '
        'len=${response.body.length} elements=${elements.length}',
      );
      if (debugRawCss != null && debugRawCss.isNotEmpty) {
        final document = html_parser.parse(response.body);
        final cssElements = document.querySelectorAll(debugRawCss);
        // ignore: avoid_print
        print(
          '[debug] raw css selector=$debugRawCss count=${cssElements.length}',
        );
        if (cssElements.isNotEmpty) {
          // ignore: avoid_print
          print('[debug] raw css first=${cssElements.first.outerHtml}');
        }
      }
      if (debugPattern != null && debugPattern.isNotEmpty) {
        final index = response.body.indexOf(debugPattern);
        // ignore: avoid_print
        print('[debug] pattern=$debugPattern index=$index');
        if (index >= 0) {
          final start = (index - 200).clamp(0, response.body.length);
          final end = (index + 800).clamp(0, response.body.length);
          // ignore: avoid_print
          print(
            '[debug] pattern excerpt=${response.body.substring(start, end)}',
          );
        }
      }
      // ignore: avoid_print
      print('[debug] search body=${_previewBody(response.body)}');
      for (final element in elements.take(3)) {
        final itemRule = rule_engine.AnalyzeRule(
          source: source,
        ).setContent(element, baseUrl: response.url);
        // ignore: avoid_print
        print(
          '[debug] parsed item '
          'name=${await itemRule.getStringAsync(searchRule?.name ?? '')} | '
          'author=${await itemRule.getStringAsync(searchRule?.author ?? '')} | '
          'bookUrl=${await itemRule.getStringAsync(searchRule?.bookUrl ?? '', isUrl: true)}',
        );
      }
      final parsedBooks = await BookListParser.parse(
        source: source,
        body: response.body,
        baseUrl: response.url,
        isSearch: true,
      );
      // ignore: avoid_print
      print('[debug] BookListParser books=${parsedBooks.length}');
      for (final book in parsedBooks.take(5)) {
        // ignore: avoid_print
        print(
          '[debug] parser book=${book.name} | '
          'author=${book.author ?? ''} | url=${book.bookUrl}',
        );
      }
      if (stopAfterDebugSearchParse) {
        return;
      }
    }

    late final Book selected;
    if (bookUrlOverride != null && bookUrlOverride.isNotEmpty) {
      selected = Book(
        name: bookNameOverride?.isNotEmpty == true ? bookNameOverride! : '',
        bookUrl: bookUrlOverride,
        origin: source.bookSourceUrl,
      );
    } else {
      final searchBooksStopwatch = Stopwatch()..start();
      final searchBooks = await service.searchBooks(source, keyword!);
      if (debugTimings) {
        // ignore: avoid_print
        print(
          '[timing] service.searchBooks=${searchBooksStopwatch.elapsedMilliseconds}ms',
        );
      }
      // ignore: avoid_print
      print('[debug] search results=${searchBooks.length}');
      for (final book in searchBooks.take(5)) {
        // ignore: avoid_print
        print(
          '[debug] result=${book.name} | author=${book.author ?? ''} | '
          'url=${book.bookUrl}',
        );
      }
      if (searchOnly) {
        expect(searchBooks, isNotEmpty);
        return;
      }
      final matchedSearchBook = selectMatchingSearchBook(searchBooks, keyword);
      if (matchedSearchBook == null) {
        throw StateError('搜尋結果未命中關鍵詞 "$keyword"');
      }
      selected = matchedSearchBook.toBook();
      // ignore: avoid_print
      print('[debug] search hit=${selected.name} | url=${selected.bookUrl}');
    }

    if (debugBookInfoParse && source.ruleBookInfo != null) {
      final detailAnalyzeUrl = await AnalyzeUrl.create(
        selected.bookUrl,
        source: source,
        ruleData: selected,
      );
      final detailResponse = await detailAnalyzeUrl.getStrResponse();
      final infoRule = source.ruleBookInfo!;
      // ignore: avoid_print
      print(
        '[debug] info rules '
        'name=${infoRule.name ?? ''} | '
        'author=${infoRule.author ?? ''} | '
        'tocUrl=${infoRule.tocUrl ?? ''} | '
        'intro=${infoRule.intro ?? ''} | '
        'cover=${infoRule.coverUrl ?? ''} | '
        'kind=${infoRule.kind ?? ''} | '
        'last=${infoRule.lastChapter ?? ''}',
      );
      final parser = AnalyzeRule(
        source: source,
        ruleData: selected,
      ).setContent(detailResponse.body, baseUrl: detailResponse.url);

      Future<void> printField(
        String label,
        String ruleValue, {
        bool isUrl = false,
      }) async {
        if (ruleValue.trim().isEmpty) return;
        try {
          final value = await parser.getStringAsync(ruleValue, isUrl: isUrl);
          // ignore: avoid_print
          print('[debug] info $label=$value');
        } catch (error) {
          // ignore: avoid_print
          print('[debug] info $label ERROR=$error');
        }
      }

      await printField('name', infoRule.name ?? '');
      await printField('author', infoRule.author ?? '');
      await printField('tocUrl', infoRule.tocUrl ?? '', isUrl: true);
      await printField('intro', infoRule.intro ?? '');
      await printField('coverUrl', infoRule.coverUrl ?? '', isUrl: true);
      await printField('kind', infoRule.kind ?? '');
      await printField('lastChapter', infoRule.lastChapter ?? '');
    }

    final book = await service.getBookInfo(source, selected);
    // ignore: avoid_print
    print('[debug] detail name=${book.name} | tocUrl=${book.tocUrl}');
    // ignore: avoid_print
    print(
      '[debug] detail latest=${book.latestChapterTitle ?? ''} | '
      'wordCount=${book.wordCount ?? ''} | '
      'infoHtml=${book.infoHtml?.length ?? 0} | '
      'tocHtml=${book.tocHtml?.length ?? 0} | '
      'brokenShell=${looksLikeBrokenBookShell(book)}',
    );
    final debugKeys = <String>[
      '单',
      '录',
      '目',
      '基',
      '查',
      '除',
      '嗅',
      '页',
      '动',
      '静',
      'ck',
      'ba',
    ];
    final debugVars = debugKeys
        .map((key) => '$key=${book.getVariable(key)}')
        .where((entry) => !entry.endsWith('='))
        .join(' | ');
    if (debugVars.isNotEmpty) {
      // ignore: avoid_print
      print('[debug] book vars $debugVars');
    }

    if (debugTocParse && source.ruleToc != null) {
      final tocAnalyzeUrl = await AnalyzeUrl.create(
        book.tocUrl.isNotEmpty ? book.tocUrl : book.bookUrl,
        source: source,
        ruleData: book,
      );
      final tocResponse = await tocAnalyzeUrl.getStrResponse();
      final tocRule = source.ruleToc!;
      // ignore: avoid_print
      print(
        '[debug] toc rules '
        'list=${tocRule.chapterList ?? ''} | '
        'name=${tocRule.chapterName ?? ''} | '
        'url=${tocRule.chapterUrl ?? ''}',
      );
      final parser = AnalyzeRule(
        source: source,
        ruleData: book,
      ).setContent(tocResponse.body, baseUrl: tocResponse.url);
      final directJsRule = _extractLeadingJsBody(tocRule.chapterList ?? '');
      if (directJsRule != null) {
        final directJsResult = await parser.evalJSAsync(
          directJsRule,
          tocResponse.body,
        );
        // ignore: avoid_print
        print(
          '[debug] toc direct js type=${directJsResult.runtimeType} '
          'preview=${_previewBody(directJsResult.toString())}',
        );
        if (directJsResult is List) {
          // ignore: avoid_print
          print('[debug] toc direct js len=${directJsResult.length}');
        } else if (directJsResult is Map) {
          // ignore: avoid_print
          print('[debug] toc direct js keys=${directJsResult.keys.join(",")}');
        }
        final tocVars = debugKeys
            .map((key) => '$key=${book.getVariable(key)}')
            .where((entry) => !entry.endsWith('='))
            .join(' | ');
        if (tocVars.isNotEmpty) {
          // ignore: avoid_print
          print('[debug] toc vars $tocVars');
        }
      }
      if (debugTocJsResult) {
        await _printTocJsIntermediate(
          source,
          book,
          tocResponse.body,
          tocResponse.url,
          tocRule.chapterList ?? '',
        );
      }
      final tocElements = await parser.getElementsAsync(
        tocRule.chapterList ?? '',
      );
      // ignore: avoid_print
      print(
        '[debug] toc response url=${tocResponse.url} '
        'len=${tocResponse.body.length} elements=${tocElements.length}',
      );
      // ignore: avoid_print
      print('[debug] toc body=${_previewBody(tocResponse.body)}');
      for (final element in tocElements.take(5)) {
        final itemRule = AnalyzeRule(
          source: source,
          ruleData: book,
        ).setContent(element, baseUrl: tocResponse.url);
        itemRule.setChapter(
          BookChapter(baseUrl: tocResponse.url, bookUrl: book.bookUrl),
        );
        final rawHref = await itemRule.getStringAsync('href');
        final resolvedHref = await itemRule.getStringAsync('href', isUrl: true);
        // ignore: avoid_print
        print('[debug] toc href raw=$rawHref | resolved=$resolvedHref');
        await _debugCompositeRule(itemRule, tocRule.chapterUrl ?? '');
        final expandedChapterUrlJs = await _expandRuleJsTemplate(
          itemRule,
          tocRule.chapterUrl ?? '',
        );
        final chapterUrlJsResult =
            expandedChapterUrlJs == null
                ? null
                : await itemRule.evalJSAsync(expandedChapterUrlJs, '');
        final rawChapterUrl = await itemRule.getStringAsync(
          tocRule.chapterUrl ?? '',
        );
        final resolvedChapterUrl = await itemRule.getStringAsync(
          tocRule.chapterUrl ?? '',
          isUrl: true,
        );
        // ignore: avoid_print
        print(
          '[debug] toc item '
          'type=${element.runtimeType} | '
          'title=${await itemRule.getStringAsync(tocRule.chapterName ?? '')} | '
          'jsUrl=${chapterUrlJsResult ?? "<none>"} | '
          'rawUrl=$rawChapterUrl | '
          'url=$resolvedChapterUrl',
        );
      }
    }

    final chapters = await service.getChapterList(source, book);
    final readable = chapters.where((chapter) => !chapter.isVolume).toList();
    // ignore: avoid_print
    print('[debug] chapters=${chapters.length} readable=${readable.length}');

    if (debugContentParse &&
        source.ruleContent != null &&
        readable.isNotEmpty &&
        debugChapterIndex >= 1 &&
        debugChapterIndex <= readable.length) {
      final chapter = readable[debugChapterIndex - 1];
      final nextChapterUrl =
          readable.length > debugChapterIndex
              ? readable[debugChapterIndex].url
              : null;
      final contentAnalyzeUrl = await AnalyzeUrl.create(
        chapter.url,
        source: source,
        ruleData: book,
      );
      final contentResponse = await contentAnalyzeUrl.getStrResponse();
      // ignore: avoid_print
      print(
        '[debug] content rules '
        'content=${source.ruleContent?.content ?? ''} | '
        'next=${source.ruleContent?.nextContentUrl ?? ''} | '
        'title=${source.ruleContent?.title ?? ''}',
      );
      final parsedContent = await ContentParser.parse(
        source: source,
        book: book,
        chapter: chapter,
        body: contentResponse.body,
        baseUrl: contentResponse.url,
        nextChapterUrl: nextChapterUrl,
      );
      // ignore: avoid_print
      print(
        '[debug] content parse chapter#$debugChapterIndex '
        'title=${chapter.title} | '
        'bodyUrl=${contentResponse.url} | '
        'nextUrls=${parsedContent.nextUrls.join(" | ")} | '
        'contentLen=${parsedContent.content.trim().runes.length}',
      );
    }

    for (var i = 0; i < readable.length && i < probeCount; i++) {
      final chapter = readable[i];
      final nextChapterUrl =
          readable.length > i + 1 ? readable[i + 1].url : null;
      // ignore: avoid_print
      print(
        '[debug] chapter#${i + 1} url=${chapter.url} | '
        'next=${nextChapterUrl ?? ''}',
      );
      if (debugJsIntermediate && i == 0 && source.ruleContent != null) {
        await _printJsIntermediate(source, book, chapter);
      }
      final content = await service.getContent(
        source,
        book,
        chapter,
        nextChapterUrl: nextChapterUrl,
      );
      // ignore: avoid_print
      print(
        '[debug] chapter#${i + 1} title=${chapter.title} | '
        'len=${content.trim().runes.length} | '
        'readable=${looksReadable(content)}',
      );
      // ignore: avoid_print
      print('[debug] preview=${_previewContent(content)}');
    }

    expect(book.name, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

String _previewContent(String content) {
  final normalized = content.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return '<empty>';
  const maxLength = 180;
  if (normalized.runes.length <= maxLength) {
    return normalized;
  }
  return '${String.fromCharCodes(normalized.runes.take(maxLength))}...';
}

String _previewBody(String content) {
  final normalized = content.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return '<empty>';
  const maxLength = 500;
  if (normalized.runes.length <= maxLength) {
    return normalized;
  }
  return '${String.fromCharCodes(normalized.runes.take(maxLength))}...';
}

Future<void> _printTocJsIntermediate(
  dynamic source,
  dynamic book,
  String body,
  String baseUrl,
  String chapterListRule,
) async {
  final jsRule = _extractLeadingJsRule(chapterListRule);
  if (jsRule == null) {
    // ignore: avoid_print
    print('[debug] toc js rule=<none>');
    return;
  }
  final trailingRule = chapterListRule.substring(jsRule.length).trim();
  final rule = AnalyzeRule(
    source: source,
    ruleData: book,
  ).setContent(body, baseUrl: baseUrl);
  final jsResult = await rule.getStringAsync(jsRule);
  // ignore: avoid_print
  print(
    '[debug] toc js len=${jsResult.length} '
    'trailing=${trailingRule.isEmpty ? "<none>" : trailingRule}',
  );
  // ignore: avoid_print
  print('[debug] toc js result=${_previewBody(jsResult)}');
  if (trailingRule.isEmpty || jsResult.isEmpty) {
    return;
  }
  final jsParser = AnalyzeRule(
    source: source,
    ruleData: book,
  ).setContent(jsResult, baseUrl: baseUrl);
  final jsElements = await jsParser.getElementsAsync(trailingRule);
  // ignore: avoid_print
  print('[debug] toc js trailing elements=${jsElements.length}');
}

String? _extractLeadingJsRule(String rule) {
  final match = RegExp(
    r'^\s*(<js>[\s\S]*?</js>)',
    caseSensitive: false,
  ).firstMatch(rule);
  return match?.group(1)?.trim();
}

String? _extractLeadingJsBody(String rule) {
  final trimmed = rule.trimLeft();
  if (trimmed.toLowerCase().startsWith('@js:')) {
    return trimmed.substring(4).trim();
  }
  final match = RegExp(
    r'^\s*<js>([\s\S]*?)</js>',
    caseSensitive: false,
  ).firstMatch(rule);
  return match?.group(1)?.trim();
}

Future<String?> _expandRuleJsTemplate(AnalyzeRule analyzer, String rule) async {
  final match = RegExp(
    r'<js>([\s\S]*?)</js>',
    caseSensitive: false,
  ).firstMatch(rule);
  final js = match?.group(1)?.trim();
  if (js == null || js.isEmpty) {
    return null;
  }
  final pattern = RegExp(r'\{\{([\s\S]*?)\}\}');
  final buffer = StringBuffer();
  var lastEnd = 0;
  for (final token in pattern.allMatches(js)) {
    buffer.write(js.substring(lastEnd, token.start));
    buffer.write(await analyzer.getStringAsync(token.group(1)!.trim()));
    lastEnd = token.end;
  }
  buffer.write(js.substring(lastEnd));
  return buffer.toString();
}

Future<void> _debugCompositeRule(AnalyzeRule analyzer, String ruleStr) async {
  final parts = analyzer.splitSourceRuleCacheString(ruleStr);
  dynamic current = analyzer.content;
  for (var i = 0; i < parts.length; i++) {
    final dynamic part = parts[i];
    final built = await part.makeUpRuleAsync(current, analyzer);
    // ignore: avoid_print
    print(
      '[debug] composite[$i] mode=${part.mode} '
      'dynamic=${part.isDynamic} paramSize=${part.paramSize} '
      'inputType=${current.runtimeType} built=${_previewBody(built.toString())}',
    );
    dynamic tempResult;
    final mode = part.mode.toString();
    if (current is Map && (part.paramSize as int) > 1) {
      tempResult = built;
    } else if (mode.endsWith('js')) {
      tempResult = await analyzer.evalJSAsync(built, current);
    } else if (mode.endsWith('json')) {
      tempResult = part
          .getAnalyzeByJSonPath(analyzer, current)
          .getString(built);
    } else {
      tempResult = '<skip>';
    }
    // ignore: avoid_print
    print(
      '[debug] composite[$i] temp=${tempResult == null ? "<null>" : _previewBody(tempResult.toString())}',
    );
    if ((part.isDynamic as bool) &&
        (tempResult == null || tempResult.toString().isEmpty)) {
      current = built;
    } else {
      current = tempResult;
    }
    // ignore: avoid_print
    print(
      '[debug] composite[$i] next=${current == null ? "<null>" : _previewBody(current.toString())}',
    );
  }
}

Future<void> _printJsIntermediate(
  dynamic source,
  dynamic book,
  dynamic chapter,
) async {
  final analyzeUrl = await AnalyzeUrl.create(
    chapter.url,
    source: source,
    ruleData: book,
  );
  final response = await analyzeUrl.getStrResponse();
  final rule = AnalyzeRule(
    source: source,
    ruleData: book,
  ).setContent(response.body, baseUrl: response.url).setChapter(chapter);

  final intermediate = await rule.evalJSAsync(r'''
      jms = JSON.parse(result);
      jm = String(jms.body.content).split("a2o@");
      key = "S3VqaWFuZ0FwcDc0NzYwNQ==";
      iv = jm[0];
      data = jm[1];
      decrypted = java.aesBase64DecodeToString(
        data,
        java.base64Decode(key),
        "AES/CBC/PKCS5Padding",
        java.base64Decode(iv)
      );
      decoded = "";
      withDecoded = "";
      bridgeBufferLength = -1;
      strBytesRaw = "";
      strBytesType = "";
      strBytesKeys = "";
      if (decrypted) {
        try {
          rawBytes = sendMessage("strToBytes", JSON.stringify([" ", "UTF-8"]));
          strBytesRaw = JSON.stringify(rawBytes);
          strBytesType = typeof rawBytes;
          if (rawBytes && typeof rawBytes === "object") {
            strBytesKeys = Object.keys(rawBytes).join(",");
          }
        } catch (e) {
          strBytesRaw = "RAW_ERROR:" + e;
        }
        try {
          decoded = java.gzipToString(
            java.base64DecodeToByteArray(decrypted),
            "UTF-8"
          );
        } catch (e) {
          decoded = "GZIP_ERROR:" + e;
        }
        try {
          var javaImport = new JavaImporter();
          javaImport.importPackage(
            Packages.java.lang,
            Packages.java.io,
            Packages.java.util,
            Packages.java.util.zip
          );
          with (javaImport) {
            function decodeWithBridge(content) {
              decodeWithBridge = Base64.getDecoder().decode(String(content));
              byteArrayOutputStream = new ByteArrayOutputStream();
              byteArrayInputStream = new ByteArrayInputStream(decodeWithBridge);
              gZIPInputStream = new GZIPInputStream(byteArrayInputStream);
              bArr = String(" ").getBytes();
              bridgeBufferLength = bArr.length;
              while (true) {
                read = gZIPInputStream.read(bArr);
                if (read > 0) {
                  byteArrayOutputStream.write(bArr, 0, read);
                } else {
                  gZIPInputStream.close();
                  byteArrayInputStream.close();
                  byteArrayOutputStream.close();
                  return byteArrayOutputStream.toString();
                }
              }
            }
          }
          withDecoded = decodeWithBridge(decrypted);
        } catch (e) {
          withDecoded = "WITH_ERROR:" + e;
        }
      }
      JSON.stringify({
        iv: iv,
        decryptedLength: decrypted ? String(decrypted).length : 0,
        decryptedPreview: decrypted ? String(decrypted).substring(0, Math.min(120, String(decrypted).length)) : "",
        decodedLength: decoded ? String(decoded).length : 0,
        decodedPreview: decoded ? String(decoded).substring(0, Math.min(180, String(decoded).length)) : "",
        strBytesRaw: strBytesRaw,
        strBytesType: strBytesType,
        strBytesKeys: strBytesKeys,
        bridgeBufferLength: bridgeBufferLength,
        withDecodedLength: withDecoded ? String(withDecoded).length : 0,
        withDecodedPreview: withDecoded ? String(withDecoded).substring(0, Math.min(180, String(withDecoded).length)) : ""
      });
    ''', response.body);
  // ignore: avoid_print
  print('[debug] js intermediate=$intermediate');

  final rawContent = await rule.getStringAsync(
    source.ruleContent?.content ?? '',
    unescape: false,
  );
  // ignore: avoid_print
  print(
    '[debug] raw rule output len=${rawContent.trim().runes.length} '
    'preview=${_previewContent(rawContent)}',
  );
}
