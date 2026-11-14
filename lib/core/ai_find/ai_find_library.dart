import 'package:dio/dio.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';

/// AI 找書的工具實際去拿的東西（ADR 0060）：搜尋、詳情、正文、發現頁與書架。
/// 正式的實作照搜尋頁、書籍詳情與閱讀器同一套引擎（`AppAiFindLibrary`），
/// 測試換成記憶體裡的書。每個方法都收 [CancelToken]：按停止時正在跑的
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

  /// 第 [number] 章（從 1 數，不算分卷標題）的正文純文字。讀不到時丟
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

  /// 這次抓過的書源的秘密（登入資料、Cookie、書源變數，ADR 0054）：工具結果
  /// 接進對話、寫進紀錄前換掉（`AgentTask.redact`）。
  Set<String> get secrets;
}

/// 一次搜尋：[books] 是合併後的書，[sources] 是送了幾個書源，[failed] 是
/// 其中幾個出錯或逾時（書源自己的問題，AI 拿它判斷搜不到是不是因為書源）。
typedef AiFindSearchResult = ({
  List<SearchBook> books,
  int sources,
  int failed,
});

/// 讀不到這一章：[message] 照實回給 AI。
class AiFindUnreadable implements Exception {
  const AiFindUnreadable(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 一章：[total] 是這本書有幾章（不算分卷標題）。
typedef AiFindChapter = ({String title, String text, int total});

/// 有發現頁的書源：[url] 是書源網址。
typedef AiFindExploreSource = ({String url, String name, BookSourceKind kind});

/// 書架上的一本或一筆閱讀紀錄。[readSeconds] 是讀了多久（各台加總），
/// [chapter] 是讀到哪一章的章名，[chapterIndex]／[chapterTotal] 從 1 數；
/// 不知道的是 null（只剩閱讀紀錄、書已經不在資料庫的，作者與類別都不知道）。
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
});

/// 正文與詳情給 AI 讀的純文字：插圖換成「（插圖）」、換行標籤換成換行、其他
/// 標籤拿掉、空行合併。
String aiFindPlainText(String raw) => raw
    .replaceAll(RegExp(r'<img\b[^>]*>', caseSensitive: false), '（插圖）')
    .replaceAll(RegExp(r'<br\s*/?>|</p>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .join('\n');
