import 'dart:typed_data';

import 'package:night_reader/core/comic/comic_chapter_files.dart';

/// 漫畫閱讀器的圖從哪裡來：第幾話依序有哪些圖、讀出一張圖（ADR 0052）。
/// 網路書（下載好的 CBZ、下載中的資料夾、還沒下載的照書源抓）與本地漫畫
/// 各一種實作，閱讀器只認這個介面。
abstract interface class ComicPageSource {
  /// 第 [chapterIndex] 話依序的每一張圖。抓不到時丟出例外：換章分隔顯示
  /// 原因與「重試」。
  Future<List<ComicPage>> pagesOf(int chapterIndex);

  /// 讀出第 [chapterIndex] 話的 [page]。讀不到時丟出例外：那一張顯示載入
  /// 失敗，其他張照常。
  Future<Uint8List> bytesOf(int chapterIndex, ComicPage page);

  /// 載入失敗時「用網頁開啟」打開的網址；本地的圖沒有網址，是 null。
  String? webUrlOf(int chapterIndex, ComicPage page);
}

/// 每一話都是手機上的圖片資料夾或 CBZ 的來源：本地漫畫，以及網路書已經
/// 下載好的章節。
class ComicChapterFilesSource implements ComicPageSource {
  ComicChapterFilesSource(this.pathOf);

  /// 第幾話的資料夾或 CBZ 路徑。
  final Future<String> Function(int chapterIndex) pathOf;

  @override
  Future<List<ComicPage>> pagesOf(int chapterIndex) async =>
      ComicChapterFiles.pagesOf(await pathOf(chapterIndex));

  @override
  Future<Uint8List> bytesOf(int chapterIndex, ComicPage page) async {
    final bytes = await ComicChapterFiles.readPage(
      await pathOf(chapterIndex),
      page.name,
    );
    if (bytes == null) throw StateError('這張圖不見了：${page.name}');
    return bytes;
  }

  @override
  String? webUrlOf(int chapterIndex, ComicPage page) => null;
}
