import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter/widgets.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';

import 'reader_v2_location.dart';
import 'reader_v2_operation_token.dart';
import 'reader_v2_progress_controller.dart';
import 'reader_v2_state.dart';
import 'reader_v2_state_machine.dart';

import 'reader_v2_viewport_bridge.dart';

typedef ReaderV2VisibleLocationCapture = ReaderV2Location? Function();
typedef ReaderV2ViewportRestore = Future<bool> Function(
  ReaderV2Location location,
);

class ReaderV2Runtime extends ChangeNotifier {
  /// Optional transition observation for deterministic state-transition tests.
  ///
  /// The production path leaves this null, and the dispatch is debug-only, so
  /// no counter or history is allocated unless a test explicitly opts in.
  @visibleForTesting
  static VoidCallback? debugOnApplyPresentationTriggered;

  @visibleForTesting
  static VoidCallback? debugOnReloadContentTriggered;

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
           phase: ReaderV2Phase.cold,
           committedLocation: initialLocation,
           visibleLocation: initialLocation,
           layoutSpec: initialLayoutSpec,
           layoutGeneration: 0,
         ),
       ) {
    viewportBridge = ReaderV2ViewportBridge(this);
  }

  final ReaderV2ChapterRepository repository;
  final ReaderV2ProgressController progressController;
  final ReaderV2Location _initialLocation;
  final ReaderV2StateMachine stateMachine;

  late final ReaderV2ViewportBridge viewportBridge;

  bool disposed = false;
  String? _pendingUserNotice;
  ReaderV2Location? get pendingLocation => stateMachine.pendingLocation;


  ReaderV2State get state => stateMachine.state;

  bool get restoreInProgress => stateMachine.restoreInProgress;

  int get chapterCount => repository.chapterCount;
  List<BookChapter> get chapters => repository.chapters;

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
    viewportBridge.unregisterViewportRestore(owner);
  }

  ReaderV2Location? captureVisibleLocation({bool notifyIfChanged = true}) =>
      viewportBridge.captureVisibleLocation(notifyIfChanged: notifyIfChanged);

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

  Future<void> jumpToChapter(int chapterIndex) => _jumpToChapter(chapterIndex);

  Future<void> jumpToLocation(
    ReaderV2Location location, {
    bool immediateSave = true,
  }) => _jumpToLocation(location, immediateSave: immediateSave);

  Future<bool> restoreFromLocation(ReaderV2Location location) async {
    final token = beginRestoreOperation(location: location);
    try {
      final restored = await _positionViewport(location: location, token: token);
      if (!restored && stateMachine.isCurrent(token)) {
        failOperation(token, StateError('Reader viewport restore failed.'));
      }
      return restored;
    } catch (error) {
      failOperation(token, error);
      return false;
    }
  }

  // -- Runtime-owned methods --

  String? takeUserNotice() {
    final notice = _pendingUserNotice;
    _pendingUserNotice = null;
    return notice;
  }

  void emitUserNotice(String message) {
    _pendingUserNotice = message;
  }

  Future<void> openBook() async {
    final token = stateMachine.beginOpen(location: _initialLocation);
    notifyListeners();
    try {
      final positioned = await _positionViewport(
        location: _initialLocation,
        token: token,
      );
      if (!positioned && stateMachine.isCurrent(token)) {
        failOperation(token, StateError('Reader viewport restore failed.'));
      }
    } catch (error) {
      failOperation(token, error);
    }
  }

  Future<void> applyPresentation({required ReaderV2LayoutSpec spec}) async {
    final needLayout = state.layoutSpec.layoutSignature != spec.layoutSignature;
    if (!needLayout) return;
    if (kDebugMode) debugOnApplyPresentationTriggered?.call();

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
      final positioned = await _positionViewport(location: location, token: token);
      if (!positioned && stateMachine.isCurrent(token)) {
        failOperation(token, StateError('Reader presentation restore failed.'));
      }
    } catch (error) {
      failOperation(token, error);
    }
  }

  Future<void> reloadContentPreservingLocation() async {
    if (kDebugMode) debugOnReloadContentTriggered?.call();
    final location =
        pendingLocation ??
        viewportBridge.captureVisibleLocation() ??
        state.visibleLocation;
    final previousContent = repository.cachedContent(location.chapterIndex);
    repository.clearContentCache();
    final token = stateMachine.beginContentReload(
      location: location,
      layoutGeneration: state.layoutGeneration + 1,
    );
    notifyListeners();
    try {
      final remappedLocation = await _remapReloadLocation(
        location: location,
        previousContent: previousContent,
        token: token,
      );
      if (!isCurrentOperationToken(token)) return;
      final positioned = await _positionViewport(
        location: remappedLocation,
        token: token,
      );
      if (!positioned && stateMachine.isCurrent(token)) {
        failOperation(token, StateError('Reader content restore failed.'));
      }
    } catch (error) {
      failOperation(token, error);
    }
  }

  Future<ReaderV2Location> _remapReloadLocation({
    required ReaderV2Location location,
    required ReaderV2Content? previousContent,
    required ReaderV2OperationToken token,
  }) async {
    final before = previousContent;
    if (before == null) return location;
    final after = await repository.loadContent(location.chapterIndex);
    if (!isCurrentOperationToken(token)) return location;
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

  bool completeReadyOperation(
    ReaderV2OperationToken token, {
    ReaderV2Location? visibleLocation,
  }) {
    if (!isCurrentOperationToken(token)) return false;
    final completed = stateMachine.completeReady(
      token,
      visibleLocation: visibleLocation,
    );
    if (completed) notifyListeners();
    return completed;
  }

  bool failOperation(ReaderV2OperationToken token, Object error) {
    if (!isCurrentOperationToken(token)) return false;
    final failed = stateMachine.fail(token, error);
    if (failed) notifyListeners();
    return failed;
  }

  void updateVisibleLocation(ReaderV2Location location, {bool notify = true}) {
    if (disposed) return;
    stateMachine.updateVisibleLocation(location);
    if (notify) notifyListeners();
  }

  void commitProgressLocation(ReaderV2Location location) {
    if (disposed) return;
    stateMachine.commitLocation(location);
    notifyListeners();
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
    return repository.loadContent(normalized.chapterIndex);
  }

  Future<ReaderV2Content> loadContentAt(int chapterIndex) {
    return repository.loadContent(chapterIndex);
  }

  Future<void> _jumpToChapter(int chapterIndex) {
    return _jumpToLocation(
      ReaderV2Location(
        chapterIndex: chapterIndex,
        charOffset: 0,
        visualOffsetPx: state.layoutSpec.anchorOffsetInViewport,
      ),
      immediateSave: true,
    );
  }

  Future<void> _jumpToLocation(
    ReaderV2Location location, {
    required bool immediateSave,
  }) async {
    final token = beginJumpOperation(location: location);
    AppLog.d(
      'Reader jump operation id=${token.id} '
      'target=${location.chapterIndex}',
    );
    try {
      final positioned = await _positionViewport(
        location: location,
        token: token,
      );
      AppLog.d(
        'Reader jump operation id=${token.id} positioned=$positioned '
        'current=${stateMachine.isCurrent(token)} phase=${state.phase} '
        'visible=${state.visibleLocation.chapterIndex}',
      );
      if (!positioned) {
        if (isCurrentOperationToken(token)) {
          failOperation(token, StateError('Reader jump restore failed.'));
        }
        return;
      }
      if (immediateSave) {
        await viewportBridge.saveProgressLocation(state.visibleLocation);
      }
    } catch (error) {
      failOperation(token, error);
    }
  }

  Future<bool> _positionViewport({
    required ReaderV2Location location,
    required ReaderV2OperationToken token,
  }) async {
    await repository.ensureChapters();
    if (!isCurrentOperationToken(token)) return false;
    final chapterCount = repository.chapterCount;
    if (chapterCount <= 0) return false;
    final chapterIndex = location.chapterIndex
        .clamp(0, chapterCount - 1)
        .toInt();
    final content = await repository.loadContent(chapterIndex);
    if (!isCurrentOperationToken(token)) return false;

    // `charOffset` is meaningful only in the display-text identity that owned
    // it when captured. Resume/source-switch locations carry that identity and
    // a two-sided text anchor. Resolve it against the exact target content
    // before the viewport sees the coordinate. Plain chapter/bookmark jumps
    // have no identity, so resolve() preserves their scalar offset.
    final resolved = ReaderV2ContentLocationMapper.resolve(
      location: location.copyWith(chapterIndex: chapterIndex),
      target: content,
    ).normalized(
      chapterCount: chapterCount,
      chapterLength: content.displayText.length,
    );

    final restore = viewportBridge.viewportRestore;
    if (restore == null) return false;
    AppLog.d(
      'Reader viewport restore start op=${token.id} '
      'target=${resolved.chapterIndex}',
    );
    final restored = await restore(resolved);
    AppLog.d(
      'Reader viewport restore done op=${token.id} restored=$restored '
      'current=${stateMachine.isCurrent(token)} phase=${state.phase} '
      'visible=${state.visibleLocation.chapterIndex}',
    );
    if (!restored) return false;
    if (!isCurrentOperationToken(token)) return false;
    final completed = completeReadyOperation(
      token,
      visibleLocation: resolved,
    );
    AppLog.d(
      'Reader viewport complete op=${token.id} completed=$completed '
      'phase=${state.phase} visible=${state.visibleLocation.chapterIndex}',
    );
    return completed;
  }

  @override
  void dispose() {
    disposed = true;
    progressController.dispose();
    super.dispose();
  }
}
