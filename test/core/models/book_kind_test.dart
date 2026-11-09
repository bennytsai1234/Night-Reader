import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/sync/progress_sync.dart';
import 'package:night_reader/features/search/search_model.dart';

/// 同名不同類是不同的書（ADR 0053）。
void main() {
  test('a book is the kind its source type says; books restored from '
      'Legado carry its bits', () {
    expect(Book(type: 0).bookKind, BookSourceKind.novel);
    expect(Book(type: 1).bookKind, BookSourceKind.audio);
    expect(Book(type: 2).bookKind, BookSourceKind.comic);
    expect(Book(type: 3).bookKind, BookSourceKind.novel);
    // Legado：文字 8、有聲 32、圖片 64，本地書再加 256。
    expect(Book(type: 8).bookKind, BookSourceKind.novel);
    expect(Book(type: 8 | 256).bookKind, BookSourceKind.novel);
    expect(Book(type: 32).bookKind, BookSourceKind.audio);
    expect(Book(type: 64).bookKind, BookSourceKind.comic);
    for (final kind in [
      BookSourceKind.novel,
      BookSourceKind.comic,
      BookSourceKind.audio,
    ]) {
      expect(BookSourceKind.ofBookType(kind.bookType), kind);
    }
  });

  test('novel keys stay as they were; comic and audio keys get a prefix', () {
    Book book(int type) => Book(name: '夜航', author: '某人', type: type);

    expect(ProgressSync.nameKeyOf(book(0)), '夜航\t某人');
    expect(ProgressSync.nameKeyOf(book(2)), 'comic:夜航\t某人');
    expect(ProgressSync.nameKeyOf(book(1)), 'audio:夜航\t某人');
    expect(book(0).recordName, '夜航');
    expect(book(2).recordName, 'comic:夜航');
    for (final type in [0, 1, 2]) {
      final split = BookSourceKind.splitRecordName(book(type).recordName);
      expect(split.kind, book(type).bookKind);
      expect(split.name, '夜航');
    }
  });

  test('search puts a novel and a comic of the same title on two cards', () {
    SearchBook result(String origin, int type) => SearchBook(
      bookUrl: '$origin/1',
      name: '夜航',
      author: '某人',
      origin: origin,
      originName: origin,
      type: type,
    );
    final cards = SearchModel.aggregateForTest(
      [result('a', 0), result('b', 2), result('c', 0), result('d', 2)],
      '夜航',
      false,
    );

    expect(cards, hasLength(2));
    expect(
      {for (final card in cards) card.bookKind: card.origins.length},
      {BookSourceKind.novel: 2, BookSourceKind.comic: 2},
    );
    expect(
      searchResultIdentity(result('a', 0)),
      isNot(searchResultIdentity(result('b', 2))),
    );
  });

  test('changing source only looks at sources of the same kind', () {
    BookSource source(int type) => BookSource(
      bookSourceUrl: 'https://$type.test',
      bookSourceName: '某站',
      bookSourceType: type,
    );

    expect(source(0).isSearchableFor(BookSourceKind.novel), isTrue);
    expect(source(2).isSearchableFor(BookSourceKind.novel), isFalse);
    expect(source(2).isSearchableFor(BookSourceKind.comic), isTrue);
    expect(source(1).isSearchableFor(BookSourceKind.comic), isFalse);
    expect(
      (source(2)..enabled = false).isSearchableFor(BookSourceKind.comic),
      isFalse,
    );
  });

  group('a source whose type changed', () {
    late AppDatabase db;
    late BookDao books;
    late BookSourceDao sources;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      books = BookDao(db);
      sources = BookSourceDao(db);
      await sources.upsert(
        BookSource(bookSourceUrl: 'https://s.test', bookSourceName: '某站'),
      );
      await books.upsertAll([
        Book(
          bookUrl: 'b1',
          name: '夜航',
          origin: 'https://s.test',
          isInBookshelf: true,
          chapterIndex: 3,
        ),
        Book(bookUrl: 'b2', name: '別本', origin: 'https://other.test'),
      ]);
    });

    tearDown(() => db.close());

    test('takes the books on it along, keeping where they were read', () async {
      await sources.upsert(
        BookSource(
          bookSourceUrl: 'https://s.test',
          bookSourceName: '某站',
          bookSourceType: 2,
        ),
      );

      final moved = (await books.getByUrl('b1'))!;
      expect(moved.bookKind, BookSourceKind.comic);
      expect(moved.chapterIndex, 3);
      expect((await books.getByUrl('b2'))!.bookKind, BookSourceKind.novel);
      expect(await books.getByRecordName('comic:夜航'), hasLength(1));
      expect(await books.getByRecordName('夜航'), isEmpty);
    });

    test('saved in a batch (sync, import) does the same', () async {
      await sources.upsertAll([
        BookSource(
          bookSourceUrl: 'https://s.test',
          bookSourceName: '某站',
          bookSourceType: 1,
        ),
        BookSource(bookSourceUrl: 'https://other.test', bookSourceName: '別站'),
      ]);

      expect((await books.getByUrl('b1'))!.bookKind, BookSourceKind.audio);
      expect((await books.getByUrl('b2'))!.bookKind, BookSourceKind.novel);
    });

    test('to a type Night Reader does not support leaves the books', () async {
      await sources.upsert(
        BookSource(
          bookSourceUrl: 'https://s.test',
          bookSourceName: '某站',
          bookSourceType: 3,
        ),
      );

      expect((await books.getByUrl('b1'))!.bookKind, BookSourceKind.novel);
    });
  });
}
