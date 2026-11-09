import 'dart:io';

import 'package:path/path.dart' as p;

import '../comic/comic_chapter_files.dart';
import '../comic/local_comic_library.dart';
import '../constant/book_type.dart';
import '../database/dao/book_dao.dart';
import '../database/dao/chapter_dao.dart';
import '../local_book/local_book_fingerprint.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../models/source/book_source_logic.dart';
import '../storage/app_storage_paths.dart';
import 'local_book_service.dart';

/// 本地漫畫的匯入（ADR 0052）：作品資料夾（一話一個 CBZ／ZIP 或圖片資料夾）
/// 或單一個 CBZ／ZIP，存進本地書資料夾裡這本書的資料夾，每話一個
/// `<章指紋>.cbz`。
///
/// 書的身分是章指紋的集合：這次匯入的任何一話已經在書架上某本本地漫畫
/// 裡，新的話就併進那本（補新章不變成另一本），已有的話不重複存。書的
/// 原檔指紋記第一話的章指紋，進度同步照它對上另一台（ADR 0039）。
class LocalComicService {
  LocalComicService({
    required this.bookDao,
    required this.chapterDao,
    this.run = runLocalBookWorkInBackground,
  });

  final BookDao bookDao;
  final ChapterDao chapterDao;

  /// 讀寫檔案的工作交給誰跑（預設背景 isolate）。
  final LocalBookWorkRunner run;

  /// 匯入 [path]（作品資料夾或單一個 CBZ／ZIP），傳回書架上的那本；找不
  /// 到任何一話時傳回 null。[name] 是新書的書名，沒給就用資料夾或檔名。
  /// [onProgress] 每存好一話呼叫一次（第幾話、共幾話）。
  Future<Book?> importPath(
    String path, {
    String? name,
    void Function(int done, int total)? onProgress,
  }) async {
    final sources = await _discoverOn(run, path);
    if (sources.isEmpty) return null;
    final prints = await _fingerprintsOn(run, [
      for (final source in sources) source.path,
    ]);
    final existing = await _bookWithAnyOf(prints.toSet());
    final title = name ?? _nameOf(path);
    final book = existing ?? await _newBook(title);
    final bookDir = LocalBookService.filePathOf(book);
    final known = existing == null
        ? <BookChapter>[]
        : await chapterDao.getByBook(book.bookUrl);
    final knownPrints = {for (final chapter in known) chapter.url};

    final added = <LocalComicChapter>[];
    for (var i = 0; i < sources.length; i++) {
      if (!knownPrints.contains(prints[i])) {
        final stored = await _storeOn(run, sources[i], bookDir);
        if (stored != null && knownPrints.add(stored.fingerprint)) {
          added.add(stored);
        }
      }
      onProgress?.call(i + 1, sources.length);
    }
    if (existing == null && added.isEmpty) {
      await _removeEmptyDir(bookDir);
      return null;
    }

    final titles = <String, String>{
      for (final chapter in known) chapter.url: chapter.title,
      for (final chapter in added) chapter.fingerprint: chapter.title,
    };
    final ordered = titles.keys.toList()
      ..sort(
        (a, b) => ComicChapterFiles.compareNatural(titles[a]!, titles[b]!),
      );
    final chapters = [
      for (final (index, print) in ordered.indexed)
        BookChapter(
          url: print,
          title: titles[print]!,
          bookUrl: book.bookUrl,
          index: index,
        ),
    ];
    book
      ..fileFingerprint ??= chapters.first.url
      ..totalChapterNum = chapters.length
      ..latestChapterTitle = chapters.last.title;
    book.fillChapterTitle(chapters);
    await bookDao.transaction(() async {
      await bookDao.upsert(book);
      await chapterDao.deleteByBook(book.bookUrl);
      await chapterDao.insertChapters(chapters);
    });
    return book;
  }

  /// 第 [chapter] 話存在手機上的 CBZ。
  static String chapterPathOf(Book book, BookChapter chapter) => p.join(
    LocalBookService.filePathOf(book),
    '${chapter.url}${LocalComicLibrary.chapterExtension}',
  );

  /// 書架上已經有這幾話其中一話的本地漫畫。
  Future<Book?> _bookWithAnyOf(Set<String> prints) async {
    for (final book in await bookDao.getInBookshelf()) {
      if (!book.isLocal || book.bookKind != BookSourceKind.comic) continue;
      final chapters = await chapterDao.getByBook(book.bookUrl);
      if (chapters.any((chapter) => prints.contains(chapter.url))) return book;
    }
    return null;
  }

  Future<Book> _newBook(String title) async {
    final dir = await _freeBookDir(title);
    return Book(
      bookUrl: 'local://$dir',
      origin: BookType.localOrigin,
      originName: p.basename(dir),
      name: title,
      type: BookSourceKind.comic.bookType,
      isInBookshelf: true,
      canUpdate: false,
      syncTime: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 本地書資料夾裡還沒用掉的資料夾名：「書名」，有了就「書名 (2)」。
  Future<String> _freeBookDir(String title) async {
    final root = await AppStoragePaths.localBooksDir(ensureExists: true);
    final safe = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    final base = safe.isEmpty ? '本地漫畫' : safe;
    for (var copy = 1; ; copy++) {
      final path = p.join(root.path, copy == 1 ? base : '$base ($copy)');
      if (await FileSystemEntity.type(path) != FileSystemEntityType.notFound) {
        continue;
      }
      if ((await bookDao.getByUrl('local://$path'))?.isInBookshelf ?? false) {
        continue;
      }
      return path;
    }
  }

  static String _nameOf(String path) => FileSystemEntity.isFileSync(path)
      ? p.basenameWithoutExtension(path)
      : p.basename(path);

  static Future<void> _removeEmptyDir(String dir) async {
    final directory = Directory(dir);
    if (await directory.exists() && await directory.list().isEmpty) {
      await directory.delete();
    }
  }
}

// 送進背景 isolate 的工作在頂層函式裡建立，只捕捉路徑（CODING_STANDARDS.md）。

Future<List<LocalComicSource>> _discoverOn(
  LocalBookWorkRunner run,
  String path,
) => run(() => LocalComicLibrary.discover(path));

Future<List<String>> _fingerprintsOn(
  LocalBookWorkRunner run,
  List<String> paths,
) => run(
  () => [for (final path in paths) LocalComicLibrary.fingerprintOf(path)],
);

Future<LocalComicChapter?> _storeOn(
  LocalBookWorkRunner run,
  LocalComicSource source,
  String bookDir,
) => run(() => LocalComicLibrary.store(source, bookDir));
