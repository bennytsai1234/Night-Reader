import 'dart:async';
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

  late final ReaderV2ViewportBridge viewportBridge;

  bool disposed = false;
  String? _pendingUserNotice;
  ReaderV2Location? get pendingLocation => stateMachine.pendingLocation;


  ReaderV2State get state => stateMachine.state;

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
    final detachedActiveOwner = viewportBridge.unregisterViewportRestore(owner);
    if (!detachedActiveOwner || disposed) return;
    final operation = stateMachine.currentOperation;
    if (operation == null || !stateMachine.abandonOperation(operation)) return;
    notifyListeners();
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
      return await _positionViewport(location: location, token: token);
    } on ReaderV2ContentUnavailableException catch (error) {
      _finishContentUnavailable(token, error);
      return false;
    } catch (error, stackTrace) {
      _rethrowOperationFailure(token, error, stackTrace);
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
      await _positionViewport(location: _initialLocation, token: token);
    } on ReaderV2ContentUnavailableException catch (error) {
      _finishContentUnavailable(token, error);
    } catch (error, stackTrace) {
      _rethrowOperationFailure(token, error, stackTrace);
    }
  }

  Future<void> applyPresentation({required ReaderV2LayoutSpec spec}) async {
    final stagedSpec = stateMachine.currentOperation?.layoutSpec ?? state.layoutSpec;
    if (stagedSpec.layoutSignature == spec.layoutSignature) return;
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
      _finishContentUnavailable(token, error);
    } catch (error, stackTrace) {
      _rethrowOperationFailure(token, error, stackTrace);
    }
  }

  Future<void> reloadContentPreservingLocation() async {
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
      );
      if (!isCurrentOperationToken(token)) return;
      await _positionViewport(location: remappedLocation, token: token);
    } on ReaderV2ContentUnavailableException catch (error) {
      _finishContentUnavailable(token, error);
    } catch (error, stackTrace) {
      _rethrowOperationFailure(token, error, stackTrace);
    }
  }

  Future<ReaderV2Location> _remapReloadLocation({
    required ReaderV2Location location,
    required ReaderV2Content? previousContent,
    required ReaderV2OperationToken token,
  }) async {
    late final ReaderV2Content after;
    try {
      after = await repository.reloadContent(location.chapterIndex);
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

  void _finishContentUnavailable(
    ReaderV2OperationToken token,
    ReaderV2ContentUnavailableException error,
  ) {
    if (!isCurrentOperationToken(token)) return;
    if (state.hasStableWorld) {
      if (!stateMachine.abandonOperation(token)) return;
      _pendingUserNotice = error.message;
    } else {
      if (!stateMachine.markUnavailable(token, error)) return;
    }
    notifyListeners();
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

  Never _failOperationInvariant(
    ReaderV2OperationToken token,
    String message,
  ) {
    if (isCurrentOperationToken(token)) {
      stateMachine.abandonOperation(token);
      notifyListeners();
    }
    throw StateError(message);
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
        'current=${stateMachine.isCurrent(token)} lifecycle=${state.lifecycle.name} '
        'visible=${state.visibleLocation.chapterIndex}',
      );
      if (!positioned) return;
      if (immediateSave) {
        await viewportBridge.saveProgressLocation(state.visibleLocation);
      }
    } on ReaderV2ContentUnavailableException catch (error) {
      _finishContentUnavailable(token, error);
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
      if (!stateMachine.commitLayoutForOperation(token)) return false;
      if (state.layoutGeneration != previousLayoutGeneration) {
        notifyListeners();
      }

      // `charOffset` is meaningful only in the display-text identity that
      // owned it when captured. Re-resolve the same operation intent whenever
      // the semantic document generation advances during viewport work.
      final resolved = ReaderV2ContentLocationMapper.resolve(
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

      final completed = completeOperation(
        token,
        visibleLocation: resolved,
      );
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
    super.dispose();
  }
}
