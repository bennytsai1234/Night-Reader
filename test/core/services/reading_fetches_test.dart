import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/chapter_content_preparation_pipeline.dart';
import 'package:night_reader/core/services/reader_chapter_content_storage.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';
import 'package:night_reader/core/services/background_work/reading_fetches.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// 閱讀器抓這一章時，背景搜尋等得到它抓完嗎。
  Future<bool> idleWhileFetching(Book book) async {
    final fetch = Completer<ChapterContentPreparationResult>();
    final asked = Completer<void>();
    final storage = ReaderChapterContentStorage(
      book: book,
      contentStore: ReaderChapterContentStore(
        chapterDao: ChapterDao(db),
        contentDao: ReaderChapterContentDao(db),
      ),
      materialize:
          ({
            required chapterIndex,
            required chapter,
            sourceOverride,
            required forceRefresh,
            required saveChapterMetadata,
            required maxAttempts,
          }) {
            asked.complete();
            return fetch.future;
          },
    );
    final reading = storage.read(
      chapterIndex: 0,
      chapter: BookChapter(
        url: '${book.bookUrl}/1',
        title: '第一章',
        bookUrl: book.bookUrl,
      ),
    );
    // 存著的正文找過、要向書源抓了。
    await asked.future;
    var idle = false;
    unawaited(ReadingFetches.instance.idle().then((_) => idle = true));
    await pumpEventQueue();
    final waited = !idle;
    fetch.complete(ChapterContentPreparationResult.failed('抓不到'));
    await reading;
    await pumpEventQueue();
    expect(idle, isTrue);
    return waited;
  }

  test('a background search waits while the reader fetches a chapter '
      'it does not have', () async {
    final waited = await idleWhileFetching(
      Book(
        bookUrl: 'https://site.example/book',
        origin: 'https://site.example',
      ),
    );
    expect(waited, isTrue);
  });

  test('reading a local book does not hold back a background search', () async {
    final waited = await idleWhileFetching(
      Book(bookUrl: 'local://book.txt', origin: 'local'),
    );
    expect(waited, isFalse);
  });

  testWidgets('a stuck fetch holds a background search back for ten seconds '
      'at most', (tester) async {
    final fetch = Completer<void>();
    unawaited(ReadingFetches.instance.track(() => fetch.future));
    var idle = false;
    unawaited(ReadingFetches.instance.idle().then((_) => idle = true));
    await tester.pump(const Duration(seconds: 9));
    expect(idle, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(idle, isTrue);
    fetch.complete();
  });
}
