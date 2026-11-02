import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_reading_state.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/book_update_service.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/core/di/injection.dart';

enum BookshelfSortMode {
  custom,
  recentRead,
  addedTime,
  updateTime,
  bookName,
  author,
}

extension BookshelfSortModeLabel on BookshelfSortMode {
  String get label {
    return switch (this) {
      BookshelfSortMode.custom => '自訂排序',
      BookshelfSortMode.recentRead => '最近閱讀',
      BookshelfSortMode.addedTime => '加入時間',
      BookshelfSortMode.updateTime => '更新時間',
      BookshelfSortMode.bookName => '書名',
      BookshelfSortMode.author => '作者',
    };
  }
}

/// 書架骨架照著畫的一本書：原始的書名與作者，畫的時候再轉成目前的中文
/// 顯示方式。
typedef ShelfSkeletonTitle = ({String name, String author});

Future<void> _keepWithDownloadService(
  String bookUrl, {
  bool hasNewChapters = false,
}) => DownloadService().keepShelfBookDownloaded(
  bookUrl,
  hasNewChapters: hasNewChapters,
);

/// BookshelfProvider 的基礎狀態與 DAO 定義
abstract class BookshelfProviderBase extends ChangeNotifier {
  Future<void> loadBooks();

  /// 進行中的讀取（[loadBooks]）都讀完時完成；沒有在讀時馬上完成。要等
  /// 「書架讀完」的地方等這個，不等通知：讀回來的書沒變時不通知。
  Future<void> get loaded;

  final BookDao bookDao = getIt<BookDao>();
  final BookSourceDao sourceDao = getIt<BookSourceDao>();
  final BookSourceService service = BookSourceService();
  final ChapterDao chapterDao = getIt<ChapterDao>();

  List<Book> books = [];
  bool isLoading = false;
  String? loadErrorMessage;

  final Map<String, _ShelfCardBook> _cardBooks = {};

  /// 一張書卡要畫的那本書：書架重讀時這本書畫面上看得到的內容（書名、
  /// 作者、封面、進度）變了才通知，只有這張書卡重建；清單本身（本數、
  /// 順序）變了才通知整頁（ADR 0029）。[book] 是書卡建立時手上的那一本，
  /// 移出書架、淡出中的書照它畫。
  ValueListenable<Book> bookListenable(Book book) =>
      _cardBooks.putIfAbsent(book.bookUrl, () => _ShelfCardBook(book));

  /// 書架上這本書現在的樣子：點開、長按選單這類動作在按下的那一刻用它，
  /// 不用書卡畫的時候手上那一本（書卡只在看得到的內容變了才重建，閱讀
  /// 位置、自動檢查更新這些看不到的欄位可能已經換過）。不在書架上（淡出中）
  /// 時就是 [shown]。
  Book current(Book shown) {
    final card = _cardBooks[shown.bookUrl];
    if (card != null) return card.value;
    for (final book in books) {
      if (book.bookUrl == shown.bookUrl) return book;
    }
    return shown;
  }

  /// 把 [books] 交給各張書卡；畫面上的內容沒變的書卡不通知。
  @protected
  void publishBooks() {
    final shelf = {for (final book in books) book.bookUrl: book};
    // 移出書架的書不再更新；淡出中的書卡可能還聽著，不釋放。
    _cardBooks.removeWhere((url, _) => !shelf.containsKey(url));
    for (final MapEntry(key: url, value: card) in _cardBooks.entries) {
      card.update(shelf[url]!);
    }
  }

  /// 上次書架讀完時的本數，初次載入的骨架畫一樣多本；從沒讀過時為 null。
  int? lastBookCount;

  /// 上次書架前面幾本的書名與作者（依當時的排序），初次載入的骨架照它們
  /// 的長度畫。
  List<ShelfSkeletonTitle> lastShelfTitles = const [];

  bool isGridView = defaultGridView;
  bool showLastUpdate = defaultShowLastUpdate;
  BookshelfSortMode sortMode = defaultSortMode;

  /// 沒存過（或同步改回預設）時的樣子。
  static const bool defaultGridView = true;
  static const bool defaultShowLastUpdate = false;
  static const BookshelfSortMode defaultSortMode = BookshelfSortMode.recentRead;

  int updatingCount = 0;

  /// 書架自動下載，預設交給 [DownloadService]。
  final ShelfBookDownloader keepBookDownloaded;

  /// 抓書源上的詳情與目錄寫回書，與書籍詳情的「檢查更新」共用進行中的檢查。
  late final BookUpdateService updates = BookUpdateService(
    keepDownloaded: keepBookDownloaded,
    bookDao: bookDao,
  );

  /// 排定書卡角標消失的計時，預設 [Timer.new]。
  final Timer Function(Duration duration, void Function() callback) startTimer;

  BookshelfProviderBase({
    ShelfBookDownloader? keepBookDownloaded,
    Timer Function(Duration duration, void Function() callback)? startTimer,
  }) : keepBookDownloaded = keepBookDownloaded ?? _keepWithDownloadService,
       startTimer = startTimer ?? Timer.new;

  bool _disposed = false;

  /// 背景檢查、載入等非同步工作可能在 provider 釋放後才結束，結束時的通知
  /// 不再送出。
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cardBooks.clear();
    super.dispose();
  }
}

/// 一張書卡的書：一直拿著最新的那一本（點開時用），書卡上看得到的內容
/// 變了才通知。
class _ShelfCardBook extends ChangeNotifier implements ValueListenable<Book> {
  _ShelfCardBook(this._book) : _face = _faceOf(_book);

  Book _book;

  /// 上次通知書卡時，書卡上看得到的那組值。比的是這份當時抄下來的值，
  /// 不是書物件本身：閱讀器會直接改它手上那本書（就是書卡拿著的同一個
  /// 物件）的章節與時間，拿物件比，讀回來的新書和被改過的舊物件一樣，
  /// 進度線就停在舊的樣子。
  _CardFace _face;

  @override
  Book get value => _book;

  void update(Book book) {
    _book = book;
    final face = _faceOf(book);
    if (face == _face) return;
    _face = face;
    notifyListeners();
  }

  /// 書卡（網格與列表）上畫得到的東西：書名、作者、封面、是否在書架上
  /// （統一封面看它）、進度線。
  static _CardFace _faceOf(Book book) => (
    name: book.name,
    author: book.author,
    cover: book.getDisplayCover(),
    isInBookshelf: book.isInBookshelf,
    type: book.type,
    totalChapterNum: book.totalChapterNum,
    chapterIndex: book.chapterIndex,
    startedReading: book.hasStartedReading,
  );
}

typedef _CardFace = ({
  String name,
  String author,
  String? cover,
  bool isInBookshelf,
  int type,
  int totalChapterNum,
  int chapterIndex,
  bool startedReading,
});
