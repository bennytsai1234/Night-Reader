import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pool/pool.dart';
import 'package:night_reader/core/config/app_config.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/book_update_service.dart';
import 'package:night_reader/core/services/bookshelf_exchange_service.dart';

import 'bookshelf_provider_base.dart';

///BookshelfProvider 的更新與網絡同步邏輯擴展
mixin BookshelfUpdateMixin on BookshelfProviderBase {
  /// 書架更新同時檢查的書數，與目錄多頁抓取的並行數（4）相同：書架上
  /// 幾十本書不會一起發請求、一起在 UI isolate 上解析目錄。
  static const int _refreshConcurrency = 4;

  Future<void>? _refreshing;

  /// 這次檢查有沒有使用者手動下拉（包括下拉時接上已在跑的那次）；只有手動
  /// 時才標出檢查失敗的書。
  bool _userRefreshed = false;

  /// 書架檢查後角標掛多久（DESIGN.md「書籍卡片與清單」）。
  static const Duration updateBadgeDuration = Duration(seconds: 5);

  /// 上一次書架檢查的結果，只留有新章節或檢查失敗的書；不存檔，
  /// [updateBadgeDuration] 後一起清掉。書卡各自聽這個訊號，角標出現與消失
  /// 只重建那幾張書卡，不通知整個書架（ADR 0018）。
  final ValueNotifier<Map<String, BookUpdateCheckResult>> updateBadges =
      ValueNotifier(const {});
  Timer? _updateBadgeTimer;

  /// 書卡角標：有新章節（+N）或檢查失敗（!）；沒有就是 null。
  BookUpdateCheckResult? updateBadgeOf(String bookUrl) =>
      updateBadges.value[bookUrl];

  /// 下拉或開 App 的書架檢查正在進行；書架頁首的「書架」字樣這時掃過淡墨
  /// 流光。多選的「檢查更新」看 [updatingCount]，不算在這裡。只有頁首標題
  /// 聽它：檢查在開 App 的換場一結束就開始，通知整個書架會讓剛換好的書架
  /// 整頁重建一次。
  final ValueNotifier<bool> checkingShelf = ValueNotifier(false);

  /// 開 App 後在背景做的事：先把書架上還沒下載完整的書排進下載（ADR
  /// 0007），再檢查更新（「啟動時檢查書架更新」關掉時不檢查）。
  Future<void> onAppLaunch() async {
    await keepShelfDownloaded();
    if (_closed || !AppConfig.autoRefresh) return;
    await refreshBookshelf();
  }

  /// 書架上每本網路書都排一次自動下載；不看 [Book.canUpdate]，那只管要不要
  /// 檢查新章節，目錄裡已有的章節照樣下載。
  Future<void> keepShelfDownloaded() async {
    final List<Book> shelf;
    try {
      shelf = await bookDao.getInBookshelf();
    } catch (error) {
      AppLog.w('書架自動下載讀取書架失敗: $error');
      return;
    }
    for (final book in shelf) {
      if (book.isLocal) continue;
      await _keepDownloaded(book.bookUrl);
    }
  }

  Future<void> _keepDownloaded(
    String bookUrl, {
    bool hasNewChapters = false,
  }) async {
    try {
      await keepBookDownloaded(bookUrl, hasNewChapters: hasNewChapters);
    } catch (error) {
      AppLog.w('書架自動下載排程失敗 $bookUrl: $error');
    }
  }

  /// 下拉與啟動時的書架更新：在背景檢查，不轉圈，不改 [updatingCount]（那是
  /// 多選檢查的進度）；檢查完在書卡上掛 [updateBadgeDuration] 的角標，有新
  /// 章節一律標，檢查失敗只在 [userInitiated]（手動下拉）時標。略過本地書與
  /// 使用者關掉「自動檢查更新」的書；已在檢查時沿用同一次，不重複發請求。
  Future<void> refreshBookshelf({bool userInitiated = false}) {
    // 書架關掉之後才輪到的檢查（例如開 App 補完下載時）不開始：訊號已釋放。
    if (_closed) return Future<void>.value();
    if (userInitiated) _userRefreshed = true;
    final running = _refreshing;
    if (running != null) return running;
    final refresh = _refreshAll().whenComplete(() {
      _refreshing = null;
      _userRefreshed = false;
      if (!_closed) checkingShelf.value = false;
    });
    _refreshing = refresh;
    checkingShelf.value = true;
    return refresh;
  }

  Future<void> _refreshAll() async {
    // 從資料庫讀：啟動時書架可能還沒載入完，記憶體裡的清單也可能是舊的。
    final targets = (await bookDao.getInBookshelf())
        .where((book) => !book.isLocal && book.canUpdate)
        .toList();
    if (targets.isEmpty) return;

    final pool = Pool(_refreshConcurrency);
    final List<BookUpdateCheckResult?> results;
    try {
      results = await Future.wait([
        for (final book in targets)
          pool.withResource(() async {
            try {
              return await checkBookUpdate(book);
            } catch (_) {
              return null;
            }
          }),
      ]);
    } finally {
      await pool.close();
    }
    _updateBadgeTimer?.cancel();
    final badges = {
      for (final result in results.nonNulls)
        if (result.hasUpdate || (result.failed && _userRefreshed))
          result.bookUrl: result,
    };
    // 先讀回更新過的書再掛角標：書卡換上新的章節數與角標是同一次更新。
    await loadBooks();
    if (_closed) return;
    updateBadges.value = badges;
    if (badges.isEmpty) return;
    _updateBadgeTimer = startTimer(updateBadgeDuration, () {
      _updateBadgeTimer = null;
      updateBadges.value = const {};
    });
  }

  /// 檢查跑完前書架就關掉時，訊號已經釋放，不再設值。
  bool _closed = false;

  @override
  void dispose() {
    _closed = true;
    _updateBadgeTimer?.cancel();
    updateBadges.dispose();
    checkingShelf.dispose();
    super.dispose();
  }

  /// 抓書源上的詳情與目錄寫回這本書；同一本書已在檢查（包括書籍詳情發起
  /// 的）時接上同一次。書架的每一種檢查（啟動、下拉、單本、多選）都從這裡
  /// 進來。
  Future<BookUpdateCheckResult> checkBookUpdate(Book book) =>
      updates.check(book);

  /// 這本書是否參與下拉與啟動時的書架更新；明確對它按「檢查更新」時照查。
  Future<void> setBookCanUpdate(Book book, bool value) async {
    await bookDao.updateCanUpdate(book.bookUrl, value);
    book.canUpdate = value;
    notifyListeners();
  }

  /// 明確選了這些書才檢查，所以不看 [Book.canUpdate]。
  Future<List<BookUpdateCheckResult>> batchCheckUpdate(Set<String> urls) async {
    final selected = await _booksForUrls(urls);
    final results = <BookUpdateCheckResult>[];
    // 以增減計數：單本與批次的檢查可能同時進行，先結束的那次只扣掉自己的
    // 剩餘數，不會把另一次的進度歸零。
    var remaining = selected.where((book) => !book.isLocal).length;
    updatingCount += remaining;
    notifyListeners();
    try {
      for (final book in selected) {
        results.add(await checkBookUpdate(book));
        if (!book.isLocal && remaining > 0) {
          remaining--;
          updatingCount--;
          notifyListeners();
        }
      }
      await loadBooks();
      return results;
    } finally {
      updatingCount -= remaining;
      notifyListeners();
    }
  }

  Future<List<Book>> _booksForUrls(Set<String> urls) async {
    final selected = <Book>[];
    for (final url in urls) {
      final book = await bookDao.getByUrl(url);
      if (book != null) selected.add(book);
    }
    return selected;
  }

  Future<void> importBookshelfFromUrl(String url) async {
    isLoading = true;
    notifyListeners();
    try {
      await BookshelfExchangeService().importFromUrl(url);
      await loadBooks();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
