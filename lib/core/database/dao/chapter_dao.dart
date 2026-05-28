import 'package:drift/drift.dart';
import '../../models/chapter.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'chapter_dao.g.dart';

@DriftAccessor(tables: [Chapters])
class ChapterDao extends DatabaseAccessor<AppDatabase> with _$ChapterDaoMixin {
  ChapterDao(super.db);

  Future<List<BookChapter>> getByBook(String bookUrl) {
    return (select(chapters)
          ..where((t) => t.bookUrl.equals(bookUrl))
          ..orderBy([(t) => OrderingTerm(expression: t.index)]))
        .get();
  }

  Stream<List<BookChapter>> watchByBook(String bookUrl) {
    return (select(chapters)
          ..where((t) => t.bookUrl.equals(bookUrl))
          ..orderBy([(t) => OrderingTerm(expression: t.index)]))
        .watch();
  }

  Future<void> insertChapters(List<BookChapter> chapterList) async {
    await batch(
      (b) => b.insertAllOnConflictUpdate(
        chapters,
        chapterList
            .map((e) => BookChapterToInsertable(e).toInsertable())
            .toList(),
      ),
    );
  }

  Future<BookChapter?> getChapter(String bookUrl, int index) {
    return (select(chapters)..where(
      (t) => t.bookUrl.equals(bookUrl) & t.index.equals(index),
    )).getSingleOrNull();
  }

  Future<void> deleteByBook(String bookUrl) {
    return (delete(chapters)..where((t) => t.bookUrl.equals(bookUrl))).go();
  }
}
