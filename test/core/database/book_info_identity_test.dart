import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/bookmark.dart';
import 'package:night_reader/core/models/highlight.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Book book(String url, {int type = 0}) => Book(
    bookUrl: url,
    origin: 'https://example.com',
    name: '原書名',
    author: '原作者',
    type: type,
  )..isInBookshelf = true;

  Future<void> addMarks(Book book, {int bookmarkId = 101, int highlightId = 201}) async {
    await db.bookmarkDao.upsertAll([
      Bookmark(
        id: bookmarkId,
        bookName: book.recordName,
        bookAuthor: book.author,
        chapterIndex: 3,
        chapterTitle: '第三章',
        charOffset: 17,
        anchor: '原文前後',
        excerpt: '書籤內容',
      ),
    ]);
    await db.highlightDao.upsertAll([
      Highlight(
        id: highlightId,
        bookName: book.recordName,
        bookAuthor: book.author,
        chapterIndex: 3,
        chapterTitle: '第三章',
        charOffset: 17,
        anchor: '原文前後',
        quote: '標註內容',
        color: HighlightColor.green,
        style: HighlightStyle.underline,
        note: '我的備忘',
      ),
    ]);
  }

  for (final change in [
    (title: '書名', name: '新書名', author: '原作者'),
    (title: '作者', name: '原書名', author: '新作者'),
    (title: '書名與作者', name: '新書名', author: '新作者'),
  ]) {
    test('編輯${change.title}會一起搬書籤與標註，保留內容和錨點', () async {
      final before = book('https://example.com/book1');
      await db.bookDao.upsert(before);
      await addMarks(before);

      final after = before.copyWith(name: change.name, author: change.author);
      await db.bookDao.upsertEditedBookInfo(before, after);

      final storedBook = await db.bookDao.getByUrl(before.bookUrl);
      expect(storedBook?.name, change.name);
      expect(storedBook?.author, change.author);
      expect(
        (await db.bookDao.getByRecordName(after.recordName))
            .any((item) => item.bookUrl == after.bookUrl),
        isTrue,
      );

      final bookmarks = await db.bookmarkDao.getAll();
      expect(bookmarks, hasLength(1));
      final mark = bookmarks.single;
      expect(mark.id, 101);
      expect(mark.bookName, after.recordName);
      expect(mark.bookAuthor, after.author);
      expect(mark.chapterIndex, 3);
      expect(mark.chapterTitle, '第三章');
      expect(mark.charOffset, 17);
      expect(mark.anchor, '原文前後');
      expect(mark.excerpt, '書籤內容');

      final highlights = await db.highlightDao.getAll();
      expect(highlights, hasLength(1));
      final highlight = highlights.single;
      expect(highlight.id, 201);
      expect(highlight.bookName, after.recordName);
      expect(highlight.bookAuthor, after.author);
      expect(highlight.chapterIndex, 3);
      expect(highlight.chapterTitle, '第三章');
      expect(highlight.charOffset, 17);
      expect(highlight.anchor, '原文前後');
      expect(highlight.quote, '標註內容');
      expect(highlight.color, HighlightColor.green);
      expect(highlight.style, HighlightStyle.underline);
      expect(highlight.note, '我的備忘');
    });
  }

  test('改漫畫書名不會搬走同名小說的書籤與標註', () async {
    final novel = book('https://example.com/novel');
    final comic = book(
      'https://example.com/comic',
      type: BookSourceKind.comic.bookType,
    );
    await db.bookDao.upsertAll([novel, comic]);
    await addMarks(novel, bookmarkId: 11, highlightId: 21);
    await addMarks(comic, bookmarkId: 12, highlightId: 22);

    final renamedComic = comic.copyWith(name: '新版漫畫');
    await db.bookDao.upsertEditedBookInfo(comic, renamedComic);

    final bookmarks = {for (final item in await db.bookmarkDao.getAll()) item.id: item};
    final highlights = {for (final item in await db.highlightDao.getAll()) item.id: item};
    expect(bookmarks[11]?.bookName, novel.recordName);
    expect(bookmarks[12]?.bookName, renamedComic.recordName);
    expect(highlights[21]?.bookName, novel.recordName);
    expect(highlights[22]?.bookName, renamedComic.recordName);
    expect(
      (await db.bookDao.getByRecordName(renamedComic.recordName)).single.bookUrl,
      comic.bookUrl,
    );
  });
}
