import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';

class _FakeBookDao extends Fake implements BookDao {}

class _FakeChapterDao extends Fake implements ChapterDao {}

class _FakeSourceDao extends Fake implements BookSourceDao {}

void main() {
  test('既有不支援本地書不會從章節內容或快取繞過格式檢查', () async {
    final book = Book(
      bookUrl: r'local://C:\books\legacy.epub',
      origin: 'local',
      name: '舊本地書',
    );
    final repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: <BookChapter>[
        BookChapter(
          url: '${book.bookUrl}#0',
          bookUrl: book.bookUrl,
          title: '第一章',
          content: '不應繼續讀取的既有內容',
        ),
      ],
      bookDao: _FakeBookDao(),
      chapterDao: _FakeChapterDao(),
      sourceDao: _FakeSourceDao(),
    );

    await expectLater(
      repository.loadContent(0),
      throwsA(
        isA<ReaderV2ChapterRepositoryException>().having(
          (error) => error.message,
          'message',
          contains('本地書格式不受支援'),
        ),
      ),
    );
  });
}
