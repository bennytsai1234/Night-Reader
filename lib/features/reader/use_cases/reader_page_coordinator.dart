import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/exception/user_error.dart';
import 'package:night_reader/core/models/book/book_extensions.dart';
import 'package:night_reader/core/models/reading/bookmark.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/features/reader/features/bookmark/reader_bookmarks.dart';
import 'package:night_reader/core/models/reading/highlight.dart';
import 'package:night_reader/features/reader/features/highlight/reader_highlights.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/features/reader/chapter/reader_content_transformer.dart';
import 'package:night_reader/features/reader/features/replace_rule/selection_source_text.dart';
import 'package:night_reader/features/reader/text_view/overlay/selection_service.dart';
import 'package:night_reader/features/reader/chapter/reader_content.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';
import 'package:night_reader/features/reader/use_cases/coordinators/reader_chapter_navigation_resolver.dart';
import 'package:night_reader/features/reader/screen/reader_controller_host.dart';
import 'package:night_reader/features/reader/features/menu/reader_menu_sheet.dart';
import 'package:night_reader/features/reader/features/menu/reader_tap_action.dart';
import 'package:night_reader/features/reader/features/replace_rule/reader_replace_rule_editor_sheet.dart';
import 'package:night_reader/features/reader/features/replace_rule/reader_replace_rule_sheet.dart';
import 'package:night_reader/features/reader/features/tts/reader_tts_highlight_follower.dart';
import 'package:night_reader/shared/widgets/popups/app_bottom_sheet.dart';
import 'package:night_reader/features/reader/features/tts/reader_tts_phase.dart';

typedef ReaderNoticeSink = void Function(
  String message, {
  ReaderNoticeAction? action,
});

/// 提示列右側的按鈕，例如「復原」。
typedef ReaderNoticeAction = ({String label, VoidCallback onPressed});

class ReaderPageCoordinator {
  ReaderPageCoordinator({required this._host, required this._showNotice}) {
    _ttsFollower = ReaderTtsHighlightFollower(
      ensureHighlightVisible: (highlight) {
        final ensureVisible = _host.viewportController.ensureCharRangeVisible;
        if (ensureVisible == null) return Future<bool>.value(false);
        return ensureVisible(
          chapterIndex: highlight.chapterIndex,
          startCharOffset: highlight.sentenceStart,
          endCharOffset: highlight.sentenceEnd,
        );
      },
    );
  }

  final ReaderControllerHost _host;
  final ReaderNoticeSink _showNotice;

  /// 點擊區域的「目錄」「日夜切換」：要用到頁面的抽屜與主題，由頁面接上，
  /// 和閱讀選單的同名按鈕做同一件事。
  VoidCallback? openChapters;
  VoidCallback? toggleDayNight;

  /// 拖動條跨檔位的預覽跳轉防抖：快速滑過多個檔位時只跳最後停留者。
  static const Duration _scrubPreviewDebounce = Duration(milliseconds: 180);
  Timer? _scrubPreviewTimer;

  late final ReaderTtsHighlightFollower _ttsFollower;

  void handleTap(TapUpDetails details, Size? viewportSize) {
    final runtime = _host.runtime;
    if (viewportSize == null || runtime == null) return;
    final row = (details.localPosition.dy / (viewportSize.height / 3))
        .floor()
        .clamp(0, 2);
    final col = (details.localPosition.dx / (viewportSize.width / 3))
        .floor()
        .clamp(0, 2);
    final action = ReaderTapAction.fromCode(
      _host.settings.clickActions[row * 3 + col],
    );
    switch (action) {
      case ReaderTapAction.menu:
        _host.menu.showControls();
        return;
      case ReaderTapAction.nextPage:
        unawaited(_movePage(forward: true));
        return;
      case ReaderTapAction.prevPage:
        unawaited(_movePage(forward: false));
        return;
      case ReaderTapAction.nextChapter:
        unawaited(jumpRelativeChapter(1));
        return;
      case ReaderTapAction.prevChapter:
        unawaited(jumpRelativeChapter(-1));
        return;
      case ReaderTapAction.toggleTts:
        unawaited(_host.tts?.toggle());
        return;
      case ReaderTapAction.openChapters:
        openChapters?.call();
        return;
      case ReaderTapAction.toggleAutoPage:
        toggleAutoPage();
        return;
      case ReaderTapAction.toggleDayNight:
        toggleDayNight?.call();
        return;
    }
  }

  Future<void> jumpRelativeChapter(int delta) async {
    final runtime = _host.runtime;
    if (runtime == null || runtime.chapterCount <= 0) return;
    final current = runtime.state.visibleLocation.chapterIndex;
    bool locked(int index) => runtime.chapterAt(index)?.isLocked ?? false;
    final target = ReaderChapterNavigationResolver.resolveRelativeTarget(
      currentChapterIndex: current,
      chapterCount: runtime.chapterCount,
      delta: delta,
      skip: locked,
    );
    if (target == null) {
      // 這一側還有章卻沒有目標，表示剩下的都是付費章節（ADR 0057）。
      final neighbor = current + delta.sign;
      final paidAhead = neighbor >= 0 && neighbor < runtime.chapterCount;
      _showNotice(
        paidAhead
            ? lockedChapterNotice
            : delta < 0
            ? '已經是第一章'
            : '已經是最後一章',
      );
      return;
    }
    await jumpToChapter(target);
  }

  /// [settled] 見 [ReaderRuntime.jumpToChapter]。
  Future<void> jumpToChapter(int index, {Future<void>? settled}) async {
    final runtime = _host.runtime;
    if (runtime == null) return;
    final safeIndex = index
        .clamp(0, (runtime.chapterCount - 1).clamp(0, 1 << 20))
        .toInt();
    await runtime.jumpToChapter(safeIndex, settled: settled);
    if (runtime.state.visibleLocation.chapterIndex == safeIndex) {
      await _host.tts?.followManualJump();
    }
  }

  /// 拖動中跨檔位的即時預覽：防抖後跳到該位置，但不寫進度——
  /// 進度只在放開（[commitChapterPercent]）時落盤。
  void previewChapterPercent(double percent) {
    _scrubPreviewTimer?.cancel();
    _scrubPreviewTimer = Timer(_scrubPreviewDebounce, () {
      unawaited(jumpToCurrentChapterPercent(percent, immediateSave: false));
    });
  }

  /// 拖動條放開：取消未觸發的預覽，跳到最終位置並存進度。
  Future<void> commitChapterPercent(double percent) async {
    _scrubPreviewTimer?.cancel();
    _scrubPreviewTimer = null;
    await jumpToCurrentChapterPercent(percent);
    await _host.tts?.followManualJump();
  }

  /// 跳到「目前章節」的百分比位置。
  ///
  /// 百分比以 displayText 字元比例換算 charOffset（與排版像素進度略有
  /// 出入，但單調且誤差可忽略）；percent 0 對齊章首（charOffset 0 +
  /// anchor offset 的 top-aligned 慣例）。
  Future<void> jumpToCurrentChapterPercent(
    double percent, {
    bool immediateSave = true,
  }) async {
    final runtime = _host.runtime;
    if (runtime == null || runtime.chapterCount <= 0) return;
    final chapterIndex = runtime.state.visibleLocation.chapterIndex
        .clamp(0, runtime.chapterCount - 1)
        .toInt();
    final ratio = (percent / 100).clamp(0.0, 1.0).toDouble();
    if (ratio <= 0) {
      await runtime.jumpToLocation(
        ReaderLocation(
          chapterIndex: chapterIndex,
          charOffset: 0,
          visualOffsetPx: runtime.state.layoutSpec.anchorOffsetInViewport,
        ),
        immediateSave: immediateSave,
      );
      return;
    }
    final content = await runtime.loadContentAt(chapterIndex);
    final length = content.displayText.length;
    final charOffset = (length * ratio).round().clamp(0, length).toInt();
    await runtime.jumpToLocation(
      ReaderLocation(chapterIndex: chapterIndex, charOffset: charOffset),
      immediateSave: immediateSave,
    );
  }

  void dispose() {
    _scrubPreviewTimer?.cancel();
    _scrubPreviewTimer = null;
  }

  void toggleAutoPage() {
    final autoPage = _host.autoPage;
    if (autoPage == null) return;
    if (!autoPage.isRunning) {
      _host.menu.dismissControls();
      // 自動捲動與朗讀跟隨不同時移動正文；後開的接手，朗讀暫停中也收掉。
      final tts = _host.tts;
      if (tts != null && tts.phase != ReaderTtsPhase.idle) {
        unawaited(tts.stop());
      }
    }
    autoPage.toggle();
  }

  void maybeFollowTtsHighlight() {
    // 拖進度條時畫面跟著拖動走，放開後朗讀改從新位置念。
    if (_host.menu.isScrubbing) return;
    // 視窗只在換句時跟隨；關掉「畫面跟著朗讀捲動」時不跟，再打開時從
    // 正在念的那一句接上。
    _ttsFollower.update(
      _host.settings.ttsFollow ? _host.tts?.currentHighlight : null,
    );
  }

  Future<void> openReplaceRule(BuildContext context) async {
    final replaceDao = _host.dependencies.replaceDao;
    if (replaceDao == null) {
      _showNotice('替換規則資料庫不可用');
      return;
    }
    // 點下去就開，和選單收起同時；測試文字與規則數由面板打開後自己讀。
    final constraints = ReaderMenuSheet.constraintsFor(context, _host.settings);
    await AppBottomSheet.showCustom<void>(
      context: context,
      constraints: constraints,
      isScrollControlled: true,
      builder: (_) => ReaderReplaceRuleSheet(
        sheetConstraints: constraints,
        book: _host.book,
        bookDao: _host.dependencies.bookDao,
        replaceDao: replaceDao,
        onReload: () async {
          await _host.runtime?.reloadContentPreservingLocation();
        },
        loadTestSample: _replaceTestSample,
      ),
    );
  }

  /// 選字選單的「隱藏」：新增一條把這段字換成空白的替換規則，套用到所有
  /// 書、排在既有規則之後，重新排版後提示可以復原。規則用這一段在既有規則
  /// 套用之後的原文：畫面上的字經過排版整理與繁簡轉換，直接用常對不到
  /// （見 [selectionSourceOf]）。跨段時連段落之間的換行一起比對（同 Legado）。
  Future<void> hideText(ParagraphSelection selection) async {
    final source = await _selectionSource(selection, action: '隱藏');
    if (source == null) return;
    final (:replaceDao, :pattern, paragraph: _) = source;
    final name = _ruleNameOf(pattern);
    final int id;
    try {
      id = await replaceDao.append(
        ReplaceRule(
          name: name,
          group: _hiddenTextGroup,
          pattern: pattern,
          replacement: '',
          isRegex: false,
        ),
      );
    } catch (error, stackTrace) {
      AppLog.e('隱藏選字失敗', error: error, stackTrace: stackTrace);
      _showNotice(failureMessage('隱藏', error));
      return;
    }
    await _reloadAfterRule(
      replaceDao,
      id,
      done: '已隱藏「$name」',
      notReloaded: '已新增隱藏規則，但正文沒有更新',
    );
  }

  /// 選字選單的「替換」：找原文的方法同「隱藏」，打開替換規則的編輯畫面、
  /// 原文先填好（不是正則、套用到所有書、放在「選字替換」分組），使用者填
  /// 要換成的字；即時測試先放選到的那幾段原文。存了就重新排版，提示可以復原；
  /// 取消就不新增。
  Future<void> replaceText(
    BuildContext context,
    ParagraphSelection selection,
  ) async {
    final source = await _selectionSource(selection, action: '替換');
    if (source == null || !context.mounted) return;
    final (:replaceDao, :pattern, :paragraph) = source;
    int? id;
    await ReaderReplaceRuleEditorSheet.show(
      context,
      constraints: ReaderMenuSheet.constraintsFor(context, _host.settings),
      rule: ReplaceRule(
        name: _ruleNameOf(pattern),
        group: _replacedTextGroup,
        pattern: pattern,
        isRegex: false,
      ),
      testSample: paragraph,
      onSave: (rule) async {
        id = await replaceDao.append(rule);
      },
    );
    final saved = id;
    if (saved == null) return;
    await _reloadAfterRule(
      replaceDao,
      saved,
      done: '已新增替換規則',
      notReloaded: '已新增替換規則，但正文沒有更新',
    );
  }

  /// 選到的字在既有規則套用之後的原文，與選到的那幾段的原文
  /// （[selectionSourceOf]）；找不到或這本書關了替換規則時提示原因、傳回
  /// null。原文用排出畫面上那份正文的同一份（[ReaderChapterRepository
  /// .rawContentOf]）：存著的正文可能已經換過（單章借源、重新取得本章），
  /// 畫面還沒換，照位置對齊會對到別的字。
  Future<({ReplaceRuleDao replaceDao, String pattern, String paragraph})?>
  _selectionSource(
    ParagraphSelection selection, {
    required String action,
  }) async {
    final book = _host.book;
    final replaceDao = _host.dependencies.replaceDao;
    final runtime = _host.runtime;
    final chapter = runtime?.chapterAt(selection.chapterIndex);
    if (replaceDao == null || runtime == null || chapter == null) {
      _showNotice('無法$action這段字');
      return null;
    }
    if (!book.getUseReplaceRule()) {
      _showNotice('這本書沒有套用替換規則，打開後才能$action');
      return null;
    }
    try {
      final raw = runtime.repository.rawContentOf(
        selection.chapterIndex,
        selection.contentHash,
      );
      final stage = raw == null
          ? null
          : await ReaderContentTransformer.ruleStageParagraphs(
              book: book,
              chapter: chapter,
              rawContent: raw,
              enabledRules: await replaceDao.getEnabledForBook(
                book.name,
                book.origin,
              ),
              chineseConvertType: runtime.repository.currentChineseConvert(),
              onRuleTimedOut: runtime.repository.disableTimedOutRule,
            );
      final found = stage == null ? null : selectionSourceOf(selection, stage);
      if (found == null) {
        _showNotice('找不到這段字的原文，沒有$action');
        return null;
      }
      if (found.crossesIllustration) {
        _showNotice('選到的字中間有插圖，沒有$action');
        return null;
      }
      return (
        replaceDao: replaceDao,
        pattern: found.pattern,
        paragraph: found.paragraphs,
      );
    } catch (error, stackTrace) {
      AppLog.e('$action選字時找原文失敗', error: error, stackTrace: stackTrace);
      _showNotice(failureMessage(action, error));
      return null;
    }
  }

  /// 規則的名稱與提示裡的段落分隔換成一個空格。
  static String _ruleNameOf(String pattern) =>
      pattern.replaceAll(RegExp(r'\s*\n\s*'), ' ');

  /// 新增了規則 [id]：重新排版，提示可以復原。規則已經存進去了，重排失敗也
  /// 留著復原，不然只能到替換規則裡刪。
  Future<void> _reloadAfterRule(
    ReplaceRuleDao replaceDao,
    int id, {
    required String done,
    required String notReloaded,
  }) async {
    final undo = (
      label: '復原',
      onPressed: () => unawaited(_removeAddedRule(replaceDao, id)),
    );
    var reloaded = false;
    try {
      reloaded =
          await _host.runtime?.reloadContentPreservingLocation() ?? false;
    } catch (error, stackTrace) {
      AppLog.e('新增規則後重排失敗', error: error, stackTrace: stackTrace);
    }
    _showNotice(reloaded ? done : notReloaded, action: undo);
  }

  /// 選字選單的「書籤」：在選到的字那一句留一個書籤，提示可「復原」。
  Future<void> addBookmark(SelectionBookmark selection) async {
    final bookmarks = _host.bookmarks;
    final Bookmark? saved;
    try {
      saved = await bookmarks.add(
        location: selection.location,
        chapterTitle: selection.chapterTitle,
        excerpt: selection.excerpt,
      );
    } catch (error, stackTrace) {
      AppLog.e('加入書籤失敗', error: error, stackTrace: stackTrace);
      _showNotice(failureMessage('加入書籤', error));
      return;
    }
    if (saved case final kept?) {
      _showNotice(
        '已加入書籤',
        action: (
          label: '復原',
          onPressed: () => unawaited(bookmarks.remove(kept)),
        ),
      );
    } else {
      _showNotice('無法加入書籤');
    }
  }

  /// 閱讀選單「更多」的「書籤」：在畫面頂端那一句的開頭留一個書籤，和選字
  /// 選單的「書籤」存的是同一筆（章、章內位置、錨點與摘錄都照同一套算）。
  Future<void> addBookmarkAtTop() async {
    final runtime = _host.runtime;
    if (runtime == null) {
      _showNotice('無法加入書籤');
      return;
    }
    final top =
        runtime.captureVisibleLocation() ?? runtime.state.visibleLocation;
    final content = runtime.repository.cachedContent(top.chapterIndex);
    final paragraph = content?.paragraphAt(top.charOffset);
    if (content == null || paragraph == null) {
      _showNotice('無法加入書籤');
      return;
    }
    var start = paragraph.offset;
    if (start >= paragraph.end && paragraph.end > paragraph.start) {
      start = paragraph.end - 1;
    }
    await addBookmark(
      bookmarkInSentence(
        displayText: content.displayText,
        contentHash: content.contentHash,
        chapterTitle: content.title,
        chapterIndex: top.chapterIndex,
        paragraphStart: paragraph.start,
        paragraphEnd: paragraph.end,
        start: start,
        end: start,
      ),
    );
  }

  /// 跳到書籤那一句，照目前的排版放在畫面上方讀起的位置（同跳章）。
  Future<void> jumpToBookmark(
    Bookmark bookmark, {
    Future<void>? settled,
  }) async {
    final runtime = _host.runtime;
    if (runtime == null) return;
    await _jumpTo(
      ReaderBookmarks.locationOf(
        bookmark,
        chapterIndex: ReaderBookmarks.chapterIndexIn(
          bookmark,
          runtime.chapters,
        ),
      ),
      settled: settled,
    );
  }

  /// 選字選單「⋮」裡的「標註」：把選到的字畫上標註（顏色與樣子沿用上一
  /// 個），提示可「復原」。
  Future<void> addHighlight(SelectionHighlight selection) async {
    final highlights = _host.highlights;
    if (selection.quote.trim().isEmpty) {
      _showNotice('選到的都是空白，沒有標註');
      return;
    }
    final Highlight? saved;
    try {
      saved = await highlights.add(
        location: selection.location,
        chapterTitle: selection.chapterTitle,
        quote: selection.quote,
      );
    } catch (error, stackTrace) {
      AppLog.e('加入標註失敗', error: error, stackTrace: stackTrace);
      _showNotice(failureMessage('加入標註', error));
      return;
    }
    if (saved case final kept?) {
      _showNotice(
        '已標註',
        action: (
          label: '復原',
          onPressed: () => unawaited(highlights.remove(kept)),
        ),
      );
    } else {
      _showNotice('無法加入標註');
    }
  }

  /// 刪掉一個標註，提示可「復原」。
  void deleteHighlight(Highlight highlight) {
    final highlights = _host.highlights;
    unawaited(highlights.remove(highlight));
    _showNotice(
      '已刪除標註',
      action: (
        label: '復原',
        onPressed: () => unawaited(highlights.save(highlight)),
      ),
    );
  }

  /// 跳到標註開頭那一行（同跳書籤）。
  Future<void> jumpToHighlight(
    Highlight highlight, {
    Future<void>? settled,
  }) async {
    final runtime = _host.runtime;
    if (runtime == null) return;
    await _jumpTo(
      ReaderHighlights.locationOf(
        highlight,
        chapterIndex: ReaderHighlights.chapterIndexIn(
          highlight,
          runtime.chapters,
        ),
      ),
      settled: settled,
    );
  }

  /// 跳到 [target]，照目前的排版放在畫面上方讀起的位置（同跳章）。
  Future<void> _jumpTo(ReaderLocation target, {Future<void>? settled}) async {
    final runtime = _host.runtime;
    if (runtime == null) return;
    final location = target.copyWith(
      visualOffsetPx: runtime.state.layoutSpec.anchorOffsetInViewport,
    );
    await runtime.jumpToLocation(location, settled: settled);
    if (runtime.state.visibleLocation.chapterIndex == location.chapterIndex) {
      await _host.tts?.followManualJump();
    }
  }

  /// 「隱藏」新增的規則都放在這一組，在替換規則清單裡找得到。
  static const String _hiddenTextGroup = '選字隱藏';

  /// 「替換」新增的規則預設放在這一組（編輯畫面裡可以改）。
  static const String _replacedTextGroup = '選字替換';

  /// 「隱藏」「替換」提示的「復原」：刪掉剛新增的規則、重新排版。
  Future<void> _removeAddedRule(ReplaceRuleDao replaceDao, int id) async {
    try {
      await replaceDao.deleteById(id);
      final reloaded =
          await _host.runtime?.reloadContentPreservingLocation() ?? false;
      if (!reloaded) _showNotice('已刪除剛新增的規則，但正文沒有更新');
    } catch (error, stackTrace) {
      AppLog.e('復原新增的規則失敗', error: error, stackTrace: stackTrace);
      _showNotice(failureMessage('復原', error));
    }
  }

  /// 替換規則即時測試的預設文字：畫面頂端那一段的原文（轉過繁簡、套用替換
  /// 規則之前，規則才測得出效果）。用畫面上這一份正文排版時的原文
  /// （[ReaderChapterRepository.rawContentOf]，同選字找原文）：存著的正文換過
  /// （單章借源、重新取得本章）而畫面還沒換時，不拿新的原文對舊的段落。
  /// 取不到時回傳 null。
  Future<String?> _replaceTestSample() async {
    final runtime = _host.runtime;
    if (runtime == null) return null;
    final location = runtime.state.visibleLocation;
    final chapter = runtime.chapterAt(location.chapterIndex);
    final shown = runtime.repository.cachedContent(location.chapterIndex);
    if (chapter == null || shown == null) return null;
    final raw = runtime.repository.rawContentOf(
      location.chapterIndex,
      shown.contentHash,
    );
    if (raw == null) return null;
    // 讀到時面板常還在滑入：整章切段落、段落修復與繁簡轉換在另一個
    // isolate 做，不算整章的雜湊。
    final convertType = runtime.repository.currentChineseConvert();
    final paragraphs = await ReaderContentTransformer.sourceParagraphs(
      rawContent: raw,
      chineseConvertType: convertType,
    );
    if (paragraphs.isEmpty) return null;
    final index = paragraphIndexAt(shown, location.charOffset);
    // 畫面上的第幾段是替換規則套用之後的：規則整段刪掉（「隱藏」）、合併或
    // 拆開段落時，和原文的第幾段對不上，照規則套用後的段落對回原文。
    final book = _host.book;
    final replaceDao = _host.dependencies.replaceDao;
    if (!book.getUseReplaceRule() || replaceDao == null) {
      return paragraphs[index.clamp(0, paragraphs.length - 1)];
    }
    try {
      final stage = await ReaderContentTransformer.ruleStageParagraphs(
        book: book,
        chapter: chapter,
        rawContent: raw,
        enabledRules: await replaceDao.getEnabledForBook(
          book.name,
          book.origin,
        ),
        chineseConvertType: convertType,
        onRuleTimedOut: runtime.repository.disableTimedOutRule,
      );
      return sourceParagraphAt(paragraphs, stage.paragraphs, index);
    } catch (error, stack) {
      AppLog.e('對齊替換規則測試文字失敗: $error', error: error, stackTrace: stack);
      return paragraphs[index.clamp(0, paragraphs.length - 1)];
    }
  }

  /// 音量鍵翻頁：音量下是下一頁、音量上是上一頁。
  Future<void> movePage({required bool forward}) => _movePage(forward: forward);

  Future<void> _movePage({required bool forward}) async {
    final command = forward
        ? _host.viewportController.moveToNextPage
        : _host.viewportController.moveToPrevPage;
    if (command == null) return;
    await command();
  }
}

/// [content] 的 `displayText` 位置 [charOffset] 落在第幾段正文；在章節標題上
/// 時是第一段。替換規則一般不增刪段落，所以這個序號也能拿來找原文的同一段。
@visibleForTesting
int paragraphIndexAt(ReaderContent content, int charOffset) {
  var end = content.bodyStartOffset;
  for (var i = 0; i < content.paragraphs.length; i++) {
    // 段落之間以兩個換行相接。
    end += content.paragraphs[i].length + 2;
    if (charOffset < end) return i;
  }
  return content.paragraphs.isEmpty ? 0 : content.paragraphs.length - 1;
}
