import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/exception/user_error.dart';
import 'package:night_reader/core/local_book/local_book_formats.dart';
import 'package:night_reader/core/local_book/local_book_service.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/storage/book_toc_reverser.dart';
import 'package:night_reader/features/book_detail/book_detail_page.dart';
import 'package:night_reader/features/reader/features/menu/reader_menu_departure.dart';
import 'package:night_reader/features/reader/features/menu/reader_menu_sheet.dart';
import 'package:night_reader/features/reader/features/replace_rule/reader_replace_rule_page.dart';
import 'package:night_reader/features/reader/features/tts/reader_tts_sheet.dart';
import 'package:night_reader/features/reader/screen/reader_chapter_info.dart';
import 'package:night_reader/features/reader/screen/reader_change_source.dart';
import 'package:night_reader/features/reader/screen/reader_controller_host.dart';
import 'package:night_reader/features/reader/screen/reader_source_remedy.dart';
import 'package:night_reader/features/reader/session/reader_open_target.dart';
import 'package:night_reader/features/reader/use_cases/reader_page_coordinator.dart';
import 'package:night_reader/features/settings/reading_settings_page.dart';
import 'package:night_reader/features/settings/settings_page.dart';
import 'package:night_reader/features/settings/sync_status_text.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';
import 'package:night_reader/shared/navigation/book_open_route.dart';
import 'package:night_reader/shared/navigation/transition_settled.dart';
import 'package:night_reader/shared/widgets/popups/app_dialogs.dart';
import 'package:night_reader/core/storage/moved_chapters.dart';

/// 從閱讀選單開出去的東西：「更多」選單、推一整頁設定、替換規則管理頁、
/// 書籍詳情，與從選單開的面板（排版、朗讀、替換規則）。推頁前等選單滑出
/// 畫面、確認閱讀器仍在最上面；推上去的頁關掉後等返回動畫播完，才重讀設定、
/// 把選單滑回來（ADR 0018）。
final class ReaderMenuPages {
  ReaderMenuPages({
    required this._context,
    required this._mounted,
    required this._book,
    required this._initialChapters,
    required this._host,
    required this._info,
    required this._coordinator,
    required this._remedy,
    required this._changeSource,
    required this._showNotice,
    required this._retire,
    required this._resume,
  });

  final BuildContext Function() _context;
  final bool Function() _mounted;
  final Book _book;
  final List<BookChapter> _initialChapters;
  final ReaderControllerHost _host;
  final ReaderChapterInfo _info;
  final ReaderPageCoordinator _coordinator;
  final ReaderSourceRemedy _remedy;
  final ReaderChangeSource _changeSource;
  final void Function(String message) _showNotice;

  /// 換目錄（改編碼）前讓舊閱讀器停止寫進度與正文，失敗時恢復。
  final VoidCallback _retire;
  final VoidCallback _resume;

  /// 從選單推一整頁時，等選單滑出畫面（見 [_pushOverMenu]）。
  late final ReaderMenuDeparture _menuDeparture = ReaderMenuDeparture(
    _host.menu,
  );

  /// 「更多」正在查登入用的書源：第一次要讀資料庫，這段按鈕還點得到，連點
  /// 兩下會疊兩個選單。選單推上去之後點擊就落在選單上。
  bool _lookingUpMore = false;

  Future<void> showMore() async {
    if (_lookingUpMore) return;
    final isLocal = _book.isLocal;
    _lookingUpMore = true;
    final BookSource? loginSource;
    try {
      loginSource = await _remedy.loginSource();
    } finally {
      _lookingUpMore = false;
    }
    if (!_mounted()) return;
    final action = await showAppActionSheet<_ReaderMoreAction>(
      context: _context(),
      // 本地書與沒有登入的書源用不到的項目灰著留在原位（ADR 0059）。
      actions: [
        AppSheetAction(
          label: '書籤',
          icon: Icons.bookmark_add_outlined,
          value: _ReaderMoreAction.bookmark,
          enabled: _host.bookmarks.available,
        ),
        AppSheetAction(
          label: '換源',
          icon: Icons.swap_horiz_rounded,
          value: _ReaderMoreAction.changeSource,
          enabled: !isLocal,
        ),
        AppSheetAction(
          label: '單章借源',
          icon: Icons.content_paste_go_rounded,
          value: _ReaderMoreAction.borrowChapter,
          enabled: !isLocal,
        ),
        AppSheetAction(
          label: '重新取得本章',
          icon: Icons.refresh_rounded,
          value: _ReaderMoreAction.refetchChapter,
          enabled: !isLocal,
        ),
        AppSheetAction(
          label: '重新分段',
          icon: Icons.wrap_text_rounded,
          value: _ReaderMoreAction.reSegment,
          selected: _host.book.getReSegment(),
        ),
        // 本地書的目錄照檔案的順序，灰掉。
        AppSheetAction(
          label: '反轉目錄',
          icon: Icons.swap_vert_rounded,
          value: _ReaderMoreAction.reverseToc,
          enabled: !isLocal,
          selected: _host.book.getReverseToc(),
        ),
        // 只有本地 TXT 有編碼可改；EPUB 與網路書沒有這一項。
        if (_isLocalTxt)
          const AppSheetAction(
            label: '設定編碼',
            icon: Icons.text_fields_rounded,
            value: _ReaderMoreAction.charset,
          ),
        AppSheetAction(
          label: '登入',
          icon: Icons.login_rounded,
          value: _ReaderMoreAction.login,
          enabled: loginSource != null,
        ),
        const AppSheetAction(
          label: '書籍詳情',
          icon: Icons.info_outline_rounded,
          value: _ReaderMoreAction.bookDetail,
        ),
        const AppSheetAction(
          label: '全域系統設定',
          icon: Icons.settings_suggest_rounded,
          value: _ReaderMoreAction.globalSettings,
        ),
      ],
    );
    if (!_mounted() || action == null) return;
    switch (action) {
      case _ReaderMoreAction.bookmark:
        _host.menu.dismissControls();
        await _coordinator.addBookmarkAtTop();
      case _ReaderMoreAction.changeSource:
        _host.menu.dismissControls();
        await _changeSource.show();
      case _ReaderMoreAction.borrowChapter:
        _host.menu.dismissControls();
        await _remedy.borrowCurrentChapter();
      case _ReaderMoreAction.refetchChapter:
        _host.menu.dismissControls();
        await _remedy.refetchCurrentChapter();
      case _ReaderMoreAction.reSegment:
        _host.menu.dismissControls();
        await _toggleReSegment();
      case _ReaderMoreAction.reverseToc:
        _host.menu.dismissControls();
        await _toggleReverseToc();
      case _ReaderMoreAction.charset:
        _host.menu.dismissControls();
        await _changeCharset();
      case _ReaderMoreAction.login:
        if (loginSource != null) {
          await _remedy.login(loginSource, ticket: _departMenu());
        }
      case _ReaderMoreAction.bookDetail:
        await showBookDetail();
      case _ReaderMoreAction.globalSettings:
        final pushed = await _pushOverMenu(
          _departMenu(),
          MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
        );
        if (!_mounted() || pushed == null) return;
        // 「閱讀偏好」頁以自己的 controller 寫入同一組偏好設定；
        // 回到閱讀器時重新載入，正文才會反映在那裡做的調整。等返回動畫
        // 播完才載入：設定變了會重排正文，不和返回動畫疊在一起（ADR 0018）。
        restoreMenuWhenUncovered(
          beforeMenu: () => unawaited(_host.settings.loadSettings()),
        );
    }
  }

  bool get _isLocalTxt =>
      _book.isLocal && localBookExtensionFromPath(_book.bookUrl) == 'txt';

  /// 下方選單的「進階」：自動翻頁、繁簡、點擊區域、音量鍵這些不常邊讀邊
  /// 調的設定只在「閱讀偏好」一個地方（ADR 0030），不另開一個內容相同的
  /// 面板。和全域系統設定一樣等返回動畫播完才重讀設定（ADR 0018）。
  Future<void> openReadingPreferences() =>
      openSettingsPage(const ReadingSettingsPage());

  /// 推一整頁設定（「進階」與圓鈕長按）：選單先滑出才推，返回動畫播完才
  /// 重讀閱讀設定、再滑回選單（ADR 0018）。[whenUncovered] 和重讀設定
  /// 同時做。
  Future<void> openSettingsPage(
    Widget page, {
    VoidCallback? whenUncovered,
  }) async {
    final pushed = await _pushOverMenu(
      _departMenu(),
      MaterialPageRoute<void>(builder: (_) => page),
    );
    if (!_mounted() || pushed == null) return;
    restoreMenuWhenUncovered(
      beforeMenu: () {
        unawaited(_host.settings.loadSettings());
        whenUncovered?.call();
      },
    );
  }

  /// 替換規則鈕長按：直接進規則管理頁。回來時規則有改動才照新規則重載
  /// 正文；推頁前讀不到規則時當作有改動。
  Future<void> openReplaceRulePage() async {
    final replaceDao = _host.dependencies.replaceDao;
    if (replaceDao == null) {
      _showNotice('替換規則資料庫不可用');
      return;
    }
    Future<String?> snapshot() async {
      try {
        return jsonEncode([
          for (final rule in await replaceDao.getAll()) rule.toJson(),
        ]);
      } catch (error) {
        AppLog.w('讀取替換規則失敗，回來時照樣重載正文: $error');
        return null;
      }
    }

    final before = snapshot();
    await openSettingsPage(
      const ReaderReplaceRulePage(),
      whenUncovered: () => unawaited(_reloadIfRulesChanged(before, snapshot)),
    );
  }

  /// 從規則管理頁回來：規則和推頁前一樣就不動；有改動（或讀不到、比不出）
  /// 才照新規則重載正文。讀規則的期間閱讀器可能已經關掉或換了一份正文，
  /// 這時不重載；重載失敗和面板一樣提示，原本的正文留著。
  Future<void> _reloadIfRulesChanged(
    Future<String?> before,
    Future<String?> Function() snapshot,
  ) async {
    final runtime = _host.runtime;
    if (runtime == null) return;
    final previous = await before;
    if (previous != null && await snapshot() == previous) return;
    if (!_mounted() || runtime.disposed || !identical(_host.runtime, runtime)) {
      return;
    }
    try {
      await runtime.reloadContentPreservingLocation();
    } catch (error, stackTrace) {
      AppLog.e('套用替換規則失敗', error: error, stackTrace: stackTrace);
      _showNotice(failureMessage('套用替換規則', error));
    }
  }

  /// 「更多」的「重新分段」：切換這本書的開關、存起來，照新的設定重載正文
  /// （ADR 0078）；替換規則面板的同一個開關看的也是這本書的設定。
  Future<void> _toggleReSegment() async {
    final book = _host.book;
    final config = book.readConfig ??= ReadConfig();
    final enabled = !config.reSegment;
    config.reSegment = enabled;
    try {
      await _host.dependencies.bookDao.saveReadConfig(book);
      await _host.runtime?.reloadContentPreservingLocation();
    } catch (error, stackTrace) {
      AppLog.e('更新重新分段設定失敗', error: error, stackTrace: stackTrace);
      config.reSegment = !enabled;
      try {
        await _host.dependencies.bookDao.saveReadConfig(book);
      } catch (rollbackError, rollbackStack) {
        AppLog.e(
          '更新重新分段設定 rollback 持久化失敗: $rollbackError',
          error: rollbackError,
          stackTrace: rollbackStack,
        );
      }
      if (_mounted()) _showNotice(failureMessage('更新重新分段設定', error));
      return;
    }
    if (_mounted()) _showNotice(enabled ? '已打開重新分段' : '已關閉重新分段');
  }

  /// 「更多」的「設定編碼」（L6，只有本地 TXT）：照選的編碼重新解碼、重新
  /// 分章，閱讀進度與書籤留在同一章，再用新的章節重開這本書。
  /// 「更多」的「反轉目錄」：這本書存著的目錄整個翻過來、之後抓的也照翻
  /// （[BookTocReverser]，同 Legado 的「反轉目錄」）。進度、書籤、標註跟著
  /// 同一章；照翻過來的目錄重開閱讀器，停在同一個位置（同「設定編碼」）。
  Future<void> _toggleReverseToc() async {
    final reversed = !_host.book.getReverseToc();
    // 先寫回畫面這一刻的進度，翻過來才對得到同一個位置。
    await _host.flushProgress();
    if (!_mounted()) return;
    // 翻目錄前讓舊閱讀器停止寫進度與正文；它關掉時不會拿舊目錄的序號把
    // 進度寫回去。
    _retire();
    final ({Book book, List<BookChapter> chapters})? result;
    try {
      result = await BookTocReverser(
        bookDao: _host.dependencies.bookDao,
        chapterDao: _host.dependencies.chapterDao,
        bookmarkDao: _host.dependencies.bookmarkDao,
        highlightDao: _host.dependencies.highlightDao,
      ).setReversed(_host.book, reversed);
    } catch (error, stackTrace) {
      AppLog.e('反轉目錄失敗', error: error, stackTrace: stackTrace);
      _resume();
      if (_mounted()) _showNotice(failureMessage('反轉目錄', error));
      return;
    }
    if (!_mounted()) return;
    if (result == null) {
      _resume();
      return;
    }
    unawaited(
      Navigator.of(_context()).pushReplacement(
        BookOpenRoute(
          book: result.book,
          openTarget: ReaderOpenTarget.resume(result.book),
          initialChapters: result.chapters,
        ),
      ),
    );
  }

  Future<void> _changeCharset() async {
    final picked = await showAppActionSheet<String>(
      context: _context(),
      title: '設定編碼',
      actions: [
        for (final choice in _charsetChoices)
          AppSheetAction(
            label: choice,
            value: choice,
            selected: _isCharsetSelected(choice, _book.charset),
          ),
      ],
    );
    if (!_mounted() || picked == null) return;
    // 先寫回畫面這一刻的進度，換編碼後才對得到同一個位置。
    await _host.flushProgress();
    if (!_mounted()) return;
    // 換目錄前讓舊閱讀器停止寫進度與正文；換好之後它被新的閱讀器取代，
    // 關掉時也不會拿舊目錄把進度寫回去。
    _retire();
    final dialog = showClosableAppAlert<void>(
      context: _context(),
      barrierDismissible: false,
      builder: (context, _) => PopScope(
        canPop: false,
        child: AppAlert<void>(
          title: '設定編碼',
          content: const SyncProgressView(value: null, label: '正在重新解碼與分章…'),
          actions: const [],
        ),
      ),
    );
    Book? updated;
    String? failure;
    try {
      updated = await LocalBookService().changeCharset(
        _book,
        picked,
        bookDao: _host.dependencies.bookDao,
        chapterDao: _host.dependencies.chapterDao,
        bookmarkDao: _host.dependencies.bookmarkDao,
        highlightDao: _host.dependencies.highlightDao,
        contentDao: _host.dependencies.readerChapterContentDao,
      );
    } catch (error, stackTrace) {
      AppLog.e('設定編碼失敗', error: error, stackTrace: stackTrace);
      failure = failureMessage('設定編碼', error);
    } finally {
      dialog.close();
      await dialog.closed;
    }
    if (!_mounted()) return;
    if (updated == null) {
      _resume();
      _showNotice(failure ?? '設定編碼失敗');
      return;
    }
    unawaited(
      Navigator.of(_context()).pushReplacement(
        BookOpenRoute(
          book: updated,
          openTarget: ReaderOpenTarget.resume(updated),
        ),
      ),
    );
  }

  /// 選編碼的清單照 Legado（`AppConst.charsets`），只去掉夜讀解不了的
  /// Unicode 與 ASCII。
  static const List<String> _charsetChoices = [
    'UTF-8',
    'GB2312',
    'GB18030',
    'GBK',
    'Big5',
    'UTF-16',
    'UTF-16LE',
  ];

  /// 目前這本書的編碼是不是 [choice]。只寫 UTF-16 時實際會照 BOM 存成
  /// 大端或小端，選單上仍畫在 UTF-16 那一項。
  static bool _isCharsetSelected(String choice, String? current) {
    String normalized(String value) =>
        value.trim().toUpperCase().replaceAll('_', '-');
    final now = normalized(current ?? 'UTF-8');
    final label = normalized(choice);
    if (label == 'UTF-8') return now == 'UTF-8' || now == 'UTF8';
    if (label == 'UTF-16') {
      return now == 'UTF-16' ||
          now == 'UTF16' ||
          now == 'UNICODE' ||
          now == 'UTF-16BE' ||
          now == 'UTF16BE';
    }
    return now == label;
  }

  void menusHidden() => _menuDeparture.menusHidden();

  /// 收起選單、開一張推頁請求；推頁期間自動捲動保持暫停，選單再打開時
  /// 解除（見 [ReaderControllerHost.holdAutoPageWhileAway]）。
  ReaderMenuDepartureTicket _departMenu() {
    _host.holdAutoPageWhileAway();
    return _menuDeparture.depart();
  }

  /// 從選單推一整頁（書籍詳情、全域設定）：等選單滑出畫面才推（見
  /// [ReaderMenuDeparture]）。推之前再確認這次請求沒有作廢（選單又打開、
  /// 改選了別的、離開閱讀器）、閱讀器仍是最上面的一頁、選單完全收著；
  /// 沒有推頁時回傳 null，推了就回傳那一頁關掉時的結果。
  Future<(T?,)?> _pushOverMenu<T>(
    ReaderMenuDepartureTicket ticket,
    Route<T> route,
  ) async {
    if (!await ticket.menusGone ||
        !_mounted() ||
        !ticket.canDepart ||
        !(pageRouteOf(_context())?.isCurrent ?? false)) {
      if (_mounted()) _host.releaseAutoPage();
      return null;
    }
    return (await Navigator.of(_context()).push(route),);
  }

  /// 推上去的頁關掉後，等返回動畫播完再把選單滑回來，回到打開選單的
  /// 樣子；滑入不和返回動畫疊在一起，也不在淡入中的閱讀器裡出現。
  /// [beforeMenu] 在返回動畫播完、選單滑回之前呼叫（閱讀器已經被別頁
  /// 蓋住時也照樣呼叫）。
  void restoreMenuWhenUncovered({VoidCallback? beforeMenu}) {
    unawaited(
      TransitionSettled.uncovered(_context()).then((_) {
        if (!_mounted()) return;
        beforeMenu?.call();
        if (!(pageRouteOf(_context())?.isCurrent ?? false)) return;
        _host.menu.showControls();
      }),
    );
  }

  /// 從閱讀器開的詳情：點章節回來跳到那一章（見 [resolveDetailChapter]），
  /// 按閱讀鈕直接回來。
  Future<void> showBookDetail() async {
    final departure = _departMenu();
    final flushed = await _host.flushProgress();
    if (!_mounted()) return;
    final chapterDao = _host.dependencies.chapterDao;
    final index =
        flushed?.chapterIndex ?? _info.currentChapterIndex(_host.runtime);
    final storedIndex = await MovedChapters.indexOf(
      chapterDao,
      _book.bookUrl,
      _info.chapterUrlAt(index),
    );
    if (!_mounted()) return;
    final book = _book.copyWith(
      chapterIndex: storedIndex ?? index,
      durChapterTitle: _info.rawChapterTitleAt(index),
    );
    // 寫入進度、查章節的期間選單可能又被打開：推之前由 [_pushOverMenu]
    // 再確認一次。
    final pushed = await _pushOverMenu(
      departure,
      MaterialPageRoute<String>(
        builder: (_) => BookDetailPage(book: book, fromReader: true),
      ),
    );
    if (!_mounted() || pushed == null) return;
    final (targetUrl,) = pushed;
    if (targetUrl == null) {
      restoreMenuWhenUncovered();
      return;
    }
    // 點了章節回來：直接跳過去、不滑回選單，自動捲動照常接著捲。
    _host.releaseAutoPage();
    final target = await resolveDetailChapter(
      url: targetUrl,
      readerChapters: _host.runtime?.chapters ?? _initialChapters,
      loadLatest: () async {
        await _host.flushProgress();
        return chapterDao.getByBook(_book.bookUrl);
      },
    );
    if (!_mounted() || target == null) return;
    final latest = target.latest;
    if (latest == null) {
      await _coordinator.jumpToChapter(target.index);
      return;
    }
    unawaited(
      Navigator.of(_context()).pushReplacement(
        BookOpenRoute(
          book: _book,
          openTarget: ReaderOpenTarget.chapterStart(target.index),
          initialChapters: latest,
        ),
      ),
    );
  }

  /// 從選單開面板：開著時上下選單與亮度條收起，正文整頁露出來（排版面板
  /// 沒有暗色遮罩，邊調邊看）；面板關掉後回到選單打開的樣子。
  ///
  /// 選單從面板滑上來的下一格才開始滑出：面板的第一格要建整個面板的骨架，
  /// 選單開始滑出那一格要重算整組選單的讀屏資訊，兩件事錯開一格（ADR 0029
  /// 做法 4；擠在同一格時那一格多 1–2ms）。
  void openPanel(Future<void> Function() open) {
    var closed = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_mounted() && !closed) _host.menu.dismissControls();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
    unawaited(
      open().whenComplete(() {
        closed = true;
        if (!_mounted() || !(pageRouteOf(_context())?.isCurrent ?? false)) {
          return;
        }
        _host.menu.showControls();
      }),
    );
  }

  Future<void> showTts() async {
    final tts = _host.tts;
    if (tts == null) return;
    await ReaderMenuSheet.show<void>(
      _context(),
      settings: _host.settings,
      builder: (_) => ReaderTtsPanel(tts: tts, settings: _host.settings),
    );
  }

  void dispose() => _menuDeparture.dispose();
}

/// 從閱讀器開的詳情點了章節 [url]，閱讀器要開哪一章。
///
/// 閱讀器整段閱讀都用開書時的目錄 [readerChapters]；詳情頁讀的是資料庫裡
/// 的目錄，可能已經被書架檢查或詳情的「檢查更新」換過，序號對不上，所以
/// 兩邊用章節網址對應：閱讀器的目錄裡有這一章就原地跳（`latest` 為 null）；
/// 沒有（新章節）就到 [loadLatest] 讀到的最新目錄裡找，找到就用最新目錄
/// 重開；都沒有回傳 null。
@visibleForTesting
Future<({int index, List<BookChapter>? latest})?> resolveDetailChapter({
  required String url,
  required List<BookChapter> readerChapters,
  required Future<List<BookChapter>> Function() loadLatest,
}) async {
  final index = readerChapters.indexWhere((c) => c.url == url);
  if (index >= 0) return (index: index, latest: null);
  final latest = await loadLatest();
  final latestIndex = latest.indexWhere((c) => c.url == url);
  if (latestIndex < 0) return null;
  return (index: latestIndex, latest: latest);
}

enum _ReaderMoreAction {
  bookmark,
  changeSource,
  borrowChapter,
  refetchChapter,
  reSegment,
  reverseToc,
  charset,
  login,
  bookDetail,
  globalSettings,
}
