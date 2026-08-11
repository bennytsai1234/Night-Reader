import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/bookshelf_state_tracker.dart';

class _DeferredBookDao extends Fake implements BookDao {
  final List<Completer<List<Book>>> requests = <Completer<List<Book>>>[];

  @override
  Future<List<Book>> getInBookshelf() {
    final request = Completer<List<Book>>();
    requests.add(request);
    return request.future;
  }
}

Book _book(String url) {
  return Book(
    bookUrl: url,
    origin: 'https://source.example',
    name: url,
    isInBookshelf: true,
  );
}

void main() {
  test('較舊的 refresh 晚完成時不會覆寫最新書架快照', () async {
    final dao = _DeferredBookDao();
    final tracker = BookshelfStateTracker(
      bookDao: dao,
      eventBus: AppEventBus(),
    );
    var changedCount = 0;

    final older = tracker.refresh(onChanged: () => changedCount++);
    final newer = tracker.refresh(onChanged: () => changedCount++);
    dao.requests[1].complete(<Book>[_book('new')]);
    await newer;
    dao.requests[0].complete(<Book>[_book('old')]);
    await older;

    expect(tracker.containsBook(_book('new')), isTrue);
    expect(tracker.containsBook(_book('old')), isFalse);
    expect(changedCount, 1);
    tracker.dispose();
  });

  test('dispose 後不套用尚未完成的 refresh', () async {
    final dao = _DeferredBookDao();
    final tracker = BookshelfStateTracker(
      bookDao: dao,
      eventBus: AppEventBus(),
    );
    var changedCount = 0;

    final pending = tracker.refresh(onChanged: () => changedCount++);
    tracker.dispose();
    dao.requests.single.complete(<Book>[_book('late')]);
    await pending;

    expect(tracker.containsBook(_book('late')), isFalse);
    expect(changedCount, 0);
  });

  test('較舊的 initialize 晚完成時不會換回舊的事件 callback', () async {
    final dao = _DeferredBookDao();
    final eventBus = AppEventBus();
    final tracker = BookshelfStateTracker(bookDao: dao, eventBus: eventBus);
    var olderChangedCount = 0;
    var newerChangedCount = 0;

    final older = tracker.initialize(onChanged: () => olderChangedCount++);
    final newer = tracker.initialize(onChanged: () => newerChangedCount++);
    dao.requests[1].complete(<Book>[_book('new')]);
    await newer;
    dao.requests[0].complete(<Book>[_book('old')]);
    await older;

    eventBus.fire(AppEventBus.upBookshelf);
    await Future<void>.delayed(Duration.zero);
    dao.requests[2].complete(<Book>[_book('latest')]);
    await Future<void>.delayed(Duration.zero);

    expect(olderChangedCount, 0);
    expect(newerChangedCount, 1);
    expect(tracker.containsBook(_book('latest')), isTrue);
    tracker.dispose();
  });
}
