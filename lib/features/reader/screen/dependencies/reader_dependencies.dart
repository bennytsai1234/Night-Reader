import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/features/reader/chapter/reader_chapter_repository.dart';
import 'package:night_reader/features/reader/text_view/overlay/reader_skeleton_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReaderDependencies {
  ReaderDependencies({
    required this.book,
    List<BookChapter> initialChapters = const <BookChapter>[],
    BookDao? bookDao,
    ChapterDao? chapterDao,
    BookSourceDao? sourceDao,
    ReaderChapterContentDao? readerChapterContentDao,
    ReplaceRuleDao? replaceDao,
    BookmarkDao? bookmarkDao,
    HighlightDao? highlightDao,
    BookSourceService? service,
    int Function()? currentChineseConvert,
    bool Function()? currentShowIllustrations,
    ReaderSkeletonPageStore? skeletonPages,
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
       highlightDao =
           highlightDao ??
           (getIt.isRegistered<HighlightDao>() ? getIt<HighlightDao>() : null),
       service = service ?? BookSourceService(),
       currentChineseConvert = currentChineseConvert ?? (() => 0),
       currentShowIllustrations = currentShowIllustrations ?? (() => false),
       skeletonPages =
           skeletonPages ??
           (getIt.isRegistered<SharedPreferences>()
               ? ReaderSkeletonPageStore(getIt<SharedPreferences>())
               : null);

  final Book book;
  final List<BookChapter> initialChapters;
  final BookDao bookDao;
  final ChapterDao chapterDao;
  final BookSourceDao sourceDao;
  final ReaderChapterContentDao? readerChapterContentDao;
  final ReplaceRuleDao? replaceDao;
  final BookmarkDao? bookmarkDao;
  final HighlightDao? highlightDao;
  final BookSourceService service;
  final int Function() currentChineseConvert;
  final bool Function() currentShowIllustrations;

  /// 開書骨架照著畫的上一頁紀錄（ADR 0024）；沒有偏好設定時不記。
  final ReaderSkeletonPageStore? skeletonPages;

  ReaderChapterRepository createChapterRepository({
    void Function(ReplaceRule rule)? onReplaceRuleDisabled,
  }) {
    return ReaderChapterRepository(
      book: book,
      initialChapters: initialChapters,
      bookDao: bookDao,
      chapterDao: chapterDao,
      sourceDao: sourceDao,
      contentDao: readerChapterContentDao,
      bookmarkDao: bookmarkDao,
      highlightDao: highlightDao,
      replaceDao: replaceDao,
      service: service,
      currentChineseConvert: currentChineseConvert,
      currentShowIllustrations: currentShowIllustrations,
      onReplaceRuleDisabled: onReplaceRuleDisabled,
    );
  }
}
