import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/chapter_alignment.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/features/reader/chapter/reader_chapter_repository.dart';
import 'package:night_reader/features/reader/chapter/reader_content.dart';
import 'package:night_reader/features/reader/text_view/progress/reader_chapter_shares.dart';
import 'package:night_reader/features/reader/layout/reader_layout_spec.dart';
import 'package:night_reader/features/reader/use_cases/coordinators/reader_chapter_navigation_resolver.dart';

import 'reader_location.dart';
import 'reader_operation_token.dart';
import 'reader_progress_controller.dart';
import 'reader_state.dart';
import 'reader_state_machine.dart';

import 'reader_viewport_bridge.dart';

typedef ReaderVisibleLocationCapture = ReaderLocation? Function();

/// 交給頁面顯示的提示；某一章取不到時 [chapterIndex] 是那一章。
typedef ReaderUserNotice = ({String message, int? chapterIndex});
typedef ReaderViewportRestore = Future<bool> Function(ReaderLocation location);

class ReaderRuntime extends ChangeNotifier {
  factory ReaderRuntime({
    required Book book,
    required ReaderChapterRepository repository,
    required ReaderProgressController progressController,
    required ReaderLayoutSpec initialLayoutSpec,
    ReaderLocation? initialLocation,
  }) {
    final location =
        (initialLocation ??
                ReaderLocation(
                  chapterIndex: book.chapterIndex,
                  charOffset: book.charOffset,
                  visualOffsetPx: book.visualOffsetPx,
                ))
            .normalized();
    return ReaderRuntime._(
      repository: repository,
      progressController: progressController,
      initialLayoutSpec: initialLayoutSpec,
      initialLocation: location,
    );
  }

  ReaderRuntime._({
    required this.repository,
    required this.progressController,
    required ReaderLayoutSpec initialLayoutSpec,
    required ReaderLocation initialLocation,
  }) : _initialLocation = initialLocation,
       stateMachine = ReaderStateMachine(
         ReaderState(
           lifecycle: ReaderLifecycle.cold,
           committedLocation: initialLocation,
           visibleLocation: initialLocation,
           layoutSpec: initialLayoutSpec,
           layoutGeneration: 0,
           contentGeneration: repository.contentGeneration,
         ),
       ) {
    viewportBridge = ReaderViewportBridge(this);
  }

  final ReaderChapterRepository repository;
  final ReaderProgressController progressController;

  /// 開著的這本書。
  Book get book => progressController.book;

  /// 開書的位置，開書前跳章失敗時也回到這裡（[openBook]）。
  ReaderLocation _initialLocation;

  /// 開書開始了沒有（[openBook]）；開始之前的跳章記在 [_jumpedBeforeOpen]，
  /// 開書時開在那裡，不蓋掉使用者的選擇。
  bool _openStarted = false;
  ReaderLocation? _jumpedBeforeOpen;
  final ReaderStateMachine stateMachine;
  final ChangeNotifier _viewportGeometryNotifier = ChangeNotifier();

  late final ReaderViewportBridge viewportBridge;

  bool disposed = false;
  ReaderUserNotice? _pendingUserNotice;
  ReaderLocation? get pendingLocation => stateMachine.pendingLocation;

  /// 正在跳到別章、還沒排好。同一章內的跳轉（例如拖進度條預覽）不算。
  bool get isJumpingToAnotherChapter {
    final operation = stateMachine.currentOperation;
    final target = pendingLocation;
    return operation != null &&
        operation.kind == ReaderOperationKind.jump &&
        target != null &&
        target.chapterIndex != state.visibleLocation.chapterIndex;
  }

  /// 正文正在照新的排版設定重排，或照新的內容設定（繁簡轉換、替換規則等）
  /// 重新載入，還沒排好。
  bool get isRebuildingText {
    final kind = stateMachine.currentOperation?.kind;
    return kind == ReaderOperationKind.presentation ||
        kind == ReaderOperationKind.contentReload;
  }

  ReaderState get state => stateMachine.state;

  /// 畫面上這一章，見 [ReaderStateMachine.visibleChapterIndex]。
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
    ReaderVisibleLocationCapture capture,
  ) {
    viewportBridge.registerVisibleLocationCapture(owner, capture);
  }

  void unregisterVisibleLocationCapture(Object owner) {
    viewportBridge.unregisterVisibleLocationCapture(owner);
  }

  void registerViewportRestore(Object owner, ReaderViewportRestore restore) {
    viewportBridge.registerViewportRestore(owner, restore);
  }

  void unregisterViewportRestore(Object owner) {
    final detachedActiveOwner = viewportBridge.unregisterViewportRestore(owner);
    if (!detachedActiveOwner || disposed) return;
    final operation = stateMachine.currentOperation;
    if (operation == null || !stateMachine.abandonOperation(operation)) return;
    notifyListeners();
  }

  ReaderLocation? captureVisibleLocation() =>
      viewportBridge.captureVisibleLocation();

  Future<ReaderLocation?> saveProgress({
    ReaderLocation? location,
    bool immediate = true,
  }) async {
    return viewportBridge.saveProgress(
      location: location,
      immediate: immediate,
    );
  }

  Future<ReaderLocation?> flushProgress() {
    return viewportBridge.flushProgress();
  }

  // -- Reader commands --

  /// 跳到 [chapterIndex] 章首。一開始就蓋紙；[settled] 給了的話，等它完成
  /// （例如收起目錄與紙蓋上的動畫播完）才開始載入（ADR 0018）。
  Future<void> jumpToChapter(int chapterIndex, {Future<void>? settled}) =>
      _jumpToChapter(chapterIndex, settled: settled);

  /// 跳到 [location]；[settled] 同 [jumpToChapter]。傳回有沒有真的定位到
  /// [location]：跳轉途中使用者自己捲動（[cancelJumpForUserScroll]）、被更新
  /// 的操作取代、那一章取不到、閱讀器關掉都傳回 false，畫面不在目標上。
  Future<bool> jumpToLocation(
    ReaderLocation location, {
    bool immediateSave = true,
    Future<void>? settled,
  }) =>
      _jumpToLocation(location, immediateSave: immediateSave, settled: settled);

  Future<bool> restoreFromLocation(ReaderLocation location) async {
    final token = beginRestoreOperation(location: location);
    try {
      return await _positionViewport(location: location, token: token);
    } on ReaderContentUnavailableException catch (error) {
      await _finishContentUnavailable(token, error);
      return false;
    } catch (error, stackTrace) {
      _rethrowOperationFailure(token, error, stackTrace);
    }
  }

  // -- Runtime-owned methods --

  ReaderUserNotice? takeUserNotice() {
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
  ValueListenable<ReaderChapterShares> get chapterShares => _chapterShares;
  final ValueNotifier<ReaderChapterShares> _chapterShares =
      ValueNotifier<ReaderChapterShares>(const ReaderChapterShares.even(0));

  /// 只讀資料庫（目錄已經載入）；讀不到就照章數平均，不擋開書。
  Future<void> _loadChapterShares() async {
    try {
      final shares = await repository.loadChapterShares();
      if (!disposed) _chapterShares.value = shares;
    } catch (error) {
      AppLog.w('讀每章長度失敗，全書進度照章數平均: $error');
    }
  }

  /// 開書，停在建立時給的位置；給了 [at]（開書前才從資料庫讀到的較新位置，
  /// 例如剛同步來的）就改停在那裡，之後跳章失敗也回到這裡。開書前使用者
  /// 已經跳章（例如在換頁動畫期間開了目錄），開在跳去的地方。給了
  /// [chapterTitle]（從書籤開書）時，讀到目錄後照章名對到這台目錄的那一章：
  /// 開書前目錄可能還沒抓，位置裡的章節序號是別處的座標。
  Future<void> openBook({ReaderLocation? at, String? chapterTitle}) async {
    _openStarted = true;
    if (at != null) _initialLocation = at.normalized();
    final jumped = _jumpedBeforeOpen;
    _jumpedBeforeOpen = null;
    var location = jumped ?? _initialLocation;
    final token = stateMachine.beginOpen(location: location);
    notifyListeners();
    try {
      // 目錄取不到的失敗和排版時一樣交給下面處理；目錄有了才讀每章長度
      // （幾十毫秒，這時紙剛蓋上），讀好才排正文。
      await repository.ensureChapters();
      await _loadChapterShares();
      if (!isCurrentOperationToken(token)) return;
      if (jumped == null) {
        if (chapterTitle != null && chapterTitle.isNotEmpty) {
          location = location.copyWith(
            chapterIndex: alignChapterIndex(
              oldIndex: location.chapterIndex,
              oldTitle: chapterTitle,
              oldTotalCount: 0,
              newChapters: repository.chapters,
            ),
          );
        }
        location = _skipLockedChapter(location);
        _initialLocation = location;
      }
      await _positionViewport(location: location, token: token);
    } on ReaderContentUnavailableException catch (error) {
      await _finishContentUnavailable(token, error);
    } catch (error, stackTrace) {
      _rethrowOperationFailure(token, error, stackTrace);
    }
  }

  /// 開書的位置停在付費章節（不抓，ADR 0057）時，改到最近的免費章節章首：
  /// 先往後找，沒有再往前找，同漫畫與有聲書。整本都是付費章節就不動，排版
  /// 時照常顯示取不到。存的進度、同步來的進度與書籤都可能停在這種章。
  ReaderLocation _skipLockedChapter(ReaderLocation location) {
    final count = repository.chapterCount;
    if (count <= 0) return location;
    final index = location.chapterIndex.clamp(0, count - 1).toInt();
    bool locked(int chapterIndex) =>
        repository.chapterAt(chapterIndex)?.isLocked ?? false;
    if (!locked(index)) return location;
    int? nearest(int delta) =>
        ReaderChapterNavigationResolver.resolveRelativeTarget(
          currentChapterIndex: index,
          chapterCount: count,
          delta: delta,
          skip: locked,
        );
    final target = nearest(1) ?? nearest(-1);
    if (target == null) return location;
    return ReaderLocation(
      chapterIndex: target,
      charOffset: 0,
      visualOffsetPx: stateMachine.effectiveLayoutSpec.anchorOffsetInViewport,
    );
  }

  Future<void> applyPresentation({required ReaderLayoutSpec spec}) async {
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
    } on ReaderContentUnavailableException catch (error) {
      await _finishContentUnavailable(token, error);
    } catch (error, stackTrace) {
      _rethrowOperationFailure(token, error, stackTrace);
    }
  }

  /// 重新整理目前這一章並停在原位。[refetch] 先向書源重抓（見
  /// [ReaderChapterRepository.reloadContent]）；抓不到時保留原本的正文，
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
    } on ReaderContentUnavailableException catch (error) {
      await _finishContentUnavailable(token, error);
      return false;
    } catch (error, stackTrace) {
      _rethrowOperationFailure(token, error, stackTrace);
    }
  }

  Future<ReaderLocation> _remapReloadLocation({
    required ReaderLocation location,
    required ReaderContent? previousContent,
    required ReaderOperationToken token,
    required bool refetch,
  }) async {
    late final ReaderContent after;
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
    return ReaderContentLocationMapper.remap(
      location: location,
      before: before,
      after: after,
    );
  }

  bool isCurrentOperationToken(ReaderOperationToken token) {
    return !disposed && stateMachine.isCurrent(token);
  }

  ReaderOperationToken beginJumpOperation({ReaderLocation? location}) {
    if (!_openStarted && location != null) _jumpedBeforeOpen = location;
    final token = stateMachine.beginJump(location: location);
    notifyListeners();
    return token;
  }

  ReaderOperationToken beginRestoreOperation({ReaderLocation? location}) {
    final token = stateMachine.beginRestore(location: location);
    notifyListeners();
    return token;
  }

  bool completeOperation(
    ReaderOperationToken token, {
    ReaderLocation? visibleLocation,
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
    if (operation == null || operation.kind != ReaderOperationKind.jump) {
      return;
    }
    if (stateMachine.abandonOperation(operation)) notifyListeners();
  }

  Future<void> _finishContentUnavailable(
    ReaderOperationToken token,
    ReaderContentUnavailableException error,
  ) async {
    if (!isCurrentOperationToken(token)) return;
    // 取不到的那一章：頁面給登入或前往驗證的路時，回來重抓的是它。
    final notice = (
      message: error.message,
      chapterIndex: token.targetLocation
          .normalized(chapterCount: repository.chapterCount)
          .chapterIndex,
    );
    if (state.lifecycle == ReaderLifecycle.cold &&
        _targetsAnotherChapterThanOpen(token)) {
      // 開書還沒排好就跳到別章（之後可能又改了排版、沿用同一個目標），
      // 那一章取不到：取不到的是跳到的章，不是這本書。回到開書的位置重新開，
      // 新的開書接手這次操作，連同已經改好的排版；並告訴使用者原因。
      _pendingUserNotice = notice;
      _jumpedBeforeOpen = null;
      await openBook();
      return;
    }
    if (state.hasStableWorld) {
      if (!stateMachine.abandonOperation(token)) return;
      _pendingUserNotice = notice;
    } else {
      if (!stateMachine.markUnavailable(token, error)) return;
      _unavailableLocation = token.targetLocation.normalized(
        chapterCount: repository.chapterCount,
      );
    }
    notifyListeners();
  }

  /// 開書取不到正文（[ReaderLifecycle.unavailable]）時要開的位置：失敗頁的
  /// 「單章借源」借的是這一章，借好在這裡重開（ADR 0080）。開書時位置會照
  /// 章名、付費章節改過，不一定是建立時給的。
  ReaderLocation? get unavailableLocation => _unavailableLocation;
  ReaderLocation? _unavailableLocation;

  bool _targetsAnotherChapterThanOpen(ReaderOperationToken token) {
    final count = repository.chapterCount;
    return token.targetLocation.normalized(chapterCount: count).chapterIndex !=
        _initialLocation.normalized(chapterCount: count).chapterIndex;
  }

  Never _rethrowOperationFailure(
    ReaderOperationToken token,
    Object error,
    StackTrace stackTrace,
  ) {
    if (isCurrentOperationToken(token)) {
      stateMachine.abandonOperation(token);
      notifyListeners();
    }
    Error.throwWithStackTrace(error, stackTrace);
  }

  Never _failOperationInvariant(ReaderOperationToken token, String message) {
    if (isCurrentOperationToken(token)) {
      stateMachine.abandonOperation(token);
      notifyListeners();
    }
    throw StateError(message);
  }

  /// 捲動讀到的位置。不通知整個 Runtime 的監聽者：位置每一格都在變，
  /// 要跟著位置變的只有章（[visibleChapterIndex]）與章內進度（正文發布的
  /// 進度），各自是小訊號；Runtime 的通知只留給操作、排版與內容換代。
  void updateVisibleLocation(ReaderLocation location) {
    if (disposed) return;
    stateMachine.updateVisibleLocation(location);
  }

  void commitProgressLocation(ReaderLocation location) {
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

  Future<ReaderContent> loadContentForTts(ReaderLocation location) {
    final normalized = location.normalized(
      chapterCount: repository.chapterCount,
    );
    return _loadContentAt(normalized.chapterIndex);
  }

  Future<ReaderContent> loadContentAt(int chapterIndex) {
    return _loadContentAt(chapterIndex);
  }

  Future<ReaderContent> _loadContentAt(int chapterIndex) async {
    ReaderContent? content;
    try {
      content = await repository.loadContent(chapterIndex);
      return content;
    } finally {
      // Repository generations fence its async/cache work. Runtime publishes
      // that semantic generation before a caller can consume newly loaded
      // coordinates, so the text view and TTS never need to infer invalidation.
      _publishRepositoryContentGeneration(materializedContent: content);
    }
  }

  void _publishRepositoryContentGeneration({
    ReaderContent? materializedContent,
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
        ReaderContentLocationMapper.resolve(
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
      ReaderLocation(
        chapterIndex: chapterIndex,
        charOffset: 0,
        visualOffsetPx: state.layoutSpec.anchorOffsetInViewport,
      ),
      immediateSave: true,
      settled: settled,
    );
  }

  Future<bool> _jumpToLocation(
    ReaderLocation location, {
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
        if (!isCurrentOperationToken(token)) return false;
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
      if (!positioned) return false;
      if (immediateSave) {
        await viewportBridge.saveProgressLocation(state.visibleLocation);
      }
      return true;
    } on ReaderContentUnavailableException catch (error) {
      await _finishContentUnavailable(token, error);
      return false;
    } catch (error, stackTrace) {
      _rethrowOperationFailure(token, error, stackTrace);
    }
  }

  Future<bool> _positionViewport({
    required ReaderLocation location,
    required ReaderOperationToken token,
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
          ReaderContentLocationMapper.resolve(
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
    repository.dispose();
    progressController.dispose();
    _viewportGeometryNotifier.dispose();
    _chapterShares.dispose();
    stateMachine.dispose();
    super.dispose();
  }
}
