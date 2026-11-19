import 'package:dio/dio.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';

/// AI 找書的工具實際去拿的東西（ADR 0060）：搜尋、詳情、正文、發現頁與書架。
/// 正式的實作照搜尋頁、書籍詳情與閱讀器同一套引擎（`AppAiFindLibrary`），
/// 測試換成記憶體裡的書。每個方法都收 [CancelToken]：按暫停或結束時正在跑的
/// 搜尋或抓取要跟著停（`agent_loop` 在工具回來後才看取消）。
abstract interface class AiFindLibrary {
  /// 照搜尋頁的搜尋範圍（開始找書時的那一份）搜 [keyword]，只回 [kind]
  /// 這一類的書；同一本合併成一張卡（[SearchBook.origins] 是有這本的書源）。
  Future<AiFindSearchResult> search(
    String keyword,
    BookSourceKind kind,
    CancelToken cancelToken,
  );

  /// 書籍詳情：照卡片的來源抓詳情頁。
  Future<Book> detail(SearchBook book, CancelToken cancelToken);

  /// 第 [number] 章（從 1 數，不算分卷標題；-1 是最後一章，`aiFindLastChapter`）
  /// 的正文純文字。讀不到時丟
  /// [AiFindUnreadable]，訊息說為什麼（付費章節、要登入、抓不到、沒有這一章）。
  Future<AiFindChapter> chapter(
    SearchBook book,
    int number,
    CancelToken cancelToken,
  );

  /// 搜尋範圍裡有發現頁的書源。
  Future<List<AiFindExploreSource>> exploreSources();

  /// 一個書源發現頁的分類（排行、分類這些清單的名稱）。
  Future<List<String>> exploreCategories(
    AiFindExploreSource source,
    CancelToken cancelToken,
  );

  /// 發現頁第 [category] 個分類（從 0 數）的第 [page] 頁（從 1 數）。
  Future<List<SearchBook>> exploreBooks(
    AiFindExploreSource source,
    int category,
    int page,
    CancelToken cancelToken,
  );

  /// 書架上的書與閱讀紀錄（含已經移出書架的）。
  Future<List<AiFindShelfEntry>> shelf();

  /// [name] 這部作品在中文維基百科的條目與各地寫法（查作品別名）；沒有條目
  /// 是 null。連不上時丟 [AiFindUnreadable]。
  Future<AiFindWorkNames?> workNames(String name, CancelToken cancelToken);

  /// 這次抓過的書源的秘密（登入資料、Cookie、書源變數，ADR 0054）：工具結果
  /// 接進對話、寫進紀錄前換掉（`AgentTask.redact`）。
  Set<String> get secrets;
}

/// 一次搜尋：[books] 是合併後的書，照搜尋頁的相關度排；[tiers] 和它一一對應，
/// 是搜尋頁的分段（0 完全相符、1 部分相符、2 其他結果）。[sources] 是送了幾個
/// 書源，[failed] 是其中幾個出錯或逾時，[pending] 是到時限還沒回來、不等了的
/// （AI 拿這些判斷搜不到是不是因為書源）。
typedef AiFindSearchResult = ({
  List<SearchBook> books,
  List<int> tiers,
  int sources,
  int failed,
  int pending,
});

/// 一部作品在中文維基百科：[title] 是條目名，[names] 是各地的寫法
/// （「台灣」「中國大陸」「香港」對寫法），[aliases] 是轉到這個條目的名稱
/// （譯名、簡稱、原文名），[intro] 是條目開頭一段，[others] 是同一個詞搜到的
/// 其他條目（名稱有歧義時讓 AI 選）。
typedef AiFindWorkNames = ({
  String title,
  Map<String, String> names,
  List<String> aliases,
  String intro,
  List<String> others,
});

/// 讀不到這一章：[message] 照實回給 AI。
class AiFindUnreadable implements Exception {
  const AiFindUnreadable(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 一章：[number] 是第幾章，[total] 是這本書有幾章（不算分卷標題）。
typedef AiFindChapter = ({String title, String text, int number, int total});

/// 有發現頁的書源：[url] 是書源網址。
typedef AiFindExploreSource = ({String url, String name, BookSourceKind kind});

/// 書架上的一本或一筆閱讀紀錄。[readSeconds] 是讀了多久（各台加總），
/// [chapter] 是讀到哪一章的章名，[chapterIndex]／[chapterTotal] 從 1 數；
/// [category] 與 [intro] 是書源給的分類與簡介，AI 拿來看他喜歡什麼樣的書。
/// [book] 是有書源的那本（本地書與只剩閱讀紀錄的沒有）：AI 拿它的編號看詳情、
/// 讀章節，也可以推薦它。不知道的是 null（只剩閱讀紀錄、書已經不在資料庫的，
/// 作者與類別都不知道）。
typedef AiFindShelfEntry = ({
  String name,
  String author,
  BookSourceKind? kind,
  bool onShelf,
  bool local,
  int readSeconds,
  String? chapter,
  int? chapterIndex,
  int? chapterTotal,
  String? category,
  String? intro,
  SearchBook? book,
});

/// 正文與詳情給 AI 讀的純文字：插圖換成「（插圖）」、換行標籤與網站寫成字面
/// 的 `\n`（反斜線加 n）換成換行、其他標籤拿掉、空行合併。
String aiFindPlainText(String raw) => raw
    .replaceAll(RegExp(r'\\r\\n|\\n'), '\n')
    .replaceAll(RegExp(r'<img\b[^>]*>', caseSensitive: false), '（插圖）')
    .replaceAll(RegExp(r'<br\s*/?>|</p>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .join('\n');
