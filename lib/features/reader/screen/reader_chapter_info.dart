import 'package:night_reader/core/chinese/chinese_display.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/features/reader/screen/reader_page_shell.dart';
import 'package:night_reader/features/reader/session/reader_open_target.dart';
import 'package:night_reader/features/reader/session/reader_runtime.dart';
import 'package:night_reader/features/reader/session/reader_state.dart';

/// 閱讀頁顯示用的章節資訊：目前章、章名（套用繁簡轉換，目錄還沒載入時用
/// 閱讀紀錄的章名）、章節網址，與頁首頁尾該畫骨架還是內容、載入時描述哪
/// 一章。Runtime 還沒建好時照開書前的資料（書、開書前的目錄、要開的位置）。
final class ReaderChapterInfo {
  ReaderChapterInfo({
    required this._book,
    required this._initialChapters,
    required this._openTarget,
    required this._runtime,
    required this._chineseConvert,
  });

  final Book _book;
  final List<BookChapter> _initialChapters;
  final ReaderOpenTarget? _openTarget;
  final ReaderRuntime? Function() _runtime;

  /// 閱讀設定的繁簡轉換（[ChineseDisplay.convert] 的 convertType）。
  final int Function() _chineseConvert;

  /// 頁首頁尾資訊列跟著正文：開書、跳到別章、改排版與重載內容時畫骨架，
  /// 開書取不到正文時不畫。同一章內的跳轉（例如拖進度條預覽）資訊列留在
  /// 原處。
  ReaderInfoState infoStateOf(ReaderRuntime? runtime) {
    if (runtime == null) return ReaderInfoState.loading;
    if (runtime.state.lifecycle == ReaderLifecycle.unavailable) {
      return ReaderInfoState.hidden;
    }
    if (!runtime.state.hasStableWorld ||
        runtime.isJumpingToAnotherChapter ||
        runtime.isRebuildingText) {
      return ReaderInfoState.loading;
    }
    return ReaderInfoState.ready;
  }

  int currentChapterIndex(ReaderRuntime? runtime) {
    final count = runtime?.chapterCount ?? _initialChapters.length;
    if (runtime == null || count <= 0) return 0;
    return runtime.state.visibleLocation.chapterIndex
        .clamp(0, count - 1)
        .toInt();
  }

  /// 目錄、選單與資訊列顯示用的章節標題，套用閱讀設定的繁簡轉換。
  String chapterTitleAt(int index) {
    return ChineseDisplay.convert(
      rawChapterTitleAt(index),
      convertType: _chineseConvert(),
    );
  }

  /// 目錄還沒載入時（從書架開書，目錄在開書途中才從資料庫讀出），上次讀到
  /// 的那一章用書的閱讀紀錄裡的章名：開書時頁首頁尾的骨架照它量。
  String rawChapterTitleAt(int index) {
    final runtime = _runtime();
    final title = runtime != null
        ? runtime.titleFor(index)
        : index >= 0 && index < _initialChapters.length
        ? _initialChapters[index].title
        : '';
    if (title.isNotEmpty || index != _book.chapterIndex) return title;
    return _book.durChapterTitle ?? '';
  }

  /// 要開的那一章：指定了開哪裡（例如書籍詳情點某一章）就是它，否則是書的
  /// 閱讀紀錄。和 Runtime 選開書位置的順序一樣。
  int get openChapterIndex =>
      _openTarget?.location.chapterIndex ?? _book.chapterIndex;

  /// 最後一次載入時頁首頁尾描述的位置，見 [infoTargetOf]。
  ReaderInfoTarget? _lastInfoTarget;

  /// 載入期間頁首頁尾描述的位置（[ReaderInfoTarget]）：跳章時是要跳去
  /// 的那一章，開書時是要開的那一章（[openChapterIndex]）。目錄還沒載入時
  /// 章數照書的紀錄。開書取不到正文時，要開的位置跟著那次開書一起清掉，
  /// 淡掉的骨架照最後一次載入時的位置畫，寬度不跳。
  ReaderInfoTarget infoTargetOf(ReaderRuntime? runtime) {
    final last = _lastInfoTarget;
    if (last != null &&
        runtime?.state.lifecycle == ReaderLifecycle.unavailable) {
      return last;
    }
    final chapterIndex =
        runtime?.pendingLocation?.chapterIndex ??
        runtime?.state.visibleLocation.chapterIndex ??
        openChapterIndex;
    final loaded = runtime?.chapterCount ?? _initialChapters.length;
    return _lastInfoTarget = ReaderInfoTarget(
      chapterIndex: chapterIndex,
      chapterCount: loaded > 0 ? loaded : _book.totalChapterNum,
      title: chapterTitleAt(chapterIndex),
      shares: runtime?.chapterShares.value,
    );
  }

  String chapterUrlAt(int index) {
    final runtime = _runtime();
    if (runtime != null) return runtime.chapterUrlAt(index);
    if (index < 0 || index >= _initialChapters.length) return '';
    return _initialChapters[index].url;
  }

  /// 第 [index] 章；Runtime 還沒建好時從開書前的目錄找，沒有就是 null。
  BookChapter? chapterAt(int index) =>
      _runtime()?.chapterAt(index) ??
      (index < _initialChapters.length ? _initialChapters[index] : null);
}
