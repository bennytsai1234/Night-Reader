import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/application/coordinators/reader_v2_chapter_navigation_resolver.dart';
import 'package:night_reader/features/reader_v2/application/reader_v2_controller_host.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_tap_action.dart';
import 'package:night_reader/features/reader_v2/features/replace_rule/reader_v2_replace_rule_sheet.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_highlight.dart';

typedef ReaderV2NoticeSink = void Function(String message);

class ReaderV2PageCoordinator {
  ReaderV2PageCoordinator({
    required ReaderV2ControllerHost host,
    required ReaderV2NoticeSink showNotice,
  }) : _host = host,
       _showNotice = showNotice;

  final ReaderV2ControllerHost _host;
  final ReaderV2NoticeSink _showNotice;

  bool _followingTtsHighlight = false;
  ReaderV2TtsHighlight? _lastFollowedTtsHighlight;
  ReaderV2TtsHighlight? _pendingTtsHighlight;

  void handleTap(TapUpDetails details, Size? viewportSize) {
    final runtime = _host.runtime;
    if (viewportSize == null || runtime == null) return;
    final row = (details.localPosition.dy / (viewportSize.height / 3))
        .floor()
        .clamp(0, 2);
    final col = (details.localPosition.dx / (viewportSize.width / 3))
        .floor()
        .clamp(0, 2);
    final action = ReaderV2TapAction.fromCode(
      _host.settings.clickActions[row * 3 + col],
    );
    switch (action) {
      case ReaderV2TapAction.menu:
        _host.menu.showControls();
        return;
      case ReaderV2TapAction.nextPage:
        _movePage(forward: true);
        return;
      case ReaderV2TapAction.prevPage:
        _movePage(forward: false);
        return;
      case ReaderV2TapAction.nextChapter:
        unawaited(jumpRelativeChapter(1));
        return;
      case ReaderV2TapAction.prevChapter:
        unawaited(jumpRelativeChapter(-1));
        return;
      case ReaderV2TapAction.toggleTts:
        unawaited(_host.tts?.toggle());
        return;
      case ReaderV2TapAction.bookmark:
        unawaited(toggleBookmark());
        return;
    }
  }

  Future<void> jumpRelativeChapter(int delta) async {
    final runtime = _host.runtime;
    if (runtime == null || runtime.chapterCount <= 0) return;
    final target = ReaderV2ChapterNavigationResolver.resolveRelativeTarget(
      currentChapterIndex: runtime.state.visibleLocation.chapterIndex,
      chapterCount: runtime.chapterCount,
      delta: delta,
    );
    if (target == null) {
      _showNotice(delta < 0 ? '已經是第一章' : '已經是最後一章');
      return;
    }
    await jumpToChapter(target);
  }

  Future<void> jumpToChapter(int index) async {
    final runtime = _host.runtime;
    if (runtime == null) return;
    final safeIndex =
        index.clamp(0, (runtime.chapterCount - 1).clamp(0, 1 << 20)).toInt();
    await runtime.jumpToChapter(safeIndex);
    _host.menu.completeChapterNavigation();
  }

  void toggleAutoPage() {
    final autoPage = _host.autoPage;
    if (autoPage == null) return;
    if (!autoPage.isRunning) _host.menu.hideControlsForAutoPage();
    autoPage.toggle();
  }

  Future<void> toggleBookmark() async {
    final bookmark = _host.bookmark;
    if (bookmark == null) {
      _showNotice('書籤資料庫不可用');
      return;
    }
    await bookmark.addVisibleLocationBookmark();
    _showNotice('已加入書籤');
  }

  void maybeFollowTtsHighlight() {
    final highlight = _host.tts?.currentHighlight;
    if (highlight == null || !highlight.isValid) {
      _lastFollowedTtsHighlight = null;
      _pendingTtsHighlight = null;
      return;
    }
    if (highlight == _lastFollowedTtsHighlight) return;
    _pendingTtsHighlight = highlight;
    if (_followingTtsHighlight) return;
    _followNextTtsHighlight();
  }

  void _followNextTtsHighlight() {
    final target = _pendingTtsHighlight;
    if (target == null) return;
    final ensureVisible = _host.viewportController.ensureCharRangeVisible;
    if (ensureVisible == null) return;

    _pendingTtsHighlight = null;
    _lastFollowedTtsHighlight = target;
    _followingTtsHighlight = true;
    unawaited(
      ensureVisible(
        chapterIndex: target.chapterIndex,
        startCharOffset: target.highlightStart,
        endCharOffset: target.highlightEnd,
      ).whenComplete(() {
        _followingTtsHighlight = false;
        _followNextTtsHighlight();
      }),
    );
  }

  void openReplaceRule(BuildContext context) {
    _host.menu.dismissControls();
    final replaceDao = _host.dependencies.replaceDao;
    if (replaceDao == null) {
      _showNotice('替換規則資料庫不可用');
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => ReaderV2ReplaceRuleSheet(
            book: _host.book,
            bookDao: _host.dependencies.bookDao,
            replaceDao: replaceDao,
            onReload: () async {
              await _host.runtime?.reloadContentPreservingLocation();
            },
          ),
    );
  }

  void _movePage({required bool forward}) {
    final runtime = _host.runtime;
    final viewportSize = _host.runtime?.state.layoutSpec.viewportSize;
    if (runtime == null || viewportSize == null) return;
    final command =
        forward
            ? _host.viewportController.moveToNextPage
            : _host.viewportController.moveToPrevPage;
    if (command != null) {
      unawaited(command());
      return;
    }
    final animateBy = _host.viewportController.animateBy;
    if (animateBy != null) {
      unawaited(animateBy(viewportSize.height * (forward ? 0.9 : -0.9)));
      return;
    }
    if (forward) {
      runtime.moveToNextPage();
    } else {
      runtime.moveToPrevPage();
    }
  }
}
