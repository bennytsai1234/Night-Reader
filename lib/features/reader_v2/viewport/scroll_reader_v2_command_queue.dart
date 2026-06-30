import 'dart:async';

class ScrollReaderV2CommandQueue {
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
