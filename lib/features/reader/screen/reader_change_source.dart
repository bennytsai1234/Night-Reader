import 'package:flutter/material.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/exception/user_error.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/search/search_book.dart';
import 'package:night_reader/core/source_switch/source_switch_service.dart';
import 'package:night_reader/core/storage/book_cover_storage_service.dart';
import 'package:night_reader/core/download/download_service.dart';
import 'package:night_reader/features/book_detail/widgets/change_source_sheet.dart';
import 'package:night_reader/features/reader/features/menu/reader_menu_sheet.dart';
import 'package:night_reader/features/reader/screen/reader_chapter_info.dart';
import 'package:night_reader/features/reader/screen/reader_controller_host.dart';
import 'package:night_reader/features/reader/session/reader_open_target.dart';
import 'package:night_reader/shared/navigation/book_open_route.dart';
import 'package:night_reader/shared/widgets/popups/app_bottom_sheet.dart';

/// 閱讀器的換源：打開換源清單，選了一個就存好進度、準備與套用換源，再用換
/// 好的書換掉整個閱讀頁。「更多」選單與開書失敗的按鈕列都開它。
final class ReaderChangeSource {
  ReaderChangeSource({
    required this._context,
    required this._mounted,
    required this._book,
    required this._host,
    required this._info,
  });

  final BuildContext Function() _context;
  final bool Function() _mounted;
  final Book _book;
  final ReaderControllerHost _host;
  final ReaderChapterInfo _info;

  final SourceSwitchService _sourceSwitchService = SourceSwitchService(
    operationQuiescer: (oldBook) =>
        DownloadService().quiesceForSourceSwitch(oldBook),
    assetRetirer: BookCoverStorageService().handoffSourceSwitchAssets,
  );

  Future<void> show() async {
    if (_book.isLocal) return;
    PreparedSourceSwitch? preparedSwitch;
    await AppBottomSheet.showCustom<void>(
      context: _context(),
      constraints: ReaderMenuSheet.constraintsFor(_context(), _host.settings),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ChangeSourceSheet(
        book: _book,
        onSelectSource: (candidate, toc) => _handleChangeSourceSelected(
          candidate,
          toc: toc,
          onSuccess: (prepared) => preparedSwitch = prepared,
        ),
      ),
    );

    final prepared = preparedSwitch;
    if (!_mounted() || prepared == null) return;
    _pushReplacementForPreparedSwitch(prepared);
  }

  Future<ChangeSourceOutcome> _handleChangeSourceSelected(
    SearchBook candidate, {
    SourceToc? toc,
    void Function(PreparedSourceSwitch prepared)? onSuccess,
  }) async {
    try {
      // The flush returns the exact snapshot that was captured and persisted.
      // Use that snapshot for source alignment; reading runtime state after
      // the await would allow a scroll/TTS update during the DAO write to
      // disagree with the progress that is authoritative for this switch.
      final flushedLocation = await _host.flushProgress();
      final runtime = _host.runtime;
      final currentLocation = flushedLocation ?? runtime?.state.visibleLocation;
      final currentIndex =
          currentLocation?.chapterIndex ?? _info.currentChapterIndex(runtime);
      final currentTitle = _info.chapterTitleAt(currentIndex);
      final switchingBook = _book.copyWith(
        chapterIndex: currentIndex,
        durChapterTitle: currentTitle.isEmpty
            ? _book.durChapterTitle
            : currentTitle,
        charOffset: currentLocation?.charOffset ?? _book.charOffset,
        visualOffsetPx: currentLocation?.visualOffsetPx ?? _book.visualOffsetPx,
      );
      final prepared = await _sourceSwitchService.prepareSwitch(
        switchingBook,
        candidate,
        targetChapterIndex: currentIndex,
        targetChapterTitle: currentTitle.isEmpty ? null : currentTitle,
        toc: toc,
      );
      await _sourceSwitchService.commitSwitch(
        _book,
        prepared,
        bookDao: _host.dependencies.bookDao,
        chapterDao: _host.dependencies.chapterDao,
      );
      AppEventBus().fire(AppEventBus.upBookshelf);
      onSuccess?.call(prepared);
      return (success: true, message: '已切換到 ${prepared.source.bookSourceName}');
    } catch (error) {
      if (!isSourceSwitchUnavailable(error)) rethrow;
      return (success: false, message: failureMessage('換源', error));
    }
  }

  void _pushReplacementForPreparedSwitch(PreparedSourceSwitch prepared) {
    Navigator.of(_context()).pushReplacement(
      BookOpenRoute(
        book: prepared.migratedBook,
        openTarget: ReaderOpenTarget.resume(prepared.migratedBook),
        initialChapters: prepared.chapters,
      ),
    );
  }
}
