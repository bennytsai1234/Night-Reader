import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/search_book.dart';

class BookshelfStateTracker {
  final BookDao _bookDao;
  final AppEventBus _eventBus;
  final Set<String> _bookshelfKeys = {};

  StreamSubscription<AppEvent>? _bookshelfSubscription;

  BookshelfStateTracker({BookDao? bookDao, AppEventBus? eventBus})
    : _bookDao = bookDao ?? getIt<BookDao>(),
      _eventBus = eventBus ?? AppEventBus();

  Future<void> initialize({VoidCallback? onChanged}) async {
    await refresh();
    _subscribeBookshelfUpdates(onChanged: onChanged);
  }

  Future<void> refresh({VoidCallback? onChanged}) async {
    final books = await _bookDao.getInBookshelf();
    _bookshelfKeys
      ..clear()
      ..addAll(books.expand(_bookshelfKeysForBook));
    onChanged?.call();
  }

  bool containsSearchBook(SearchBook book) {
    return contains(
      name: book.name,
      author: book.author,
      bookUrl: book.bookUrl,
      origin: book.origin,
    );
  }

  bool containsBook(Book book) {
    return contains(
      name: book.name,
      author: book.author,
      bookUrl: book.bookUrl,
      origin: book.origin,
    );
  }

  bool contains({
    required String name,
    required String? author,
    required String bookUrl,
    String? origin,
  }) {
    final exactKey = makeBookshelfKey(bookUrl: bookUrl, origin: origin);
    return _bookshelfKeys.contains(exactKey);
  }

  void dispose() {
    _bookshelfSubscription?.cancel();
  }

  void _subscribeBookshelfUpdates({VoidCallback? onChanged}) {
    _bookshelfSubscription?.cancel();
    _bookshelfSubscription = _eventBus
        .onName(AppEventBus.upBookshelf)
        .listen((_) => unawaited(refresh(onChanged: onChanged)));
  }

  Iterable<String> _bookshelfKeysForBook(Book book) sync* {
    final normalizedKey = makeBookshelfKey(
      bookUrl: book.bookUrl,
      origin: book.origin,
    );
    if (normalizedKey.isNotEmpty) {
      yield normalizedKey;
    }
  }

  static String makeBookshelfKey({required String bookUrl, String? origin}) {
    final normalizedUrl = bookUrl.trim();
    if (normalizedUrl.isEmpty) return '';
    final normalizedOrigin = origin?.trim() ?? '';
    return normalizedOrigin.isEmpty
        ? normalizedUrl
        : '$normalizedOrigin\n$normalizedUrl';
  }
}
