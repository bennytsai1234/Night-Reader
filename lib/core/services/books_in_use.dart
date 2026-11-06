import 'dart:async';

import 'package:night_reader/core/engine/app_event_bus.dart';

/// 正開著的書：書籍詳情與閱讀器開著時各登記一筆，關掉時放掉。清掉書架以外
/// 的書時跳過這些（`BookStorageService.discardUnshelvedBooks`）：開 App 後
/// 清理還在跑時就能打開書，從閱讀器也能進設定還原備份。照書的網址記，換源
/// （[AppEventBus.bookSwitched]）時跟著換成新網址。
class BooksInUse {
  BooksInUse._();

  static final Set<BookInUse> _held = {};
  static StreamSubscription<AppEvent>? _switches;

  static BookInUse hold(String bookUrl) {
    _switches ??= AppEventBus().onName(AppEventBus.bookSwitched).listen((
      event,
    ) {
      final switched = event.data as BookSwitchedEvent;
      for (final book in _held) {
        if (book.bookUrl == switched.fromBookUrl) {
          book.bookUrl = switched.toBookUrl;
        }
      }
    });
    final book = BookInUse._(bookUrl);
    _held.add(book);
    return book;
  }

  /// 現在開著的書的網址。
  static Set<String> get bookUrls => {for (final book in _held) book.bookUrl};
}

/// [BooksInUse.hold] 登記的一筆。
final class BookInUse {
  BookInUse._(this.bookUrl);

  String bookUrl;

  void release() => BooksInUse._held.remove(this);
}
