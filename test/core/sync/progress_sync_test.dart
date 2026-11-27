import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/local_book/local_book_service.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/sync/progress_sync.dart';
import 'package:night_reader/core/sync/sync_records.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BookDao bookDao;
  late ChapterDao chapterDao;
  late Directory dir;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bookDao = BookDao(db);
    chapterDao = ChapterDao(db);
    dir = await Directory.systemTemp.createTemp('progress_sync_txt');
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  String body(String marker) => '　　$marker${'正文內容。' * 60}\n';
  final text = '第１章 開始\n${body('甲')}第２章 中間\n${body('乙')}第３章 結尾\n${body('丙')}';

  // 舊版分章規則切的 TXT（整本一章）：另一台的進度照新目錄記「第３章」，
  // 照這台的舊目錄套用會落到別章。
  test('cloud progress is not applied in the background to a TXT that still '
      'has the old contents, and is not recorded as synced', () async {
    final file = File('${dir.path}/全形.txt');
    await file.writeAsString(text);
    final book = Book(
      bookUrl: 'local://${file.path}',
      origin: 'local',
      name: '全形',
      author: '本地',
      isInBookshelf: true,
      charset: 'UTF-8',
      fileFingerprint: 'print',
      charOffset: 10,
    );
    await bookDao.upsert(book);
    await chapterDao.insertChapters([
      BookChapter(
        url: '${book.bookUrl}#0',
        title: '正文',
        bookUrl: book.bookUrl,
        index: 0,
        start: 0,
        end: await file.length(),
      ),
    ]);
    final theirs = SyncRecord(
      time: 9,
      data: const {
        'chapterIndex': 2,
        'charOffset': 50,
        'chapterTitle': '第３章 結尾',
      },
    );
    final progress = ProgressSync(bookDao: bookDao, chapterDao: chapterDao);
    final key = ProgressSync.keyOf(book);

    expect(await progress.apply({key: theirs}), isEmpty);
    final kept = (await bookDao.getByUrl(book.bookUrl))!;
    expect(kept.chapterIndex, 0);
    expect(kept.charOffset, 10);

    // 開書重新分章之後，下一輪同步照新目錄套上。
    await LocalBookService().ensureTxtChapters(
      kept,
      bookDao: bookDao,
      chapterDao: chapterDao,
    );
    final applied = await progress.apply({key: theirs});
    expect(applied.keys, [key]);
    final moved = (await bookDao.getByUrl(book.bookUrl))!;
    expect(moved.chapterIndex, 2);
    expect(moved.charOffset, 50);
  });
}
