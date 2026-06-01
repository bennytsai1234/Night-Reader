import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';

void main() {
  group('Database optimizations', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('creates performance indexes on fresh databases', () async {
      final rows =
          await db.customSelect('''
                SELECT name
                FROM sqlite_master
                WHERE type = 'index'
                  AND name LIKE 'idx_%'
                ORDER BY name
                ''').get();
      final names = rows.map((row) => row.read<String>('name')).toSet();

      expect(
        names,
        containsAll({
          'idx_books_bookshelf_recent',
          'idx_chapters_book_index',
          'idx_reader_content_book_status_index',
          'idx_book_sources_order',
          'idx_search_books_name_author_order',
          'idx_download_tasks_status',
        }),
      );
    });

    test(
      'reader content presence queries avoid loading full entries',
      () async {
        final contentKey = ReaderChapterContentDao.contentKey(
          origin: 'https://source.example',
          bookUrl: 'https://book.example/1',
          chapterUrl: 'https://book.example/1/1',
        );

        await db.readerChapterContentDao.saveContent(
          contentKey: contentKey,
          origin: 'https://source.example',
          bookUrl: 'https://book.example/1',
          chapterUrl: 'https://book.example/1/1',
          chapterIndex: 1,
          content: '正文內容',
          updatedAt: 1,
        );

        expect(
          await db.readerChapterContentDao.hasReadyContent(
            contentKey: contentKey,
          ),
          isTrue,
        );
        expect(
          await db.readerChapterContentDao.getStoredChapterIndices(
            origin: 'https://source.example',
            bookUrl: 'https://book.example/1',
          ),
          {1},
        );
      },
    );
  });
}
