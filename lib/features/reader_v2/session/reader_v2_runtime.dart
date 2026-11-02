import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/hybrid/progress/chapter_shares.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';

import 'reader_v2_location.dart';
import 'reader_v2_operation_token.dart';
import 'reader_v2_progress_controller.dart';
import 'reader_v2_state.dart';
import 'reader_v2_state_machine.dart';

import 'reader_v2_viewport_bridge.dart';

typedef ReaderV2VisibleLocationCapture = ReaderV2Location? Function();

/// 交給頁面顯示的提示；某一章取不到時 [chapterIndex] 是那一章。
typedef ReaderV2UserNotice = ({String message, int? chapterIndex});
typedef ReaderV2ViewportRestore = Future<bool> Function(
  ReaderV2Location location,
);

class ReaderV2Runtime extends ChangeNotifier {
  factory ReaderV2Runtime({
    required Book book,
    required ReaderV2ChapterRepository repository,
    required ReaderV2ProgressController progressController,
    required ReaderV2LayoutSpec initialLayoutSpec,
    ReaderV2Location? initialLocation,
  }) {
    final location =
        (initialLocation ??
                ReaderV2Location(
                  chapterIndex: book.chapterIndex,
                  charOffset: book.charOffset,
                  visualOffsetPx: book.visualOffsetPx,
                ))
            .normalized();
    return ReaderV2Runtime._(
      repository: repository,
      progressController: progressController,
      initialLayoutSpec: initialLayoutSpec,
      initialLocation: location,
    );
  }

  ReaderV2Runtime._({
    required this.repository,
    required this.progressController,
    required ReaderV2LayoutSpec initialLayoutSpec,
    required ReaderV2Location initialLocation,
  }) : _initialLocation = initialLocation,
       stateMachine = ReaderV2StateMachine(
         ReaderV2State(
           lifecycle: ReaderV2Lifecycle.cold,
           committedLocation: initialLocation,
           visibleLocation: initialLocation,
           layoutSpec: initialLayoutSpec,
           layoutGeneration: 0,
           contentGeneration: repository.contentGeneration,
         ),
       ) {
    viewportBridge = ReaderV2ViewportBridge(this);
  }

  final ReaderV2ChapterRepository repository;
  final ReaderV2ProgressController progressController;
  final ReaderV2Location _initialLocation;
  final ReaderV2StateMachine stateMachine;
  final ChangeNotifier _viewportGeometryNotifier = ChangeNotifier();

  late final ReaderV2ViewportBridge viewportBridge;

  bool disposed = false;
  ReaderV2UserNotice? _pendingUserNotice;
  ReaderV2Location? get pendingLocation => stateMachine.pendingLocation;

  /// 正在跳到別章、還沒排好。同一章內的跳轉（例如拖進度條預覽）不算。
  bool get isJumpingToAnotherChapter {
    final operation = stateMachine.currentOperation;
    final target = pendingLocation;
    return operation != null &&
        operation.kind == ReaderV2OperationKind.jump &&
        target != null &&
        target.chapterIndex != state.visibleLocation.chapterIndex;
  }

  /// 正文正在照新的排版設定重排，或照新的內容設定（繁簡轉換、替換規則等）
  /// 重新載入，還沒排好。
  bool get isRebuildingText {
    final kind = stateMachine.currentOperation?.kind;
    return kind == ReaderV2OperationKind.presentation ||
        kind == ReaderV2OperationKind.contentReload;
  }

  ReaderV2State get state => stateMachine.state;

  /// 畫面上這一章，見 [ReaderV2StateMachine.visibleChapterIndex]。
  ValueListenable<int> get visibleChapterIndex =>
      stateMachine.visibleChapterIndex;

  int get chapterCount => repository.chapterCount;
  List<BookChapter> get chapters => repository.chapters;

  void addViewportGeometryListener(VoidCallback listener) {
    _viewportGeometryNotifier.addListener(listener);
  }

  void removeViewportGeometryListener(VoidCallback listener) {
    _viewportGeometryNotifier.removeListener(listener);
  }

  BookChapter? chapterAt(int index) => repository.chapterAt(index);
  String titleFor(int index) => repository.titleFor(index);
  String chapterUrlAt(int index) => chapterAt(index)?.url ?? '';

  // -- Viewport bridge delegation --

  void registerVisibleLocationCapture(
    Object owner,
    ReaderV2VisibleLocationCapture capture,
  ) {
    viewportBridge.registerVisibleLocationCapture(owner, capture);
  }

  void unregisterVisibleLocationCapture(Object owner) {
    viewportBridge.unregisterVisibleLocationCapture(owner);
  }

  void registerViewportRestore(Object owner, ReaderV2ViewportRestore restore) {
    viewportBridge.registerViewportRestore(owner, restore);
  }

  void unregisterViewportRestore(Object owner) {
    final detachedActiveOwner = viewportBridge.unregisterViewportRestore(owner);
    if (!detachedActiveOwner || disposed) return;
    final operation = stateMachine.currentOperation;
    if (operation == null || !stateMachine.abandonOperation(operation)) return;
    notifyListeners();
  }

  ReaderV2Location? captureVisibleLocation() =>
      viewportBridge.captureVisibleLocation();

  Future<ReaderV2Location?> saveProgress({
    ReaderV2Location? location,
    bool immediate = true,
  }) async {
    return viewportBridge.saveProgress(
      location: location,
      immediate: immediate,
    );
  }

  Future<ReaderV2Location?> flushProgress() {
    return viewportBridge.flushProgress();
  }

  // -- Reader commands --

  /// 跳到 [chapterIndex] 章首。一開始就蓋紙；[settled] 給了的話，等它完成
  /// （例如收起目錄與紙蓋上的動畫播完）才開始載入（ADR 0018）。
  Future<void> jumpToChapter(int chapterIndex, {Future<void>? settled}) =>
      _jumpToChapter(chapterIndex, settled: settled);

  Future<void> jumpToLocation(
    ReaderV2Location location, {
    bool immediateSave = true,
  }) => _jumpToLocation(location, immediateSave: immediateSave);

  Future<bool> restoreFromLocation(ReaderV2Location location) async {
    final token = beginRestoreOperation(location: location);
    try {
      return await _positionViewport(location: location, token: token);
    } on ReaderV2ContentUnavailableException catch (error) {
      await _finishContentUnavailable(token, error);
      return false;
    } catch (error, stackTrace) {
      _rethrowOperationFailure(token, error, stackTrace);
    }
  }

  // -- Runtime-owned methods --

  ReaderV2UserNotice? takeUserNotice() {
    final notice = _pendingUserNotice;
    _pendingUserNotice = null;
    return notice;
  }

  /// 交給頁面顯示的提示；通知監聽者，頁面才會馬上取走並顯示。是某一章
  /// 取不到時帶著 [chapterIndex]。
  void emitUserNotice(String message, {int? chapterIndex}) {
    _pendingUserNotice = (message: message, chapterIndex: chapterIndex);
    notifyListeners();
  }

  /// 每章佔全書多少，全書進度照它算。開書時先讀好（[openBook]）再排正文：
  /// 頁尾第一次出現就是加權過的數字，之後不會在換場途中換數字。讀到之前
  /// 是 `even(0)`（章數對不上，照章數平均）。
  ValueListenable<ReaderV2ChapterShares> get chapterShares => _chapterShares;
  final ValueNotifier<ReaderV2ChapterShares> _chapterShares =
      ValueNotifier<ReaderV2ChapterShares>(const ReaderV2ChapterShares.even(0));

  /// 只讀資料庫（目錄已經載入）；讀不到就照章數平均，不擋開書。
  Future<void> _loadChapterShares() async {
    try {
      final shares = await repository.loadChapterShares();
      if (!disposed) _chapterShares.value = shares;
    } catch (error) {
      AppLog.w('讀每章長度失敗，全書進度照章數平均: $error');
    }
  }

  Future<void> openBook() async {
    final token = stateMachine.beginOpen(location: _initialLocation);
    notifyListeners();
    try {
      // 目錄取不到的失敗和排版時一樣交給下面處理；目錄有了才讀每章長度
      // （幾十毫秒，這時紙剛蓋上），讀好才排正文。
      await repository.ensureChapters();
      await _loadChapterShares();
      if (!isCurrentOperationToken(token)) return;
      await _positionViewport(location: _initialLocation, token: token);
    } on ReaderV2ContentUnavailableException catch (error) {
      await _finishContentUnavailable(token, error);
    } catch (error, stackTrace) {
      _rethrowOperationFailure(token, error, stackTrace);
    }
  }

  Future<void> applyPresentation({required ReaderV2LayoutSpec spec}) async {
    final stagedSpec = stateMachine.effectiveLayoutSpec;
    if (stagedSpec.presentationSignature == spec.presentationSignature) return;

    final sameTextLayout = stagedSpec.layoutSignature == spec.layoutSignature;
    if (sameTextLayout) {
      if (stateMachine.updateViewportSpec(spec)) {
        _viewportGeometryNotifier.notifyListeners();
      }
      return;
    }

    final location =
        pendingLocation ??
        viewportBridge.captureVisibleLocation() ??
        state.visibleLocation;
    final token = stateMachine.beginPresentation(
      spec: spec,
      location: location,
      layoutGeneration: state.layoutGeneration + 1,
    );
    notifyListeners();
    try {
      await _positionViewport(location: location, token: token);
    } on ReaderV2ContentUnavailableException catch (error) {
      await _finishContentUnavailable(token, error);
    } catch (error, stackTrace) {
      _rethrowOperationFailure(token, error, stackTrace);
    }
  }

  /// 重新整理目前這一章並停在原位。[refetch] 先向書源重抓（見
  /// [ReaderV2ChapterRepository.reloadContent]）；抓不到時保留原本的正文，
  /// 並把原因交給頁面顯示。
  Future<bool> reloadContentPreservingLocation({bool refetch = false}) async {
    final location =
        pendingLocation ??
        viewportBridge.captureVisibleLocation() ??
        state.visibleLocation;
    final previousContent = repository.cachedContent(location.chapterIndex);
    final token = stateMachine.beginContentReload(location: location);
    notifyListeners();
    try {
      final remappedLocation = await _remapReloadLocation(
        location: location,
        previousContent: previousContent,
        token: token,
        refetch: refetch,
      );
      if (!isCurrentOperationToken(token)) return true;
      await _positionViewport(location: remappedLocation, token: token);
      return true;
    } on ReaderV2ContentUnavailableException catch (error) {
      await _finishContentUnavailable(token, error);
      return false;
    } catch (error, stackTrace) {
      _rethrowOperationFailure(token, error, stackTrace);
    }
  }

  Future<ReaderV2Location> _remapReloadLocation({
    required ReaderV2Location location,
    required ReaderV2Content? previousContent,
    required ReaderV2OperationToken token,
    required bool refetch,
  }) async {
    late final ReaderV2Content after;
    try {
      after = await repository.reloadContent(
        location.chapterIndex,
        refetch: refetch,
      );
    } finally {
      _publishRepositoryContentGeneration();
    }
    if (!isCurrentOperationToken(token)) return location;
    final before = previousContent;
    if (before == null) return location;
    return ReaderV2ContentLocationMapper.remap(
      location: location,
      before: before,
      after: after,
    );
  }

  bool isCurrentOperationToken(ReaderV2OperationToken token) {
    return !disposed && stateMachine.isCurrent(token);
  }

  ReaderV2OperationToken beginJumpOperation({ReaderV2Location? location}) {
    final token = stateMachine.beginJump(location: location);
    notifyListeners();
    return token;
  }

  ReaderV2OperationToken beginRestoreOperation({ReaderV2Location? location}) {
    final token = stateMachine.beginRestore(location: location);
    notifyListeners();
    return token;
  }

  bool completeOperation(
    ReaderV2OperationToken token, {
    ReaderV2Location? visibleLocation,
  }) {
    if (!isCurrentOperationToken(token)) return false;
    final completed = stateMachine.completeOperation(
      token,
      visibleLocation: visibleLocation,
    );
    if (completed) notifyListeners();
    return completed;
  }

  /// 跳轉還沒完成，使用者就自己捲動正文：以使用者捲到的位置為準，
  /// 放棄這次跳轉。開書、排版與內容重載不受影響，它們不是使用者發起的移動。
  void cancelJumpForUserScroll() {
    final operation = stateMachine.currentOperation;
    if (operation == null || operation.kind != ReaderV2OperationKind.jump) {
      return;
    }
    if (stateMachine.abandonOperation(operation)) notifyListeners();
  }

  Future<void> _finishContentUnavailable(
    ReaderV2OperationToken token,
    ReaderV2ContentUnavailableException error,
  ) async {
    if (!isCurrentOperationToken(token)) return;
    // 取不到的那一章：頁面給登入或前往驗證的路時，回來重抓的是它。
    final notice = (
      message: error.message,
      chapterIndex: token.targetLocation
          .normalized(chapterCount: repository.chapterCount)
          .chapterIndex,
    );
    if (state.lifecycle == ReaderV2Lifecycle.cold &&
        _targetsAnotherChapterThanOpen(token)) {
      // 開書還沒排好就跳到別章（之後可能又改了排版、沿用同一個目標），
      // 那一章取不到：取不到的是跳到的章，不是這本書。回到開書的位置重新開，
      // 新的開書接手這次操作，連同已經改好的排版；並告訴使用者原因。
      _pendingUserNotice = notice;
      await openBook();
      return;
    }
    if (state.hasStableWorld) {
      if (!stateMachine.abandonOperation(token)) return;
      _pendingUserNotice = notice;
    } else {
      if (!stateMachine.markUnavailable(token, error)) return;
    }
    notifyListeners();
  }

  bool _targetsAnotherChapterThanOpen(ReaderV2OperationToken token) {
    final count = repository.chapterCount;
    return token.targetLocation.normalized(chapterCount: count).chapterIndex !=
        _initialLocation.normalized(chapterCount: count).chapterIndex;
  }

  Never _rethrowOperationFailure(
    ReaderV2OperationToken token,
    Object error,
    StackTrace stackTrace,
  ) {
    if (isCurrentOperationToken(token)) {
      stateMachine.abandonOperation(token);
      notifyListeners();
    }
    Error.throwWithStackTrace(error, stackTrace);
  }

  Never _failOperationInvariant(ReaderV2OperationToken token, String message) {
    if (isCurrentOperationToken(token)) {
      stateMachine.abandonOperation(token);
      notifyListeners();
    }
    throw StateError(message);
  }

  /// 捲動讀到的位置。不通知整個 Runtime 的監聽者：位置每一格都在變，
  /// 要跟著位置變的只有章（[visibleChapterIndex]）與章內進度（正文發布的
  /// 進度），各自是小訊號；Runtime 的通知只留給操作、排版與內容換代。
  void updateVisibleLocation(ReaderV2Location location) {
    if (disposed) return;
    stateMachine.updateVisibleLocation(location);
  }

  void commitProgressLocation(ReaderV2Location location) {
    if (disposed) return;
    // committedLocation is persistence bookkeeping, not rendered Reader state.
    // visibleLocation already owns viewport notifications, so a background
    // flush must not rebuild the Reader merely because persistence caught up.
    stateMachine.commitLocation(location);
  }

  void notifySessionChanged() {
    if (disposed) return;
    notifyListeners();
  }

  Future<void> ensureChapters() {
    return repository.ensureChapters();
  }

  Future<String> textFromVisibleLocation() async {
    final location = state.visibleLocation.normalized(
      chapterCount: repository.chapterCount,
    );
    final content = await loadContentForTts(location);
    final safeOffset = location.charOffset
        .clamp(0, content.displayText.length)
        .toInt();
    return content.displayText.substring(safeOffset).trim();
  }

  Future<ReaderV2Content> loadContentForTts(ReaderV2Location location) {
    final normalized = location.normalized(
      chapterCount: repository.chapterCount,
    );
    return _loadContentAt(normalized.chapterIndex);
  }

  Future<ReaderV2Content> loadContentAt(int chapterIndex) {
    return _loadContentAt(chapterIndex);
  }

  Future<ReaderV2Content> _loadContentAt(int chapterIndex) async {
    ReaderV2Content? content;
    try {
      content = await repository.loadContent(chapterIndex);
      return content;
    } finally {
      // Repository generations fence its async/cache work. Runtime publishes
      // that semantic generation before a caller can consume newly loaded
      // coordinates, so Hybrid/TTS never need to infer invalidation.
      _publishRepositoryContentGeneration(materializedContent: content);
    }
  }

  void _publishRepositoryContentGeneration({
    ReaderV2Content? materializedContent,
  }) {
    if (disposed) return;
    final generation = repository.contentGeneration;
    if (generation == state.contentGeneration) return;

    final operation = stateMachine.currentOperation;
    final content = materializedContent;
    if (operation == null &&
        content != null &&
        content.chapterIndex == state.visibleLocation.chapterIndex) {
      stateMachine.updateVisibleLocation(
        ReaderV2ContentLocationMapper.resolve(
          location: state.visibleLocation,
          target: content,
        ),
      );
    }

    if (stateMachine.publishContentGeneration(generation)) {
      notifyListeners();
    }
  }

  Future<void> _jumpToChapter(int chapterIndex, {Future<void>? settled}) {
    return _jumpToLocation(
      ReaderV2Location(
        chapterIndex: chapterIndex,
        charOffset: 0,
        visualOffsetPx: state.layoutSpec.anchorOffsetInViewport,
      ),
      immediateSave: true,
      settled: settled,
    );
  }

  Future<void> _jumpToLocation(
    ReaderV2Location location, {
    required bool immediateSave,
    Future<void>? settled,
  }) async {
    final token = beginJumpOperation(location: location);
    AppLog.d(
      'Reader jump operation id=${token.id} '
      'target=${location.chapterIndex}',
    );
    try {
      if (settled != null) {
        await settled;
        if (!isCurrentOperationToken(token)) return;
      }
      final positioned = await _positionViewport(
        location: location,
        token: token,
      );
      AppLog.d(
        'Reader jump operation id=${token.id} positioned=$positioned '
        'current=${stateMachine.isCurrent(token)} lifecycle=${state.lifecycle.name} '
        'visible=${state.visibleLocation.chapterIndex}',
      );
      if (!positioned) return;
      if (immediateSave) {
        await viewportBridge.saveProgressLocation(state.visibleLocation);
      }
    } on ReaderV2ContentUnavailableException catch (error) {
      await _finishContentUnavailable(token, error);
    } catch (error, stackTrace) {
      _rethrowOperationFailure(token, error, stackTrace);
    }
  }

  Future<bool> _positionViewport({
    required ReaderV2Location location,
    required ReaderV2OperationToken token,
  }) async {
    await repository.ensureChapters();
    if (!isCurrentOperationToken(token)) return false;
    final chapterCount = repository.chapterCount;
    if (chapterCount <= 0) {
      _failOperationInvariant(
        token,
        'Reader chapter repository has no chapters after ensureChapters().',
      );
    }
    final chapterIndex = location.chapterIndex
        .clamp(0, chapterCount - 1)
        .toInt();

    while (isCurrentOperationToken(token)) {
      final content = await _loadContentAt(chapterIndex);
      if (!isCurrentOperationToken(token)) return false;

      final previousLayoutGeneration = state.layoutGeneration;
      final previousPresentationSignature =
          state.layoutSpec.presentationSignature;
      if (!stateMachine.commitLayoutForOperation(token)) return false;
      if (state.layoutGeneration != previousLayoutGeneration ||
          state.layoutSpec.presentationSignature !=
              previousPresentationSignature) {
        notifyListeners();
      }

      // `charOffset` is meaningful only in the display-text identity that
      // owned it when captured. Re-resolve the same operation intent whenever
      // the semantic document generation advances during viewport work.
      final resolved =
          ReaderV2ContentLocationMapper.resolve(
            location: location.copyWith(chapterIndex: chapterIndex),
            target: content,
          ).normalized(
            chapterCount: chapterCount,
            chapterLength: content.displayText.length,
          );
      final targetContentGeneration = state.contentGeneration;

      final restore = viewportBridge.viewportRestore;
      if (restore == null) {
        _failOperationInvariant(
          token,
          'Reader viewport owner is not registered.',
        );
      }
      AppLog.d(
        'Reader viewport restore start op=${token.id} '
        'target=${resolved.chapterIndex} '
        'contentGeneration=$targetContentGeneration',
      );
      final restored = await restore(resolved);
      AppLog.d(
        'Reader viewport restore done op=${token.id} restored=$restored '
        'current=${stateMachine.isCurrent(token)} lifecycle=${state.lifecycle.name} '
        'visible=${state.visibleLocation.chapterIndex} '
        'contentGeneration=${state.contentGeneration}',
      );
      if (!isCurrentOperationToken(token)) return false;

      if (state.contentGeneration != targetContentGeneration) {
        // The operation still owns the same semantic intent, but its viewport
        // attempt belonged to an older document generation. Re-resolve it
        // against the newly published content without creating a new token.
        continue;
      }
      if (!restored) {
        _failOperationInvariant(
          token,
          'Reader viewport could not materialize the current operation target.',
        );
      }

      final completed = completeOperation(token, visibleLocation: resolved);
      AppLog.d(
        'Reader viewport complete op=${token.id} completed=$completed '
        'lifecycle=${state.lifecycle.name} '
        'visible=${state.visibleLocation.chapterIndex}',
      );
      return completed;
    }
    return false;
  }

  @override
  void dispose() {
    disposed = true;
    progressController.dispose();
    _viewportGeometryNotifier.dispose();
    _chapterShares.dispose();
    stateMachine.dispose();
    super.dispose();
  }
}
