import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/book/book_help.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/utils/html_formatter.dart';
import 'package:night_reader/core/utils/network_utils.dart';
import 'package:night_reader/core/utils/string_utils.dart';

class BookInfoParser {
  static Future<Book> parse({
    required BookSource source,
    required Book book,
    required String body,
    required String baseUrl,
    String? redirectUrl,
  }) async {
    // 沒有詳情規則時照一份空的算（同 Legado BookSource.getBookInfoRule）：
    // 書名這類沿用書上的，目錄網址照樣退回詳情頁網址。
    final infoRule = source.ruleBookInfo ?? BookInfoRule();

    // 同 Legado（BookInfo.analyzeBookInfo）照書名、作者、分類、字數、最新
    // 章節、簡介、封面、目錄網址的順序算，每一項算完就寫到書上：後面的規則 JS
    // 讀 `book.intro` 這類欄位時拿到的是這一頁剛算出來的。用一份複本，交回前
    // 不動到傳進來的書。
    final working = book.copyWith();
    // 閱讀設定是可以改的物件，規則寫 `book.reverseToc` 時只改複本那一份。
    final readConfig = book.readConfig;
    if (readConfig != null) {
      working.readConfig = ReadConfig.fromJson(readConfig.toJson());
    }
    // [baseUrl] 是請求詳情頁的網址，[redirectUrl] 是網站轉址後回應的網址
    // （同 Legado）；沒給時是同一個。
    final pageUrl = redirectUrl ?? baseUrl;
    final rule = AnalyzeRule(
      source: source,
      ruleData: working,
    ).setContent(body, baseUrl: baseUrl, redirectUrl: pageUrl);

    try {
      // 執行 init 規則 (對標 Android BookInfoRule.init)
      // init 規則用於頁面預處理，例如 Ajax 載入或 JS 解密
      if (infoRule.init != null && infoRule.init!.isNotEmpty) {
        final initResult = rule.getElement(infoRule.init!);
        final hasInitResult =
            initResult != null &&
            (initResult is! String || initResult.trim().isNotEmpty) &&
            (initResult is! List || initResult.isNotEmpty);
        if (hasInitResult) {
          // init 規則的結果替換為新的解析內容
          rule.setContent(initResult, baseUrl: baseUrl, redirectUrl: pageUrl);
        }
      }

      // 已經有書名、作者時不拿詳情頁的蓋掉，書源寫了 canReName 才換（同
      // Legado BookInfo）：搜尋結果的書名常比詳情頁的乾淨（詳情頁多了
      // 「《》最新章節」），書名加作者也是書架、同步與換源認書的身分。
      final keepNames =
          infoRule.canReName == null || infoRule.canReName!.trim().isEmpty;
      String pick(String parsed, String current) =>
          parsed.isEmpty || (keepNames && current.isNotEmpty)
          ? current
          : parsed;

      // 書名、作者拿掉網站常帶的「作者：」「某某 著」這類字樣，和搜尋結果
      // 同一套（同 Legado BookInfo）：書名加作者是同步、書籤認書的身分，帶著
      // 字樣的話，另一個書源的同一本書對不上。
      working.name = pick(
        BookHelp.formatBookName(_format(rule.getString(infoRule.name ?? ''))),
        working.name,
      );
      working.author = pick(
        BookHelp.formatBookAuthor(
          _format(rule.getString(infoRule.author ?? '')),
        ),
        working.author,
      );
      final kind = _optional(
        '分類',
        () => rule.getStringList(infoRule.kind ?? '').join(','),
      );
      if (kind.isNotEmpty) working.kind = kind;
      final wordCount = _optional(
        '字數',
        () => StringUtils.wordCountFormat(
          rule.getString(infoRule.wordCount ?? ''),
        ),
      );
      if (wordCount.isNotEmpty) working.wordCount = wordCount;
      final latestChapterTitle = _optional(
        '最新章節',
        () => rule.getString(infoRule.lastChapter ?? ''),
      );
      if (latestChapterTitle.isNotEmpty) {
        working.latestChapterTitle = latestChapterTitle;
      }
      // 同 Legado：規則取整段 HTML（`#intro@html`）時，標籤換成換行或拿掉。
      final intro = HtmlFormatter.format(
        _optional('簡介', () => rule.getString(infoRule.intro ?? '')),
      );
      if (intro.isNotEmpty) working.intro = intro;
      final coverUrl = _optional(
        '封面',
        () => coverUrlFrom(rule.getString(infoRule.coverUrl ?? ''), pageUrl),
      );
      if (coverUrl.isNotEmpty) working.coverUrl = coverUrl;

      // 同 Legado（BookInfo.kt）：目錄網址規則沒有結果時，詳情頁就是目錄的
      // 第一頁。不照頁面上「目录」這類連結的字另找目錄頁：書源的目錄規則是
      // 照詳情頁寫的，換了起點，下一頁的規則就接不上。
      final tocUrl = rule.getString(infoRule.tocUrl ?? '', isUrl: true);
      working.tocUrl = tocUrl.isEmpty ? baseUrl : tocUrl;
      return working;
    } finally {
      rule.dispose();
    }
  }

  static String _format(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// 讀一個附帶的欄位；規則出錯時這一欄留空（沿用書上原有的值），詳情頁照常
  /// 讀完。書名、作者、目錄網址出錯仍整頁失敗。同 Legado（BookInfo.kt）。
  static String _optional(String field, String Function() read) {
    try {
      return read();
    } on ParsingException catch (error, stackTrace) {
      AppLog.e('詳情頁的$field規則解析失敗，這一欄留空', error: error, stackTrace: stackTrace);
      return '';
    }
  }

  /// 封面規則的結果（不帶 `isUrl` 讀出）補成完整網址；抓到好幾個時取第一
  /// 個，沒抓到時是空的。不帶 `isUrl`：那會在沒抓到時改回傳頁面網址（書籍
  /// 與目錄網址要這樣），封面就成了一張載不出來的網頁，清單或書籍詳情原本
  /// 有的封面也被它蓋掉。同 Legado 讀封面的做法。
  static String coverUrlFrom(String raw, String baseUrl) {
    for (final line in raw.split('\n')) {
      final url = line.trim();
      if (url.isNotEmpty) return NetworkUtils.getAbsoluteURL(baseUrl, url);
    }
    return '';
  }
}
