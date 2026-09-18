import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/source_debug_service.dart';
import 'package:night_reader/features/source_manager/source_debug_provider.dart';

class _FakeDebugService implements SourceDebugService {
  final StreamController<DebugLog> controller =
      StreamController<DebugLog>.broadcast();
  Completer<void> runCompleter = Completer<void>();
  int startCount = 0;
  bool cancelCalled = false;

  @override
  Stream<DebugLog> get logStream => controller.stream;

  @override
  void cancel() {
    cancelCalled = true;
  }

  @override
  void log(String msg, {int state = 1, bool isHtml = false}) {
    controller.add(DebugLog(state, msg, DateTime(2026)));
  }

  @override
  Future<void> startDebug(BookSource source, String key) {
    startCount += 1;
    return runCompleter.future;
  }
}

void main() {
  test(
    'debug provider ignores duplicate starts and finishes cleanly',
    () async {
      final service = _FakeDebugService();
      addTearDown(service.controller.close);
      final provider = SourceDebugProvider(
        BookSource(bookSourceUrl: 'https://source.test', bookSourceName: '書源'),
        '關鍵字',
        debugService: service,
      );

      final firstRun = provider.startDebug();
      await provider.startDebug();
      expect(service.startCount, 1);
      expect(provider.isRunning, isTrue);

      service.log('完成', state: 1000);
      await Future<void>.delayed(Duration.zero);
      service.runCompleter.complete();
      await firstRun;

      expect(provider.isFinished, isTrue);
      expect(provider.isRunning, isFalse);
      expect(provider.logs.single.message, '完成');
      provider.dispose();
    },
  );

  test('debug provider cancels and ignores logs after dispose', () async {
    final service = _FakeDebugService();
    addTearDown(service.controller.close);
    final provider = SourceDebugProvider(
      BookSource(bookSourceUrl: 'https://source.test', bookSourceName: '書源'),
      '關鍵字',
      debugService: service,
    );
    final run = provider.startDebug();
    await Future<void>.delayed(Duration.zero);
    expect(service.startCount, 1);
    provider.dispose();

    service.log('過期日誌');
    await Future<void>.delayed(Duration.zero);

    expect(service.cancelCalled, isTrue);
    expect(provider.logs, isEmpty);
    expect(provider.isDisposed, isTrue);
    service.runCompleter.complete();
    await run;
  });
}
