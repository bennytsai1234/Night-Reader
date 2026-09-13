import 'dart:async';

/// Serializes user-triggered startup retries into one reset/start operation.
///
/// A second tap while the first retry is still resetting GetIt must observe
/// the same Future instead of starting a second dependency graph in parallel.
final class StartupRetryGate {
  Future<void>? _inFlight;

  Future<void> run({
    required Future<void> Function() reset,
    required Future<void> Function() start,
  }) {
    final pending = _inFlight;
    if (pending != null) return pending;

    final future = _run(reset: reset, start: start);
    _inFlight = future;
    future.then<void>(
      (_) {
        if (identical(_inFlight, future)) _inFlight = null;
      },
      onError: (Object _, StackTrace __) {
        if (identical(_inFlight, future)) _inFlight = null;
      },
    );
    return future;
  }

  Future<void> _run({
    required Future<void> Function() reset,
    required Future<void> Function() start,
  }) async {
    await reset();
    await start();
  }
}
