import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/book/chapter_alignment.dart';
import 'package:night_reader/core/models/reading/bookmark.dart';
import 'package:night_reader/core/models/reading/highlight.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:share_plus/share_plus.dart';

/// 匯出的一筆：書籤的那一句，或標註畫到的字；[note] 是標註的備忘。
typedef BookmarkHighlightExportItem = ({
  /// 這台目錄裡的第幾章，排先後用。
  int chapter,
  int charOffset,
  String chapterTitle,
  String text,
  String note,
});

/// 一本書要匯出的書籤與標註。
typedef BookmarkHighlightExportBook = ({
  String bookName,
  String bookAuthor,
  List<BookmarkHighlightExportItem> items,
});

/// 一本書的書籤與標註合成匯出的一筆一筆：章照 [toc] 對到這台目錄（還沒抓
/// 目錄時照記下的序號），同一章照第幾個字；同一個位置先書籤、再標註。
List<BookmarkHighlightExportItem> bookmarkHighlightExportItems({
  required Iterable<Bookmark> bookmarks,
  required Iterable<Highlight> highlights,
  required List<BookChapter> toc,
}) {
  int chapterOf(int chapterIndex, String chapterTitle) => alignChapterIndex(
    oldIndex: chapterIndex,
    oldTitle: chapterTitle,
    oldTotalCount: 0,
    newChapters: toc,
  );
  final items = [
    for (final bookmark in bookmarks)
      (
        chapter: chapterOf(bookmark.chapterIndex, bookmark.chapterTitle),
        charOffset: bookmark.charOffset,
        chapterTitle: bookmark.chapterTitle,
        text: bookmark.excerpt,
        note: '',
      ),
    for (final highlight in highlights)
      (
        chapter: chapterOf(highlight.chapterIndex, highlight.chapterTitle),
        charOffset: highlight.charOffset,
        chapterTitle: highlight.chapterTitle,
        text: highlight.quote,
        note: highlight.note,
      ),
  ];
  return _inReadingOrder(items);
}

/// 照章節序號與章內位置排；同一個位置時照給的順序。
List<BookmarkHighlightExportItem> _inReadingOrder(
  List<BookmarkHighlightExportItem> items,
) {
  final indexed = items.indexed.toList()
    ..sort((a, b) {
      final byChapter = a.$2.chapter.compareTo(b.$2.chapter);
      if (byChapter != 0) return byChapter;
      final byOffset = a.$2.charOffset.compareTo(b.$2.charOffset);
      return byOffset != 0 ? byOffset : a.$1.compareTo(b.$1);
    });
  return [for (final (_, item) in indexed) item];
}

/// 書籤與標註匯出成 Markdown：一本書一個標題（書名、作者），照章節序號與
/// 章內位置排，同一章的排在章名下面，每一筆是一段引用，標註有備忘時接在
/// 引用下面一段。文字照記下的原樣，不做繁簡轉換。
String bookmarksAndHighlightsToMarkdown(
  List<BookmarkHighlightExportBook> books,
) {
  final out = StringBuffer();
  for (final (:bookName, :bookAuthor, :items) in books) {
    if (items.isEmpty) continue;
    if (out.isNotEmpty) out.writeln();
    out.writeln('# $bookName');
    if (bookAuthor.isNotEmpty) {
      out
        ..writeln()
        ..writeln(bookAuthor);
    }
    // 呼叫端照在書裡的先後給；同一章同一個位置時照給的順序。
    final ordered = _inReadingOrder(items);
    int? chapter;
    for (final item in ordered) {
      if (item.chapter != chapter) {
        chapter = item.chapter;
        out
          ..writeln()
          ..writeln(
            '## ${item.chapterTitle.isEmpty ? '（沒有章名）' : item.chapterTitle}',
          );
      }
      out.writeln();
      for (final line in item.text.split('\n')) {
        out.writeln(line.isEmpty ? '>' : '> $line');
      }
      final note = item.note.trim();
      if (note.isNotEmpty) {
        out
          ..writeln()
          ..writeln(note);
      }
    }
  }
  return out.toString();
}

/// 把書籤與標註寫成 Markdown 檔，從系統的分享選單存起來或傳出去。只有一本
/// 書時檔名是書名，好幾本時是「夜讀」，後面都接「書籤與標註」。
Future<void> shareBookmarksAndHighlights(
  List<BookmarkHighlightExportBook> books,
) async {
  final kept = [
    for (final book in books)
      if (book.items.isNotEmpty) book,
  ];
  if (kept.isEmpty) return;
  final title = kept.length == 1 ? '${kept.single.bookName} 書籤與標註' : '夜讀書籤與標註';
  final file = await AppStoragePaths.shareExportFile(
    '${title.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')}.md',
  );
  await file.writeAsString(bookmarksAndHighlightsToMarkdown(kept));
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'text/markdown')],
      text: title,
    ),
  );
}
