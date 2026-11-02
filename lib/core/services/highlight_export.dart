import 'package:night_reader/core/models/highlight.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:share_plus/share_plus.dart';

/// 一本書要匯出的標註，已照在書裡的先後排好。
typedef HighlightExportBook = ({
  String bookName,
  String bookAuthor,
  List<Highlight> items,
});

/// 標註匯出成 Markdown：一本書一個標題（書名、作者），同一章的標註排在
/// 章名下面，每個標註是一段引用。文字照記下的原樣，不做繁簡轉換。
String highlightsToMarkdown(List<HighlightExportBook> books) {
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
    String? chapter;
    for (final highlight in items) {
      if (highlight.chapterTitle != chapter) {
        chapter = highlight.chapterTitle;
        out
          ..writeln()
          ..writeln('## ${chapter.isEmpty ? '（沒有章名）' : chapter}');
      }
      out.writeln();
      for (final line in highlight.quote.split('\n')) {
        out.writeln(line.isEmpty ? '>' : '> $line');
      }
    }
  }
  return out.toString();
}

/// 把標註寫成 Markdown 檔，從系統的分享選單存起來或傳出去。只有一本書時
/// 檔名是書名，好幾本時是「標註」。
Future<void> shareHighlights(List<HighlightExportBook> books) async {
  final kept = [
    for (final book in books)
      if (book.items.isNotEmpty) book,
  ];
  if (kept.isEmpty) return;
  final title = kept.length == 1 ? '${kept.single.bookName} 標註' : '夜讀標註';
  final file = await AppStoragePaths.shareExportFile(
    '${title.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')}.md',
  );
  await file.writeAsString(highlightsToMarkdown(kept));
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'text/markdown')],
      text: title,
    ),
  );
}
