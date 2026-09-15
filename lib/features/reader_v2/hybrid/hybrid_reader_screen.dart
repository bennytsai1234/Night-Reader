import 'dart:async';
import 'dart:convert' show jsonEncode;
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kDebugMode, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

import 'package:night_reader/core/config/app_config.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_highlight.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_state.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_pointer_tap_layer.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';

import 'anchor/anchor_manager.dart';
import 'core/hybrid_contracts.dart';
import 'core/hybrid_types.dart';

import 'package:night_reader/features/reader_v2/correctness/reader_correctness_visual_oracle.dart';
import 'package:night_reader/features/reader_v2/correctness/reader_correctness_foundation.dart';

import 'measure/document_index.dart';
import 'measure/measurement_store.dart';
import 'measure/metrics_disk_cache.dart';
import 'overlay/tts_highlight_overlay.dart';
import 'paragraph/paragraph_cache.dart';
import 'progress/hybrid_progress.dart';
import 'pump/budget_governor.dart';
import 'pump/layout_pump.dart';
import 'telemetry/hybrid_telemetry.dart';
import 'text/hybrid_chapter_repository.dart';
import 'text/text_preprocessor.dart';
import 'view/admission_controller.dart';
import 'view/hybrid_scroll_view.dart';
import 'view/hybrid_ensure_gate.dart';

/// 方案 B 混合架構的閱讀主面（W3 整合層）。
///
/// 取代 `EngineReaderV2Screen`：對上維持 D5 的三個契約面——
/// 1. `ReaderV2ViewportController` 七閉包 attach/detach（前六個經 FIFO 佇列，
///    settleScroll 直達）；
/// 2. runtime 的 capture / restore 註冊（owner 語意照舊）；
/// 3. settle 點（拖曳結束、fling 停止、跳章完成、epoch 重建完成）一律
///    capture + saveProgress。
/// 對下組裝 hybrid 各模組：text→measure→paragraph/pump→view，錨點換算
/// 全部經 [HybridAnchor]（I6），epoch 對齊 runtime 的 layoutGeneration（D9）。
class HybridReaderScreen extends StatefulWidget {
  /// Debug-only frame invariant probe.  It is deliberately opt-in so the
  /// normal reader path does not register a frame callback or allocate probe
  /// state.
  @visibleForTesting
  static bool debugFrameInvariantsEnabled = false;

  /// Debug-only pixel oracle.  The normal reader does not create the
  /// RepaintBoundary, register a post-frame callback, or retain raster state
  /// while this is false.  The flag is intentionally separate from the
  /// semantic invariant hook because performance runs must disable both.
  @visibleForTesting
  static bool debugVisualOracleEnabled = false;

  const HybridReaderScreen({
    super.key,
    required this.runtime,
    required this.backgroundColor,
    required this.textColor,
    required this.style,
    this.onContentTapUp,
    this.viewportController,
    this.ttsHighlight,
    this.progressListenable,
    this.bookUrl,
    this.preprocessor = const TextPreprocessor(),
    this.enableDiskMetrics = true,
    this.paragraphCacheCapacity = 512,
  });

  final ReaderV2Runtime runtime;
  final Color backgroundColor;
  final Color textColor;
  final ReaderV2Style style;
  final GestureTapUpCallback? onContentTapUp;
  final ReaderV2ViewportController? viewportController;
  final ReaderV2TtsHighlight? ttsHighlight;

  /// D6：章序 + 章內百分比的對外通道（頁面組裝層讀取顯示）。
  final ValueNotifier<HybridProgressSnapshot?>? progressListenable;

  /// D10 磁碟 metrics 的檔名 key；null 時停用磁碟快取。
  final String? bookUrl;

  /// 測試可注入 `TextPreprocessor(useIsolate: false)` 避免真 isolate。
  final HybridTextPreprocessor preprocessor;
  final bool enableDiskMetrics;

  /// 測試 seam：縮小 ParagraphCache 容量以重現 LRU 逐出；正式路徑用預設。
  final int paragraphCacheCapacity;

  @override
  State<HybridReaderScreen> createState() => _HybridReaderScreenState();
}

/// The deliberately small record captured by the frame invariant hook.  It
/// contains only scalar state and the keys currently intersecting the
/// viewport; it is not a [HybridReaderScreen.debugSnapshot].
@visibleForTesting
final class HybridFrameInvariantRecord {
  const HybridFrameInvariantRecord({
    required this.timestampMicros,
    required this.phase,
    required this.scrollOffset,
    required this.viewportHeight,
    required this.dragging,
    required this.isScrolling,
    required this.restoreLocked,
    required this.initialRestoreCompleted,
    required this.pendingChapterJumpTarget,
    required this.epoch,
    required this.layoutGeneration,
    required this.documentIndexRevision,
    required this.resetGeneration,
    required this.indexBindingResetGeneration,
    required this.indexCenter,
    required this.visibleKeys,
    required this.visibleChapters,
    required this.missingParagraphCount,
    required this.unloadedChapterCount,
    required this.dominantVisibleChapter,
    this.anchorVisibleChapter,
    required this.displayedProgressChapter,
    required this.pumpQueueDepth,
    required this.scrollPixels,
    required this.minScrollExtent,
    required this.maxScrollExtent,
    required this.scrollActivity,
    required this.scrollVelocity,
    required this.operationTokenId,
    required this.operationIsCurrent,
    required this.chapterCount,
    required this.errorPresent,
  });

  final int timestampMicros;
  final String phase;
  final double? scrollOffset;
  final double? viewportHeight;
  final bool dragging;
  final bool isScrolling;
  final bool restoreLocked;
  final bool initialRestoreCompleted;
  final ReaderV2Location? pendingChapterJumpTarget;
  final int epoch;
  final int layoutGeneration;
  final int documentIndexRevision;
  final int resetGeneration;
  final int indexBindingResetGeneration;
  final BlockKey indexCenter;
  final List<BlockKey> visibleKeys;
  final List<int> visibleChapters;
  final int missingParagraphCount;
  final int unloadedChapterCount;
  final int? dominantVisibleChapter;
  final int? anchorVisibleChapter;
  final int? displayedProgressChapter;
  final int pumpQueueDepth;
  final double? scrollPixels;
  final double? minScrollExtent;
  final double? maxScrollExtent;
  final String scrollActivity;
  final double? scrollVelocity;
  final int? operationTokenId;
  final bool operationIsCurrent;
  final int chapterCount;
  final bool errorPresent;

  bool get isIdle =>
      !dragging &&
      !isScrolling &&
      pumpQueueDepth == 0 &&
      pendingChapterJumpTarget == null;

  Map<String, Object?> toJson() {
    Map<String, int> keyJson(BlockKey key) => <String, int>{
      'chapterIndex': key.chapterIndex,
      'blockIndex': key.blockIndex,
    };
    return <String, Object?>{
      'timestampMicros': timestampMicros,
      'phase': phase,
      'scrollOffset': scrollOffset,
      'viewportHeight': viewportHeight,
      'dragging': dragging,
      'isScrolling': isScrolling,
      'restoreLocked': restoreLocked,
      'initialRestoreCompleted': initialRestoreCompleted,
      'pendingChapterJumpTarget': pendingChapterJumpTarget?.toJson(),
      'epoch': epoch,
      'layoutGeneration': layoutGeneration,
      'documentIndexRevision': documentIndexRevision,
      'resetGeneration': resetGeneration,
      'indexBindingResetGeneration': indexBindingResetGeneration,
      'indexCenter': keyJson(indexCenter),
      'visibleKeyCount': visibleKeys.length,
      'visibleKeyRange': visibleKeys.isEmpty
          ? null
          : <String, Object?>{
              'first': keyJson(visibleKeys.first),
              'last': keyJson(visibleKeys.last),
            },
      'visibleKeys': [for (final key in visibleKeys) keyJson(key)],
      'visibleChapters': visibleChapters,
      'missingParagraphCount': missingParagraphCount,
      'unloadedChapterCount': unloadedChapterCount,
      'dominantVisibleChapter': dominantVisibleChapter,
      'anchorVisibleChapter': anchorVisibleChapter,
      'displayedProgressChapter': displayedProgressChapter,
      'pumpQueueDepth': pumpQueueDepth,
      'scrollPixels': scrollPixels,
      'minScrollExtent': minScrollExtent,
      'maxScrollExtent': maxScrollExtent,
      'scrollActivity': scrollActivity,
      'scrollVelocity': scrollVelocity,
      'operationTokenId': operationTokenId,
      'operationIsCurrent': operationIsCurrent,
      'chapterCount': chapterCount,
      'errorPresent': errorPresent,
    };
  }
}

@visibleForTesting
final class HybridFrameInvariantViolation {
  const HybridFrameInvariantViolation({
    required this.invariant,
    required this.reason,
    required this.current,
    required this.previous,
    this.oracle = 'runtime',
    this.windowEvidence,
    this.sourceInvariant,
  });

  final String invariant;
  final String reason;
  final HybridFrameInvariantRecord current;
  final HybridFrameInvariantRecord? previous;
  final String oracle;
  final Map<String, Object?>? windowEvidence;
  final String? sourceInvariant;

  Map<String, Object?> toJson() => <String, Object?>{
    'invariant': invariant,
    'reason': reason,
    'oracle': oracle,
    'sourceInvariant': sourceInvariant,
    'current': current.toJson(),
    'previous': previous?.toJson(),
    'windowEvidence': windowEvidence,
  };
}

bool _sameBlockKeyList(List<BlockKey> a, List<BlockKey> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _isConsecutiveBlockKey(BlockKey previous, BlockKey next) {
  if (previous.chapterIndex == next.chapterIndex) {
    return next.blockIndex == previous.blockIndex + 1;
  }
  return next.chapterIndex == previous.chapterIndex + 1 && next.blockIndex == 0;
}

bool _isFiniteScrollGeometry(HybridFrameInvariantRecord record) {
  final pixels = record.scrollPixels;
  final minExtent = record.minScrollExtent;
  final maxExtent = record.maxScrollExtent;
  return pixels != null &&
      minExtent != null &&
      maxExtent != null &&
      pixels.isFinite &&
      minExtent.isFinite &&
      maxExtent.isFinite;
}

bool _sameReadyGeneration(
  HybridFrameInvariantRecord current,
  HybridFrameInvariantRecord previous,
) {
  return current.phase == 'ready' &&
      previous.phase == 'ready' &&
      current.initialRestoreCompleted &&
      previous.initialRestoreCompleted &&
      !current.restoreLocked &&
      !previous.restoreLocked &&
      current.epoch == previous.epoch &&
      current.layoutGeneration == previous.layoutGeneration &&
      current.resetGeneration == previous.resetGeneration &&
      current.indexBindingResetGeneration ==
          previous.indexBindingResetGeneration;
}

bool _hasExplicitNavigation(
  HybridFrameInvariantRecord current,
  HybridFrameInvariantRecord previous,
) {
  return current.pendingChapterJumpTarget != null ||
      previous.pendingChapterJumpTarget != null ||
      (current.operationTokenId != null &&
          previous.operationTokenId != null &&
          current.operationTokenId != previous.operationTokenId);
}

/// Evaluate the same rules used by the production debug hook.  Keeping the
/// rule evaluator pure makes it possible to prove synthetic violations in a
/// fast widget test without adding a test-only mutation path to the reader.
@visibleForTesting
List<HybridFrameInvariantViolation> evaluateHybridFrameInvariants({
  required HybridFrameInvariantRecord current,
  HybridFrameInvariantRecord? previous,
  HybridFrameInvariantRecord? previousPrevious,
}) {
  final violations = <HybridFrameInvariantViolation>[];
  void add(String invariant, String reason) {
    violations.add(
      HybridFrameInvariantViolation(
        invariant: invariant,
        reason: reason,
        current: current,
        previous: previous,
      ),
    );
  }

  final readyFrame =
      current.phase == 'ready' &&
      current.initialRestoreCompleted &&
      !current.restoreLocked;
  if (readyFrame && current.visibleKeys.isNotEmpty) {
    for (var i = 1; i < current.visibleKeys.length; i += 1) {
      if (!_isConsecutiveBlockKey(
        current.visibleKeys[i - 1],
        current.visibleKeys[i],
      )) {
        add(
          'I1',
          'visible keys 不連續：previous=${current.visibleKeys[i - 1]} '
              'current=${current.visibleKeys[i]}',
        );
        break;
      }
    }
    if (current.missingParagraphCount > 0) {
      add(
        'I2',
        'visible 範圍有 ${current.missingParagraphCount} 個 paragraph 不 fresh',
      );
    }
    final uniqueKeys = current.visibleKeys.toSet();
    if (uniqueKeys.length != current.visibleKeys.length) {
      add(
        'I3',
        'visible keys 有重複：count=${current.visibleKeys.length} '
            'unique=${uniqueKeys.length}',
      );
    }
    if (current.unloadedChapterCount > 0) {
      add('I5', 'visible chapters 有 ${current.unloadedChapterCount} 章未載入或已失效');
    }
    if (current.pendingChapterJumpTarget == null &&
        current.displayedProgressChapter != null &&
        current.dominantVisibleChapter != null &&
        current.displayedProgressChapter != current.dominantVisibleChapter) {
      add(
        'I6',
        'displayedProgressChapter=${current.displayedProgressChapter} '
            'dominantVisibleChapter=${current.dominantVisibleChapter}',
      );
    }
    if (current.epoch != current.layoutGeneration ||
        current.resetGeneration != current.indexBindingResetGeneration) {
      add(
        'I4',
        'epoch=${current.epoch} layoutGeneration=${current.layoutGeneration} '
            'reset=${current.resetGeneration}/'
            '${current.indexBindingResetGeneration} indexCenter=${current.indexCenter}',
      );
    }
  }

  if (previous != null &&
      readyFrame &&
      previous.phase == 'ready' &&
      previous.initialRestoreCompleted &&
      !previous.restoreLocked &&
      current.resetGeneration == previous.resetGeneration &&
      current.indexCenter == previous.indexCenter &&
      current.epoch == previous.epoch &&
      current.layoutGeneration == previous.layoutGeneration &&
      previous.isIdle &&
      current.isIdle) {
    final offsetChanged =
        current.scrollOffset == null ||
        previous.scrollOffset == null ||
        (current.scrollOffset! - previous.scrollOffset!).abs() > 0.01;
    final keysChanged = !_sameBlockKeyList(
      current.visibleKeys,
      previous.visibleKeys,
    );
    if (offsetChanged || keysChanged) {
      add(
        'I7',
        'idle 後畫面仍變動：offsetChanged=$offsetChanged '
            'keysChanged=$keysChanged',
      );
    }
  }

  // I9：ready 代表可以呈現內容；一個 ready、非 restoring frame 不得是
  // 沒有任何可見 block 的空視窗。這和 I1 的「已有 keys 時排序連續」是
  // 不同的資料完整性條件。
  if (readyFrame && current.visibleKeys.isEmpty) {
    add('I9', 'ready 非 restoring frame 沒有 visible keys');
  }

  // I11：drag 必須由實際 user drag 狀態支持；ballistic 只允許從同一條
  // drag/ballistic stream 延續。driven activity（例如 explicit restore）
  // 不是 user input，也不會被這條誤判。
  if (readyFrame && current.pendingChapterJumpTarget == null) {
    final unsolicitedDrag =
        current.scrollActivity == 'drag' && !current.dragging;
    final unsolicitedBallistic =
        current.scrollActivity == 'ballistic' &&
        !current.dragging &&
        previous != null &&
        (previous.scrollActivity != 'drag' &&
            previous.scrollActivity != 'ballistic');
    if (unsolicitedDrag || unsolicitedBallistic) {
      add(
        'I11',
        '無 user input／pending navigation 卻進入 ${current.scrollActivity}',
      );
    }
  }

  // I15：ScrollPosition 的三個幾何 scalar 必須同時存在、有限且彼此
  // 合法。ClampingScrollPhysics 在 user drag/ballistic hand-off 期間可
  // 暫時保留 out-of-range pixels，直到 activity 回到 idle；這裡只判定
  // 穩定 idle frame，不把框架既有的 clamping transient 當成錯誤。
  if (readyFrame && current.scrollActivity == 'idle') {
    final pixels = current.scrollPixels;
    final minExtent = current.minScrollExtent;
    final maxExtent = current.maxScrollExtent;
    // A ready frame can be painted while ScrollController is between detach
    // and attach. Nullable geometry is therefore an unobservable sample, not
    // itself a range violation; a supplied partial/non-finite tuple is still
    // rejected by I15.
    final hasAnyGeometry =
        pixels != null || minExtent != null || maxExtent != null;
    if (hasAnyGeometry) {
      if (!_isFiniteScrollGeometry(current) ||
          minExtent! > maxExtent! ||
          pixels! < minExtent ||
          pixels > maxExtent) {
        add(
          'I15',
          'scroll geometry 非法：min=$minExtent pixels=$pixels max=$maxExtent',
        );
      }

      if (current.visibleChapters.contains(0) &&
          _isFiniteScrollGeometry(current) &&
          pixels! < minExtent!) {
        add(
          'I16',
          '第一章 visible 時越過 document top：pixels=$pixels min=$minExtent',
        );
      }
      if (current.chapterCount > 0 &&
          current.visibleChapters.contains(current.chapterCount - 1) &&
          _isFiniteScrollGeometry(current) &&
          pixels! > maxExtent!) {
        add(
          'I17',
          '最後一章 visible 時越過 document bottom：pixels=$pixels max=$maxExtent',
        );
      }
    }
  }

  // I18：pending jump 必須仍有一個可觀測 operation owner。state machine
  // 的正式實作本身只保留一個 current token；這條也捕捉 owner 丟失的
  // 反面，讓 pending 狀態不會在 trace 中變成無主操作。
  if (current.pendingChapterJumpTarget != null &&
      current.operationTokenId == null) {
    add('I18', 'pending operation 沒有唯一 operation token owner');
  }

  // I19：operation token id 由 state machine 單調遞增。若較新的 request
  // 已出現在前一幀，後一幀卻仍回報更舊的 id 且宣稱 current，就是 stale
  // owner 重新取得 current 身分。
  if (previous != null &&
      current.operationIsCurrent &&
      current.operationTokenId != null &&
      previous.operationTokenId != null &&
      current.operationTokenId! < previous.operationTokenId!) {
    add(
      'I19',
      '較新的 operation request 後仍回報舊 current token：'
          'previous=${previous.operationTokenId} current=${current.operationTokenId}',
    );
  }

  // I20：stale token 沒有 write-back 權限；只要它所屬的 frame 改變了
  // scrollPixels，就留下明確的 ownership violation。這條不要求 phase
  // ready，因為 stale completion 常發生在 layingOut/restoring 轉場。
  if (previous != null &&
      current.operationTokenId != null &&
      !current.operationIsCurrent &&
      current.scrollPixels != null &&
      previous.scrollPixels != null &&
      current.scrollPixels!.isFinite &&
      previous.scrollPixels!.isFinite &&
      current.scrollPixels != previous.scrollPixels) {
    add(
      'I20',
      '非 current operation token 改動 scrollPixels：'
          'previous=${previous.scrollPixels} current=${current.scrollPixels}',
    );
  }

  // I21：世代與索引 revision 只能向前。這條故意不受 ready gate 限制，
  // 因為 stale async completion 在非 ready phase 也必須被觀測。
  if (previous != null &&
      (current.epoch < previous.epoch ||
          current.layoutGeneration < previous.layoutGeneration ||
          current.documentIndexRevision < previous.documentIndexRevision ||
          current.resetGeneration < previous.resetGeneration)) {
    add(
      'I21',
      'generation/revision 倒退：'
          'epoch ${previous.epoch}->${current.epoch}, '
          'layout ${previous.layoutGeneration}->${current.layoutGeneration}, '
          'document ${previous.documentIndexRevision}->'
          '${current.documentIndexRevision}, '
          'reset ${previous.resetGeneration}->${current.resetGeneration}',
    );
  }

  // I24：error recovery 可以成功，但 ready frame 不得仍攜帶 error。current
  // record 同時保存 phase + errorPresent，故 failure bundle 能在不重跑時
  // 清楚表達這個 error -> ready transition。
  if (previous != null &&
      previous.phase == 'error' &&
      current.phase == 'ready' &&
      current.errorPresent) {
    add('I24', 'error -> ready 後 errorPresent 仍為 true');
  }

  // I26：沒有 explicit navigation 的 ready stream 中，顯示進度章節不可
  // 跨章跳躍。operation token 的變更視為明確操作邊界；pending target 則
  // 覆蓋 jump 的中間幀與完成幀。
  if (previous != null &&
      _sameReadyGeneration(current, previous) &&
      !_hasExplicitNavigation(current, previous) &&
      current.displayedProgressChapter != null &&
      previous.displayedProgressChapter != null &&
      current.displayedProgressChapter != previous.displayedProgressChapter) {
    add(
      'I26',
      '非 explicit navigation 時 displayedProgressChapter 跳躍：'
          '${previous.displayedProgressChapter}->'
          '${current.displayedProgressChapter}',
    );
  }

  // I12'/I13'：I8 仍是對外 invariant id，但其資料來源改為真實
  // ScrollActivity.velocity。HybridScrollPhysics 對 ballistic 使用
  // ClampingScrollSimulation，因此同一 stream 的速度方向不得反轉，
  // magnitude 應向 0 收斂。HybridScrollPhysics 會隨 admission lead 在
  // baseFlingFriction=0.015 與 deficitFlingFriction=0.09 間重建
  // ClampingScrollSimulation；因此同一 activity 的相鄰 post-frame 速度
  // 可能因摩擦解除而上升，允許的最大倍率取實際物理摩擦比 0.09/0.015=6，
  // 再加 5% 無單位 sampling jitter，不使用固定 logical-pixel 常數。
  if (previous != null &&
      _sameReadyGeneration(current, previous) &&
      !current.dragging &&
      !previous.dragging &&
      current.pendingChapterJumpTarget == null &&
      previous.pendingChapterJumpTarget == null &&
      current.scrollActivity == 'ballistic' &&
      previous.scrollActivity == 'ballistic' &&
      current.scrollVelocity != null &&
      previous.scrollVelocity != null &&
      current.scrollVelocity!.isFinite &&
      previous.scrollVelocity!.isFinite &&
      current.timestampMicros > previous.timestampMicros) {
    final velocity = current.scrollVelocity!;
    final previousVelocity = previous.scrollVelocity!;
    if (velocity != 0 &&
        previousVelocity != 0 &&
        velocity.sign != previousVelocity.sign) {
      add(
        'I8',
        "I12' ballistic velocity 方向反轉："
            'previous=$previousVelocity current=$velocity',
      );
    } else {
      const allowedRelativeJitter = 0.05;
      // The first post-handoff sample can carry a near-zero velocity before
      // the simulation exposes its first meaningful derivative. It is not a
      // convergence comparison yet; use a unitless warm-up ratio rather than
      // a fixed logical-pixel threshold.
      final hasMeaningfulPreviousSample =
          previousVelocity.abs() >= velocity.abs() * allowedRelativeJitter;
      const maxFrictionReliefRatio = 0.09 / 0.015;
      final allowedMagnitude =
          previousVelocity.abs() *
          maxFrictionReliefRatio *
          (1 + allowedRelativeJitter);
      if (hasMeaningfulPreviousSample && velocity.abs() > allowedMagnitude) {
        add(
          'I8',
          "I13' ballistic velocity 超過物理摩擦倍率（6x + 5%）："
              'previous=$previousVelocity current=$velocity',
        );
      }
    }
  }

  // I14'：非 explicit operation frame 若在同一 owner 下跨過一個完整
  // viewport，視為 teleport。合法 driven/restore/navigation 會取得新
  // token（或保有 pending target），因此不走這條。threshold 直接採用
  // 當前 viewportHeight，沒有固定 pixel 常數。
  if (previous != null &&
      _sameReadyGeneration(current, previous) &&
      current.pendingChapterJumpTarget == null &&
      previous.pendingChapterJumpTarget == null &&
      current.operationIsCurrent &&
      current.operationTokenId == previous.operationTokenId &&
      current.scrollPixels != null &&
      previous.scrollPixels != null &&
      current.scrollPixels!.isFinite &&
      previous.scrollPixels!.isFinite &&
      current.viewportHeight != null &&
      current.viewportHeight!.isFinite &&
      current.viewportHeight! > 0) {
    final delta = (current.scrollPixels! - previous.scrollPixels!).abs();
    if (delta > current.viewportHeight!) {
      add(
        'I8',
        "I14' 非 navigation／restore 的 viewport teleport："
            'delta=$delta viewport=${current.viewportHeight}',
      );
    }
  }

  return violations;
}

/// The temporal probe intentionally has its own source and state.  Runtime
/// invariants remain a current/previous-frame evaluator; this class only
/// consumes the ordered frame stream and the runtime events emitted for each
/// frame.  The fixed ring keeps both steady-state work and retained evidence
/// bounded when the debug hook is enabled.
@visibleForTesting
const int hybridTemporalWindowCapacity = 240;

@visibleForTesting
const int hybridTemporalStableFrameThreshold = 8;

@visibleForTesting
const int hybridTemporalShortWindowFrames = 4;

@visibleForTesting
const int hybridTemporalOscillationWindowFrames = 12;

@visibleForTesting
const double hybridTemporalIdleDriftViewportRatio = 0.05;

@visibleForTesting
const int hybridTemporalEpisodeEvidenceCapacity = 3;

Map<String, Object?> _temporalWindowEvidence(
  List<HybridFrameInvariantRecord> records,
) {
  final timestamps = <int>[];
  final pixels = <double?>[];
  final deltas = <double?>[];
  final activities = <String>[];
  final queueDepths = <int>[];
  final progressChapters = <int?>[];
  final visibleKeys = <List<Map<String, int>>>[];
  double? previousPixels;
  for (final record in records) {
    final currentPixels = record.scrollPixels;
    final priorPixels = previousPixels;
    timestamps.add(record.timestampMicros);
    pixels.add(currentPixels);
    deltas.add(
      currentPixels == null || priorPixels == null
          ? null
          : currentPixels - priorPixels,
    );
    previousPixels = currentPixels;
    activities.add(record.scrollActivity);
    queueDepths.add(record.pumpQueueDepth);
    progressChapters.add(record.displayedProgressChapter);
    visibleKeys.add([
      for (final key in record.visibleKeys)
        <String, int>{
          'chapterIndex': key.chapterIndex,
          'blockIndex': key.blockIndex,
        },
    ]);
  }
  return <String, Object?>{
    'startTimestampMicros': timestamps.first,
    'endTimestampMicros': timestamps.last,
    'frameCount': records.length,
    'timestampsMicros': timestamps,
    'scrollPixels': pixels,
    'scrollDeltas': deltas,
    'scrollActivity': activities,
    'pumpQueueDepth': queueDepths,
    'displayedProgressChapter': progressChapters,
    'visibleKeys': visibleKeys,
    // Keep the complete scalar records in the evidence bundle.  A failure can
    // therefore be explained without re-running the case or consulting
    // mutable Reader state.
    'records': [for (final record in records) record.toJson()],
  };
}

final class _TemporalEpisode {
  _TemporalEpisode(this.records);

  final List<HybridFrameInvariantRecord> records;
}

final class _TemporalExitEpisode {
  _TemporalExitEpisode({
    required this.key,
    required this.left,
    required this.startPixels,
  });

  final BlockKey key;
  final HybridFrameInvariantRecord left;
  final double? startPixels;
  int absentFrames = 1;
}

@visibleForTesting
final class HybridTemporalOracle {
  final List<HybridFrameInvariantRecord?> _ring =
      List<HybridFrameInvariantRecord?>.filled(
        hybridTemporalWindowCapacity,
        null,
      );
  final Map<String, _TemporalEpisode> _episodes = <String, _TemporalEpisode>{};
  final Map<BlockKey, _TemporalExitEpisode> _exits =
      <BlockKey, _TemporalExitEpisode>{};

  HybridFrameInvariantRecord? _previous;
  int _ringCount = 0;
  int _ringNext = 0;

  int _idleFrames = 0;
  double _idleTravel = 0;
  int _teleportFrames = 0;
  double _teleportTravel = 0;

  int _oscillationFrames = 0;
  int _oscillationReversals = 0;
  double _oscillationTravel = 0;
  double _oscillationNet = 0;
  int _oscillationDirection = 0;

  int _restoreDrainFrames = 0;
  bool _restoreDrainArmed = false;
  int _readyRestoreLockFrames = 0;

  int _stableFrames = 0;
  HybridFrameInvariantRecord? _stableStart;

  /// Add one ordered sample.  The returned list contains only newly observed
  /// temporal events and transient classifications.  The caller owns the
  /// outer 256-event cap used by the existing hook.
  List<HybridFrameInvariantViolation> observe(
    HybridFrameInvariantRecord current, {
    List<HybridFrameInvariantViolation> runtimeViolations =
        const <HybridFrameInvariantViolation>[],
  }) {
    _append(current);
    final previous = _previous;
    final temporal = <HybridFrameInvariantViolation>[];

    _observeT1(current, previous, temporal);
    _observeT2(current, previous, temporal);
    _observeT3(current, previous, temporal);
    _observeT5(temporal);
    _observeT6(current, previous, temporal);
    _observeT7(current, previous, temporal);
    _observeT8(current, previous, temporal);
    _observeT9(current, temporal);
    _observeT10(current, previous, temporal);

    final stream = <HybridFrameInvariantViolation>[
      ...runtimeViolations,
      ...temporal,
    ];
    final transient = _classifyTransient(stream);
    _previous = current;
    return <HybridFrameInvariantViolation>[...temporal, ...transient];
  }

  void reset() {
    _ring.fillRange(0, _ring.length, null);
    _episodes.clear();
    _exits.clear();
    _previous = null;
    _ringCount = 0;
    _ringNext = 0;
    _idleFrames = 0;
    _idleTravel = 0;
    _teleportFrames = 0;
    _teleportTravel = 0;
    _oscillationFrames = 0;
    _oscillationReversals = 0;
    _oscillationTravel = 0;
    _oscillationNet = 0;
    _oscillationDirection = 0;
    _restoreDrainFrames = 0;
    _restoreDrainArmed = false;
    _readyRestoreLockFrames = 0;
    _stableFrames = 0;
    _stableStart = null;
  }

  void _append(HybridFrameInvariantRecord record) {
    _ring[_ringNext] = record;
    _ringNext = (_ringNext + 1) % _ring.length;
    if (_ringCount < _ring.length) _ringCount += 1;
  }

  List<HybridFrameInvariantRecord> _lastRecords([int? limit]) {
    final count = math.min(limit ?? _ringCount, _ringCount);
    final start = (_ringNext - count + _ring.length) % _ring.length;
    return [
      for (var i = 0; i < count; i += 1) _ring[(start + i) % _ring.length]!,
    ];
  }

  bool _readyStable(HybridFrameInvariantRecord record) {
    return record.phase == 'ready' &&
        record.initialRestoreCompleted &&
        !record.restoreLocked &&
        record.isIdle &&
        record.visibleKeys.isNotEmpty &&
        record.scrollPixels?.isFinite == true &&
        record.viewportHeight?.isFinite == true &&
        record.viewportHeight! > 0;
  }

  bool _sameGeneration(
    HybridFrameInvariantRecord a,
    HybridFrameInvariantRecord b,
  ) {
    return a.phase == 'ready' &&
        b.phase == 'ready' &&
        a.initialRestoreCompleted &&
        b.initialRestoreCompleted &&
        !a.restoreLocked &&
        !b.restoreLocked &&
        a.epoch == b.epoch &&
        a.layoutGeneration == b.layoutGeneration &&
        a.resetGeneration == b.resetGeneration &&
        a.indexBindingResetGeneration == b.indexBindingResetGeneration &&
        a.pendingChapterJumpTarget == null &&
        b.pendingChapterJumpTarget == null &&
        a.operationTokenId == b.operationTokenId;
  }

  HybridFrameInvariantViolation _violation(
    String invariant,
    String reason,
    Iterable<HybridFrameInvariantRecord> records, {
    String? sourceInvariant,
  }) {
    final window = records.toList(growable: false);
    return HybridFrameInvariantViolation(
      invariant: invariant,
      reason: reason,
      current: window.last,
      previous: window.length > 1 ? window[window.length - 2] : null,
      oracle: 'temporal',
      sourceInvariant: sourceInvariant,
      windowEvidence: _temporalWindowEvidence(window),
    );
  }

  void _observeT1(
    HybridFrameInvariantRecord current,
    HybridFrameInvariantRecord? previous,
    List<HybridFrameInvariantViolation> output,
  ) {
    final eligible =
        _readyStable(current) &&
        (previous == null ||
            (_readyStable(previous) && _sameGeneration(current, previous)));
    if (!eligible) {
      _idleFrames = 0;
      _idleTravel = 0;
      return;
    }
    final delta = previous == null
        ? 0.0
        : (current.scrollPixels! - previous.scrollPixels!).abs();
    _idleFrames += 1;
    _idleTravel += delta;
    final threshold =
        current.viewportHeight! * hybridTemporalIdleDriftViewportRatio;
    if (_idleFrames >= hybridTemporalStableFrameThreshold &&
        _idleTravel > threshold) {
      output.add(
        _violation(
          'T1',
          'idle 且無 pending navigation 仍累積位移：'
              'travel=$_idleTravel threshold=$threshold '
              'frames=$_idleFrames',
          _lastRecords(hybridTemporalStableFrameThreshold),
        ),
      );
    }
  }

  void _observeT2(
    HybridFrameInvariantRecord current,
    HybridFrameInvariantRecord? previous,
    List<HybridFrameInvariantViolation> output,
  ) {
    final eligible =
        previous != null &&
        _sameGeneration(current, previous) &&
        _readyStable(current) &&
        current.operationIsCurrent &&
        current.scrollPixels != null &&
        previous.scrollPixels != null;
    if (!eligible) {
      _teleportFrames = 0;
      _teleportTravel = 0;
      return;
    }
    final delta = (current.scrollPixels! - previous.scrollPixels!).abs();
    final viewport = current.viewportHeight!;
    if (delta > viewport) {
      // A single-frame jump is C2 I14'. T2 is deliberately the complementary
      // short-window case, where every individual step is below that bound.
      _teleportFrames = 0;
      _teleportTravel = 0;
      return;
    }
    _teleportFrames += 1;
    _teleportTravel += delta;
    if (_teleportFrames <= hybridTemporalShortWindowFrames &&
        _teleportTravel > viewport) {
      output.add(
        _violation(
          'T2',
          '無 navigation token 的短窗位移累積超過 viewport：'
              'travel=$_teleportTravel viewport=$viewport '
              'frames=$_teleportFrames',
          _lastRecords(_teleportFrames + 1),
        ),
      );
    }
    if (_teleportFrames >= hybridTemporalShortWindowFrames) {
      _teleportFrames = 0;
      _teleportTravel = 0;
    }
  }

  void _observeT3(
    HybridFrameInvariantRecord current,
    HybridFrameInvariantRecord? previous,
    List<HybridFrameInvariantViolation> output,
  ) {
    final eligible =
        previous != null &&
        _sameGeneration(current, previous) &&
        _readyStable(previous) &&
        _readyStable(current);
    if (!eligible) {
      _oscillationFrames = 0;
      _oscillationReversals = 0;
      _oscillationTravel = 0;
      _oscillationNet = 0;
      _oscillationDirection = 0;
      return;
    }
    final delta = current.scrollPixels! - previous.scrollPixels!;
    final direction = delta == 0 ? 0 : delta.sign.toInt();
    _oscillationFrames += 1;
    _oscillationTravel += delta.abs();
    _oscillationNet += delta;
    if (direction != 0 &&
        _oscillationDirection != 0 &&
        direction != _oscillationDirection) {
      _oscillationReversals += 1;
    }
    if (direction != 0) _oscillationDirection = direction;
    if (_oscillationReversals >= 3 &&
        _oscillationTravel > 0 &&
        _oscillationNet.abs() <= _oscillationTravel * 0.25) {
      output.add(
        _violation(
          'T3',
          'idle 位移方向反轉=$_oscillationReversals 次且淨位移接近 0：'
              'net=$_oscillationNet travel=$_oscillationTravel',
          _lastRecords(math.min(_oscillationFrames + 1, 13)),
        ),
      );
    }
    if (_oscillationFrames >= hybridTemporalOscillationWindowFrames) {
      _oscillationFrames = 0;
      _oscillationReversals = 0;
      _oscillationTravel = 0;
      _oscillationNet = 0;
      _oscillationDirection = 0;
    }
  }

  void _observeT5(List<HybridFrameInvariantViolation> output) {
    final records = _lastRecords(5);
    if (records.length < 5) return;
    final first = records.first;
    final last = records.last;
    if (!records.every((record) => _sameGeneration(record, first))) return;
    int? chapter(HybridFrameInvariantRecord record) =>
        record.displayedProgressChapter ?? record.dominantVisibleChapter;
    final firstChapter = chapter(first);
    final lastChapter = chapter(last);
    if (firstChapter == null || firstChapter != lastChapter) return;
    if (records
        .sublist(1, records.length - 1)
        .any((record) => chapter(record) != firstChapter)) {
      output.add(
        _violation(
          'T5',
          '無 navigation token 的章節短暫偏離後恢復：'
              '${records.map(chapter).toList()}',
          records,
        ),
      );
    }
  }

  void _observeT6(
    HybridFrameInvariantRecord current,
    HybridFrameInvariantRecord? previous,
    List<HybridFrameInvariantViolation> output,
  ) {
    if (previous == null || !_sameGeneration(current, previous)) return;
    final currentChapter = current.displayedProgressChapter;
    final previousChapter = previous.displayedProgressChapter;
    if (currentChapter == null || previousChapter == null) return;
    final chapterDelta = currentChapter - previousChapter;
    if (chapterDelta == 0) return;
    final pixelDelta =
        current.scrollPixels == null || previous.scrollPixels == null
        ? null
        : current.scrollPixels! - previous.scrollPixels!;
    final viewport = current.viewportHeight;
    if (pixelDelta == null || viewport == null || viewport <= 0) return;
    final explainedChapterSpan = pixelDelta.abs() / viewport;
    final maxContinuousDelta = math.max(1, explainedChapterSpan.ceil() + 1);
    final directionMismatch =
        pixelDelta.abs() > viewport * 0.05 &&
        chapterDelta.sign != pixelDelta.sign;
    if (chapterDelta.abs() > maxContinuousDelta || directionMismatch) {
      output.add(
        _violation(
          'T6',
          'progress 變化無法由位移解釋：chapter $previousChapter->'
              '$currentChapter pixelDelta=$pixelDelta '
              'viewport=$viewport maxContinuousDelta=$maxContinuousDelta',
          _lastRecords(2),
        ),
      );
    }
  }

  void _observeT7(
    HybridFrameInvariantRecord current,
    HybridFrameInvariantRecord? previous,
    List<HybridFrameInvariantViolation> output,
  ) {
    // During drag/ballistic scrolling, visibleKeys are expected to enter and
    // leave the viewport. T7 concerns a stable viewport being internally
    // inconsistent, so both samples must be idle before opening an exit
    // episode. This also prevents ordinary fling window replacement from
    // becoming a temporal violation.
    if (previous == null ||
        !_sameGeneration(current, previous) ||
        !current.isIdle ||
        !previous.isIdle ||
        previous.viewportHeight?.isFinite != true ||
        previous.viewportHeight! <= 0) {
      _exits.clear();
      return;
    }
    final previousKeys = previous.visibleKeys.toSet();
    final currentKeys = current.visibleKeys.toSet();
    for (final key in previousKeys.difference(currentKeys)) {
      if (_exits.length < 64 && !_exits.containsKey(key)) {
        _exits[key] = _TemporalExitEpisode(
          key: key,
          left: previous,
          startPixels: previous.scrollPixels,
        );
      }
    }
    for (final key in currentKeys.toList()) {
      final exit = _exits[key];
      if (exit == null) continue;
      exit.absentFrames += 1;
      final pixels = current.scrollPixels;
      final startPixels = exit.startPixels;
      final paragraphProxy =
          previous.viewportHeight! / math.max(1, previous.visibleKeys.length);
      if (exit.absentFrames <= hybridTemporalStableFrameThreshold &&
          pixels != null &&
          startPixels != null &&
          (pixels - startPixels).abs() < paragraphProxy) {
        output.add(
          _violation(
            'T7',
            'visible key $key 離開後在短窗內回來，位移小於段落高度 proxy：'
                'delta=${(pixels - startPixels).abs()} '
                'proxy=$paragraphProxy',
            _lastRecords(exit.absentFrames + 1),
          ),
        );
      }
      _exits.remove(key);
    }
    for (final entry in _exits.entries.toList()) {
      if (entry.value.absentFrames > hybridTemporalStableFrameThreshold) {
        _exits.remove(entry.key);
      }
    }
  }

  void _observeT8(
    HybridFrameInvariantRecord current,
    HybridFrameInvariantRecord? previous,
    List<HybridFrameInvariantViolation> output,
  ) {
    if (previous != null && previous.restoreLocked && !current.restoreLocked) {
      _restoreDrainArmed = true;
      _restoreDrainFrames = 0;
    }
    if (!_restoreDrainArmed ||
        current.restoreLocked ||
        current.pumpQueueDepth == 0) {
      if (current.pumpQueueDepth == 0) _restoreDrainArmed = false;
      _restoreDrainFrames = 0;
      return;
    }
    _restoreDrainFrames += 1;
    if (_restoreDrainFrames > hybridTemporalStableFrameThreshold) {
      output.add(
        _violation(
          'T8',
          'restoreLocked 解除後 LayoutPump queue 未 drain：'
              'queue=${current.pumpQueueDepth} frames=$_restoreDrainFrames '
              'threshold=$hybridTemporalStableFrameThreshold',
          _lastRecords(_restoreDrainFrames + 1),
        ),
      );
    }
  }

  void _observeT9(
    HybridFrameInvariantRecord current,
    List<HybridFrameInvariantViolation> output,
  ) {
    if (current.phase == 'ready' && current.restoreLocked) {
      _readyRestoreLockFrames += 1;
      if (_readyRestoreLockFrames > hybridTemporalStableFrameThreshold) {
        output.add(
          _violation(
            'T9',
            'ready 與 restoreLocked 共存：frames=$_readyRestoreLockFrames '
                'threshold=$hybridTemporalStableFrameThreshold',
            _lastRecords(_readyRestoreLockFrames),
          ),
        );
      }
    } else {
      _readyRestoreLockFrames = 0;
    }
  }

  void _observeT10(
    HybridFrameInvariantRecord current,
    HybridFrameInvariantRecord? previous,
    List<HybridFrameInvariantViolation> output,
  ) {
    if (!_readyStable(current)) {
      _stableFrames = 0;
      _stableStart = null;
      return;
    }
    if (_stableStart == null) {
      _stableStart = current;
      _stableFrames = 1;
      return;
    }
    final baseline = _stableStart!;
    final sameStableViewport =
        current.scrollPixels == baseline.scrollPixels &&
        _sameBlockKeyList(current.visibleKeys, baseline.visibleKeys) &&
        current.operationTokenId == baseline.operationTokenId &&
        _sameGeneration(current, baseline);
    if (sameStableViewport) {
      _stableFrames += 1;
      return;
    }
    if (_stableFrames >= hybridTemporalStableFrameThreshold &&
        !_sameBlockKeyList(current.visibleKeys, baseline.visibleKeys) &&
        current.scrollPixels == baseline.scrollPixels &&
        current.operationTokenId == baseline.operationTokenId &&
        _sameGeneration(current, baseline)) {
      output.add(
        _violation(
          'T10',
          '穩定 viewport 在無輸入／navigation 下 visibleKeys 整體改變：'
              'stableFrames=$_stableFrames documentRevision '
              '${baseline.documentIndexRevision}->${current.documentIndexRevision}',
          _lastRecords(_stableFrames + 1),
        ),
      );
    }
    _stableStart = current;
    _stableFrames = 1;
  }

  List<HybridFrameInvariantViolation> _classifyTransient(
    List<HybridFrameInvariantViolation> stream,
  ) {
    final present = <String>{};
    for (final violation in stream) {
      if (violation.invariant == 'TRANSIENT') continue;
      present.add(violation.invariant);
      final episode = _episodes.putIfAbsent(
        violation.invariant,
        () => _TemporalEpisode(<HybridFrameInvariantRecord>[]),
      );
      if (episode.records.length < hybridTemporalEpisodeEvidenceCapacity &&
          (episode.records.isEmpty ||
              episode.records.last.timestampMicros !=
                  violation.current.timestampMicros)) {
        episode.records.add(violation.current);
      }
    }
    final output = <HybridFrameInvariantViolation>[];
    for (final entry in _episodes.entries.toList()) {
      if (present.contains(entry.key)) continue;
      final episode = entry.value;
      if (episode.records.isNotEmpty && episode.records.length <= 2) {
        output.add(
          _violation(
            'TRANSIENT',
            '${entry.key} violation 僅持續 ${episode.records.length} 幀後恢復',
            episode.records,
            sourceInvariant: entry.key,
          ),
        );
      }
      _episodes.remove(entry.key);
    }
    return output;
  }
}

/// 判斷一次「完整翻頁」是否真的完成。
///
/// Hybrid 的目前 scroll extent 只包含已 admission 的 block。若排版供給
/// 落後，`ScrollPosition.animateTo` 會把目標夾到暫時的 extent；這種情況
/// 畫面雖然有移動，卻不代表完成了呼叫端要求的整頁距離。只有真正到達
/// 已確認的書首／書尾時，最後不足整頁的移動才是合法成功。
@visibleForTesting
bool isHybridPageMoveComplete({
  required double requestedDistance,
  required double actualDistance,
  required bool atBookBoundary,
}) {
  if (!requestedDistance.isFinite || requestedDistance <= 0) return false;
  if (!actualDistance.isFinite || actualDistance <= 0) return false;
  // animateTo／DocumentIndex 的浮點誤差不應讓完整頁面被誤判為失敗；
  // 0.5 logical px 遠小於閱讀器一行，且不會掩蓋明顯的 lazy-edge 短移動。
  const tolerance = 0.5;
  if (actualDistance + tolerance >= requestedDistance) return true;
  return atBookBoundary;
}

class _HybridReaderScreenState extends State<HybridReaderScreen>
    with WidgetsBindingObserver {
  /// Restore only needs the anchor and the bounded guaranteed viewport window.
  /// Keep each restore pass small; [_pumpUntilAnchorReady] checks the actual
  /// admitted geometry and asks for another pass only when it is still short.
  /// This prevents a long chapter's complete prefetch tail from sitting in the
  /// queue after the anchor is already presentable.
  static const int _restoreGroupsPerSide = 8;

  /// Ordinary scrolling uses the same bounded frontier.  Each user-owned
  /// settle submits one bounded batch; a later settle can advance the frontier
  /// again while the admission controller still reports a lead deficit.  A
  /// queue drain must not recursively submit the next batch, because a long
  /// chapter would turn one harmless release into an unbounded settle backlog.
  static const int _progressiveGroupsPerSide = 8;

  static const Duration _ensureAnimateDuration = Duration(milliseconds: 260);
  static const Duration _telemetryHeartbeatInterval = Duration(seconds: 15);
  static const double _minimumViewportMovement = 0.01;
  static const int _visualMaxInFlight = 2;
  static const int _visualProfileBlockIndexOffset = 1;

  final GlobalKey _centerKey = GlobalKey(debugLabel: 'hybrid-center-sliver');
  final GlobalKey _visualBoundaryKey = GlobalKey(
    debugLabel: 'reader-visual-oracle-boundary',
  );
  final MeasurementStore _measurementStore = MeasurementStore();
  final DocumentIndex _documentIndex = DocumentIndex(
    centerKey: const BlockKey(chapterIndex: 0, blockIndex: 0),
  );
  final AnchorManager _anchorManager = AnchorManager();
  final BudgetGovernor _governor = BudgetGovernor();
  final HybridTelemetry _telemetry = HybridTelemetry();
  final _HybridCommandQueue _commands = _HybridCommandQueue();
  final HybridEnsureGate _ensureGate = HybridEnsureGate();

  late HybridChapterRepository _chapterRepo;
  late final AdmissionController _admission;

  /// 單一穩定實例：`Scrollable` 只認 physics 的 runtimeType 鏈，position
  /// 抱的是第一顆——動態摩擦由 physics 透過 [_admission] 即時查詢。
  late final HybridScrollPhysics _physics;
  late ParagraphCache _paragraphCache;
  late LayoutPump _pump;
  late LayoutEpoch _epoch;
  late StyleFingerprint _fingerprint;
  late MeasurementNamespace _namespace;

  final Map<int, ChapterBlocks> _blocks = <int, ChapterBlocks>{};
  final Map<int, Future<ChapterBlocks?>> _blocksInFlight =
      <int, Future<ChapterBlocks?>>{};
  final Set<BlockKey> _enqueued = <BlockKey>{};
  final Set<({MeasurementNamespace namespace, int chapter, String contentHash})>
  _warmedChapters =
      <({MeasurementNamespace namespace, int chapter, String contentHash})>{};

  StreamSubscription<ChapterEvent>? _chapterEventsSub;
  Timer? _telemetryHeartbeatTimer;
  ScrollController? _scrollController;
  MetricsDiskCache? _metricsDiskCache;

  Size _viewportSize = Size.zero;
  double? _pendingScrollOffset;
  int _windowCenter = 0;
  // Invalidates async ordinary-prefetch continuations when the viewport
  // center, epoch, or restore transaction changes.  The repository has its
  // own cache generation, but this screen also needs to protect the later
  // enqueue side effect, which can run after a user drag has started.
  int _prefetchGeneration = 0;
  int _lastLayoutGeneration = 0;
  int _runtimeLocationRevision = 0;
  int _restoreTicket = 0;
  ReaderV2Location? _lastReportedLocation;
  ReaderV2Location? _lastSyncedLocation;
  String? _lastLoggedErrorMessage;
  bool _initialRestoreCompleted = false;
  bool _restorePrefetchBarrierActive = false;
  // A ScrollEnd inherited from the gesture/ballistic stream that triggered a
  // jump is not an ordinary user settle. It can arrive after restoreLocked
  // is released but before ReaderV2Runtime clears pendingChapterJumpTarget.
  // Only a new drag that starts after the restore may release the barrier.
  bool _restoreUserScrollObserved = false;
  /// 累計被需求失效丟棄的排版工作數（整個 session，不隨 epoch 重置）。
  /// 沒有這個計數就無從得知「舊工作撤不掉」在真機上還發生多少次——
  /// 之前正是因為沒人量，這條路徑才一直只能靠旗標猜。
  int _discardedLayoutTaskCount = 0;
  bool _capturing = false;

  /// restore 進行中旗標：此期間投放的 block 於建置「之前」即 pin 進
  /// ParagraphCache（見 [_admitOrSubmitGroup]），防止初始視窗建置量超過
  /// 快取容量時 LRU 把首屏段落逐出。
  bool _restorePinning = false;
  bool _dragging = false;
  String? _invariantScrollActivityHint;
  bool _sawUserScroll = false;
  bool _rebuildQueued = false;
  bool _pumpFramePending = false;
  bool _captureFramePending = false;
  double? _lastDebugSnapshotOffset;
  int _indexBindingResetGeneration = 0;
  HybridFrameInvariantRecord? _previousInvariantRecord;
  HybridFrameInvariantRecord? _lastInvariantRecord;
  List<HybridFrameInvariantRecord>? _invariantRecordHistory;
  List<HybridFrameInvariantViolation>? _invariantViolations;
  HybridTemporalOracle? _temporalOracle;
  ReaderVisualOracle? _visualOracle;
  ReaderVisualRaster? _previousVisualRaster;
  ReaderVisualInjection _visualInjection = ReaderVisualInjection.none;
  int _visualInjectionStep = 0;
  bool _visualInjectionAdvanceQueued = false;
  bool _visualFrameCallbackScheduled = false;
  int _visualNextSequence = 0;
  int _visualNextSequenceToProcess = 0;
  int _visualGeneration = 0;
  int _visualInFlight = 0;
  int _visualMaxObservedInFlight = 0;
  int _visualTotalFrames = 0;
  int _visualCapturedFrames = 0;
  int _visualDroppedFrames = 0;
  int _visualCaptureErrorCount = 0;
  int _visualCaptureCostMicros = 0;
  int _visualLastSourceWidth = 0;
  int _visualLastSourceHeight = 0;
  final List<int> _visualCaptureCostsMicros = <int>[];
  final Set<int> _visualDroppedSequences = <int>{};
  final Map<int, _VisualCaptureResult> _visualPendingResults =
      <int, _VisualCaptureResult>{};

  @override
  void initState() {
    super.initState();
    _chapterRepo = HybridChapterRepository(
      repository: widget.runtime.repository,
    );
    _chapterEventsSub = _chapterRepo.events.listen(_onChapterEvent);
    // 放行不再驅動 widget 層 setState：新 block 的材料化由
    // DocumentIndex.revision → RenderHybridBlockSliver.markNeedsLayout
    // 直驅（fling 幀 build 成本歸零的關鍵）。
    _admission = AdmissionController(documentIndex: _documentIndex);
    _physics = HybridScrollPhysics(admission: _admission);
    _paragraphCache = ParagraphCache(capacity: widget.paragraphCacheCapacity);
    _refreshEpochBinding();
    _indexBindingResetGeneration = _documentIndex.resetGeneration;
    _lastLayoutGeneration = widget.runtime.state.layoutGeneration;
    _lastReportedLocation = widget.runtime.state.visibleLocation;
    _windowCenter = widget.runtime.state.visibleLocation.chapterIndex;

    widget.runtime.registerHybridViewport(this);
    widget.runtime.addListener(_onRuntimeChanged);
    widget.runtime.registerVisibleLocationCapture(this, _captureForBridge);
    widget.runtime.registerViewportRestore(this, _restoreToLocation);
    _attachController();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addTimingsCallback(_handleFrameTimings);
    if (kDebugMode && HybridReaderScreen.debugFrameInvariantsEnabled) {
      _invariantRecordHistory = <HybridFrameInvariantRecord>[];
      _invariantViolations = <HybridFrameInvariantViolation>[];
      _temporalOracle = HybridTemporalOracle();
      WidgetsBinding.instance.addPostFrameCallback(_handleInvariantFrame);
    }
    if (kDebugMode && HybridReaderScreen.debugVisualOracleEnabled) {
      _startVisualOracle();
    }
    if (kDebugMode) {
      _telemetryHeartbeatTimer = Timer.periodic(
        _telemetryHeartbeatInterval,
        (_) => _logTelemetryHeartbeat(),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 冷開機由 runtime.openBook() 經 restore 鏈進來；熱掛載（runtime 已
      // ready）沒有人會再叫 restore，這裡自己補一次同步。
      if (widget.runtime.state.phase == ReaderV2Phase.ready) {
        unawaited(_syncToRuntimeLocation(force: true));
      }
    });
  }

  @override
  void didUpdateWidget(covariant HybridReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runtime != widget.runtime) {
      oldWidget.runtime.unregisterHybridViewport(this);
      oldWidget.runtime.removeListener(_onRuntimeChanged);
      oldWidget.runtime.unregisterVisibleLocationCapture(this);
      oldWidget.runtime.unregisterViewportRestore(this);
      _chapterEventsSub?.cancel();
      unawaited(_chapterRepo.dispose());
      _chapterRepo = HybridChapterRepository(
        repository: widget.runtime.repository,
      );
      _chapterEventsSub = _chapterRepo.events.listen(_onChapterEvent);
      widget.runtime.registerHybridViewport(this);
      widget.runtime.addListener(_onRuntimeChanged);
      widget.runtime.registerVisibleLocationCapture(this, _captureForBridge);
      widget.runtime.registerViewportRestore(this, _restoreToLocation);
      _lastLayoutGeneration = widget.runtime.state.layoutGeneration;
      _lastReportedLocation = widget.runtime.state.visibleLocation;
      _lastSyncedLocation = null;
      _lastLoggedErrorMessage = null;
      _windowCenter = widget.runtime.state.visibleLocation.chapterIndex;
      _restoreTicket += 1;
      _initialRestoreCompleted = false;
      _resetVisualOracleState();
      _handleEpochRebuild();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_syncToRuntimeLocation(force: true));
      });
    }
    if (oldWidget.viewportController != widget.viewportController) {
      _detachController(oldWidget.viewportController);
      _attachController();
    }
    if (oldWidget.textColor != widget.textColor) {
      // textColor is part of ParagraphCache freshness even though it does
      // not change geometry. Do not expose the new widget color while the
      // old cached paragraphs are still considered fresh by the renderer:
      // rebuild the bounded namespace and restore the existing anchor through
      // the same testable restore path used by a presentation change.
      final location =
          _captureVisibleLocation() ?? widget.runtime.state.visibleLocation;
      _handleEpochRebuild();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_restoreToLocation(location));
      });
    }
  }

  @override
  void dispose() {
    _telemetryHeartbeatTimer?.cancel();
    _visualOracle?.finish();
    _visualPendingResults.clear();
    _visualDroppedSequences.clear();
    _logTelemetrySessionSummary();
    widget.runtime.unregisterHybridViewport(this);
    widget.runtime.removeListener(_onRuntimeChanged);
    widget.runtime.unregisterVisibleLocationCapture(this);
    widget.runtime.unregisterViewportRestore(this);
    _detachController(widget.viewportController);
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.removeTimingsCallback(_handleFrameTimings);
    _chapterEventsSub?.cancel();
    unawaited(_writeDiskMetrics(_measurementStore.snapshot(_namespace)));
    unawaited(_chapterRepo.dispose());
    _admission.dispose();
    _ensureGate.dispose();
    _pump.dispose();
    _paragraphCache.dispose();
    _scrollController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      unawaited(widget.runtime.flushProgress());
      unawaited(_writeDiskMetrics(_measurementStore.snapshot(_namespace)));
    }
  }

  /// session 結束時把 telemetry 累計摘要寫入 AppLog（設定頁日誌可回收），
  /// 附帶影響幀成本的關鍵樣式脈絡，供真機驗收劇本對比（如 B2 開/關）。
  void _logTelemetrySessionSummary() {
    final summary = _telemetry.sessionSummary();
    if ((summary['frames'] as int? ?? 0) == 0) return;
    summary['fontSize'] = _fingerprint.fontSize;
    summary['lastLineSpacingCompensation'] =
        _fingerprint.lastLineSpacingCompensation;
    AppLog.i('ReaderV2 telemetry session: ${jsonEncode(summary)}');
  }

  void _logTelemetryHeartbeat() {
    if (!mounted) return;
    _telemetry.recordPumpQueueDepth(_pump.queueDepth);
    final summary = _telemetry.heartbeatSummary();
    summary['fontSize'] = _fingerprint.fontSize;
    summary['lastLineSpacingCompensation'] =
        _fingerprint.lastLineSpacingCompensation;
    AppLog.i('ReaderV2 telemetry heartbeat: ${jsonEncode(summary)}');
  }

  /// 連續滾動／layout race 的語意診斷快照。
  ///
  /// 這個 seam 只供 integration workload 讀取，不參與正式畫面建置，也
  /// 不用 screenshot 去猜內容是否正確。快照把同一時刻的 viewport、runtime
  /// location、DocumentIndex revision、admission 範圍、ParagraphCache 與
  /// LayoutPump queue 放在一起，讓短暫的空白或舊座標能和動作歷史對齊。
  @visibleForTesting
  Map<String, Object?> debugSnapshot() {
    final controller = _scrollController;
    final position = controller != null && controller.hasClients
        ? controller.position
        : null;
    final offset = _effectiveScrollOffset();
    final viewportHeight = _viewportSize.height;
    final hasViewport = offset != null && viewportHeight > 0;
    final visibleKeys = hasViewport
        ? _documentIndex
              .keysInRange(offset, offset + viewportHeight)
              .toList(growable: false)
        : const <BlockKey>[];
    final missingParagraphKeys = <BlockKey>[];
    for (final key in visibleKeys) {
      if (!_paragraphCache.containsFresh(key, _epoch, widget.textColor)) {
        missingParagraphKeys.add(key);
      }
    }

    String scrollDirection = 'idle';
    final previousOffset = _lastDebugSnapshotOffset;
    if (offset != null && previousOffset != null) {
      final delta = offset - previousOffset;
      if (delta > 0.5) {
        scrollDirection = 'forward';
      } else if (delta < -0.5) {
        scrollDirection = 'backward';
      }
    }
    _lastDebugSnapshotOffset = offset;

    final captured = _captureVisibleLocation();
    final runtimeState = widget.runtime.state;
    final telemetry = _telemetry.snapshot;
    _telemetry.recordPumpQueueDepth(_pump.queueDepth);

    Map<String, int> keyJson(BlockKey key) => <String, int>{
      'chapterIndex': key.chapterIndex,
      'blockIndex': key.blockIndex,
    };

    double? finiteOrNull(double value) => value.isFinite ? value : null;

    bool isConsecutive(BlockKey previous, BlockKey next) {
      if (previous.chapterIndex == next.chapterIndex) {
        return next.blockIndex == previous.blockIndex + 1;
      }
      return next.chapterIndex == previous.chapterIndex + 1 &&
          next.blockIndex == 0;
    }

    final visibleKeysContiguous = visibleKeys.length < 2
        ? true
        : Iterable<int>.generate(visibleKeys.length - 1).every(
            (index) =>
                isConsecutive(visibleKeys[index], visibleKeys[index + 1]),
          );
    final visibleChapters = <int>[];
    for (final key in visibleKeys) {
      if (visibleChapters.isEmpty || visibleChapters.last != key.chapterIndex) {
        visibleChapters.add(key.chapterIndex);
      }
    }

    return <String, Object?>{
      'capturedAtMs': DateTime.now().millisecondsSinceEpoch,
      'displayRefreshRate': ui.PlatformDispatcher.instance.views.isEmpty
          ? null
          : finiteOrNull(
              ui.PlatformDispatcher.instance.views.first.display.refreshRate,
            ),
      'phase': runtimeState.phase.name,
      'scrollOffset': finiteOrNull(offset ?? double.nan),
      'viewportHeight': finiteOrNull(viewportHeight),
      'viewportBottom': hasViewport
          ? finiteOrNull(offset + viewportHeight)
          : null,
      'scrollDirection': scrollDirection,
      'isScrolling': position?.isScrollingNotifier.value ?? false,
      'dragging': _dragging,
      'restoreLocked': _anchorManager.restoreLocked,
      'initialRestoreCompleted': _initialRestoreCompleted,
      'restorePrefetchBarrierActive': _restorePrefetchBarrierActive,
      'restoreUserScrollObserved': _restoreUserScrollObserved,
      'runtimeLocationRevision': _runtimeLocationRevision,
      'pendingChapterJumpTarget': widget.runtime.pendingChapterJumpTarget
          ?.toJson(),
      'runtimeVisibleLocation': runtimeState.visibleLocation.toJson(),
      'runtimeCommittedLocation': runtimeState.committedLocation.toJson(),
      'capturedLocation': captured?.toJson(),
      'layoutGeneration': runtimeState.layoutGeneration,
      'epoch': _epoch.value,
      'documentIndexRevision': _documentIndex.revisionNumber,
      'documentIndexResetGeneration': _documentIndex.resetGeneration,
      'documentIndexCenter': keyJson(_documentIndex.centerKey),
      'admittedCount': _documentIndex.admittedCount,
      'beforeCount': _documentIndex.beforeCount,
      'centerAndAfterCount': _documentIndex.centerAndAfterCount,
      'beforeExtent': finiteOrNull(_documentIndex.beforeExtent),
      'afterExtent': finiteOrNull(_documentIndex.afterExtent),
      'backwardEdge': _documentIndex.backwardEdgeKey == null
          ? null
          : keyJson(_documentIndex.backwardEdgeKey!),
      'forwardEdge': _documentIndex.forwardEdgeKey == null
          ? null
          : keyJson(_documentIndex.forwardEdgeKey!),
      'visibleKeys': [for (final key in visibleKeys) keyJson(key)],
      'visibleChapters': visibleChapters,
      'visibleKeysContiguous': visibleKeysContiguous,
      'missingParagraphKeys': [
        for (final key in missingParagraphKeys) keyJson(key),
      ],
      'paragraphCacheLength': _paragraphCache.length,
      'loadedChapterCount': _blocks.length,
      'chaptersInFlight': _blocksInFlight.keys.toList(growable: false),
      'enqueuedCount': _enqueued.length,
      'pumpQueueDepth': _pump.queueDepth,
      'discardedLayoutTasks': _discardedLayoutTaskCount,
      'forwardLeadPx': finiteOrNull(_admission.latestForwardLead),
      'backwardLeadPx': finiteOrNull(_admission.latestBackwardLead),
      'rollingFrameP50Micros': telemetry.frameP50Micros,
      'rollingFrameP95Micros': telemetry.frameP95Micros,
      'rollingFrameP99Micros': telemetry.frameP99Micros,
      'rollingJankOver8ms': telemetry.jankOver8ms,
      'rollingJankOver16ms': telemetry.jankOver16ms,
      'rollingJankOver33ms': telemetry.jankOver33ms,
      'worstFrameMicros': telemetry.worstFrameMicros,
      'consecutiveMissedFrames': telemetry.consecutiveMissedFrames,
      'maxConsecutiveMissedFrames': telemetry.maxConsecutiveMissedFrames,
      'layoutTaskCount': telemetry.layoutTaskCount,
      'layoutTaskP99Micros': telemetry.layoutTaskP99Micros,
      'worstLayoutTaskMicros': telemetry.worstLayoutTaskMicros,
      'worstLayoutTaskPredictedMicros':
          telemetry.worstLayoutTaskPredictedMicros,
      'worstLayoutTaskCharCount': telemetry.worstLayoutTaskCharCount,
      'layoutTasksOver8ms': telemetry.layoutTasksOver8ms,
      'vsyncOverheadP99Micros': telemetry.vsyncOverheadP99Micros,
      'buildP99Micros': telemetry.buildP99Micros,
      'rasterP99Micros': telemetry.rasterP99Micros,
      'worstVsyncOverheadMicros': telemetry.worstVsyncOverheadMicros,
      'worstBuildMicros': telemetry.worstBuildMicros,
      'worstRasterMicros': telemetry.worstRasterMicros,
      'invariantHookEnabled':
          kDebugMode && HybridReaderScreen.debugFrameInvariantsEnabled,
    };
  }

  /// 連續 workload 的效能 window seam；正式畫面不讀取這個方法。
  @visibleForTesting
  Map<String, Object?> debugPerformanceSummary() {
    _telemetry.recordPumpQueueDepth(_pump.queueDepth);
    return <String, Object?>{
      ..._telemetry.sessionSummary(),
      'invariantHookEnabled':
          kDebugMode && HybridReaderScreen.debugFrameInvariantsEnabled,
    };
  }

  /// Read and optionally clear the bounded debug-hook history. The hook does
  /// not throw: the integration workload decides at action boundaries how to
  /// classify and report the captured events.
  @visibleForTesting
  List<Map<String, Object?>> debugFrameInvariantViolations({
    bool clear = false,
    String? oracle,
  }) {
    final violations = <Map<String, Object?>>[
      for (final violation in _invariantViolations ?? const [])
        if (oracle == null || violation.oracle == oracle) violation.toJson(),
    ];
    if (clear) {
      if (oracle == null) {
        _invariantViolations?.clear();
      } else {
        _invariantViolations?.removeWhere(
          (violation) => violation.oracle == oracle,
        );
      }
    }
    return violations;
  }

  @visibleForTesting
  Map<String, int> debugFrameInvariantViolationCounts() {
    var runtime = 0;
    var temporal = 0;
    for (final violation in _invariantViolations ?? const []) {
      if (violation.oracle == 'temporal') {
        temporal += 1;
      } else {
        runtime += 1;
      }
    }
    return <String, int>{'runtime': runtime, 'temporal': temporal};
  }

  @visibleForTesting
  void debugResetFrameInvariantHistory() {
    _invariantViolations?.clear();
    _invariantRecordHistory?.clear();
    _temporalOracle?.reset();
    _previousInvariantRecord = null;
    _lastInvariantRecord = null;
  }

  @visibleForTesting
  List<Map<String, Object?>> debugFrameInvariantRecords() {
    return [
      for (final record in _invariantRecordHistory ?? const []) record.toJson(),
    ];
  }

  /// Enable a bounded debug visual injection on the mounted reader.  The
  /// switch is effective only in debug mode and is intentionally exposed via
  /// `visibleForTesting`; it is not a production runtime knob.
  @visibleForTesting
  void debugSetVisualInjection(ReaderVisualInjection injection) {
    if (!kDebugMode) return;
    _startVisualOracle();
    _visualInjection = injection;
    _visualInjectionStep = 0;
    _visualInjectionAdvanceQueued = false;
    if (mounted) setState(() {});
  }

  @visibleForTesting
  void debugResetVisualOracle() {
    _visualOracle?.reset();
    _previousVisualRaster = null;
    _visualNextSequence = 0;
    _visualNextSequenceToProcess = 0;
    _visualGeneration += 1;
    _visualInFlight = 0;
    _visualMaxObservedInFlight = 0;
    _visualTotalFrames = 0;
    _visualCapturedFrames = 0;
    _visualDroppedFrames = 0;
    _visualCaptureErrorCount = 0;
    _visualCaptureCostMicros = 0;
    _visualLastSourceWidth = 0;
    _visualLastSourceHeight = 0;
    _visualCaptureCostsMicros.clear();
    _visualDroppedSequences.clear();
    _visualPendingResults.clear();
    _visualInjection = ReaderVisualInjection.none;
    _visualInjectionStep = 0;
    _visualInjectionAdvanceQueued = false;
  }

  @visibleForTesting
  void debugStopVisualMotionForTesting() {
    if (!kDebugMode) return;
    final controller = _scrollController;
    if (controller != null && controller.hasClients) {
      (controller.position as dynamic).goIdle();
    }
    _dragging = false;
    _sawUserScroll = false;
    _invariantScrollActivityHint = 'idle';
    _setPumpState(PumpState.idle);
  }

  @visibleForTesting
  Map<String, Object?> debugVisualOracleSummary() {
    final costs = [..._visualCaptureCostsMicros]..sort();
    int percentile(double fraction) {
      if (costs.isEmpty) return 0;
      final index = (costs.length * fraction).ceil() - 1;
      return costs[index.clamp(0, costs.length - 1)];
    }

    final violationCounts = <String, int>{};
    for (final violation
        in _visualOracle?.violations ?? const <ReaderVisualViolation>[]) {
      violationCounts.update(
        violation.invariant,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final profileMatchStats =
        _visualOracle?.profileMatchStats() ??
        const <String, Object?>{
          'framesWithDecodedProfiles': 0,
          'decodedProfiles': 0,
          'matchingProfiles': 0,
          'matchRate': 0.0,
        };
    return <String, Object?>{
      'enabled': _visualOracle != null,
      'totalFrames': _visualTotalFrames,
      'capturedFrames': _visualCapturedFrames,
      'droppedFrames': _visualDroppedFrames,
      'coverage': _visualTotalFrames == 0
          ? 0.0
          : _visualCapturedFrames / _visualTotalFrames,
      'analysisWidth': readerVisualDefaultAnalysisWidth,
      'sourceRasterWidth': _visualLastSourceWidth,
      'sourceRasterHeight': _visualLastSourceHeight,
      'maxInFlight': _visualMaxInFlight,
      'maxObservedInFlight': _visualMaxObservedInFlight,
      'captureErrorCount': _visualCaptureErrorCount,
      'captureCostTotalMicros': _visualCaptureCostMicros,
      'captureCostP50Micros': percentile(0.50),
      'captureCostP95Micros': percentile(0.95),
      'captureCostP99Micros': percentile(0.99),
      ...profileMatchStats,
      'violations': violationCounts,
      'retainedRawFrames': [
        for (final raw
            in _visualOracle?.lastRetainedRawFrames ??
                const <ReaderVisualRawFrame>[])
          raw.toJson(),
      ],
      'coverageBoundary': 'in-process RepaintBoundary pixels; Flutter compositor, Impeller, and SurfaceFlinger remain outside this observation source',
    };
  }

  @visibleForTesting
  List<Map<String, Object?>> debugVisualOracleFrames() {
    return [
      for (final frame in _visualOracle?.frames ?? const <ReaderVisualFrame>[])
        frame.toJson(),
    ];
  }

  /// Return the original RGBA frames retained by the visual oracle for its
  /// latest failure window.  This is deliberately a test-only bridge: normal
  /// frames are not retained, and the production render path never calls it.
  @visibleForTesting
  List<ReaderVisualRawFrame> debugVisualOracleRetainedRawFrames() {
    return [...?_visualOracle?.lastRetainedRawFrames];
  }

  @visibleForTesting
  List<Map<String, Object?>> debugVisualOracleViolations({bool clear = false}) {
    final violations = [
      for (final violation
          in _visualOracle?.violations ?? const <ReaderVisualViolation>[])
        violation.toJson(),
    ];
    if (clear) _visualOracle?.reset();
    return violations;
  }

  void _startVisualOracle() {
    if (!kDebugMode || _visualOracle != null) return;
    _visualOracle = ReaderVisualOracle();
    _visualFrameCallbackScheduled = false;
    _scheduleVisualFrameCallback();
  }

  void _resetVisualOracleState() {
    if (_visualOracle == null) return;
    _visualOracle!.reset();
    _previousVisualRaster = null;
    _visualNextSequence = 0;
    _visualNextSequenceToProcess = 0;
    _visualGeneration += 1;
    _visualInFlight = 0;
    _visualMaxObservedInFlight = 0;
    _visualTotalFrames = 0;
    _visualCapturedFrames = 0;
    _visualDroppedFrames = 0;
    _visualCaptureErrorCount = 0;
    _visualCaptureCostMicros = 0;
    _visualLastSourceWidth = 0;
    _visualLastSourceHeight = 0;
    _visualCaptureCostsMicros.clear();
    _visualDroppedSequences.clear();
    _visualPendingResults.clear();
  }

  void _scheduleVisualFrameCallback() {
    if (_visualFrameCallbackScheduled || !mounted || _visualOracle == null) {
      return;
    }
    _visualFrameCallbackScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback(_handleVisualFrame);
    // A post-frame callback alone does not request the next frame.  The
    // oracle is opt-in debug instrumentation, so keep its sampling loop
    // alive explicitly while it is enabled; the normal reader path never
    // reaches this method and pays no scheduling cost.
    WidgetsBinding.instance.scheduleFrame();
  }

  void _handleVisualFrame(Duration timestamp) {
    _visualFrameCallbackScheduled = false;
    if (!mounted || !kDebugMode || _visualOracle == null) return;
    final sequence = _visualNextSequence++;
    _visualTotalFrames += 1;
    final boundaryContext = _visualBoundaryKey.currentContext;
    final renderObject = boundaryContext?.findRenderObject();
    final boundary = renderObject is RenderRepaintBoundary
        ? renderObject
        : null;
    if (boundary == null ||
        !boundary.hasSize ||
        _visualInFlight >= _visualMaxInFlight) {
      _visualDroppedFrames += 1;
      _visualDroppedSequences.add(sequence);
      _drainVisualResults();
      _scheduleVisualFrameCallback();
      return;
    }
    final runtime = _captureInvariantFrame(timestamp);
    final generation = _visualGeneration;
    _visualInFlight += 1;
    _visualMaxObservedInFlight = math.max(
      _visualMaxObservedInFlight,
      _visualInFlight,
    );
    unawaited(
      _captureVisualFrame(
        boundary: boundary,
        sequence: sequence,
        timestamp: timestamp,
        generation: generation,
        runtime: runtime,
      ),
    );
    _scheduleVisualFrameCallback();
  }

  Future<void> _captureVisualFrame({
    required RenderRepaintBoundary boundary,
    required int sequence,
    required Duration timestamp,
    required int generation,
    required HybridFrameInvariantRecord runtime,
  }) async {
    final stopwatch = Stopwatch()..start();
    ui.Image? image;
    try {
      image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (generation != _visualGeneration) return;
      if (byteData == null) {
        _visualDroppedFrames += 1;
        _visualDroppedSequences.add(sequence);
        _drainVisualResults();
        return;
      }
      final rgba = Uint8List.fromList(
        byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
      );
      final raster = ReaderVisualRaster.fromRgba(
        sourceWidth: image.width,
        sourceHeight: image.height,
        rgba: rgba,
        analysisWidth: readerVisualDefaultAnalysisWidth,
      );
      final raw = ReaderVisualRawFrame(
        sequence: sequence,
        timestampMicros: timestamp.inMicroseconds,
        width: image.width,
        height: image.height,
        rgba: rgba,
      );
      _visualPendingResults[sequence] = _VisualCaptureResult(
        sequence: sequence,
        timestampMicros: timestamp.inMicroseconds,
        raster: raster,
        raw: raw,
        runtime: _visualRuntimeRecord(runtime),
        costMicros: stopwatch.elapsedMicroseconds,
      );
      _drainVisualResults();
    } catch (error) {
      if (generation != _visualGeneration) return;
      _visualDroppedFrames += 1;
      _visualCaptureErrorCount += 1;
      _visualDroppedSequences.add(sequence);
      debugPrint('Reader visual oracle capture failed: $error');
      _drainVisualResults();
    } finally {
      image?.dispose();
      _visualInFlight = math.max(0, _visualInFlight - 1);
    }
  }

  void _drainVisualResults() {
    while (true) {
      if (_visualDroppedSequences.remove(_visualNextSequenceToProcess)) {
        _visualNextSequenceToProcess += 1;
        continue;
      }
      final result = _visualPendingResults.remove(_visualNextSequenceToProcess);
      if (result == null) return;
      _visualNextSequenceToProcess += 1;
      _processVisualResult(result);
    }
  }

  void _processVisualResult(_VisualCaptureResult result) {
    final previous = _previousVisualRaster;
    final frame = ReaderVisualFrame.fromRaster(
      sequence: result.sequence,
      timestampMicros: result.timestampMicros,
      raster: result.raster,
      previousRaster: previous,
      profileBlockIndexOffset: _visualProfileBlockIndexOffset,
      opaquePixelRatio: _opaquePixelRatio(result.raw.rgba),
    );
    _previousVisualRaster = result.raster;
    _visualCapturedFrames += 1;
    _visualLastSourceWidth = result.raw.width;
    _visualLastSourceHeight = result.raw.height;
    _visualCaptureCostMicros += result.costMicros;
    _visualCaptureCostsMicros.add(result.costMicros);
    if (_visualCaptureCostsMicros.length > readerVisualMaxFrames) {
      _visualCaptureCostsMicros.removeAt(0);
    }
    var runtime = result.runtime;
    if (_visualInjection == ReaderVisualInjection.visualScrollWhileIdle) {
      // The endpoint deliberately reports an idle runtime sample while the
      // pixel child is translated below. This keeps the proof focused on
      // V19 even if the host scroll position has a late physics hand-off.
      runtime = ReaderVisualRuntimeRecord(
        timestampMicros: runtime.timestampMicros,
        visibleKeys: runtime.visibleKeys,
        scrollPixels: null,
        dominantVisibleChapter: runtime.dominantVisibleChapter,
        displayedProgressChapter: runtime.displayedProgressChapter,
        phase: runtime.phase,
        scrollActivity: 'idle',
        isScrolling: false,
        viewportHeight: runtime.viewportHeight,
      );
    } else if (_visualInjection == ReaderVisualInjection.crossOracleMismatch) {
      final displayed =
          runtime.displayedProgressChapter ??
          runtime.dominantVisibleChapter ??
          0;
      runtime = ReaderVisualRuntimeRecord(
        timestampMicros: runtime.timestampMicros,
        visibleKeys: runtime.visibleKeys,
        scrollPixels: runtime.scrollPixels,
        dominantVisibleChapter: runtime.dominantVisibleChapter,
        displayedProgressChapter: displayed + 1,
        phase: runtime.phase,
        scrollActivity: runtime.scrollActivity,
        isScrolling: runtime.isScrolling,
        viewportHeight: runtime.viewportHeight,
      );
    }
    _visualOracle?.observe(frame, runtime: runtime, rawFrame: result.raw);
  }

  double _opaquePixelRatio(Uint8List rgba) {
    if (rgba.isEmpty) return 0;
    var opaque = 0;
    for (var offset = 3; offset < rgba.length; offset += 4) {
      if (rgba[offset] == 255) opaque += 1;
    }
    return opaque / (rgba.length ~/ 4);
  }

  ReaderVisualRuntimeRecord _visualRuntimeRecord(
    HybridFrameInvariantRecord record,
  ) {
    return ReaderVisualRuntimeRecord(
      timestampMicros: record.timestampMicros,
      visibleKeys: record.visibleKeys,
      scrollPixels: record.scrollPixels,
      dominantVisibleChapter: record.dominantVisibleChapter,
      displayedProgressChapter: record.displayedProgressChapter,
      phase: record.phase,
      scrollActivity: record.scrollActivity,
      isScrolling: record.isScrolling,
      viewportHeight: record.viewportHeight ?? _viewportSize.height,
    );
  }

  void _queueVisualInjectionAdvance() {
    if (_visualInjectionAdvanceQueued) return;
    _visualInjectionAdvanceQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visualInjectionAdvanceQueued = false;
      if (!mounted || !kDebugMode) return;
      if (_visualInjection == ReaderVisualInjection.blankNextFrame) {
        setState(() {
          _visualInjection = ReaderVisualInjection.none;
          _visualInjectionStep = 0;
        });
        return;
      }
      if (_visualInjection != ReaderVisualInjection.visualScrollWhileIdle) {
        return;
      }
      if (_visualInjectionStep >= 4) return;
      setState(() => _visualInjectionStep += 1);
    });
  }

  String _scrollActivityName(ScrollActivity? activity) {
    if (activity is DragScrollActivity) return 'drag';
    if (activity is BallisticScrollActivity) return 'ballistic';
    if (activity is DrivenScrollActivity) return 'driven';
    return 'idle';
  }

  double? _finiteActivityVelocity(ScrollActivity? activity) {
    final velocity = activity?.velocity ?? 0.0;
    return velocity.isFinite ? velocity : null;
  }

  HybridFrameInvariantRecord _captureInvariantFrame(Duration timestamp) {
    final controller = _scrollController;
    final position = controller != null && controller.hasClients
        ? controller.position
        : null;
    // ScrollPosition.activity is a protected Flutter diagnostic seam. Read it
    // through the already-attached concrete position so the oracle observes
    // the real activity without making the production scroll path depend on a
    // test-only subclass.
    final activity = position == null
        ? null
        : (position as dynamic).activity as ScrollActivity?;
    // The post-frame callback can run after ScrollPosition has already
    // converted a just-finished drag into its ballistic hand-off. Keep the
    // real notification-backed drag bit for that sampling boundary, and use
    // ScrollPosition.activity for the remaining activity kinds.
    final scrollActivity =
        _invariantScrollActivityHint ??
        (_dragging ? 'drag' : _scrollActivityName(activity));
    final offset = _effectiveScrollOffset();
    final viewportHeight = _viewportSize.height;
    final hasViewport = offset != null && viewportHeight > 0;
    final visibleKeys = hasViewport
        ? _documentIndex
              .keysInRange(offset, offset + viewportHeight)
              .toList(growable: false)
        : const <BlockKey>[];
    final visibleChapters = <int>[];
    final seenChapters = <int>{};
    var missingParagraphCount = 0;
    for (final key in visibleKeys) {
      if (seenChapters.add(key.chapterIndex)) {
        visibleChapters.add(key.chapterIndex);
      }
      if (!_paragraphCache.containsFresh(key, _epoch, widget.textColor)) {
        missingParagraphCount += 1;
      }
    }
    final anchorOffset = hasViewport
        ? offset + AnchorManager.anchorOffsetInViewport(viewportHeight)
        : null;
    final anchorKey = anchorOffset == null
        ? null
        : _documentIndex.blockAtOffset(anchorOffset);
    final anchorChapter = anchorKey?.chapterIndex;
    // The reader intentionally keeps the public chapter at a short-chapter
    // boundary until the physical offset leaves that chapter's admitted
    // range. This is the same semantic source used by capture/restore and
    // the title/navigation state; the raw anchor chapter is retained above
    // for diagnosing a cross-chapter frame.
    final dominantChapter = widget.runtime.state.visibleLocation.chapterIndex;
    final progress = widget.progressListenable?.value;
    final unloadedChapterCount = visibleChapters
        .where((chapter) => !_blocks.containsKey(chapter))
        .length;
    final operation = widget.runtime.stateMachine.currentOperation;
    return HybridFrameInvariantRecord(
      timestampMicros: timestamp.inMicroseconds,
      phase: widget.runtime.state.phase.name,
      scrollOffset: offset?.isFinite == true ? offset : null,
      viewportHeight: viewportHeight.isFinite ? viewportHeight : null,
      // In the debug oracle path a ScrollStartNotification is the only
      // reliable boundary left after Flutter's test gesture has already
      // handed the position to ballistic; pair its activity hint with the
      // existing drag bit so I11 does not call that real hand-off unsolicited.
      dragging: _dragging || scrollActivity == 'drag',
      isScrolling: position?.isScrollingNotifier.value ?? false,
      restoreLocked: _anchorManager.restoreLocked,
      initialRestoreCompleted: _initialRestoreCompleted,
      pendingChapterJumpTarget: widget.runtime.pendingChapterJumpTarget,
      epoch: _epoch.value,
      layoutGeneration: widget.runtime.state.layoutGeneration,
      documentIndexRevision: _documentIndex.revisionNumber,
      resetGeneration: _documentIndex.resetGeneration,
      indexBindingResetGeneration: _indexBindingResetGeneration,
      indexCenter: _documentIndex.centerKey,
      visibleKeys: visibleKeys,
      visibleChapters: List<int>.unmodifiable(visibleChapters),
      missingParagraphCount: missingParagraphCount,
      unloadedChapterCount: unloadedChapterCount,
      dominantVisibleChapter: dominantChapter,
      anchorVisibleChapter: anchorChapter,
      displayedProgressChapter: progress?.chapterIndex,
      pumpQueueDepth: _pump.queueDepth,
      scrollPixels: position?.pixels.isFinite == true ? position!.pixels : null,
      minScrollExtent: position?.minScrollExtent.isFinite == true
          ? position!.minScrollExtent
          : null,
      maxScrollExtent: position?.maxScrollExtent.isFinite == true
          ? position!.maxScrollExtent
          : null,
      scrollActivity: scrollActivity,
      scrollVelocity: _finiteActivityVelocity(activity),
      operationTokenId: operation?.id,
      operationIsCurrent:
          operation != null &&
          widget.runtime.isCurrentOperationToken(operation),
      chapterCount: widget.runtime.chapterCount,
      errorPresent: widget.runtime.state.phase == ReaderV2Phase.error,
    );
  }

  void _handleInvariantFrame(Duration timestamp) {
    if (!mounted ||
        !kDebugMode ||
        !HybridReaderScreen.debugFrameInvariantsEnabled) {
      return;
    }
    final current = _captureInvariantFrame(timestamp);
    if (_invariantScrollActivityHint == 'drag') {
      // A ScrollStartNotification and its first update can be delivered in
      // one frame. Consume the notification-backed drag sample so the next
      // frame can expose the real ballistic hand-off.
      _invariantScrollActivityHint = null;
    }
    final records = _invariantRecordHistory!;
    if (records.length >= 256) records.removeAt(0);
    records.add(current);
    final previous = _lastInvariantRecord;
    final previousPrevious = _previousInvariantRecord;
    final violations = evaluateHybridFrameInvariants(
      current: current,
      previous: previous,
      previousPrevious: previousPrevious,
    );
    final temporalViolations =
        _temporalOracle?.observe(current, runtimeViolations: violations) ??
        const <HybridFrameInvariantViolation>[];
    final history = _invariantViolations!;
    for (final violation in <HybridFrameInvariantViolation>[
      ...violations,
      ...temporalViolations,
    ]) {
      if (history.length >= 256) history.removeAt(0);
      history.add(violation);
    }
    _previousInvariantRecord = previous;
    _lastInvariantRecord = current;
    WidgetsBinding.instance.addPostFrameCallback(_handleInvariantFrame);
  }

  /// 初始開書完成後開始計算 scroll/chapter workload 的效能 window。
  @visibleForTesting
  void debugResetPerformanceWindow() {
    _telemetry.resetPerformanceWindow();
  }

  void _handleFrameTimings(List<ui.FrameTiming> timings) {
    if (!mounted || timings.isEmpty) return;
    widget.runtime.recordFrameTimings(timings);
    _governor.recordFrameTimings(timings);
    _telemetry.recordFrameTimings(timings);
  }

  void _handleLayoutTaskCompleted(LayoutPumpTaskStats stats) {
    _telemetry.recordLayoutTask(
      elapsedMicros: stats.elapsed.inMicroseconds.toDouble(),
      predictedMicros: stats.predicted.inMicroseconds.toDouble(),
      charCount: stats.charCount,
    );
  }

  // ---- epoch / namespace（D9：epoch 對齊 layoutGeneration） ----

  void _refreshEpochBinding() {
    _epoch = LayoutEpoch(widget.runtime.state.layoutGeneration);
    _fingerprint = StyleFingerprint.fromLayoutSpec(
      widget.runtime.state.layoutSpec,
      justify: AppConfig.readerV2ContentJustify,
      platformFontSignature:
          '${defaultTargetPlatform.name}:${io.Platform.operatingSystemVersion}',
    );
    _namespace = MeasurementNamespace(epoch: _epoch, fingerprint: _fingerprint);
    _pump = LayoutPump(
      paragraphCache: _paragraphCache,
      measurementStore: _measurementStore,
      namespace: _namespace,
      governor: _governor,
      onTaskCompleted: _handleLayoutTaskCompleted,
      isTaskStillDesired: _isLayoutTaskStillDesired,
      onTaskDiscarded: _handleLayoutTaskDiscarded,
    );
    _admission.reset(epoch: _epoch, chapterCount: widget.runtime.chapterCount);
    _admission.attach(_pump.completed);
  }

  void _handleEpochRebuild() {
    // Do not leave a mounted sliver reading the old render tree while the
    // index and metrics namespace are being replaced. The extent callback has
    // a defensive fallback as a same-frame guard, but the normal transition
    // must render the loading state until restore has rebuilt the window.
    _prefetchGeneration += 1;
    _initialRestoreCompleted = false;
    _lastSyncedLocation = null;
    // 舊 namespace 的量測 best-effort 落盤後自 store 回收——同款樣式改回
    // 來可直接 warm；不回收的話每次樣式變更都漏一整組 metrics 在記憶體。
    final oldNamespace = _namespace;
    unawaited(
      _writeDiskMetrics(
        _measurementStore.snapshot(oldNamespace),
        fingerprint: oldNamespace.fingerprint,
      ),
    );
    _measurementStore.invalidateNamespace(oldNamespace);
    _enqueued.clear();
    _blocks.clear();
    _blocksInFlight.clear();
    _chapterRepo.invalidateLoaded(emitEvents: false);
    _pump.dispose();
    final oldCache = _paragraphCache;
    _paragraphCache = ParagraphCache(capacity: widget.paragraphCacheCapacity);
    WidgetsBinding.instance.addPostFrameCallback((_) => oldCache.dispose());
    // 舊索引的 extent 屬於已回收的舊 namespace；不清空的話重建到 restore
    // 完成之間的幀會拿舊座標配空 metrics 觸發 I1。restore 會重定中心。
    _documentIndex.reset(centerKey: _documentIndex.centerKey);
    _indexBindingResetGeneration = _documentIndex.resetGeneration;
    _refreshEpochBinding();
    _warmedChapters.removeWhere((entry) => entry.namespace != _namespace);
  }

  // ---- runtime 事件 ----

  void _onRuntimeChanged() {
    if (!mounted) return;
    final state = widget.runtime.state;
    final errorMessage = state.errorMessage;
    if (state.phase != ReaderV2Phase.error) {
      _lastLoggedErrorMessage = null;
    } else if (errorMessage != null &&
        errorMessage.isNotEmpty &&
        errorMessage != _lastLoggedErrorMessage) {
      _lastLoggedErrorMessage = errorMessage;
      debugPrint('ReaderV2 operation failed: $errorMessage');
    }
    final layoutChanged = _lastLayoutGeneration != state.layoutGeneration;
    if (layoutChanged) {
      _lastLayoutGeneration = state.layoutGeneration;
      _handleEpochRebuild();
    }
    if (state.phase == ReaderV2Phase.ready && _initialRestoreCompleted) {
      _publishProgress();
    }
    if (_capturing) {
      _scheduleRebuild();
      return;
    }
    final locationChanged = state.visibleLocation != _lastReportedLocation;
    final needsViewportSync =
        locationChanged ||
        (layoutChanged && !widget.runtime.hybridViewportActive);
    final jumpOwnsViewport =
        widget.runtime.pendingChapterJumpTarget != null ||
        _anchorManager.restoreLocked;
    if (needsViewportSync && !jumpOwnsViewport) {
      _runtimeLocationRevision += 1;
      final revision = _runtimeLocationRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || revision != _runtimeLocationRevision) return;
        unawaited(_syncToRuntimeLocation(force: true));
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
    _scheduleRebuild();
  }

  Future<void> _syncToRuntimeLocation({bool force = false}) async {
    final runtime = widget.runtime;
    if (runtime.chapterCount <= 0) return;
    final location = runtime.state.visibleLocation.normalized(
      chapterCount: runtime.chapterCount,
    );
    if (!force && _initialRestoreCompleted && _lastSyncedLocation == location) {
      return;
    }
    final generation = runtime.state.layoutGeneration;
    bool still() =>
        mounted &&
        runtime.state.layoutGeneration == generation &&
        runtime.state.visibleLocation.normalized(
              chapterCount: runtime.chapterCount,
            ) ==
            location;
    final ok = await _restoreCore(location, isCurrent: still);
    if (!ok || !still()) return;
    _lastSyncedLocation = location;
    _lastReportedLocation = location;
    _scheduleRebuild();
  }

  // ---- capture / restore（D5 條款 2；I6：一切重建以 HybridAnchor 為基準） ----

  ReaderV2Location? _captureForBridge() {
    final location = _captureVisibleLocation();
    if (location != null) _lastReportedLocation = location;
    return location;
  }

  ReaderV2Location? _captureVisibleLocation() {
    final offset = _effectiveScrollOffset();
    if (offset == null || _viewportSize.height <= 0) return null;
    final anchorLine = AnchorManager.anchorOffsetInViewport(
      _viewportSize.height,
    );
    final worldY = offset + anchorLine;
    final anchorHit = _documentIndex.hitTest(worldY);
    final scrollTopHit = _documentIndex.hitTest(offset);
    final preserved = _preserveShortChapterAtBoundary(
      anchorHit: anchorHit,
      scrollOffset: offset,
    );
    if (preserved != null) return preserved;
    final hit = anchorHit ?? scrollTopHit;
    if (hit == null) return null;
    final blocks = _blocks[hit.key.chapterIndex];
    if (blocks == null || hit.key.blockIndex >= blocks.blocks.length) {
      return null;
    }
    final block = blocks.blocks[hit.key.blockIndex];
    var lineTop = 0.0;
    var charOffset = block.charRange.start;
    // hit.key 的 Paragraph 可能與同一連續排版 group 內的其他 block 共用；
    // hit.offsetInBlock 是「這個 block 自己 Y 窗」內的座標，要先平移回
    // 共用 Paragraph 的座標系（+entry.localTop）才能查行／查字元。
    final entry = _paragraphCache.acquireEntry(hit.key, _epoch);
    if (entry != null) {
      final paragraph = entry.paragraph;
      final line = _lineAt(paragraph, hit.offsetInBlock + entry.localTop);
      if (line != null) {
        final group = blocks.groupContaining(hit.key);
        final indent = _indentCharsFor(group.first);
        final groupTextLength = indent + _groupTextLength(group);
        final position = paragraph.getPositionForOffset(
          Offset(0, line.top + 0.1),
        );
        final boxTop = _textBoxTopForOffset(
          paragraph,
          position.offset,
          groupTextLength,
        );
        // 換算回這個 block 自己的 Y 窗座標，才能跟 hit.blockTop 相加。
        lineTop = (boxTop ?? line.top) - entry.localTop;
        final groupStart = group.first.charRange.start;
        final groupEnd = group.last.charRange.end;
        charOffset = (groupStart + math.max(0, position.offset - indent))
            .clamp(groupStart, groupEnd)
            .toInt();
      }
    }
    final visual = (worldY - (hit.blockTop + lineTop))
        .clamp(
          ReaderV2Location.minVisualOffsetPx,
          ReaderV2Location.maxVisualOffsetPx,
        )
        .toDouble();
    return ReaderV2Location(
      chapterIndex: hit.key.chapterIndex,
      charOffset: charOffset,
      visualOffsetPx: visual,
    ).normalized(
      chapterCount: widget.runtime.chapterCount,
      chapterLength: blocks.displayText.length,
    );
  }

  /// A short chapter can end before the visual anchor line while the viewport
  /// is still at that chapter's physical start.  In that transition the
  /// anchor hit points at the next chapter, but the reader has not scrolled
  /// past the current chapter yet.  Keep the last reported chapter until the
  /// scroll offset leaves its admitted range; otherwise opening a book at a
  /// one-line preface is immediately persisted as chapter 1.
  ReaderV2Location? _preserveShortChapterAtBoundary({
    required DocumentOffsetHit? anchorHit,
    required double scrollOffset,
  }) {
    final previous = _lastReportedLocation;
    if (previous == null ||
        anchorHit == null ||
        anchorHit.key.chapterIndex != previous.chapterIndex + 1) {
      return null;
    }
    final range = _documentIndex.chapterRange(previous.chapterIndex);
    if (range == null || scrollOffset > range.bottom + 0.5) return null;
    return previous;
  }

  Future<bool> _restoreToLocation(ReaderV2Location location) async {
    if (!mounted || widget.runtime.chapterCount <= 0) return false;
    // 拖曳中拒絕 restore——settle-restore 硬拉回目標會跟手勢打架。
    // 明確的 runtime chapter jump 已先取得 pending ownership；它可能在
    // ballistic 尾端收到最後一個 drag notification，仍應由 jump 接管
    // viewport，而不是被那個短暫旗標拒絕。
    final jumpOwnsViewport = widget.runtime.pendingChapterJumpTarget != null;
    if (!_anchorManager.beginRestore(
      isDragging: _dragging && !jumpOwnsViewport,
    )) {
      return false;
    }
    try {
      final ok = await _restoreCore(location);
      if (!ok || !mounted) return false;
      _scheduleRebuild();
      // A ballistic jump can finish before the rebuilt sliver has painted a
      // frame. The requested location is already the restore contract; do
      // not turn that transiently uncapturable frame into a failed jump.
      // _lastReportedLocation is intentionally set to the requested anchor
      // below, before runtime.completeReady() publishes the new state.  Bump
      // the revision here as well so a scroll callback queued by the old
      // viewport cannot run after that publication and overwrite the target.
      _runtimeLocationRevision += 1;
      _lastSyncedLocation = location;
      _lastReportedLocation = location;
      return true;
    } finally {
      _anchorManager.completeRestore();
    }
  }

  Future<bool> _restoreCore(
    ReaderV2Location location, {
    bool Function()? isCurrent,
  }) async {
    final runtime = widget.runtime;
    if (runtime.chapterCount <= 0) return false;
    final ticket = ++_restoreTicket;
    _prefetchGeneration += 1;
    // Chapter repository prefetch is asynchronous and its loaded event can
    // arrive after _restorePinning is released. Keep that event on the same
    // bounded restore path until an ordinary settled scroll explicitly asks
    // for the full lead window.
    _restorePrefetchBarrierActive = true;
    _restoreUserScrollObserved = false;
    bool still() =>
        mounted && ticket == _restoreTicket && (isCurrent?.call() ?? true);
    final chapterIndex = location.chapterIndex
        .clamp(0, runtime.chapterCount - 1)
        .toInt();
    _pump.onScrollStateChanged(PumpState.rebuilding);
    try {
      final blocks = await _ensureChapterBlocks(chapterIndex);
      if (blocks == null || !still()) return false;
      final normalized = location.normalized(
        chapterCount: runtime.chapterCount,
        chapterLength: blocks.displayText.length,
      );
      final anchor = _anchorManager.captureFromLocation(normalized, blocks);
      // reset() invalidates the mounted sliver's old index synchronously.
      // Hide that sliver on the next frame while the anchor window is rebuilt;
      // the total extent callback above also protects the current frame.
      _initialRestoreCompleted = false;
      _lastSyncedLocation = null;
      _scheduleRebuild();
      // 重定中心：admitted 度量由 store 回填（經 _ensureWindowTasks 的
      // 連續段 direct-admit），上側走 center 負座標生長（I3）。
      _documentIndex.reset(centerKey: anchor.blockKey);
      _indexBindingResetGeneration = _documentIndex.resetGeneration;
      _admission.reset(epoch: _epoch, chapterCount: runtime.chapterCount);
      _admission.attach(_pump.completed);
      for (final loadedBlocks in _blocks.values) {
        _admission.registerChapter(loadedBlocks);
      }
      // restore 期間畫面停在 loading，_updateParagraphPins 不會執行；先清
      // 舊 pin、預 pin 錨點，並開啟 submit-time pinning——不 pin 的話初始
      // 視窗建置量超過快取容量時，LRU 會把首屏段落逐出（開書只剩錨點
      // 一行、其餘佔位空白）。正式 build 的 _updateParagraphPins 會接手
      // 重整 pin 集合。
      _paragraphCache
        ..unpinAll()
        ..pinKeys(<BlockKey>[anchor.blockKey], _epoch);
      _restorePinning = true;
      _enqueued.clear();
      _windowCenter = chapterIndex;
      _chapterRepo.setPrefetchCenter(chapterIndex);
      _ensureWindowTasks(anchorKey: anchor.blockKey, restoreOnly: true);
      final ready = await _pumpUntilAnchorReady(anchor, stillCurrent: still);
      if (!ready || !still()) return false;
      final target = _offsetForAnchor(anchor, blocks);
      if (target == null) return false;
      _applyScrollOffset(target);
      _admission.activateViewport(
        visibleTop: target,
        visibleBottom: target + _viewportSize.height,
        cacheExtent: _viewportSize.height,
      );
      _initialRestoreCompleted = true;
      // Restore changes the document coordinate system and can complete
      // without a scroll notification. Publish the new chapter immediately
      // through the narrow progress channel; otherwise the page shell can
      // keep showing the previous chapter label while the new content is
      // already visible.
      _publishProgress();
      _scheduleRebuild();
      _schedulePump();
      return true;
    } finally {
      if (ticket == _restoreTicket) {
        _restorePinning = false;
        _pump.onScrollStateChanged(
          _dragging ? PumpState.dragging : PumpState.idle,
        );
      }
    }
  }

  Future<bool> _pumpUntilAnchorReady(
    HybridAnchor anchor, {
    required bool Function() stillCurrent,
  }) async {
    bool anchorReady() =>
        _measurementStore.get(_namespace, anchor.blockKey) != null &&
        _paragraphCache.contains(anchor.blockKey, _epoch);
    bool initialWindowReady() {
      if (!anchorReady()) return false;
      final blocks = _blocks[anchor.chapterIndex];
      final target = blocks == null ? null : _offsetForAnchor(anchor, blocks);
      if (target == null) return false;
      final viewport = math.max(1.0, _viewportSize.height);
      // Initial restore only needs enough admitted geometry to present the
      // target viewport.  The full 3000/6000 logical-pixel lead is a normal
      // scrolling safety window, not an initial-restore prerequisite.  A
      // multi-chapter book can legitimately have only the bounded nearby
      // chapters loaded at first open; requiring the full lead here makes a
      // drained, presentable first viewport report `restored=false` before
      // ordinary settled scrolling gets a chance to grow that window.
      final requiredTop = target;
      final requiredBottom = target + viewport;
      final hasTop = -_documentIndex.beforeExtent <= requiredTop;
      final hasBottom = _documentIndex.afterExtent >= requiredBottom;
      return (hasTop || _isBookStartAdmitted()) &&
          (hasBottom || _isBookEndAdmitted());
    }

    var guard = 0;
    while (guard++ < 600) {
      if (!stillCurrent()) return false;
      // A jump owns the viewport for the whole restore transaction.  The
      // final drag/ballistic notifications from the old scroll position can
      // still arrive while an async chapter load is completing; they must not
      // change the pump back to dragging and starve the anchor task.  Ordinary
      // user-drag restores never enter this method because beginRestore rejects
      // them above.
      _pump.onScrollStateChanged(PumpState.rebuilding);
      // A restore must not return with a tail of non-visible work already in
      // the pump.  The old all-chapter enqueue path made the anchor ready
      // while hundreds of groups still drained in the background, which is
      // observable as real frame starvation and trips the existing bounded
      // settle contract.  Restore batches are intentionally small, so drain
      // the current batch before publishing completion.
      if (initialWindowReady() && _pump.queueDepth == 0) return true;
      final completed = await _pump.pumpPending();
      if (completed != 0) continue;
      // A zero result is only terminal when there is no queued work.  The
      // governor may have observed the stale scroll state in the same turn;
      // reasserting rebuilding above makes the next bounded pass eligible to
      // consume the already-submitted anchor task.
      if (_pump.queueDepth > 0) continue;
      final pendingLoads = _blocksInFlight.values.toList(growable: false);
      if (pendingLoads.isEmpty) {
        final admittedBefore = _documentIndex.admittedCount;
        _ensureWindowTasks(anchorKey: anchor.blockKey, restoreOnly: true);
        if (_pump.queueDepth == 0 &&
            _documentIndex.admittedCount == admittedBefore) {
          return initialWindowReady();
        }
        continue;
      }
      await Future.wait(pendingLoads);
      if (!stillCurrent()) return false;
      _ensureWindowTasks(anchorKey: anchor.blockKey, restoreOnly: true);
    }
    return anchorReady();
  }

  bool _isBookStartAdmitted() {
    const first = BlockKey(chapterIndex: 0, blockIndex: 0);
    return _documentIndex.metricsFor(first) != null;
  }

  bool _isBookEndAdmitted() {
    final lastChapter = widget.runtime.chapterCount - 1;
    if (lastChapter < 0) return true;
    final blocks = _blocks[lastChapter];
    if (blocks == null || blocks.blocks.isEmpty) return false;
    return _documentIndex.metricsFor(blocks.blocks.last.key) != null;
  }

  double? _offsetForAnchor(HybridAnchor anchor, ChapterBlocks blocks) {
    final resolved = _visualPositionForChar(blocks, anchor.charOffsetInChapter);
    final key = resolved?.key ?? anchor.blockKey;
    final top = _documentIndex.topOf(key);
    if (top == null) return null;
    final lineTop = resolved?.localTop ?? 0.0;
    final anchorLine = AnchorManager.anchorOffsetInViewport(
      _viewportSize.height,
    );
    return top + lineTop - anchorLine + anchor.visualOffsetPx;
  }

  /// 把「章節絕對 charOffset」換算成視覺上真正落點的
  /// `(BlockKey, 這個 block 自己 Y 窗內的 local top)`。
  ///
  /// 純文字模型的 `blockForCharOffset` 只看 charRange；當人工效能切點落
  /// 在一行中間時，那一整行仍完整畫在前一個切塊的 Y 窗裡（見
  /// [LayoutPump._groupSplitYs]），此時字元的視覺歸屬與 charRange 歸屬
  /// 不同。DocumentIndex 的座標以視覺歸屬為準，兩者不一致時必須以此為準
  /// 才能讓 restore／TTS／ensureCharRangeVisible 卷到正確的世界座標。
  ({BlockKey key, double localTop})? _visualPositionForChar(
    ChapterBlocks blocks,
    int charOffsetInChapter,
  ) {
    final rawBlock = blocks.blockForCharOffset(charOffsetInChapter);
    final group = blocks.groupContaining(rawBlock.key);
    if (group.isEmpty) return null;
    final head = group.first;
    final rawEntry = _paragraphCache.acquireEntry(rawBlock.key, _epoch);
    if (rawEntry == null) return null;
    final indent = _indentCharsFor(head);
    final groupTextLength = indent + _groupTextLength(group);
    final groupLocalOffset =
        indent +
        (charOffsetInChapter - head.charRange.start)
            .clamp(0, groupTextLength - indent)
            .toInt();
    final paragraphY =
        _textBoxTopForOffset(
          rawEntry.paragraph,
          groupLocalOffset,
          groupTextLength,
        ) ??
        0.0;
    var owningKey = rawBlock.key;
    var owningLocalTop = rawEntry.localTop;
    for (final member in group) {
      final memberEntry = _paragraphCache.acquireEntry(member.key, _epoch);
      if (memberEntry == null) continue;
      if (memberEntry.localTop <= paragraphY + 0.001) {
        owningKey = member.key;
        owningLocalTop = memberEntry.localTop;
      } else {
        break;
      }
    }
    return (key: owningKey, localTop: paragraphY - owningLocalTop);
  }

  int _groupTextLength(List<ChapterBlock> group) {
    var total = 0;
    for (final block in group) {
      total += block.text.length;
    }
    return total;
  }

  void _applyScrollOffset(double target) {
    final controller = _scrollController;
    if (controller != null && controller.hasClients) {
      controller.position.jumpTo(target);
    } else {
      _pendingScrollOffset = target;
    }
  }

  double? _effectiveScrollOffset() {
    final controller = _scrollController;
    if (controller != null && controller.hasClients) {
      return controller.position.pixels;
    }
    return _pendingScrollOffset;
  }

  // ---- 章節文字 → block 管線 ----

  Future<ChapterBlocks?> _ensureChapterBlocks(int chapterIndex) {
    final cached = _blocks[chapterIndex];
    if (cached != null) return Future<ChapterBlocks?>.value(cached);
    final inFlight = _blocksInFlight[chapterIndex];
    if (inFlight != null) return inFlight;
    final generation = _lastLayoutGeneration;
    late final Future<ChapterBlocks?> task;
    task = () async {
      try {
        final text = await _chapterRepo.load(chapterIndex);
        final blocks = await widget.preprocessor.process(
          text,
          maxBlockChars: _pump.maxCharsForBudget(
            _governor.ballisticSliceBudget,
          ),
        );
        if (!mounted || _lastLayoutGeneration != generation) return null;
        await _warmDiskMetricsForChapter(blocks);
        if (!mounted || _lastLayoutGeneration != generation) return null;
        _blocks[chapterIndex] = blocks;
        _admission.registerChapter(blocks);
        return blocks;
      } catch (_) {
        return null;
      }
    }();
    _blocksInFlight[chapterIndex] = task;
    task.whenComplete(() {
      if (identical(_blocksInFlight[chapterIndex], task)) {
        _blocksInFlight.remove(chapterIndex);
      }
    });
    return task;
  }

  void _onChapterEvent(ChapterEvent event) {
    if (!mounted) return;
    switch (event.kind) {
      case ChapterEventKind.loaded:
        if (_restorePinning) return;
        if ((event.chapterId - _windowCenter).abs() <=
            _chapterRepo.windowRadius) {
          final restoreOnly = _restorePrefetchBarrierActive;
          final prefetchGeneration = _prefetchGeneration;
          final restoreTicket = _restoreTicket;
          final requestCenter = _windowCenter;
          unawaited(
            _ensureChapterBlocks(event.chapterId).then((blocks) {
              if (blocks == null ||
                  !_canApplyPrefetchResult(
                    chapterIndex: event.chapterId,
                    requestCenter: requestCenter,
                    prefetchGeneration: prefetchGeneration,
                    restoreTicket: restoreTicket,
                    restoreOnly: restoreOnly,
                  )) {
                return;
              }
              _enqueueChapterTasks(blocks, restoreOnly: restoreOnly);
              _schedulePump();
            }),
          );
        }
      case ChapterEventKind.evicted:
      case ChapterEventKind.invalidated:
        // maxBlockChars 由 LayoutCostModel 即時校準推導，同一章重新載入時
        // 可能切出不同的 block 邊界；evicted 與 invalidated 因此都必須清掉
        // 舊 metrics／Paragraph，否則同一個 BlockKey 換到新切法後可能重用
        // 舊切法量到的高度／文字（見任務規劃文件 Background）。DocumentIndex
        // 與 AdmissionController 也要同步清該章已放行的座標與記住的舊章節
        // 形狀，否則新 segmentation 缺席的舊高 blockIndex 會永遠殘留，錯誤
        // 貢獻文檔幾何。
        _blocks.remove(event.chapterId);
        _measurementStore.invalidateChapter(event.chapterId);
        _paragraphCache.invalidateChapter(event.chapterId);
        _admission.invalidateChapter(event.chapterId);
        if (_documentIndex.invalidateChapter(event.chapterId)) {
          _indexBindingResetGeneration = _documentIndex.resetGeneration;
          _scheduleRebuild();
        }
        _enqueued.removeWhere((key) => key.chapterIndex == event.chapterId);
    }
  }

  void _shiftWindow(int chapterIndex) {
    if (chapterIndex == _windowCenter) return;
    _windowCenter = chapterIndex;
    _prefetchGeneration += 1;
    _chapterRepo.setPrefetchCenter(chapterIndex);
    _ensureWindowTasks();
    _schedulePump();
  }

  // ---- 排版任務投放（admit 保持每側自 center 起連續，I2/I3 前提） ----

  void _ensureWindowTasks({BlockKey? anchorKey, bool restoreOnly = false}) {
    if (restoreOnly) {
      if (!mounted || !_restorePrefetchBarrierActive) return;
    } else if (!_canStartOrdinaryPrefetch()) {
      return;
    }
    final prefetchGeneration = _prefetchGeneration;
    final restoreTicket = _restoreTicket;
    final requestCenter = _windowCenter;
    // Restore still needs the nearest chapters when the current chapter is
    // shorter than the guaranteed window. They use the same bounded group
    // batches below; only the old unbounded whole-chapter submission is
    // excluded.
    final deltas = const <int>[0, 1, -1, 2, -2];
    for (final delta in deltas) {
      final chapter = _windowCenter + delta;
      if (chapter < 0 || chapter >= widget.runtime.chapterCount) continue;
      final blocks = _blocks[chapter];
      if (blocks == null) {
        unawaited(
          _ensureChapterBlocks(chapter).then((loaded) {
            if (loaded == null ||
                !_canApplyPrefetchResult(
                  chapterIndex: loaded.chapterIndex,
                  requestCenter: requestCenter,
                  prefetchGeneration: prefetchGeneration,
                  restoreTicket: restoreTicket,
                  restoreOnly: restoreOnly,
                )) {
              return;
            }
            _enqueueChapterTasks(loaded, restoreOnly: restoreOnly);
            _schedulePump();
          }),
        );
        continue;
      }
      _enqueueChapterTasks(
        blocks,
        anchorKey: delta == 0 ? anchorKey : null,
        restoreOnly: restoreOnly,
      );
    }
  }

  bool _canStartOrdinaryPrefetch() {
    return mounted &&
        _initialRestoreCompleted &&
        !_dragging &&
        !_anchorManager.restoreLocked &&
        !_restorePrefetchBarrierActive;
  }

  bool _canApplyPrefetchResult({
    required int chapterIndex,
    required int requestCenter,
    required int prefetchGeneration,
    required int restoreTicket,
    required bool restoreOnly,
  }) {
    if (!mounted ||
        _dragging ||
        prefetchGeneration != _prefetchGeneration ||
        restoreTicket != _restoreTicket ||
        requestCenter != _windowCenter ||
        (chapterIndex - _windowCenter).abs() > _chapterRepo.windowRadius) {
      return false;
    }
    if (restoreOnly) return _restorePrefetchBarrierActive;
    return _canStartOrdinaryPrefetch();
  }

  void _enqueueChapterTasks(
    ChapterBlocks blocks, {
    BlockKey? anchorKey,
    bool restoreOnly = false,
  }) {
    final groups = blocks.paragraphGroups();
    if (groups.isEmpty) return;
    final centerKey = _documentIndex.centerKey;
    List<List<ChapterBlock>> forward;
    List<List<ChapterBlock>> backward;
    if (blocks.chapterIndex == centerKey.chapterIndex) {
      // center 可能落在某個 group 中間；該 group 不可切半送 forward/
      // backward 兩側（會破壞「group 只用一個 ui.Paragraph 連續排版」的
      // 前提），因此整個含 center 的 group 一律算進 forward。
      var centerGroupIndex = groups.indexWhere(
        (group) => group.first.key <= centerKey && centerKey <= group.last.key,
      );
      if (centerGroupIndex < 0) centerGroupIndex = 0;
      forward = groups.sublist(centerGroupIndex);
      backward = groups
          .sublist(0, centerGroupIndex)
          .reversed
          .toList(growable: false);
    } else if (blocks.chapterIndex > centerKey.chapterIndex) {
      forward = groups;
      backward = const <List<ChapterBlock>>[];
    } else {
      forward = const <List<ChapterBlock>>[];
      backward = groups.reversed.toList(growable: false);
    }
    final batchSize = restoreOnly
        ? _restoreGroupsPerSide
        : _progressiveGroupsPerSide;
    forward = _boundedTaskBatch(forward, batchSize);
    backward = _boundedTaskBatch(backward, batchSize);
    var forwardBlocked = false;
    var backwardBlocked = false;
    final rounds = math.max(forward.length, backward.length);
    for (var i = 0; i < rounds; i += 1) {
      if (i < forward.length) {
        forwardBlocked = _admitOrSubmitGroup(
          blocks,
          forward[i],
          blocked: forwardBlocked,
          anchorKey: anchorKey,
        );
      }
      if (i < backward.length) {
        backwardBlocked = _admitOrSubmitGroup(
          blocks,
          backward[i],
          blocked: backwardBlocked,
          anchorKey: anchorKey,
        );
      }
    }
  }

  List<List<ChapterBlock>> _boundedTaskBatch(
    List<List<ChapterBlock>> groups,
    int limit,
  ) {
    // Skip groups that are already both admitted and fresh.  This makes a
    // subsequent bounded pass advance its frontier instead of repeatedly
    // looking at the first batch when metrics came from disk/cache.  The same
    // frontier rule is used for restore and ordinary progressive prefetch so a
    // queue drain can safely request the next batch without duplicating work.
    final firstPending = groups.indexWhere(
      (group) => group.any(
        (block) =>
            _documentIndex.metricsFor(block.key) == null ||
            !_paragraphCache.containsFresh(block.key, _epoch, widget.textColor),
      ),
    );
    if (firstPending < 0) return const <List<ChapterBlock>>[];
    return groups.skip(firstPending).take(limit).toList(growable: false);
  }

  /// group 內每個 block 就緒（有 metrics + paragraph）且同側尚未斷檔 →
  /// 整組直接 admit；否則整組送 pump（連續排版必須整組一起重建，不能
  /// 只補其中一塊，否則會在切點退回獨立 Paragraph 的硬換行）。回傳
  /// 「此側是否已斷檔」（斷檔後不得再 direct-admit，否則 DocumentIndex
  /// 會出現中間洞，補齊時可見內容會位移，違反 I3）。
  bool _admitOrSubmitGroup(
    ChapterBlocks blocks,
    List<ChapterBlock> group, {
    required bool blocked,
    BlockKey? anchorKey,
  }) {
    // pin 必須發生在建置之前：pumpPending 單一批次就可能建掉整個初始
    // 視窗，put 之後才 pin 救不回批次途中已被 LRU 逐出的條目。
    if (_restorePinning) {
      _paragraphCache.pinKeys(<BlockKey>[for (final b in group) b.key], _epoch);
    }
    final anchor = anchorKey != null && group.any((b) => b.key == anchorKey);
    final notYetAdmitted = group
        .where((b) => _documentIndex.metricsFor(b.key) == null)
        .toList(growable: false);
    if (notYetAdmitted.isEmpty) {
      // 整組已 admit，只可能缺 paragraph（被 LRU 逐出）；缺就整組重建，
      // 不影響既有座標與斷檔狀態。
      final missingParagraph = group.any(
        (b) => !_paragraphCache.containsFresh(b.key, _epoch, widget.textColor),
      );
      if (missingParagraph) _submitGroupTask(blocks, group, anchor: anchor);
      return blocked;
    }
    final allReady = notYetAdmitted.every(
      (b) =>
          _measurementStore.get(_namespace, b.key) != null &&
          _paragraphCache.containsFresh(b.key, _epoch, widget.textColor),
    );
    if (allReady && !blocked) {
      for (final b in notYetAdmitted) {
        final metrics = _measurementStore.get(_namespace, b.key)!;
        _admission.offer(
          BlockReady(key: b.key, epoch: _epoch, metrics: metrics),
        );
      }
      return blocked;
    }
    _submitGroupTask(blocks, group, anchor: anchor);
    return true;
  }

  /// 排版需求的唯一判準：`(epoch, fingerprint, windowCenter)`。
  ///
  /// 投放端（[_ensureWindowTasks]／[_onChapterEvent]）已經用同一組條件決定
  /// 「要不要送」；這裡是它的對偶——送出去之後中心移動了，同一組條件回答
  /// 「還要不要做」。兩邊用同一個半徑，才不會出現投放端願意送、drain 端
  /// 立刻丟的來回震盪。
  ///
  /// epoch／fingerprint 改變時 [_handleEpochRebuild] 會整個換掉 pump，理論上
  /// 走不到這裡；仍然檢查，讓失效鍵在單一處完整表達。
  bool _isLayoutTaskStillDesired(LayoutTask task) {
    if (task.epoch != _epoch || task.fingerprint != _fingerprint) return false;
    final chapter = task.block.key.chapterIndex;
    return (chapter - _windowCenter).abs() <= _chapterRepo.windowRadius;
  }

  /// 丟棄的 task 必須同時撤銷 [_enqueued] 記錄，否則 [_submitGroupTask] 的
  /// 去重會讓這個 group 在重新進入視窗後永遠無法再投放。
  void _handleLayoutTaskDiscarded(LayoutTask task) {
    _discardedLayoutTaskCount += 1;
    for (final block in task.groupBlocks) {
      _enqueued.remove(block.key);
    }
  }

  void _submitGroupTask(
    ChapterBlocks blocks,
    List<ChapterBlock> group, {
    bool anchor = false,
  }) {
    final head = group.first;
    final headKey = head.key;
    if (!_enqueued.add(headKey)) return;
    for (final b in group.skip(1)) {
      _enqueued.add(b.key);
    }
    final last = group.last;
    final spec = widget.runtime.state.layoutSpec;
    _pump.submit(
      LayoutTask(
        block: head,
        continuationBlocks: group.length > 1
            ? group.sublist(1)
            : const <ChapterBlock>[],
        epoch: _epoch,
        fingerprint: _fingerprint,
        textStyle: HybridBlockTextStyle.fromLayoutStyle(
          spec.style,
          isTitle: head.isTitle,
          // em-grid 鎖寬後滿列天生切齊右緣，justify 只剩把避頭尾列殘差
          // 攤進字距、破壞直行格線的副作用，內文預設 start 對齊；
          // AppConfig 開關僅供真機對照。
          justify: AppConfig.readerV2ContentJustify && !head.isTitle,
        ),
        contentWidth: spec.contentWidth,
        cellWidth: spec.cellWidth,
        textColor: widget.textColor,
        priority: _priorityFor(headKey, anchor: anchor),
        direction: headKey < _documentIndex.centerKey
            ? HybridScrollDirection.backward
            : HybridScrollDirection.forward,
        indentChars: _indentCharsFor(head),
        // 只有 group 真正的最後一塊（邏輯段落真正結尾）計入間距；
        // group 內部的效能切點恆為 0（見 _trailingSpacingFor）。
        trailingSpacing: _trailingSpacingFor(blocks, last),
      ),
    );
  }

  LayoutTaskPriority _priorityFor(BlockKey key, {required bool anchor}) {
    if (anchor) return LayoutTaskPriority.anchor;
    final center = _documentIndex.centerKey;
    if (key.chapterIndex == center.chapterIndex &&
        (key.blockIndex - center.blockIndex).abs() <= 40) {
      return LayoutTaskPriority.visible;
    }
    return LayoutTaskPriority.prefetch;
  }

  int _indentCharsFor(ChapterBlock block) {
    if (block.isTitle || block.isContinuation) return 0;
    return widget.runtime.state.layoutSpec.style.textIndent.clamp(0, 8).toInt();
  }

  /// 沿用舊引擎間距規則：標題後 = paragraphSpacing*8px（硬編碼特例）；
  /// 段落後 = fontSize×行高×paragraphSpacing；超長段切塊之間零間距（D2）。
  double _trailingSpacingFor(ChapterBlocks blocks, ChapterBlock block) {
    final style = widget.runtime.state.layoutSpec.style;
    if (block.isTitle) return style.paragraphSpacing * 8;
    final nextIndex = block.blockIndex + 1;
    if (nextIndex < blocks.blocks.length) {
      final next = blocks.blocks[nextIndex];
      if (next.isContinuation &&
          next.sourceParagraphIndex == block.sourceParagraphIndex) {
        return 0.0;
      }
    }
    return style.fontSize * style.effectiveLineHeight * style.paragraphSpacing;
  }

  // ---- pump 驅動 ----

  void _setPumpState(PumpState state) {
    _pump.onScrollStateChanged(state);
  }

  void _schedulePump() {
    if (_pumpFramePending || !mounted) return;
    _pumpFramePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pumpFramePending = false;
      if (!mounted) return;
      unawaited(_pumpOnce());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _pumpOnce() async {
    // 已排定的 post-frame pump 可能剛好撞上使用者開始拖曳；
    // I4 在這裡硬停，待 ScrollEnd 再恢復，不能讓 debug assert 擊穿手勢。
    if (_dragging) return;
    final prefetchGeneration = _prefetchGeneration;
    await _pump.pumpPending();
    if (!mounted || _dragging || prefetchGeneration != _prefetchGeneration) {
      // The pump may have yielded while a drag, restore, or epoch rebuild
      // changed ownership of the viewport. Do not clear the new generation's
      // admission set or refill it from the stale completion.
      return;
    }
    if (_pump.queueDepth > 0) {
      _schedulePump();
    } else {
      // 佇列見底 → 允許之後的視窗掃描重新投放（處理段落被 LRU 逐出的重排）。
      if (!_canStartOrdinaryPrefetch()) return;
      _enqueued.clear();
      _updateLeadTelemetry();
      // A normal settled prefetch is progressive, but its next batch belongs
      // to the next user-owned settle.  Do not recursively refill here just
      // because the lead is still below its target: doing so makes a long
      // chapter's bounded batches behave like one unbounded settle backlog.
      // The next settle will call [_ensureWindowTasks] again, and the existing
      // generation/ticket checks still reject callbacks from the old frontier.
    }
    // 完成的排版經 admission 放行時由 DocumentIndex.revision 直驅 sliver
    // relayout，這裡不再 setState 世界重建。
  }

  void _updateLeadTelemetry() {
    // A pump that started before a chapter restore may resume after
    // DocumentIndex.reset() but before the new viewport offset is installed.
    // Its old scroll position is not meaningful in the new centered world;
    // reading it here can trip AdmissionController I5 during a large jump.
    if (!_initialRestoreCompleted || _anchorManager.restoreLocked) return;
    final offset = _effectiveScrollOffset();
    if (offset == null || _viewportSize.height <= 0) return;
    _admission.updateLead(
      viewportTop: offset,
      viewportBottom: offset + _viewportSize.height,
    );
    _governor.updateLeadDeficit(_admission.hasLeadDeficit);
    _telemetry.updateRuntimeStats(
      pumpQueueDepth: _pump.queueDepth,
      forwardLeadPx: _admission.latestForwardLead,
      backwardLeadPx: _admission.latestBackwardLead,
    );
  }

  // ---- 滾動事件 / settle（D5 條款 3） ----

  bool _handleScrollNotification(ScrollNotification notification) {
    // The reader's overlay can add a notification depth on some host layouts.
    // Keep the debug-only activity hint independent of that routing detail so
    // the frame oracle still records the real drag hand-off.
    if (kDebugMode &&
        HybridReaderScreen.debugFrameInvariantsEnabled &&
        notification.depth != 0) {
      if (notification is ScrollStartNotification) {
        _invariantScrollActivityHint = 'drag';
      } else if (notification is ScrollUpdateNotification) {
        if (_invariantScrollActivityHint != 'drag') {
          _invariantScrollActivityHint = notification.dragDetails == null
              ? 'ballistic'
              : 'drag';
        }
      } else if (notification is ScrollEndNotification) {
        _invariantScrollActivityHint = 'idle';
      }
    }
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      if (notification.dragDetails != null) {
        if (_initialRestoreCompleted && !_anchorManager.restoreLocked) {
          // Invalidate ordinary async admissions that were started before the
          // pointer went down.  The state check in the continuation protects
          // the active drag; this generation bump also protects the case in
          // which that continuation resumes after the drag has already been
          // released.
          _prefetchGeneration += 1;
        }
        _dragging = true;
        _sawUserScroll = true;
        if (_restorePrefetchBarrierActive) {
          // This drag began after the restore transaction. Its later
          // ScrollEnd is the first ordinary user-owned settle allowed to
          // request the full lead window.
          _restoreUserScrollObserved = true;
        }
        _ensureGate.beginUserScroll();
        _setPumpState(PumpState.dragging);
      }
      if (kDebugMode && HybridReaderScreen.debugFrameInvariantsEnabled) {
        _invariantScrollActivityHint = 'drag';
      }
    } else if (notification is ScrollUpdateNotification) {
      if (_dragging && notification.dragDetails == null) {
        _dragging = false;
        if (kDebugMode && HybridReaderScreen.debugFrameInvariantsEnabled) {
          if (_invariantScrollActivityHint != 'drag') {
            _invariantScrollActivityHint = 'ballistic';
          }
        }
        _setPumpState(PumpState.ballistic);
        _schedulePump();
      }
      _scheduleMotionCapture();
    } else if (notification is ScrollEndNotification) {
      final wasUser = _sawUserScroll;
      _dragging = false;
      if (kDebugMode && HybridReaderScreen.debugFrameInvariantsEnabled) {
        _invariantScrollActivityHint = 'idle';
      }
      _sawUserScroll = false;
      _setPumpState(PumpState.idle);
      _schedulePump();
      if (wasUser) {
        unawaited(_settleUserScrollAndFlushEnsures());
      } else {
        unawaited(_ensureGate.releaseAndFlush());
      }
    }
    return false;
  }

  void _scheduleMotionCapture() {
    if (_captureFramePending || !mounted) return;
    _captureFramePending = true;
    final scheduledRevision = _runtimeLocationRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _captureFramePending = false;
      if (!mounted) return;
      if (!_initialRestoreCompleted || _anchorManager.restoreLocked) return;
      // Programmatic restore/jump can emit a scroll notification before the
      // runtime publishes its target location.  That callback belongs to the
      // old viewport address; letting it capture after completeReady would
      // replace a short target chapter with the next chapter at the anchor
      // line (for example the 34-byte preface followed by chapter 1).
      if (scheduledRevision != _runtimeLocationRevision) return;
      if (widget.runtime.pendingChapterJumpTarget != null) return;
      // 動作中一律靜默 capture：runtime notify 會連鎖 ReaderV2Page 與本
      // screen 的整面 setState（fling 中的節奏性重活）。頁面層滾動中需要
      // 跟動的顯示走 progressListenable 窄通道；完整 notify 留給 settle。
      final location = _captureAndReport(notify: false);
      final offset = _effectiveScrollOffset();
      if (offset != null) {
        _admission.updateViewport(
          visibleTop: offset,
          visibleBottom: offset + _viewportSize.height,
          cacheExtent: _viewportSize.height,
        );
      }
      _updateParagraphPins();
      _publishProgress();
      _updateLeadTelemetry();
      if (location != null && location.chapterIndex != _windowCenter) {
        _shiftWindow(location.chapterIndex);
      }
    });
  }

  ReaderV2Location? _captureAndReport({required bool notify}) {
    _capturing = true;
    try {
      final location = widget.runtime.captureVisibleLocation(
        notifyIfChanged: notify,
      );
      if (location != null) _lastReportedLocation = location;
      return location;
    } finally {
      _capturing = false;
    }
  }

  Future<void> _handleScrollSettled({bool allowFullPrefetch = false}) async {
    if (!mounted ||
        _dragging ||
        !_initialRestoreCompleted ||
        _anchorManager.restoreLocked) {
      return;
    }
    // A programmatic restore can emit ScrollEnd from _applyScrollOffset. The
    // notification may be delivered after restoreLocked is released while
    // the runtime still owns the viewport through pendingChapterJumpTarget.
    // Treat that callback, and any inherited callback while the barrier is
    // active, as restore-owned. The bounded restore pump has already drained
    // the anchor/guaranteed viewport work; reopening the full lead here would
    // recreate the long-chapter queue that C6 caught. A new post-restore drag
    // (or an explicit ordinary movement) is the only release path.
    final restoreOwnedSettle =
        widget.runtime.pendingChapterJumpTarget != null ||
        (_restorePrefetchBarrierActive &&
            !allowFullPrefetch &&
            !_restoreUserScrollObserved);
    final settlePrefetchGeneration = _prefetchGeneration;
    final settleRestoreTicket = _restoreTicket;
    final settleWindowCenter = _windowCenter;
    final settleBarrier = _restorePrefetchBarrierActive;
    final location = _captureAndReport(notify: true);
    if (location != null) {
      // settle 即刻落盤：背景 flush 靠不住（app 可能被系統回收）。
      final saved = await widget.runtime.saveProgress(
        location: location,
        immediate: true,
      );
      if (saved != null) _lastReportedLocation = saved;
      // saveProgress yields.  A restore, a new drag, or a window shift can
      // take ownership of the viewport while it is suspended; in that case
      // this settle must not reopen ordinary prefetch from its old state.
      if (!mounted ||
          _dragging ||
          _anchorManager.restoreLocked ||
          settlePrefetchGeneration != _prefetchGeneration ||
          settleRestoreTicket != _restoreTicket ||
          settleWindowCenter != _windowCenter ||
          settleBarrier != _restorePrefetchBarrierActive) {
        return;
      }
      if (location.chapterIndex != _windowCenter) {
        _shiftWindow(location.chapterIndex);
      }
    }
    if (!mounted) return;
    _publishProgress();
    _updateLeadTelemetry();
    if (restoreOwnedSettle) {
      _ensureWindowTasks(
        anchorKey: _documentIndex.centerKey,
        restoreOnly: true,
      );
      _schedulePump();
      return;
    }
    _restorePrefetchBarrierActive = false;
    _restoreUserScrollObserved = false;
    _ensureWindowTasks();
    _schedulePump();
  }

  Future<void> _settleUserScrollAndFlushEnsures() async {
    try {
      await _handleScrollSettled();
    } finally {
      if (mounted) await _ensureGate.releaseAndFlush();
    }
  }

  void _publishProgress() {
    final notifier = widget.progressListenable;
    if (notifier == null) return;
    final offset = _effectiveScrollOffset();
    if (offset == null || _viewportSize.height <= 0) return;
    final worldY =
        offset + AnchorManager.anchorOffsetInViewport(_viewportSize.height);
    final progress = HybridProgress(
      documentIndex: _documentIndex,
      chapterCount: widget.runtime.chapterCount,
    ).progressForOffset(worldY);
    final runtimeLocation = widget.runtime.state.visibleLocation;
    final runtimeLocationIsPublished =
        _initialRestoreCompleted &&
        widget.runtime.state.phase == ReaderV2Phase.ready &&
        !_anchorManager.restoreLocked;
    if (runtimeLocationIsPublished &&
        runtimeLocation.chapterIndex != progress.chapterIndex) {
      final blocks = _blocks[runtimeLocation.chapterIndex];
      if (blocks != null) {
        final length = math.max(1, blocks.displayText.length);
        notifier.value = HybridProgressSnapshot(
          chapterIndex: runtimeLocation.chapterIndex,
          chapterCount: widget.runtime.chapterCount,
          chapterPercent: (runtimeLocation.charOffset / length * 100)
              .clamp(0.0, 100.0)
              .toDouble(),
        );
        return;
      }
    }
    final captured = _captureVisibleLocation();
    if (captured != null && captured.chapterIndex != progress.chapterIndex) {
      final blocks = _blocks[captured.chapterIndex];
      if (blocks != null) {
        final length = math.max(1, blocks.displayText.length);
        notifier.value = HybridProgressSnapshot(
          chapterIndex: captured.chapterIndex,
          chapterCount: widget.runtime.chapterCount,
          chapterPercent: (captured.charOffset / length * 100)
              .clamp(0.0, 100.0)
              .toDouble(),
        );
        return;
      }
    }
    notifier.value = progress;
  }

  // ---- D5 條款 1：七閉包 attach/detach（前六個經 FIFO 佇列） ----

  void _attachController() {
    widget.viewportController
      ?..scrollBy = _scrollBy
      ..continuousScrollBy = _continuousScrollBy
      ..animateBy = _animateBy
      ..moveToNextPage = _moveToNextPage
      ..moveToPrevPage = _moveToPrevPage
      ..settleScroll = _settleScroll
      ..ensureCharRangeVisible = _ensureCharRangeVisible;
  }

  void _detachController(ReaderV2ViewportController? controller) {
    if (controller == null) return;
    if (controller.scrollBy == _scrollBy) controller.scrollBy = null;
    if (controller.continuousScrollBy == _continuousScrollBy) {
      controller.continuousScrollBy = null;
    }
    if (controller.animateBy == _animateBy) controller.animateBy = null;
    if (controller.moveToNextPage == _moveToNextPage) {
      controller.moveToNextPage = null;
    }
    if (controller.moveToPrevPage == _moveToPrevPage) {
      controller.moveToPrevPage = null;
    }
    if (controller.settleScroll == _settleScroll) {
      controller.settleScroll = null;
    }
    if (controller.ensureCharRangeVisible == _ensureCharRangeVisible) {
      controller.ensureCharRangeVisible = null;
    }
  }

  Future<bool> _enqueueCommand(Future<bool> Function() command) {
    return _commands.enqueue(isMounted: () => mounted, command: command);
  }

  Future<bool> _scrollBy(double delta) =>
      _enqueueCommand(() => _scrollByNow(delta));

  Future<bool> _continuousScrollBy(double delta) =>
      _enqueueCommand(() => _continuousScrollByNow(delta));

  Future<bool> _animateBy(double delta) =>
      _enqueueCommand(() => _animateByNow(delta));

  Future<bool> _moveToNextPage() =>
      _enqueueCommand(() => _movePageNow(forward: true));

  Future<bool> _moveToPrevPage() =>
      _enqueueCommand(() => _movePageNow(forward: false));

  Future<bool> _ensureCharRangeVisible({
    required int chapterIndex,
    required int startCharOffset,
    required int endCharOffset,
  }) {
    return _enqueueCommand(
      () => _ensureGate.submit(
        () => _ensureCharRangeVisibleNow(
          chapterIndex: chapterIndex,
          startCharOffset: startCharOffset,
          endCharOffset: endCharOffset,
        ),
      ),
    );
  }

  /// settleScroll 不經佇列（D5）：先停住殘餘慣性再走 settle。
  Future<void> _settleScroll() async {
    final controller = _scrollController;
    if (controller != null && controller.hasClients) {
      final pixels = controller.position.pixels;
      controller.position.jumpTo(pixels);
    }
    await _handleScrollSettled();
  }

  bool _jumpBy(double delta) {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients || delta == 0) {
      return false;
    }
    final position = controller.position;
    final before = position.pixels;
    final max = math.max(position.minScrollExtent, position.maxScrollExtent);
    final target = (before + delta)
        .clamp(position.minScrollExtent, max)
        .toDouble();
    if ((target - before).abs() < _minimumViewportMovement) return false;
    position.jumpTo(target);
    return true;
  }

  Future<bool> _scrollByNow(double delta) async {
    if (!mounted || !_jumpBy(delta)) return false;
    await _handleScrollSettled(allowFullPrefetch: true);
    return mounted;
  }

  Future<bool> _continuousScrollByNow(double delta) async {
    if (!mounted || !_jumpBy(delta)) return false;
    _scheduleMotionCapture();
    _schedulePump();
    return mounted;
  }

  Future<bool> _animateByNow(double delta) async {
    final controller = _scrollController;
    if (!mounted ||
        controller == null ||
        !controller.hasClients ||
        delta == 0) {
      return false;
    }
    final position = controller.position;
    final before = position.pixels;
    final max = math.max(position.minScrollExtent, position.maxScrollExtent);
    final target = (before + delta)
        .clamp(position.minScrollExtent, max)
        .toDouble();
    if ((target - before).abs() < _minimumViewportMovement) return false;
    await position.animateTo(
      target,
      duration: _ensureAnimateDuration,
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return false;
    await _handleScrollSettled(allowFullPrefetch: true);
    return mounted;
  }

  Future<bool> _movePageNow({required bool forward}) async {
    final height = _viewportSize.height;
    if (height <= 0) return false;
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return false;
    final before = controller.position.pixels;
    final style = widget.runtime.state.layoutSpec.style;
    final overlap = math.max(24.0, style.fontSize * style.effectiveLineHeight);
    final magnitude = math.max(height * 0.5, height - overlap - 8.0);
    final moved = await _animateByNow(forward ? magnitude : -magnitude);
    if (!moved) _emitBookBoundaryNotice(forward: forward);
    if (!moved || !mounted || !controller.hasClients) return false;

    final after = controller.position.pixels;
    final atBookBoundary = forward
        ? _admission.atForwardBookBoundary
        : _admission.atBackwardBookBoundary;
    final complete = isHybridPageMoveComplete(
      requestedDistance: magnitude,
      actualDistance: (after - before).abs(),
      atBookBoundary: atBookBoundary,
    );
    if (!complete) {
      // 目前只到 lazy edge：不要讓 page coordinator／auto page 把短移動
      // 當成完整一頁。settle 已安排下一輪 window/pump，這裡再確保尚有
      // pending task 時會繼續供給；下一次翻頁命令即可重新嘗試。
      _schedulePump();
    }
    return complete;
  }

  void _emitBookBoundaryNotice({required bool forward}) {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return;
    final position = controller.position;
    final atExtent = forward
        ? position.pixels >= position.maxScrollExtent - _minimumViewportMovement
        : position.pixels <=
              position.minScrollExtent + _minimumViewportMovement;
    final atBookBoundary = forward
        ? _admission.atForwardBookBoundary
        : _admission.atBackwardBookBoundary;
    if (!atExtent || !atBookBoundary) return;
    widget.runtime.emitUserNotice(forward ? '已到書尾' : '已到書首');
  }

  // ---- D5 條款 6：ensureCharRangeVisible ----

  Future<bool> _ensureCharRangeVisibleNow({
    required int chapterIndex,
    required int startCharOffset,
    required int endCharOffset,
  }) async {
    final runtime = widget.runtime;
    if (!mounted || runtime.chapterCount <= 0) return false;
    final safeChapter = chapterIndex.clamp(0, runtime.chapterCount - 1).toInt();
    final blocks = await _ensureChapterBlocks(safeChapter);
    if (blocks == null || !mounted) return false;
    final start = math.min(startCharOffset, endCharOffset);
    final end = math.max(startCharOffset, endCharOffset);
    final anchorKey = blocks.blockForCharOffset(start).key;
    if (_documentIndex.topOf(anchorKey) == null) {
      // 目標不在目前 world（跨窗跳讀）：以 restore 流程重定中心過去。
      final ok = await _restoreCore(
        ReaderV2Location(chapterIndex: safeChapter, charOffset: start),
      );
      // This is still the restore-owned transaction. Its bounded pump has
      // already established the target; do not reopen the full lead window
      // before the caller gives the viewport back to ordinary scrolling.
      if (ok && mounted) await _handleScrollSettled();
      return ok && mounted;
    }
    await _ensureRangeLaidOut(blocks, start, end);
    if (!mounted) return false;
    final rect = _worldRectForRange(blocks, start, end);
    final offset = _effectiveScrollOffset();
    if (rect == null || offset == null) return false;
    final height = _viewportSize.height;
    final topPadding = math.min(80.0, height * 0.14);
    final bottomPadding = math.min(120.0, height * 0.20);
    final preferredTopInset = math.min(180.0, height * 0.32);
    final comfortBottom = offset + math.min(220.0, height * 0.46);
    final visibleTop = offset + topPadding;
    final visibleBottom = offset + height - bottomPadding;
    final safelyVisible =
        rect.top >= visibleTop && rect.bottom <= visibleBottom;
    if (safelyVisible && rect.top <= comfortBottom) return true;
    final preferredTarget = rect.top - preferredTopInset;
    final minTarget = rect.bottom - height + bottomPadding;
    final maxTarget = rect.top - topPadding;
    final target = minTarget <= maxTarget
        ? preferredTarget.clamp(minTarget, maxTarget).toDouble()
        : minTarget;
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return false;
    final position = controller.position;
    final bounded = target
        .clamp(
          math.min(position.minScrollExtent, position.pixels),
          math.max(position.maxScrollExtent, position.pixels),
        )
        .toDouble();
    await position.animateTo(
      bounded,
      duration: _ensureAnimateDuration,
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return false;
    await _handleScrollSettled(allowFullPrefetch: true);
    return mounted;
  }

  Future<void> _ensureRangeLaidOut(
    ChapterBlocks blocks,
    int start,
    int end,
  ) async {
    final range = HybridTextRange(math.max(0, start), math.max(0, end));
    final targets = blocks.blocks
        .where((block) {
          return block.charRange.intersects(range) ||
              (range.isEmpty && block.charRange.containsOffset(range.start));
        })
        .toList(growable: false);
    // 逐 block 讀 ready 狀態，但缺件時整個 group 一起送 pump——只補其中
    // 一塊會退回獨立 Paragraph，重新產生已修正的硬換行問題。
    final seenGroupHeads = <BlockKey>{};
    for (final block in targets) {
      if (_paragraphCache.contains(block.key, _epoch) &&
          _measurementStore.get(_namespace, block.key) != null) {
        continue;
      }
      final group = blocks.groupContaining(block.key);
      if (group.isEmpty || !seenGroupHeads.add(group.first.key)) continue;
      _submitGroupTask(blocks, group, anchor: true);
    }
    var guard = 0;
    bool allReady() => targets.every(
      (block) =>
          _paragraphCache.contains(block.key, _epoch) &&
          _measurementStore.get(_namespace, block.key) != null,
    );
    while (guard++ < 100 && !allReady()) {
      final completed = await _pump.pumpPending();
      if (completed == 0) break;
    }
  }

  /// [block] 內、與 [range] 相交的字元對應的 boxes；y 座標已從共用
  /// Paragraph 的座標系換算回「這個 block 自己 Y 窗」座標（減去
  /// entry.localTop），呼叫端不需要知道 block 是否與同 group 其他 block
  /// 共用 ui.Paragraph。回傳 null 表示 Paragraph 尚未就緒。
  List<ui.TextBox>? _blockLocalBoxesForRange(
    ChapterBlocks blocks,
    ChapterBlock block,
    HybridTextRange range,
  ) {
    final entry = _paragraphCache.acquireEntry(block.key, _epoch);
    if (entry == null) return null;
    final group = blocks.groupContaining(block.key);
    if (group.isEmpty) return null;
    final indent = _indentCharsFor(group.first);
    final groupStart = group.first.charRange.start;
    final localStart =
        math.max(range.start, block.charRange.start) - groupStart + indent;
    final localEnd =
        math.min(range.end, block.charRange.end) - groupStart + indent;
    if (localEnd <= localStart) return const <ui.TextBox>[];
    final boxes = entry.paragraph.getBoxesForRange(localStart, localEnd);
    if (boxes.isEmpty) return boxes;
    return <ui.TextBox>[
      for (final box in boxes)
        ui.TextBox.fromLTRBD(
          box.left,
          box.top - entry.localTop,
          box.right,
          box.bottom - entry.localTop,
          box.direction,
        ),
    ];
  }

  Rect? _worldRectForRange(ChapterBlocks blocks, int start, int end) {
    double? top;
    double? bottom;
    final range = HybridTextRange(math.max(0, start), math.max(0, end));
    for (final block in blocks.blocks) {
      if (!block.charRange.intersects(range) &&
          !(range.isEmpty && block.charRange.containsOffset(range.start))) {
        continue;
      }
      final blockTop = _documentIndex.topOf(block.key);
      if (blockTop == null) continue;
      double localTop = 0;
      double localBottom = _documentIndex.metricsFor(block.key)?.height ?? 0;
      final boxes = _blockLocalBoxesForRange(blocks, block, range);
      if (boxes != null && boxes.isNotEmpty) {
        localTop = boxes.first.top;
        localBottom = boxes
            .map((box) => box.bottom)
            .reduce(math.max)
            .toDouble();
      }
      final rangeTop = blockTop + localTop;
      final rangeBottom = blockTop + localBottom;
      top = top == null ? rangeTop : math.min(top, rangeTop);
      bottom = bottom == null ? rangeBottom : math.max(bottom, rangeBottom);
    }
    if (top == null || bottom == null) return null;
    return Rect.fromLTRB(0, top, 0, bottom);
  }

  // ---- D5 條款 5：TTS 高亮 ----

  List<HybridLineBox> _ttsLineBoxes(ReaderV2TtsHighlight highlight) {
    final offset = _effectiveScrollOffset();
    final blocks = _blocks[highlight.chapterIndex];
    if (offset == null || blocks == null) return const <HybridLineBox>[];
    final range = HybridTextRange(
      math.max(0, highlight.highlightStart),
      math.max(0, highlight.highlightEnd),
    );
    if (range.isEmpty) return const <HybridLineBox>[];
    final result = <HybridLineBox>[];
    final seenLines = <({BlockKey key, double top, double bottom})>{};
    // ChapterBlocks preserves display-text order. Find the first possible
    // overlap with binary search so a short TTS range does not rescan an
    // entire long chapter on every scroll frame.
    final blockList = blocks.blocks;
    var low = 0;
    var high = blockList.length;
    while (low < high) {
      final middle = low + (high - low) ~/ 2;
      if (blockList[middle].charRange.end <= range.start) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    for (var index = low; index < blockList.length; index += 1) {
      final block = blockList[index];
      if (block.charRange.start >= range.end) break;
      if (!block.charRange.intersects(range)) continue;
      final top = _documentIndex.topOf(block.key);
      if (top == null) continue;
      final boxes = _blockLocalBoxesForRange(blocks, block, range);
      if (boxes == null || boxes.isEmpty) continue;
      final clipped = HybridTextRange(
        math.max(range.start, block.charRange.start),
        math.min(range.end, block.charRange.end),
      );
      for (final box in boxes) {
        final screenTop = top + box.top - offset;
        final screenBottom = top + box.bottom - offset;
        if (!seenLines.add((
          key: block.key,
          top: screenTop,
          bottom: screenBottom,
        ))) {
          continue;
        }
        result.add(
          HybridLineBox(
            key: block.key,
            top: screenTop,
            bottom: screenBottom,
            charRange: clipped,
          ),
        );
      }
    }
    return result;
  }

  // ---- D10：磁碟 metrics ----

  Future<void> _warmDiskMetricsForChapter(ChapterBlocks blocks) async {
    if (!widget.enableDiskMetrics || widget.bookUrl == null) return;
    final warmKey = (
      namespace: _namespace,
      chapter: blocks.chapterIndex,
      contentHash: blocks.contentHash,
    );
    if (!_warmedChapters.add(warmKey)) return;
    try {
      final cache = await _obtainDiskCache();
      final namespace = _namespace;
      final count = await cache.warmIntoStore(
        bookUrl: widget.bookUrl!,
        namespace: namespace,
        chapterContentHashes: <int, String>{
          blocks.chapterIndex: blocks.contentHash,
        },
        put: (key, metrics) {
          if (namespace == _namespace) {
            _measurementStore.put(namespace, key, metrics);
          }
        },
      );
      _telemetry.recordDiskMetricsHit(count > 0);
    } catch (_) {
      // 測試環境無 path_provider、或 IO 失敗：磁碟快取屬最佳努力，靜默略過。
    }
  }

  Future<void> _writeDiskMetrics(
    Map<BlockKey, BlockMetrics> snapshot, {
    StyleFingerprint? fingerprint,
  }) async {
    if (!widget.enableDiskMetrics ||
        widget.bookUrl == null ||
        snapshot.isEmpty) {
      return;
    }
    // await 前同步快照：epoch 重建 / dispose 之後 _blocks 與 _fingerprint
    // 都可能已被換掉。
    final targetFingerprint = fingerprint ?? _fingerprint;
    final chapterContentHashes = <int, String>{
      for (final blocks in _blocks.values)
        blocks.chapterIndex: blocks.contentHash,
    };
    try {
      final cache = await _obtainDiskCache();
      await cache.write(
        bookUrl: widget.bookUrl!,
        fingerprint: targetFingerprint,
        metrics: snapshot,
        chapterContentHashes: chapterContentHashes,
      );
    } catch (_) {
      // 同上：最佳努力。
    }
  }

  Future<MetricsDiskCache> _obtainDiskCache() async {
    final existing = _metricsDiskCache;
    if (existing != null) return existing;
    final directory = await getApplicationSupportDirectory();
    return _metricsDiskCache = MetricsDiskCache(baseDirectory: directory);
  }

  // ---- 建構 ----

  void _scheduleRebuild() {
    if (!mounted || _rebuildQueued) return;
    _rebuildQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildQueued = false;
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _holdScrollOnPointerDown(PointerDownEvent event) {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return false;
    final scrolling = controller.position.isScrollingNotifier.value;
    if (scrolling && !_dragging) {
      final pixels = controller.position.pixels;
      controller.position.jumpTo(pixels);
      return true; // 動畫中的點擊只用來停住，不觸發分區動作。
    }
    return false;
  }

  /// 找 dy 所在行（超出末行時回末行）。每個滾動幀都會進來——用單行查詢
  /// API，不可用 computeLineMetrics（整串 LineMetrics 配置進熱路徑）。
  ({double top, double bottom})? _lineAt(ui.Paragraph paragraph, double dy) {
    final lineCount = paragraph.numberOfLines;
    if (lineCount <= 0) return null;
    // x=0 取該行行首字元；y 由引擎 clamp 到首/末行。
    final position = paragraph.getPositionForOffset(Offset(0, dy));
    final lineNumber =
        (paragraph.getLineNumberAt(math.max(0, position.offset)) ??
                lineCount - 1)
            .clamp(0, lineCount - 1)
            .toInt();
    final line = paragraph.getLineMetricsAt(lineNumber);
    if (line == null) return null;
    final lineTop = line.baseline - line.ascent;
    return (top: lineTop, bottom: lineTop + line.height);
  }

  /// capture 與 restore 必須共用同一種文字 box 幾何；混用 LineMetrics.top
  /// 與 TextBox.top 會把字型 leading 的差值寫進 visualOffsetPx。
  double? _textBoxTopForOffset(
    ui.Paragraph paragraph,
    int textOffset,
    int textLength,
  ) {
    if (textLength <= 0) return 0.0;
    final safeOffset = textOffset.clamp(0, textLength).toInt();
    final start = safeOffset >= textLength ? textLength - 1 : safeOffset;
    final boxes = paragraph.getBoxesForRange(start, start + 1);
    if (boxes.isEmpty) return null;
    return boxes.first.top;
  }

  /// 高亮 overlay 的水平 padding 必須用 spec 調整後的值：em-grid 鎖寬把
  /// 殘差平分回左右 padding，widget.style 仍是使用者原始設定。
  ReaderV2Style _overlayStyle() {
    final specStyle = widget.runtime.state.layoutSpec.style;
    return widget.style.copyWith(
      paddingTop: 0.0,
      paddingLeft: specStyle.paddingLeft,
      paddingRight: specStyle.paddingRight,
    );
  }

  void _updateParagraphPins() {
    final offset = _effectiveScrollOffset();
    if (offset == null || _viewportSize.height <= 0) return;
    final top = offset - _admission.backwardGuaranteedWindow;
    final bottom = offset + _viewportSize.height + _admission.guaranteedWindow;
    _paragraphCache
      ..unpinAll()
      ..pinKeys(_documentIndex.keysInRange(top, bottom), _epoch);
    _paragraphCache.trimToCapacity();
  }

  Widget _buildLoading(ReaderV2State state) {
    final Widget child;
    if (state.phase == ReaderV2Phase.error) {
      child = Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: widget.textColor.withValues(alpha: 0.72),
            ),
            const SizedBox(height: 10),
            Text(
              _friendlyErrorMessage,
              style: TextStyle(color: widget.textColor, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    } else {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: widget.textColor.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _phaseMessage(state.phase),
            style: TextStyle(
              color: widget.textColor.withValues(alpha: 0.72),
              fontSize: 13,
            ),
          ),
        ],
      );
    }
    return ColoredBox(
      color: widget.backgroundColor,
      child: ReaderV2PointerTapLayer(
        onTapUp: widget.onContentTapUp,
        child: Semantics(
          liveRegion: true,
          excludeSemantics: true,
          label: state.phase == ReaderV2Phase.error
              ? _friendlyErrorMessage
              : _phaseMessage(state.phase),
          child: Center(child: child),
        ),
      ),
    );
  }

  static const String _friendlyErrorMessage = '閱讀內容暫時無法顯示，請稍後再試';

  String _phaseMessage(ReaderV2Phase phase) {
    return switch (phase) {
      ReaderV2Phase.cold => '正在準備閱讀內容',
      ReaderV2Phase.loading => '正在載入章節',
      ReaderV2Phase.layingOut => '正在整理版面',
      ReaderV2Phase.restoring => '正在恢復閱讀位置',
      ReaderV2Phase.switchingMode => '正在套用閱讀設定',
      ReaderV2Phase.ready => '',
      ReaderV2Phase.error => _friendlyErrorMessage,
    };
  }

  Widget _buildOperationOverlay(ReaderV2State state) {
    if (state.phase == ReaderV2Phase.ready) return const SizedBox.shrink();
    final isError = state.phase == ReaderV2Phase.error;
    final message = isError
        ? _friendlyErrorMessage
        : _phaseMessage(state.phase);
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        excludeSemantics: true,
        label: message,
        child: Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            minimum: const EdgeInsets.only(top: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.backgroundColor.withValues(alpha: 0.92),
                border: Border.all(
                  color: widget.textColor.withValues(alpha: 0.16),
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isError)
                      Icon(
                        Icons.error_outline_rounded,
                        size: 16,
                        color: widget.textColor.withValues(alpha: 0.72),
                      )
                    else
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.textColor.withValues(alpha: 0.6),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.textColor.withValues(alpha: 0.78),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        final state = widget.runtime.state;
        if (!_initialRestoreCompleted) return _buildLoading(state);
        final controller = _scrollController ??= ScrollController(
          initialScrollOffset: _pendingScrollOffset ?? 0.0,
        );
        _updateParagraphPins();
        final highlight = widget.ttsHighlight;
        Widget visualContent = NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: HybridScrollView(
            centerKey: _centerKey,
            documentIndex: _documentIndex,
            namespace: _namespace,
            measurementStore: _measurementStore,
            paragraphCache: _paragraphCache,
            epoch: _epoch,
            controller: controller,
            cacheExtent: _viewportSize.height,
            textColor: widget.textColor,
            // 鎖寬後的置中殘差在 spec.style 的 padding 裡，
            // 不可用 widget.style（使用者原始 padding）。
            horizontalPadding: EdgeInsets.only(
              left: state.layoutSpec.style.paddingLeft,
              right: state.layoutSpec.style.paddingRight,
            ),
            physics: _physics,
          ),
        );
        if (kDebugMode &&
            _visualInjection == ReaderVisualInjection.blankNextFrame &&
            _visualInjectionStep == 0) {
          _visualInjectionStep = 1;
          _queueVisualInjectionAdvance();
          visualContent = Positioned.fill(
            child: ColoredBox(color: widget.backgroundColor),
          );
        } else if (kDebugMode &&
            _visualInjection == ReaderVisualInjection.visualScrollWhileIdle) {
          _queueVisualInjectionAdvance();
          visualContent = Transform.translate(
            offset: Offset(0, _visualInjectionStep * 12.0),
            child: visualContent,
          );
        } else if (kDebugMode &&
            _visualInjection == ReaderVisualInjection.crossOracleMismatch) {
          // Keep the endpoint deterministic even when the current viewport
          // does not contain a natural C1 profile band. The overlay is a
          // test-only pixel witness; the paired runtime record is separately
          // shifted below in _processVisualResult, so this remains a genuine
          // cross-source disagreement rather than a Reader-state shortcut.
          final profile = encodeReaderInkProfile(
            chapterIndex: (state.visibleLocation.chapterIndex + 1).clamp(
              0,
              127,
            ),
            paragraphIndex: 0,
          );
          visualContent = Stack(
            fit: StackFit.expand,
            children: <Widget>[
              visualContent,
              Positioned(
                left: 0,
                top: 16,
                width: 280,
                height: 16 + 19 * 28,
                child: IgnorePointer(
                  child: ColoredBox(
                    color: widget.backgroundColor,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final bit in profile.bits)
                          SizedBox(
                            width: 280,
                            height: 28,
                            child: Text(
                              bit ? '墨' : '\u2060',
                              style: TextStyle(
                                color: widget.textColor,
                                fontSize: 18,
                                height: 1.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        final readerStack = Stack(
          fit: StackFit.expand,
          children: <Widget>[
            visualContent,
            if (highlight != null && highlight.isValid)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) {
                    return HybridTtsHighlightOverlay(
                      lines: _ttsLineBoxes(highlight),
                      style: _overlayStyle(),
                      textColor: widget.textColor,
                      highlight: highlight,
                    );
                  },
                ),
              ),
            if (state.phase != ReaderV2Phase.ready)
              Positioned.fill(child: _buildOperationOverlay(state)),
          ],
        );
        final readerContent = _visualOracle == null
            ? readerStack
            : RepaintBoundary(key: _visualBoundaryKey, child: readerStack);
        return ColoredBox(
          color: widget.backgroundColor,
          child: ReaderV2PointerTapLayer(
            onTapUp: widget.onContentTapUp,
            onPointerDownTapPolicy: _holdScrollOnPointerDown,
            child: readerContent,
          ),
        );
      },
    );
  }
}

final class _VisualCaptureResult {
  const _VisualCaptureResult({
    required this.sequence,
    required this.timestampMicros,
    required this.raster,
    required this.raw,
    required this.runtime,
    required this.costMicros,
  });

  final int sequence;
  final int timestampMicros;
  final ReaderVisualRaster raster;
  final ReaderVisualRawFrame raw;
  final ReaderVisualRuntimeRecord runtime;
  final int costMicros;
}

/// D5 條款 1 的 FIFO 命令佇列——hybrid 自帶實作，不 import 舊 viewport 內部。
final class _HybridCommandQueue {
  Future<void> _tail = Future<void>.value();

  Future<bool> enqueue({
    required bool Function() isMounted,
    required Future<bool> Function() command,
  }) {
    if (!isMounted()) return Future<bool>.value(false);
    final completer = Completer<bool>();
    _tail = _tail
        .catchError((_) {})
        .then((_) async {
          if (!isMounted()) return false;
          return command();
        })
        .then(
          completer.complete,
          onError: (Object error, StackTrace stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          },
        );
    return completer.future;
  }
}
