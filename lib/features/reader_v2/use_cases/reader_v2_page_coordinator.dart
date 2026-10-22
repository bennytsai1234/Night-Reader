import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/exception/user_error.dart';
import 'package:night_reader/core/models/book/book_extensions.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content_transformer.dart';
import 'package:night_reader/features/reader_v2/features/replace_rule/selection_source_text.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/selection_service.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/use_cases/coordinators/reader_v2_chapter_navigation_resolver.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_controller_host.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_tap_action.dart';
import 'package:night_reader/features/reader_v2/features/replace_rule/reader_v2_replace_rule_sheet.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_highlight_follower.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';

typedef ReaderV2NoticeSink = void Function(
  String message, {
  ReaderV2NoticeAction? action,
});

/// 提示列右側的按鈕，例如「復原」。
typedef ReaderV2NoticeAction = ({String label, VoidCallback onPressed});

class ReaderV2PageCoordinator {
  ReaderV2PageCoordinator({required this._host, required this._showNotice}) {
    _ttsFollower = ReaderV2TtsHighlightFollower(
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

  final ReaderV2ControllerHost _host;
  final ReaderV2NoticeSink _showNotice;

  /// 拖動條跨檔位的預覽跳轉防抖：快速滑過多個檔位時只跳最後停留者。
  static const Duration _scrubPreviewDebounce = Duration(milliseconds: 180);
  Timer? _scrubPreviewTimer;

  late final ReaderV2TtsHighlightFollower _ttsFollower;

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
        unawaited(_movePage(forward: true));
        return;
      case ReaderV2TapAction.prevPage:
        unawaited(_movePage(forward: false));
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

  /// [settled] 見 [ReaderV2Runtime.jumpToChapter]。
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
        ReaderV2Location(
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
      ReaderV2Location(chapterIndex: chapterIndex, charOffset: charOffset),
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
      _host.menu.hideControlsForAutoPage();
      // 自動捲動與朗讀跟隨不同時移動正文；後開的接手。
      final tts = _host.tts;
      if (tts != null && (tts.isPlaying || tts.currentHighlight != null)) {
        unawaited(tts.stop());
      }
    }
    autoPage.toggle();
  }

  void maybeFollowTtsHighlight() {
    // 拖進度條時畫面跟著拖動走，放開後朗讀改從新位置念。
    if (_host.menu.isScrubbing) return;
    // 視窗只在換句時跟隨。
    _ttsFollower.update(_host.tts?.currentHighlight);
  }

  Future<void> openReplaceRule(BuildContext context) async {
    final replaceDao = _host.dependencies.replaceDao;
    if (replaceDao == null) {
      _showNotice('替換規則資料庫不可用');
      return;
    }
    // 面板滑上來的第一幀，骨架就照輸入框裡的字與啟用的規則數算高度，所以
    // 兩樣都先讀好再開；資料庫在背景 isolate，等的這一下主執行緒沒在忙。
    final (sample, enabledRules) = await (
      _replaceTestSample(),
      ReaderV2ReplaceRuleSheet.loadEnabledRules(replaceDao, _host.book),
    ).wait;
    if (!context.mounted) return;
    await AppBottomSheet.showCustom<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReaderV2ReplaceRuleSheet(
        book: _host.book,
        bookDao: _host.dependencies.bookDao,
        replaceDao: replaceDao,
        onReload: () async {
          await _host.runtime?.reloadContentPreservingLocation();
        },
        testSample: sample,
        enabledRules: enabledRules,
      ),
    );
  }

  /// 選字選單的「隱藏」：新增一條把這段字換成空白的替換規則，套用到所有
  /// 書、排在既有規則之後，重新排版後提示可以復原。規則用這一段在既有規則
  /// 套用之後的原文：畫面上的字經過排版整理與繁簡轉換，直接用常對不到
  /// （見 [sourceRangeOf]）。
  Future<void> hideText(ParagraphSelection selection) async {
    final book = _host.book;
    final replaceDao = _host.dependencies.replaceDao;
    final contentDao = _host.dependencies.readerChapterContentDao;
    final chapter = _host.runtime?.chapterAt(selection.chapterIndex);
    if (replaceDao == null || contentDao == null || chapter == null) {
      _showNotice('無法隱藏這段字');
      return;
    }
    if (!book.getUseReplaceRule()) {
      _showNotice('這本書沒有套用替換規則，打開後才能隱藏');
      return;
    }
    final String pattern;
    final int id;
    try {
      final raw = await ReaderChapterContentStore(
        chapterDao: _host.dependencies.chapterDao,
        contentDao: contentDao,
      ).getRawContent(book: book, chapter: chapter);
      final paragraphs = raw == null
          ? const <String>[]
          : await ReaderV2ContentTransformer.ruleStageParagraphs(
              book: book,
              chapter: chapter,
              rawContent: raw,
              enabledRules: await replaceDao.getEnabledForBook(
                book.name,
                book.origin,
              ),
            );
      final source = selection.paragraphIndex < paragraphs.length
          ? paragraphs[selection.paragraphIndex]
          : null;
      final range = source == null
          ? null
          : sourceRangeOf(
              source: source,
              shown: selection.paragraph,
              start: selection.start,
              end: selection.end,
            );
      if (source == null || range == null) {
        _showNotice('找不到這段字的原文，沒有隱藏');
        return;
      }
      pattern = source.substring(range.start, range.end);
      final rules = await replaceDao.getAll();
      id = await replaceDao.insert(
        ReplaceRule(
          name: pattern,
          group: _hiddenTextGroup,
          pattern: pattern,
          replacement: '',
          isRegex: false,
          order: rules.fold(0, (last, rule) => math.max(last, rule.order + 1)),
        ),
      );
    } catch (error, stackTrace) {
      AppLog.e('隱藏選字失敗', error: error, stackTrace: stackTrace);
      _showNotice(failureMessage('隱藏', error));
      return;
    }
    // 規則已經存進去了：重排失敗也留著復原，不然只能到替換規則裡刪。
    final undo = (
      label: '復原',
      onPressed: () => unawaited(_restoreHiddenText(replaceDao, id)),
    );
    var reloaded = false;
    try {
      reloaded =
          await _host.runtime?.reloadContentPreservingLocation() ?? false;
    } catch (error, stackTrace) {
      AppLog.e('隱藏選字後重排失敗', error: error, stackTrace: stackTrace);
    }
    _showNotice(reloaded ? '已隱藏「$pattern」' : '已新增隱藏規則，但正文沒有更新', action: undo);
  }

  /// 「隱藏」新增的規則都放在這一組，在替換規則清單裡找得到。
  static const String _hiddenTextGroup = '選字隱藏';

  Future<void> _restoreHiddenText(ReplaceRuleDao replaceDao, int id) async {
    try {
      await replaceDao.deleteById(id);
      final reloaded =
          await _host.runtime?.reloadContentPreservingLocation() ?? false;
      if (!reloaded) _showNotice('已刪除隱藏規則，但正文沒有更新');
    } catch (error, stackTrace) {
      AppLog.e('復原隱藏的字失敗', error: error, stackTrace: stackTrace);
      _showNotice(failureMessage('復原', error));
    }
  }

  /// 替換規則即時測試的預設文字：畫面頂端那一段的原文（套用替換規則之前，
  /// 規則才測得出效果）。原文存在手機裡才有；取不到時回傳 null。
  Future<String?> _replaceTestSample() async {
    final runtime = _host.runtime;
    final contentDao = _host.dependencies.readerChapterContentDao;
    if (runtime == null || contentDao == null) return null;
    final location = runtime.state.visibleLocation;
    final chapter = runtime.chapterAt(location.chapterIndex);
    if (chapter == null) return null;
    final String? raw;
    try {
      raw = await ReaderChapterContentStore(
        chapterDao: _host.dependencies.chapterDao,
        contentDao: contentDao,
      ).getRawContent(book: _host.book, chapter: chapter);
    } catch (error, stack) {
      AppLog.e('讀取替換規則測試文字失敗: $error', error: error, stackTrace: stack);
      return null;
    }
    if (raw == null) return null;
    final paragraphs = ReaderV2Content.fromRaw(
      chapterIndex: location.chapterIndex,
      title: '',
      rawText: raw,
    ).paragraphs;
    if (paragraphs.isEmpty) return null;
    final shown = runtime.repository.cachedContent(location.chapterIndex);
    final index = shown == null
        ? 0
        : paragraphIndexAt(shown, location.charOffset);
    return paragraphs[index.clamp(0, paragraphs.length - 1)];
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
int paragraphIndexAt(ReaderV2Content content, int charOffset) {
  var end = content.bodyStartOffset;
  for (var i = 0; i < content.paragraphs.length; i++) {
    // 段落之間以兩個換行相接。
    end += content.paragraphs[i].length + 2;
    if (charOffset < end) return i;
  }
  return content.paragraphs.isEmpty ? 0 : content.paragraphs.length - 1;
}
