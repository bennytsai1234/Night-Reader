import 'package:flutter/material.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/source_switch/chapter_borrow.dart';
import 'package:night_reader/features/book_detail/widgets/change_source_sheet.dart';
import 'package:night_reader/features/reader/features/menu/reader_menu_sheet.dart';
import 'package:night_reader/features/reader/screen/reader_controller_host.dart';

/// 閱讀器的單章借源（ADR 0080）：打開借源面板，借好第幾章由呼叫端換上畫面
/// （[show] 的 `apply`：目前這一章重排、開書失敗的重開、跳章取不到的跳過去），
/// 換好了才提示借自哪個書源。「更多」選單、開書失敗的按鈕列與跳章取不到的
/// 提示都開它。
final class ReaderBorrowChapter {
  ReaderBorrowChapter({
    required this._context,
    required this._mounted,
    required this._book,
    required this._host,
    required this._showNotice,
  });

  final BuildContext Function() _context;
  final bool Function() _mounted;
  final Book _book;
  final ReaderControllerHost _host;
  final void Function(String message) _showNotice;

  /// 借第 [chapterIndex] 章；借好之後 [apply] 換上畫面，換好了回傳 true。
  Future<void> show(
    int chapterIndex, {
    required Future<bool> Function() apply,
  }) async {
    final chapter = _host.runtime?.chapterAt(chapterIndex);
    if (_book.isLocal || chapter == null || !chapterBorrowable(chapter)) {
      return;
    }
    final dependencies = _host.dependencies;
    final source = await ChangeSourceSheet.showForBorrow(
      context: _context(),
      constraints: ReaderMenuSheet.constraintsFor(_context(), _host.settings),
      book: _book,
      chapter: chapter,
      borrowFrom: (source, toc, index, cancelToken) => borrowChapter(
        book: _book,
        chapter: chapter,
        source: source,
        lenderBook: toc.book,
        lenderChapters: toc.chapters,
        lenderIndex: index,
        chapterDao: dependencies.chapterDao,
        contentDao:
            dependencies.readerChapterContentDao ??
            getIt<ReaderChapterContentDao>(),
        cancelToken: cancelToken,
      ),
    );
    if (source == null || !_mounted()) return;
    if (await apply() && _mounted()) {
      _showNotice('已從 ${source.bookSourceName} 借來本章');
    }
  }
}
