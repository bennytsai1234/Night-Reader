import 'dart:io';

import 'package:path/path.dart' as p;

import 'comic_chapter_files.dart';
import 'local_comic_library.dart';
import '../constant/book_type.dart';
import '../database/dao/book_dao.dart';
import '../database/dao/chapter_dao.dart';
import '../diagnostics/app_log_service.dart';
import '../local_book/local_book_fingerprint.dart';
import '../models/book/book.dart';
import '../models/book/book_chapter.dart';
import '../models/source/book_source_logic.dart';
import '../storage/app_storage_paths.dart';
import '../local_book/local_book_service.dart';

/// 本地漫畫的匯入（ADR 0052）：作品資料夾（一話一個 CBZ／ZIP 或圖片資料夾）
/// 或單一個 CBZ／ZIP，存進本地書資料夾裡這本書的資料夾，每話一個
/// `<章指紋>.cbz`。
///
/// 書的身分是章指紋的集合：這次匯入的任何一話已經在書架上某本本地漫畫
/// 裡，新的話就併進那本（補新章不變成另一本），已有的話不重複存。章名相同
/// 但章指紋不同的一話（舊版匯入漏了頁、重新匯入）換成新的那份，不並存。
/// 書的原檔指紋（兩台之間認書的鍵）起初記第一話的章指紋；兩台記成不同的
/// 鍵時，「同步本地書」統一成同一個（`adoptComicKeys`，ADR 0039、0052）。
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
  ///
  /// 同步本地書下載時：[related] 是雲端那本的每一話（有其中一話的書就是
  /// 同一本），[titles] 照章指紋給章名（下載的檔是照順序編號的），
  /// [fingerprint] 是新書的原檔指紋。
  Future<Book?> importPath(
    String path, {
    String? name,
    Set<String> related = const {},
    Map<String, String> titles = const {},
    String? fingerprint,
    void Function(int done, int total)? onProgress,
  }) async {
    final sources = await _discoverOn(run, path);
    if (sources.isEmpty) return null;
    final prints = await _fingerprintsOn(run, [
      for (final source in sources) source.path,
    ]);
    final existing = await _bookWithAnyOf({...prints, ...related});
    final title = name ?? _nameOf(path);
    final book = existing ?? await _newBook(title);
    final bookDir = LocalBookService.filePathOf(book);
    final known = existing == null
        ? <BookChapter>[]
        : await chapterDao.getByBook(book.bookUrl);
    final knownPrints = {for (final chapter in known) chapter.url};
    // 重新匯入時同一話（同一個檔或資料夾）認的是章名：舊版漏了頁的那一話
    // 章指紋變了，才不會被當成新的一話、和舊的並存。下載回來的章（[titles]
    // 有給章名）不比對：同步的章名可以重複，換掉會少一話。
    final titlesOfSources = [
      for (var i = 0; i < sources.length; i++)
        titles[prints[i]] ?? sources[i].title,
    ];
    final titleCounts = <String, int>{};
    for (final title in titlesOfSources) {
      titleCounts[title] = (titleCounts[title] ?? 0) + 1;
    }
    final allPrints = prints.toSet();
    final replacedBy = <String, String>{};
    final stale = <String>{};

    final added = <LocalComicChapter>[];
    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      final print = prints[i];
      final title = titlesOfSources[i];
      // 章名相同、章指紋不同的一話可能是同一話更新過（例如補上舊版漏掉
      // 的頁）：存好這次的之後換掉舊的。同一話只有一個來源、書裡也只有
      // 這一話時才算；舊的內容還在這次匯入的別的來源、或這一話是下載回來
      // 的（同步的章名可以重複）時不算。
      final same = !titles.containsKey(print) && titleCounts[title] == 1
          ? [
              for (final chapter in known)
                if (chapter.title == title && !stale.contains(chapter.url))
                  chapter,
            ]
          : const <BookChapter>[];
      // 目錄裡有、檔案不見了（還原備份沒帶回檔案）的那一話也重新存。
      final missing =
          knownPrints.contains(print) &&
          !await File(
            p.join(bookDir, '$print${LocalComicLibrary.chapterExtension}'),
          ).exists();
      if (!knownPrints.contains(print) || missing) {
        final stored = await _storeOn(run, source, bookDir);
        if (stored != null && knownPrints.add(stored.fingerprint)) {
          added.add(stored);
          if (same.length == 1 &&
              same.single.url != stored.fingerprint &&
              !allPrints.contains(same.single.url)) {
            stale.add(same.single.url);
            replacedBy[same.single.url] = stored.fingerprint;
          }
        }
      }
      onProgress?.call(i + 1, sources.length);
    }
    if (existing == null && added.isEmpty) {
      await _removeEmptyDir(bookDir);
      return null;
    }

    final names = <String, String>{
      for (final chapter in known)
        if (!stale.contains(chapter.url)) chapter.url: chapter.title,
      for (final chapter in added)
        chapter.fingerprint: titles[chapter.fingerprint] ?? chapter.title,
    };
    final ordered = names.keys.toList()
      ..sort((a, b) => ComicChapterFiles.compareNatural(names[a]!, names[b]!));
    final chapters = [
      for (final (index, print) in ordered.indexed)
        BookChapter(
          url: print,
          title: names[print]!,
          bookUrl: book.bookUrl,
          index: index,
        ),
    ];
    // 補進更前面的話時序號會往後移：照讀到的那一話的章指紋找回它的新序號，
    // 第幾張不變。那一話這次換掉了就照換掉的章指紋找。
    if (known.isNotEmpty) {
      final reading = known[book.chapterIndex.clamp(0, known.length - 1)].url;
      final moved = ordered.indexOf(reading);
      if (moved >= 0) {
        book.chapterIndex = moved;
      } else if (replacedBy[reading] case final print?) {
        final index = ordered.indexOf(print);
        if (index >= 0) book.chapterIndex = index;
      }
    }
    book
      ..fileFingerprint ??= fingerprint ?? chapters.first.url
      ..totalChapterNum = chapters.length
      ..latestChapterTitle = chapters.last.title;
    book.fillChapterTitle(chapters);
    await bookDao.transaction(() async {
      await bookDao.upsert(book);
      await chapterDao.deleteByBook(book.bookUrl);
      await chapterDao.insertChapters(chapters);
    });
    // 換掉的舊章節檔在目錄寫好之後才刪：中途失敗時書裡的章節與檔案都還在。
    final obsolete = [
      for (final print in stale)
        if (!names.containsKey(print))
          p.join(bookDir, '$print${LocalComicLibrary.chapterExtension}'),
    ];
    if (obsolete.isNotEmpty) await _deleteOn(run, obsolete);
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

/// 換掉、不再用的章節檔；刪不掉只記下來，不留著擋匯入。
Future<void> _deleteOn(LocalBookWorkRunner run, List<String> paths) =>
    run(() async {
      for (final path in paths) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } on FileSystemException catch (error) {
          AppLog.w('舊的漫畫章節檔刪不掉 $path: $error');
        }
      }
    });
