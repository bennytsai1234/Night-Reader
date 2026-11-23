import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source/source_interaction.dart';
import 'package:night_reader/core/source_switch/chapter_borrow.dart';
import 'package:night_reader/features/reader/chapter/reader_chapter_repository.dart';
import 'package:night_reader/features/reader/features/menu/reader_menu_departure.dart';
import 'package:night_reader/features/reader/screen/reader_borrow_chapter.dart';
import 'package:night_reader/features/reader/screen/reader_chapter_info.dart';
import 'package:night_reader/features/reader/screen/reader_change_source.dart';
import 'package:night_reader/features/reader/screen/reader_controller_host.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';
import 'package:night_reader/features/reader/session/reader_runtime.dart';
import 'package:night_reader/features/reader/use_cases/reader_page_coordinator.dart';
import 'package:night_reader/features/reader/session/reader_state.dart';
import 'package:night_reader/features/source_login/source_browser_page.dart';
import 'package:night_reader/features/source_login/source_login_page.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';

/// 讀不到正文時的補救（ADR 0038）：開書失敗時正文底下的按鈕列（前往驗證、
/// 登入、重試、換源、單章借源、返回），閱讀中提示旁的「登入」「前往驗證」
/// 「借源」，查這本書有登入的書源，登入或驗證回來後重開、跳到取不到的那一
/// 章或重抓這一章；借源（ADR 0080）借好後同樣重開、跳過去或重排這一章。
final class ReaderSourceRemedy {
  ReaderSourceRemedy({
    required this._context,
    required this._mounted,
    required this._book,
    required this._host,
    required this._info,
    required this._changeSource,
    required this._borrowChapter,
    required this._showNotice,
    required this._jumpToChapter,
    required this._jumpToChapterAndWait,
    required this._exit,
    required this._restoreMenuWhenUncovered,
  });

  final BuildContext Function() _context;
  final bool Function() _mounted;
  final Book _book;
  final ReaderControllerHost _host;
  final ReaderChapterInfo _info;
  final ReaderChangeSource _changeSource;
  final ReaderBorrowChapter _borrowChapter;
  final void Function(String message, {ReaderNoticeAction? action}) _showNotice;

  /// 跳到別章，同從目錄點一章（取不到的是別章時）。
  final void Function(int index) _jumpToChapter;

  /// 跳到別章、等跳完（借來取不到的那一章之後）。
  final Future<void> Function(int index) _jumpToChapterAndWait;

  /// 離開閱讀器（按鈕列的「返回」）。
  final VoidCallback _exit;

  /// 推上去的頁關掉後滑回選單（從選單開的登入）。
  final VoidCallback _restoreMenuWhenUncovered;

  Widget errorActions(ReaderRuntime runtime) {
    final message = runtime.state.unavailableMessage ?? '';
    if (_verificationFor(message) case final request?) {
      // 書源要在網頁上驗證：「前往驗證」排第一，關掉就重開（ADR 0038）。
      return _readerErrorActions(
        runtime,
        first: (
          label: '前往驗證',
          icon: Icons.open_in_browser_rounded,
          onPressed: () => unawaited(_verify(request)),
        ),
      );
    }
    if (LoginCheckException.describes(message)) {
      // 要登入才讀得到：「登入」排第一，登入完自動重開（ADR 0038）。
      return FutureBuilder<BookSource?>(
        future: loginSource(),
        builder: (_, snapshot) => _readerErrorActions(
          runtime,
          first: switch (snapshot.data) {
            final source? => (
              label: '登入',
              icon: Icons.login_rounded,
              onPressed: () => unawaited(login(source)),
            ),
            null => null,
          },
        ),
      );
    }
    return _readerErrorActions(runtime);
  }

  /// 開書失敗的按鈕列；[first] 是能解決這次失敗的那一顆（登入、前往驗證），
  /// 有的話排第一、重試退成次要。
  Widget _readerErrorActions(
    ReaderRuntime runtime, {
    ({String label, IconData icon, VoidCallback onPressed})? first,
  }) {
    void retry() => unawaited(_retryReader(runtime));
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (first != null) ...[
          FilledButton.icon(
            onPressed: first.onPressed,
            icon: Icon(first.icon),
            label: UiText(first.label),
          ),
          OutlinedButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const UiText('重試'),
          ),
        ] else
          FilledButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const UiText('重試'),
          ),
        // 本地書沒有換源，灰著留在原位（ADR 0059）。
        OutlinedButton.icon(
          onPressed: _book.isLocal ? null : _changeSource.show,
          icon: const Icon(Icons.swap_horiz),
          label: const UiText('換源'),
        ),
        // 開不起來的那一章（ADR 0080）；本地書、還沒有目錄、付費章節灰著。
        OutlinedButton.icon(
          onPressed: switch (runtime.unavailableLocation) {
            final failed? when _canBorrow(runtime, failed.chapterIndex) =>
              () => unawaited(_borrowUnavailable(runtime, failed)),
            _ => null,
          },
          icon: const Icon(Icons.content_paste_go_rounded),
          label: const UiText('單章借源'),
        ),
        TextButton.icon(
          onPressed: _exit,
          icon: const Icon(Icons.arrow_back),
          label: const UiText('返回'),
        ),
      ],
    );
  }

  bool _canBorrow(ReaderRuntime runtime, int chapterIndex) {
    if (_book.isLocal) return false;
    final chapter = runtime.chapterAt(chapterIndex);
    return chapter != null && chapterBorrowable(chapter);
  }

  /// 開書失敗的「單章借源」：借開不起來的那一章，借好在那個位置重開；
  /// 開在那一章才算換好。
  Future<void> _borrowUnavailable(
    ReaderRuntime runtime,
    ReaderLocation failed,
  ) => _borrowChapter.show(
    failed.chapterIndex,
    apply: () async {
      if (!await _rereadBorrowed(runtime, failed.chapterIndex)) return false;
      await runtime.openBook(at: failed);
      return !runtime.disposed &&
          runtime.state.hasStableWorld &&
          runtime.state.visibleLocation.chapterIndex == failed.chapterIndex;
    },
  );

  /// 「更多」的「單章借源」：借目前這一章，借好照目前的位置重排。
  Future<void> borrowCurrentChapter() async {
    final runtime = _host.runtime;
    if (runtime == null || !runtime.state.hasStableWorld) return;
    await _borrowChapter.show(
      _info.currentChapterIndex(runtime),
      apply: () => runtime.disposed
          ? Future.value(false)
          : runtime.reloadContentPreservingLocation(),
    );
  }

  /// 跳章或捲到下一章取不到時提示旁的「借源」：借好跳過去；取不到的就是
  /// 正在讀的這一章（例如重新取得本章抓不到）時照目前的位置重排。
  Future<void> _borrowFailed(int chapterIndex) async {
    final runtime = _host.runtime;
    if (runtime == null) return;
    await _borrowChapter.show(
      chapterIndex,
      apply: () async {
        if (runtime.disposed) return false;
        if (_info.currentChapterIndex(runtime) == chapterIndex) {
          return runtime.reloadContentPreservingLocation();
        }
        if (!await _rereadBorrowed(runtime, chapterIndex)) return false;
        await _jumpToChapterAndWait(chapterIndex);
        return !runtime.disposed &&
            runtime.state.visibleLocation.chapterIndex == chapterIndex;
      },
    );
  }

  /// 借好了要開過去、跳過去的那一章，閱讀器手上可能還是主書源的（例如面板
  /// 開著時預載又抓到了）：先重讀存著的。讀不到就不算換好。
  Future<bool> _rereadBorrowed(ReaderRuntime runtime, int chapterIndex) async {
    if (runtime.disposed) return false;
    try {
      await runtime.rereadStoredContent(chapterIndex);
    } on ReaderContentUnavailableException {
      return false;
    }
    return !runtime.disposed;
  }

  Future<void> _retryReader(ReaderRuntime runtime) async {
    if (runtime.chapterCount <= 0) {
      await runtime.openBook();
      return;
    }
    await runtime.reloadContentPreservingLocation();
  }

  void drainNotice() {
    final notice = _host.runtime?.takeUserNotice();
    if (!_mounted() || notice == null || notice.message.isEmpty) return;
    final (:message, :chapterIndex) = notice;
    if (_verificationFor(message) case final request?) {
      // 書源要在網頁上驗證：提示旁給「前往驗證」，關掉就重抓取不到的那一章。
      _showNotice(
        message,
        action: (
          label: '前往驗證',
          onPressed: () =>
              unawaited(_verify(request, failedChapter: chapterIndex)),
        ),
      );
      return;
    }
    if (!LoginCheckException.describes(message)) {
      final runtime = _host.runtime;
      // 別的書源借這一章（ADR 0080）。
      _showNotice(
        message,
        action:
            chapterIndex != null &&
                runtime != null &&
                _canBorrow(runtime, chapterIndex)
            ? (
                label: '借源',
                onPressed: () => unawaited(_borrowFailed(chapterIndex)),
              )
            : null,
      );
      return;
    }
    // 要登入才讀得到：提示旁給「登入」，登入完重抓取不到的那一章（ADR 0038）。
    unawaited(
      loginSource().then((source) {
        if (!_mounted()) return;
        _showNotice(
          message,
          action: source == null
              ? null
              : (
                  label: '登入',
                  onPressed: () =>
                      unawaited(login(source, failedChapter: chapterIndex)),
                ),
        );
      }),
    );
  }

  /// 這本書的書源，有登入（ADR 0038）時才有；換源會換掉整個閱讀頁，所以
  /// 一頁查一次。
  Future<BookSource?> loginSource() => _loginSourceLookup ??= () async {
    if (_book.isLocal) return null;
    final source = await _host.dependencies.sourceDao.getByUrl(_book.origin);
    return source != null && source.hasLogin ? source : null;
  }();

  Future<BookSource?>? _loginSourceLookup;

  /// 開書源的登入；登入資料變了就重抓（[_refetchFailed]）。[ticket] 是從
  /// 選單開的那一次：等選單滑出才推頁，回來後選單滑回來。
  Future<void> login(
    BookSource source, {
    ReaderMenuDepartureTicket? ticket,
    int? failedChapter,
  }) async {
    final changed = await openSourceLogin(
      _context(),
      source,
      beforePush: ticket == null
          ? null
          : () async {
              final ready =
                  await ticket.menusGone &&
                  _mounted() &&
                  ticket.canDepart &&
                  (pageRouteOf(_context())?.isCurrent ?? false);
              if (!ready && _mounted()) _host.releaseAutoPage();
              return ready;
            },
    );
    if (!_mounted()) return;
    if (ticket != null) _restoreMenuWhenUncovered();
    if (!changed) return;
    await _refetchFailed(failedChapter);
  }

  /// 失敗是因為書源要在網頁上驗證時，書源要開的那一頁（ADR 0038）。
  SourceBrowseRequest? _verificationFor(String message) {
    if (_book.isLocal || !SourceVerificationException.describes(message)) {
      return null;
    }
    return SourceInteraction.verificationFor(_book.origin);
  }

  /// 「前往驗證」：開書源要的那一頁，關掉就重抓（[_refetchFailed]；不論
  /// 有沒有按完成，網頁的 Cookie 都存了）。
  Future<void> _verify(
    SourceBrowseRequest request, {
    int? failedChapter,
  }) async {
    await openSourceVerification(
      _context(),
      sourceUrl: _book.origin,
      sourceName: _book.originName,
      request: request,
    );
    if (_mounted()) await _refetchFailed(failedChapter);
  }

  /// 登入或驗證回來之後重抓：開書失敗的重開；取不到的是別章
  /// （[failedChapter]，例如跳章或捲到下一章時）就跳過去；否則重抓這一章、
  /// 停在原位。
  Future<void> _refetchFailed([int? failedChapter]) async {
    final runtime = _host.runtime;
    if (runtime == null) return;
    if (runtime.state.lifecycle == ReaderLifecycle.unavailable) {
      await _retryReader(runtime);
    } else if (failedChapter != null &&
        failedChapter != _info.currentChapterIndex(runtime)) {
      _jumpToChapter(failedChapter);
    } else {
      await refetchCurrentChapter();
    }
  }

  /// 書源回了擋爬蟲頁或不完整的正文時，向書源重抓這一章、停在原位；
  /// 抓不到時保留原本的正文並顯示原因。
  Future<void> refetchCurrentChapter() async {
    final runtime = _host.runtime;
    if (runtime == null || !runtime.state.hasStableWorld) return;
    _showNotice('正在重新取得本章…');
    final succeeded = await runtime.reloadContentPreservingLocation(
      refetch: true,
    );
    if (_mounted() && succeeded) _showNotice('已重新取得本章');
  }
}
