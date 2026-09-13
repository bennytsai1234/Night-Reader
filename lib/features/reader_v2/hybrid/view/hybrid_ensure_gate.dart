import 'dart:async';

typedef HybridEnsureCommand = Future<bool> Function();

/// Holds programmatic ensure commands while a user scroll gesture is active.
///
/// The gate is deliberately separate from [ScrollPosition]: it prevents a
/// TTS/layout command from competing with the same position, while the screen
/// decides when the user scroll has fully settled and calls
/// [releaseAndFlush].
final class HybridEnsureGate {
  bool _userScrollActive = false;
  _PendingEnsure? _pending;
  bool _flushing = false;
  bool _disposed = false;

  void beginUserScroll() {
    if (_disposed) return;
    _userScrollActive = true;
  }

  Future<bool> submit(HybridEnsureCommand command) {
    if (_disposed) return Future<bool>.value(false);
    if (!_userScrollActive && !_flushing && _pending == null) {
      return command();
    }

    final completer = Completer<bool>();
    _pending?.complete(false);
    _pending = _PendingEnsure(command, completer);
    return completer.future;
  }

  Future<void> releaseAndFlush() async {
    if (_disposed || _flushing) return;
    _userScrollActive = false;
    _flushing = true;
    try {
      while (!_userScrollActive && _pending != null && !_disposed) {
        final pending = _pending!;
        _pending = null;
        try {
          pending.complete(await pending.command());
        } catch (_) {
          pending.complete(false);
        }
      }
    } finally {
      _flushing = false;
    }
  }

  void dispose() {
    _disposed = true;
    _userScrollActive = false;
    _flushing = false;
    _pending?.complete(false);
    _pending = null;
  }
}

final class _PendingEnsure {
  _PendingEnsure(this.command, this.completer);

  final HybridEnsureCommand command;
  final Completer<bool> completer;

  void complete(bool result) {
    if (!completer.isCompleted) completer.complete(result);
  }
}
