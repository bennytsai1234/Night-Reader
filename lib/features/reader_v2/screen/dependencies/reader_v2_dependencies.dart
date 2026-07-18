import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/japanese_translation_service.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';

class ReaderV2Dependencies {
  ReaderV2Dependencies({
    required this.book,
    List<BookChapter> initialChapters = const <BookChapter>[],
    BookDao? bookDao,
    ChapterDao? chapterDao,
    BookSourceDao? sourceDao,
    ReaderChapterContentDao? readerChapterContentDao,
    ReplaceRuleDao? replaceDao,
    BookmarkDao? bookmarkDao,
    BookSourceService? service,
    int Function()? currentChineseConvert,
    JapaneseParagraphTranslator? Function()? currentJapaneseTranslator,
  }) : initialChapters = List<BookChapter>.from(initialChapters),
       bookDao = bookDao ?? getIt<BookDao>(),
       chapterDao = chapterDao ?? getIt<ChapterDao>(),
       sourceDao = sourceDao ?? getIt<BookSourceDao>(),
       readerChapterContentDao =
           readerChapterContentDao ??
           (getIt.isRegistered<ReaderChapterContentDao>()
               ? getIt<ReaderChapterContentDao>()
               : null),
       replaceDao =
           replaceDao ??
           (getIt.isRegistered<ReplaceRuleDao>()
               ? getIt<ReplaceRuleDao>()
               : null),
       bookmarkDao =
           bookmarkDao ??
           (getIt.isRegistered<BookmarkDao>() ? getIt<BookmarkDao>() : null),
       service = service ?? BookSourceService(),
       currentChineseConvert = currentChineseConvert ?? (() => 0),
       currentJapaneseTranslator = currentJapaneseTranslator ?? (() => null);

  final Book book;
  final List<BookChapter> initialChapters;
  final BookDao bookDao;
  final ChapterDao chapterDao;
  final BookSourceDao sourceDao;
  final ReaderChapterContentDao? readerChapterContentDao;
  final ReplaceRuleDao? replaceDao;
  final BookmarkDao? bookmarkDao;
  final BookSourceService service;
  final int Function() currentChineseConvert;
  final JapaneseParagraphTranslator? Function() currentJapaneseTranslator;

  ReaderV2ChapterRepository createChapterRepository() {
    return ReaderV2ChapterRepository(
      book: book,
      initialChapters: initialChapters,
      bookDao: bookDao,
      chapterDao: chapterDao,
      sourceDao: sourceDao,
      contentDao: readerChapterContentDao,
      replaceDao: replaceDao,
      service: service,
      currentChineseConvert: currentChineseConvert,
      currentJapaneseTranslator: currentJapaneseTranslator,
    );
  }
}
